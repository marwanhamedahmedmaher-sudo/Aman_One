-- ============================================================================
-- 032_task_plan_items.sql — Weekly tasks planning (rep-driven)
--
-- Feature: before the working week (Sun–Thu), the rep plans it out. On Fri/Sat
-- they pre-pick the specific places they intend to visit in each of the 3 daily
-- windows, using the SAME pickers as the visit form (place / merchant / branch +
-- governorate). During the week, tapping a planned stop opens the visit form
-- pre-filled — "plan drives the visit" — and logging it flips the plan item to
-- 'visited'.
--
-- Design (mirrors the existing task_visits idioms, migration 024/029):
--   * ONE wide table + per-mission CHECK (chk_plan_shape) — same shape as
--     task_visits but WITHOUT the execution-only fields (GPS, photo, counts,
--     application_submitted). A plan is just "which place", not "what happened".
--   * The only client write paths are add_plan_item() / remove_plan_item()
--     (SECURITY DEFINER, rep-only, owns the task) — parity with record_task_visit.
--   * template_slug is derived server-side from the task's template, never
--     client-trusted.
--   * Week generation reuses the idempotent per-day logic from migration 019:
--     ensure_my_week_field_tasks() pre-creates the 5 working days' tasks so plan
--     items always hang off a real field_tasks row (FK), exactly like today.
--   * record_task_visit() gains an optional p_plan_item_id: when passed it links
--     the new visit and marks the plan item 'visited' in the same transaction.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. task_plan_items — many planned stops per field task
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.task_plan_items (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id         uuid        NOT NULL REFERENCES public.field_tasks(id) ON DELETE CASCADE,
  rep_id          uuid        NOT NULL REFERENCES auth.users(id),  -- forced = auth.uid()
  template_slug   text        NOT NULL,                            -- form discriminator

  -- shared -------------------------------------------------------------------
  governorate_id  smallint    REFERENCES public.governorates(id),
  notes           text        DEFAULT '',

  -- mission 1: gov_schools_hospitals ----------------------------------------
  place_kind      text,       -- 'school' | 'gov_institution' | 'hospital'
  place_name      text,

  -- mission 2: merchants_acceptance_finance ---------------------------------
  products        text[],     -- subset of {microfinance, acceptance}
  merchant_name   text,
  business_name   text,

  -- mission 3: aman_branch_visit --------------------------------------------
  branch_id       uuid        REFERENCES public.aman_branches(id),

  -- execution ----------------------------------------------------------------
  status          text        NOT NULL DEFAULT 'planned'
                              CHECK (status IN ('planned', 'visited', 'skipped')),
  visit_id        uuid        REFERENCES public.task_visits(id) ON DELETE SET NULL,

  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_plan_place_kind CHECK (
    place_kind IS NULL OR place_kind IN ('school', 'gov_institution', 'hospital')
  ),

  CONSTRAINT chk_plan_products_valid CHECK (
    products IS NULL OR products <@ ARRAY['microfinance','acceptance']::text[]
  ),

  -- Per-mission shape: exactly the right place fields present/absent per
  -- template. No GPS/photo/counts here — planning captures WHERE, not WHAT.
  CONSTRAINT chk_plan_shape CHECK (
    (   template_slug = 'gov_schools_hospitals'
        AND place_kind IS NOT NULL AND place_name IS NOT NULL
        AND governorate_id IS NOT NULL
        AND products IS NULL AND merchant_name IS NULL AND business_name IS NULL
        AND branch_id IS NULL)
 OR (   template_slug = 'merchants_acceptance_finance'
        AND products IS NOT NULL AND array_length(products, 1) >= 1
        AND merchant_name IS NOT NULL AND business_name IS NOT NULL
        AND governorate_id IS NOT NULL
        AND place_kind IS NULL AND place_name IS NULL
        AND branch_id IS NULL)
 OR (   template_slug = 'aman_branch_visit'
        AND branch_id IS NOT NULL
        AND place_kind IS NULL AND place_name IS NULL
        AND products IS NULL AND merchant_name IS NULL AND business_name IS NULL)
  )
);

COMMENT ON TABLE public.task_plan_items IS
  'One row per planned stop for a field task (weekly planning). Many per field_task. Written only via add_plan_item()/remove_plan_item(). Per-mission shape enforced by chk_plan_shape. status flips to ''visited'' when the linked visit is logged.';

