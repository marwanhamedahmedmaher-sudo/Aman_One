-- ============================================================================
-- 028_visit_photo_hardening.sql — Lock down visit-photo uploads
--
-- 1. Bucket limits: cap object size + restrict to image MIME types. The app
--    already downscales to 1600px/q70 (~100-400 KB); this is the hard server
--    backstop against a modified client uploading a huge or non-image file.
-- 2. record_task_visit() now verifies the photo_path is (a) under the caller's
--    own {uid}/{task_id}/ folder and (b) an object that actually exists in the
--    bucket — closing the "record a visit with a fake/never-uploaded path" gap.
-- ============================================================================

-- 1. Bucket: 5 MB cap + image-only MIME allowlist.
UPDATE storage.buckets
SET file_size_limit   = 5242880,                                  -- 5 MB
    allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp']
WHERE id = 'task-visit-photos';

-- 2. Re-create record_task_visit with the photo_path ownership + existence checks.
CREATE OR REPLACE FUNCTION public.record_task_visit(
  p_task_id         uuid,
  p_lat             double precision,
  p_lng             double precision,
  p_recorded_at     timestamptz,
  p_photo_path      text,
  p_contacted_count int,
  p_onboarded_count int,
  p_accuracy_m      real     DEFAULT NULL,
  p_governorate_id  smallint DEFAULT NULL,
  p_notes           text     DEFAULT '',
  p_place_kind      text     DEFAULT NULL,
  p_place_name      text     DEFAULT NULL,
  p_products        text[]   DEFAULT NULL,
  p_merchant_name   text     DEFAULT NULL,
  p_business_name   text     DEFAULT NULL,
  p_branch_id       uuid     DEFAULT NULL
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

  -- Photo must live under the caller's own {uid}/{task_id}/ folder ...
  IF p_photo_path NOT LIKE (_caller_id::text || '/' || p_task_id::text || '/%') THEN
    RAISE EXCEPTION 'مسار الصورة غير صالح' USING ERRCODE = '42501'; -- invalid photo path
  END IF;
  -- ... and must be a real object that was actually uploaded.
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'task-visit-photos' AND name = p_photo_path
  ) THEN
    RAISE EXCEPTION 'لم يتم رفع الصورة بشكل صحيح' USING ERRCODE = '23514'; -- photo not uploaded
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
    place_kind, place_name, products, merchant_name, business_name, branch_id
  ) VALUES (
    p_task_id, _caller_id, _slug,
    p_lat, p_lng, p_accuracy_m, p_recorded_at, _in_window,
    p_governorate_id, p_photo_path, COALESCE(p_notes, ''), p_contacted_count, p_onboarded_count,
    p_place_kind, p_place_name, p_products, p_merchant_name, p_business_name, p_branch_id
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

-- ============================================================================
-- End of 028_visit_photo_hardening.sql
-- ============================================================================
