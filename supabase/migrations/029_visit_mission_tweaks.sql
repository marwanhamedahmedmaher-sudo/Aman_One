-- ============================================================================
-- 029_visit_mission_tweaks.sql — per-mission form changes (supervisor feedback)
--
-- M1 (gov/schools): add 'hospital' as a place_kind option (still single-select).
-- M2 (merchants):   drop the contacted/onboarded question for the form; replace
--                   with «هل تم التقديم؟» → new application_submitted boolean.
--                   Counts stay in the table (defaulted 0) so the schema and
--                   report stay uniform, but the M2 form no longer collects them.
-- ============================================================================

-- 1. New column for the M2 "was the application submitted?" answer.
ALTER TABLE public.task_visits
  ADD COLUMN IF NOT EXISTS application_submitted boolean;

COMMENT ON COLUMN public.task_visits.application_submitted IS
  'M2 only: answer to «هل تم التقديم؟». NULL for other missions (enforced by chk_visit_shape).';

-- 2. place_kind now allows 'hospital'.
ALTER TABLE public.task_visits DROP CONSTRAINT IF EXISTS chk_place_kind;
ALTER TABLE public.task_visits
  ADD CONSTRAINT chk_place_kind
  CHECK (place_kind IS NULL OR place_kind IN ('school', 'gov_institution', 'hospital'));

-- 3. Per-mission shape: M1/M3 → application_submitted NULL; M2 → NOT NULL.
ALTER TABLE public.task_visits DROP CONSTRAINT IF EXISTS chk_visit_shape;
ALTER TABLE public.task_visits
  ADD CONSTRAINT chk_visit_shape CHECK (
    (   template_slug = 'gov_schools_hospitals'
        AND place_kind IS NOT NULL AND place_name IS NOT NULL
        AND governorate_id IS NOT NULL
        AND products IS NULL AND merchant_name IS NULL AND business_name IS NULL
        AND branch_id IS NULL
        AND application_submitted IS NULL)
 OR (   template_slug = 'merchants_acceptance_finance'
        AND products IS NOT NULL AND array_length(products, 1) >= 1
        AND merchant_name IS NOT NULL AND business_name IS NOT NULL
        AND governorate_id IS NOT NULL
        AND place_kind IS NULL AND place_name IS NULL AND branch_id IS NULL
        AND application_submitted IS NOT NULL)
 OR (   template_slug = 'aman_branch_visit'
        AND branch_id IS NOT NULL
        AND place_kind IS NULL AND place_name IS NULL
        AND products IS NULL AND merchant_name IS NULL AND business_name IS NULL
        AND application_submitted IS NULL)
  );

-- 4. record_task_visit gains p_application_submitted (drop+recreate: signature change).
DROP FUNCTION IF EXISTS public.record_task_visit(
  uuid, double precision, double precision, timestamptz, text, int, int, real,
  smallint, text, text, text, text[], text, text, uuid);

CREATE OR REPLACE FUNCTION public.record_task_visit(
  p_task_id              uuid,
  p_lat                  double precision,
  p_lng                  double precision,
  p_recorded_at          timestamptz,
  p_photo_path           text,
  p_contacted_count      int,
  p_onboarded_count      int,
  p_accuracy_m           real     DEFAULT NULL,
  p_governorate_id       smallint DEFAULT NULL,
  p_notes                text     DEFAULT '',
  p_place_kind           text     DEFAULT NULL,
  p_place_name           text     DEFAULT NULL,
  p_products             text[]   DEFAULT NULL,
  p_merchant_name        text     DEFAULT NULL,
  p_business_name        text     DEFAULT NULL,
  p_branch_id            uuid     DEFAULT NULL,
  p_application_submitted boolean DEFAULT NULL
)
RETURNS TABLE (visit_id uuid, in_window boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _consent   boolean;
  _status    text;
  _role      text;
  _task      record;
  _in_window boolean;
  _slug      text;
  _existing  int;
  _new_id    uuid;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat <  -90  OR p_lat >  90
     OR p_lng < -180  OR p_lng > 180 THEN
    RAISE EXCEPTION 'إحداثيات غير صحيحة' USING ERRCODE = '22023';
  END IF;

  IF p_photo_path IS NULL OR length(trim(p_photo_path)) = 0 THEN
    RAISE EXCEPTION 'صورة المكان مطلوبة' USING ERRCODE = '23514';
  END IF;

  IF p_photo_path NOT LIKE (_caller_id::text || '/' || p_task_id::text || '/%') THEN
    RAISE EXCEPTION 'مسار الصورة غير صالح' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'task-visit-photos' AND name = p_photo_path
  ) THEN
    RAISE EXCEPTION 'لم يتم رفع الصورة بشكل صحيح' USING ERRCODE = '23514';
  END IF;

  IF p_contacted_count IS NULL OR p_onboarded_count IS NULL
     OR p_contacted_count < 0 OR p_onboarded_count < 0
     OR p_onboarded_count > p_contacted_count THEN
    RAISE EXCEPTION 'أعداد العملاء غير صحيحة' USING ERRCODE = '23514';
  END IF;

  SELECT location_consent, status, role INTO _consent, _status, _role
  FROM public.users WHERE id = _caller_id;

  IF _role IS DISTINCT FROM 'sales_rep' THEN
    RAISE EXCEPTION 'تسجيل الزيارة متاح لمناديب المبيعات فقط' USING ERRCODE = '42501';
  END IF;
  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501';
  END IF;
  IF _consent IS NOT TRUE THEN
    RAISE EXCEPTION 'لم يتم منح إذن تسجيل الموقع' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id AND assigned_to = _caller_id
  FOR UPDATE;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  SELECT slug INTO _slug FROM public.task_templates WHERE id = _task.template_id;
  IF _slug IS NULL THEN
    RAISE EXCEPTION 'نوع المهمة غير معروف' USING ERRCODE = '22023';
  END IF;

  IF _slug = 'aman_branch_visit' THEN
    SELECT count(*) INTO _existing FROM public.task_visits WHERE task_id = p_task_id;
    IF _existing >= 2 THEN
      RAISE EXCEPTION 'الحد الأقصى زيارتين لهذه المهمة' USING ERRCODE = '23514';
    END IF;
  END IF;

  _in_window := (p_recorded_at >= _task.window_start AND p_recorded_at <= _task.window_end);

  INSERT INTO public.task_visits (
    task_id, rep_id, template_slug,
    lat, lng, accuracy_m, recorded_at, in_window,
    governorate_id, photo_path, notes, contacted_count, onboarded_count,
    place_kind, place_name, products, merchant_name, business_name, branch_id,
    application_submitted
  ) VALUES (
    p_task_id, _caller_id, _slug,
    p_lat, p_lng, p_accuracy_m, p_recorded_at, _in_window,
    p_governorate_id, p_photo_path, COALESCE(p_notes, ''), p_contacted_count, p_onboarded_count,
    p_place_kind, p_place_name, p_products, p_merchant_name, p_business_name, p_branch_id,
    p_application_submitted
  )
  RETURNING id INTO _new_id;

  UPDATE public.field_tasks
  SET status = 'in_progress'
  WHERE id = p_task_id AND status = 'pending';

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id, 'task_visit_added', 'task_visits', _new_id, NULL,
    jsonb_build_object('task_id', p_task_id, 'template_slug', _slug,
                       'in_window', _in_window, 'recorded_at', p_recorded_at)
  );

  visit_id  := _new_id;
  in_window := _in_window;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean) TO authenticated;