CREATE INDEX IF NOT EXISTS idx_task_plan_items_task_id ON public.task_plan_items(task_id);
CREATE INDEX IF NOT EXISTS idx_task_plan_items_rep_id  ON public.task_plan_items(rep_id);
CREATE INDEX IF NOT EXISTS idx_task_plan_items_status  ON public.task_plan_items(status);

-- ---------------------------------------------------------------------------
-- 2. RLS — read for owner/supervisor/admin; NO direct write policy.
-- ---------------------------------------------------------------------------

ALTER TABLE public.task_plan_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_plan_items_select ON public.task_plan_items;
CREATE POLICY task_plan_items_select ON public.task_plan_items
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR public.is_supervisor()
    OR public.is_admin()
  );

-- No INSERT/UPDATE/DELETE policy — writes go through the RPCs below.

-- ---------------------------------------------------------------------------
-- 3. ensure_my_week_field_tasks() — pre-generate the working week's tasks.
--    Sun–Thu × 3 windows for the calling rep. Idempotent (same ON CONFLICT
--    as ensure_my_field_tasks, migration 019). Returns the week's Sunday so the
--    app knows the date range to query. Plan items hang off these rows.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_my_week_field_tasks(p_week_start date DEFAULT NULL)
RETURNS date   -- the Sunday the generated week starts on
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _rep_id      uuid;
  _cairo_today date;
  _dow         int;
  _week_start  date;
  _d           date;
  _i           int;
BEGIN
  _rep_id := auth.uid();
  IF _rep_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Only generate for active sales reps (no-op for anyone else).
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = _rep_id AND status = 'active' AND role = 'sales_rep'
  ) THEN
    RETURN NULL;
  END IF;

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  IF p_week_start IS NOT NULL THEN
    _week_start := p_week_start;
  ELSE
    -- dow: 0=Sun .. 6=Sat. Planning happens Fri/Sat for the COMING Sun–Thu;
    -- during the working week (Sun–Thu) target the week already in progress.
    _dow := EXTRACT(DOW FROM _cairo_today)::int;
    IF _dow IN (5, 6) THEN            -- Fri / Sat → upcoming Sunday
      _week_start := _cairo_today + (7 - _dow);
    ELSE                             -- Sun..Thu → this week's Sunday
      _week_start := _cairo_today - _dow;
    END IF;
  END IF;

  -- Generate Sun..Thu (5 working days) × the 3 windows. Idempotent per day.
  FOR _i IN 0..4 LOOP
    _d := _week_start + _i;
    INSERT INTO public.field_tasks
      (template_id, task_date, title, description, address,
       window_start, window_end, assigned_to, status)
    SELECT
      t.id,
      _d,
      t.title,
      t.description,
      '',
      ((_d::timestamp + t.window_start_time) AT TIME ZONE 'Africa/Cairo'),
      ((_d::timestamp + t.window_end_time)   AT TIME ZONE 'Africa/Cairo'),
      _rep_id,
      'pending'
    FROM public.task_templates t
    WHERE t.active
    ON CONFLICT (template_id, assigned_to, task_date)
      WHERE template_id IS NOT NULL AND task_date IS NOT NULL
      DO NOTHING;
  END LOOP;

  RETURN _week_start;
END;
$$;

COMMENT ON FUNCTION public.ensure_my_week_field_tasks IS
  'Pre-generates the working week (Sun–Thu × 3 windows) of field tasks for the calling active rep. Idempotent. p_week_start overrides the auto-computed Sunday. Returns the week''s Sunday. Called by the app when the weekly-planning screen opens.';

REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_week_field_tasks(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. add_plan_item() — the only client write path for a planned stop.
--    Rep-only, active, owns the task. No location consent (no GPS in planning).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_plan_item(
  p_task_id        uuid,
  p_governorate_id smallint DEFAULT NULL,
  p_notes          text     DEFAULT '',
  p_place_kind     text     DEFAULT NULL,
  p_place_name     text     DEFAULT NULL,
  p_products       text[]   DEFAULT NULL,
  p_merchant_name  text     DEFAULT NULL,
  p_business_name  text     DEFAULT NULL,
  p_branch_id      uuid     DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _status    text;
  _role      text;
  _task      record;
  _slug      text;
  _new_id    uuid;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Sales-rep-only, active (parity with record_task_visit).
  SELECT status, role INTO _status, _role
  FROM public.users WHERE id = _caller_id;

  IF _role IS DISTINCT FROM 'sales_rep' THEN
    RAISE EXCEPTION 'التخطيط متاح لمناديب المبيعات فقط' USING ERRCODE = '42501';
  END IF;
  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501';
  END IF;

  -- Task must exist and belong to the caller.
  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id AND assigned_to = _caller_id;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  -- Derive the form discriminator from the task's template (not client-trusted).
  SELECT slug INTO _slug FROM public.task_templates WHERE id = _task.template_id;
  IF _slug IS NULL THEN
    RAISE EXCEPTION 'نوع المهمة غير معروف' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.task_plan_items (
    task_id, rep_id, template_slug,
    governorate_id, notes,
    place_kind, place_name,
    products, merchant_name, business_name,
    branch_id, status
  ) VALUES (
    p_task_id, _caller_id, _slug,
    p_governorate_id, COALESCE(p_notes, ''),
    p_place_kind, p_place_name,
    p_products, p_merchant_name, p_business_name,
    p_branch_id, 'planned'
  )
  RETURNING id INTO _new_id;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id, 'plan_item_added', 'task_plan_items', _new_id, NULL,
    jsonb_build_object('task_id', p_task_id, 'template_slug', _slug)
  );

  RETURN _new_id;
END;
$$;

COMMENT ON FUNCTION public.add_plan_item IS
  'Adds one planned stop for the caller''s field task. Rep-only, active, owns the task. Per-mission shape enforced by the table CHECK. Only client write path to task_plan_items (insert).';

REVOKE ALL ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. remove_plan_item() — delete a not-yet-visited planned stop.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.remove_plan_item(p_plan_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _item      record;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _item
  FROM public.task_plan_items
  WHERE id = p_plan_item_id AND rep_id = _caller_id;

  IF _item.id IS NULL THEN
    RAISE EXCEPTION 'العنصر غير موجود أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  -- Once executed, the plan item is a historical link to a visit — don't delete.
  IF _item.status <> 'planned' THEN
    RAISE EXCEPTION 'لا يمكن حذف عنصر تم تنفيذه' USING ERRCODE = '23514';
  END IF;

  DELETE FROM public.task_plan_items WHERE id = p_plan_item_id;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (_caller_id, 'plan_item_removed', 'task_plan_items', p_plan_item_id,
          jsonb_build_object('task_id', _item.task_id), NULL);
END;
$$;

COMMENT ON FUNCTION public.remove_plan_item IS
  'Deletes a still-planned stop owned by the caller. Refuses once the item has been executed (status <> planned).';

REVOKE ALL ON FUNCTION public.remove_plan_item(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_plan_item(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_plan_item(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. record_task_visit() gains p_plan_item_id (drop+recreate: signature change).
--    When passed, the new visit links the plan item and flips it to 'visited'
--    in the same transaction. Everything else is unchanged from migration 029.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.record_task_visit(
  uuid, double precision, double precision, timestamptz, text, int, int, real,
  smallint, text, text, text, text[], text, text, uuid, boolean);

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
  p_application_submitted boolean DEFAULT NULL,
  p_plan_item_id         uuid     DEFAULT NULL
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
  _plan      record;
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

  -- If this visit executes a planned stop, validate it up front: must belong to
  -- the caller, to THIS task, and still be pending.
  IF p_plan_item_id IS NOT NULL THEN
    SELECT * INTO _plan
    FROM public.task_plan_items
    WHERE id = p_plan_item_id AND rep_id = _caller_id
    FOR UPDATE;

    IF _plan.id IS NULL OR _plan.task_id <> p_task_id THEN
      RAISE EXCEPTION 'عنصر التخطيط غير موجود أو غير مصرح بالوصول' USING ERRCODE = '42501';
    END IF;
    IF _plan.status <> 'planned' THEN
      RAISE EXCEPTION 'تم تنفيذ هذا العنصر بالفعل' USING ERRCODE = '23514';
    END IF;
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

  -- Link + close out the planned stop, if this visit executed one.
  IF p_plan_item_id IS NOT NULL THEN
    UPDATE public.task_plan_items
    SET status = 'visited', visit_id = _new_id
    WHERE id = p_plan_item_id;
  END IF;

  UPDATE public.field_tasks
  SET status = 'in_progress'
  WHERE id = p_task_id AND status = 'pending';

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id, 'task_visit_added', 'task_visits', _new_id, NULL,
    jsonb_build_object('task_id', p_task_id, 'template_slug', _slug,
                       'in_window', _in_window, 'recorded_at', p_recorded_at,
                       'plan_item_id', p_plan_item_id)
  );

  visit_id  := _new_id;
  in_window := _in_window;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid, boolean, uuid) TO authenticated;

-- ============================================================================
-- End of 032_task_plan_items.sql
-- ============================================================================