-- 5. Report view: surface «تم التقديم» for M2, and don't show meaningless 0 counts for M2.
-- (DROP first — the new «تم التقديم» column changes column order, which
-- CREATE OR REPLACE VIEW disallows.)
DROP VIEW IF EXISTS public.v_visit_report;
CREATE VIEW public.v_visit_report
WITH (security_invoker = true) AS
SELECT
  u.name                                                            AS "اسم المندوب",
  u.employee_id                                                     AS "رقم الموظف",
  u.region                                                          AS "المنطقة",
  ft.title                                                          AS "المهمة",
  ft.task_date                                                      AS "التاريخ",
  CASE tv.template_slug
    WHEN 'gov_schools_hospitals'        THEN 'مؤسسات حكومية / مدارس / مستشفيات'
    WHEN 'merchants_acceptance_finance' THEN 'تجار — Acceptance / تمويل'
    WHEN 'aman_branch_visit'            THEN 'فرع أمان'
    ELSE tv.template_slug
  END                                                               AS "نوع الزيارة",
  COALESCE(
    tv.place_name,
    NULLIF(concat_ws(' - ', tv.merchant_name, tv.business_name), ''),
    b.name_ar
  )                                                                 AS "الجهة",
  CASE tv.place_kind
    WHEN 'school'          THEN 'مدرسة'
    WHEN 'gov_institution' THEN 'مؤسسة حكومية'
    WHEN 'hospital'        THEN 'مستشفى'
    ELSE NULL
  END                                                               AS "التصنيف",
  array_to_string(
    ARRAY(SELECT CASE p WHEN 'microfinance' THEN 'تمويل'
                        WHEN 'acceptance'  THEN 'Acceptance'
                        ELSE p END
          FROM unnest(tv.products) p), ' + ')                       AS "المنتجات",
  CASE WHEN tv.application_submitted IS NULL THEN NULL
       WHEN tv.application_submitted THEN 'نعم' ELSE 'لا' END        AS "تم التقديم",
  g.name_ar                                                         AS "المحافظة",
  CASE WHEN tv.template_slug = 'merchants_acceptance_finance' THEN NULL
       ELSE tv.contacted_count END                                  AS "عدد المتواصل معهم",
  CASE WHEN tv.template_slug = 'merchants_acceptance_finance' THEN NULL
       ELSE tv.onboarded_count END                                  AS "عدد المسجلين",
  to_char(tv.recorded_at AT TIME ZONE 'Africa/Cairo', 'HH24:MI')    AS "وقت الزيارة",
  CASE WHEN tv.in_window THEN 'في الموعد' ELSE 'خارج الموعد' END     AS "الالتزام",
  'https://maps.google.com/?q=' || tv.lat || ',' || tv.lng          AS "رابط الخريطة",
  tv.notes                                                          AS "تفاصيل الزيارة",
  tv.photo_path                                                     AS "مسار الصورة",
  tv.recorded_at                                                    AS "recorded_at_utc"
FROM public.task_visits tv
JOIN public.field_tasks ft  ON ft.id = tv.task_id
JOIN public.users u         ON u.id  = tv.rep_id
LEFT JOIN public.governorates g ON g.id = tv.governorate_id
LEFT JOIN public.aman_branches b ON b.id = tv.branch_id;

GRANT SELECT ON public.v_visit_report TO authenticated;

-- ============================================================================
-- End of 029_visit_mission_tweaks.sql
-- ============================================================================
