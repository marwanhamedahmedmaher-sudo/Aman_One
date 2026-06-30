-- ============================================================================
-- 024_task_visits.sql — Multi-visit logging per field task
--
-- Supervisor feedback (2026-06-29): each of the 3 daily field tasks should let
-- the rep log MANY visits, not a single GPS check-in. Every visit captures a
-- rich, per-mission form + GPS + a required photo + contacted/onboarded counts.
--
-- Design (mirrors existing idioms):
--   * ONE wide table + per-mission CHECK constraints — same pattern as
--     merchants.microfinance_amount / acceptance_device_count (migration 011).
--   * The ONLY client write path is record_task_visit() (SECURITY DEFINER),
--     mirroring record_task_checkin() (migration 018): rep-only, active,
--     consented, owns the task. rep_id is forced to auth.uid().
--   * task_checkins (018) is left intact — historical data is preserved; the
--     app simply stops writing it and writes task_visits instead.
--
-- Decisions locked 2026-06-29:
--   * Photo REQUIRED (photo_path NOT NULL).
--   * Counts REQUIRED (defaults present, but the client always sends them).
--   * Completion is EXPLICIT — a visit sets the task to 'in_progress';
--     complete_field_task() flips it to 'completed'. New status value added.
--   * Mission 3 (aman_branch_visit) capped at 2 visits, enforced in the RPC.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend field_tasks.status with 'in_progress'
-- ---------------------------------------------------------------------------

ALTER TABLE public.field_tasks DROP CONSTRAINT IF EXISTS field_tasks_status_check;
ALTER TABLE public.field_tasks
  ADD CONSTRAINT field_tasks_status_check
  CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped'));

-- ---------------------------------------------------------------------------
-- 2. task_visits — many rows per field task
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.task_visits (
  id              uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id         uuid             NOT NULL REFERENCES public.field_tasks(id) ON DELETE CASCADE,
  rep_id          uuid             NOT NULL REFERENCES auth.users(id),  -- forced = auth.uid()
  template_slug   text             NOT NULL,                            -- form discriminator

  -- location (every visit) ---------------------------------------------------
  lat             double precision NOT NULL,
  lng             double precision NOT NULL,
  accuracy_m      real,
  recorded_at     timestamptz      NOT NULL,
  in_window       boolean          NOT NULL,

  -- shared, required by the client ------------------------------------------
  governorate_id  smallint         REFERENCES public.governorates(id),
  photo_path      text             NOT NULL,                            -- Storage object path
  notes           text             DEFAULT '',
  contacted_count int              NOT NULL DEFAULT 0 CHECK (contacted_count >= 0),
  onboarded_count int              NOT NULL DEFAULT 0 CHECK (onboarded_count >= 0),

  -- mission 1: gov_schools_hospitals ----------------------------------------
  place_kind      text,            -- 'school' | 'gov_institution'
  place_name      text,

  -- mission 2: merchants_acceptance_finance ---------------------------------
  products        text[],          -- subset of {microfinance, acceptance}
  merchant_name   text,
  business_name   text,

  -- mission 3: aman_branch_visit --------------------------------------------
  branch_id       uuid             REFERENCES public.aman_branches(id),

  created_at      timestamptz      NOT NULL DEFAULT now(),

  CONSTRAINT chk_onboarded_le_contacted CHECK (onboarded_count <= contacted_count),

  CONSTRAINT chk_place_kind CHECK (place_kind IS NULL OR place_kind IN ('school', 'gov_institution')),

  CONSTRAINT chk_products_valid CHECK (
    products IS NULL OR products <@ ARRAY['microfinance','acceptance']::text[]
  ),

  -- Per-mission shape: exactly the right fields present/absent per template.
  CONSTRAINT chk_visit_shape CHECK (
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

COMMENT ON TABLE public.task_visits IS
  'One row per logged field visit. Many per field_task. Written only via record_task_visit(). Per-mission shape enforced by chk_visit_shape. photo_path/counts required.';

CREATE INDEX IF NOT EXISTS idx_task_visits_task_id  ON public.task_visits(task_id);
CREATE INDEX IF NOT EXISTS idx_task_visits_rep_id   ON public.task_visits(rep_id);
CREATE INDEX IF NOT EXISTS idx_task_visits_template ON public.task_visits(template_slug);

-- ---------------------------------------------------------------------------
-- 3. RLS — read for owner/supervisor/admin; NO direct write policy.
-- ---------------------------------------------------------------------------

ALTER TABLE public.task_visits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_visits_select ON public.task_visits;
CREATE POLICY task_visits_select ON public.task_visits
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR public.is_supervisor()
    OR public.is_admin()
  );

-- No INSERT/UPDATE/DELETE policy — the only write path is record_task_visit().

-- ---------------------------------------------------------------------------
-- 4. record_task_visit() — the only client write path for a visit
-- ---------------------------------------------------------------------------

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
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- Coordinate sanity.
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat <  -90  OR p_lat >  90
     OR p_lng < -180  OR p_lng > 180 THEN
    RAISE EXCEPTION 'إحداثيات غير صحيحة' USING ERRCODE = '22023'; -- invalid coordinates
  END IF;

  -- Required photo + non-negative, consistent counts (defense in depth vs CHECK).
  IF p_photo_path IS NULL OR length(trim(p_photo_path)) = 0 THEN
    RAISE EXCEPTION 'صورة المكان مطلوبة' USING ERRCODE = '23514'; -- photo required
  END IF;
  IF p_contacted_count IS NULL OR p_onboarded_count IS NULL
     OR p_contacted_count < 0 OR p_onboarded_count < 0
     OR p_onboarded_count > p_contacted_count THEN
    RAISE EXCEPTION 'أعداد العملاء غير صحيحة' USING ERRCODE = '23514'; -- invalid counts
  END IF;

  -- Role + consent + account-status gate. Sales-rep only (parity with 018).
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

  -- Task must exist and belong to the caller. Lock the row so the mission-3
  -- cap count below is race-safe against concurrent inserts.
  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id AND assigned_to = _caller_id
  FOR UPDATE;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  -- Derive the form discriminator from the task's template (not client-trusted).
  SELECT slug INTO _slug FROM public.task_templates WHERE id = _task.template_id;
  IF _slug IS NULL THEN
    RAISE EXCEPTION 'نوع المهمة غير معروف' USING ERRCODE = '22023'; -- unknown task type
  END IF;

  -- Mission-3 cap: at most 2 visits per aman_branch_visit task.
  IF _slug = 'aman_branch_visit' THEN
    SELECT count(*) INTO _existing FROM public.task_visits WHERE task_id = p_task_id;
    IF _existing >= 2 THEN
      RAISE EXCEPTION 'الحد الأقصى زيارتين لهذه المهمة' USING ERRCODE = '23514'; -- max 2 visits
    END IF;
  END IF;

  -- Soft window: record whether the fix fell inside the task window.
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

  -- First visit moves the task to in_progress (explicit "done" completes it).
  UPDATE public.field_tasks
  SET status = 'in_progress'
  WHERE id = p_task_id AND status = 'pending';

  -- Forensic record (parity with record_task_checkin / reveal_national_id).
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

COMMENT ON FUNCTION public.record_task_visit IS
  'Inserts one field visit for the caller''s task and moves the task to in_progress. Rep-only, active, consented, owns the task. Enforces required photo/counts, per-mission shape (via table CHECK), and the mission-3 two-visit cap. Returns the new visit id + in_window. Only client write path to task_visits.';

REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_task_visit(uuid, double precision, double precision, timestamptz, text, int, int, real, smallint, text, text, text, text[], text, text, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. complete_field_task() — explicit "done" (requires >= 1 visit)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_field_task(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _task      record;
  _visits    int;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id AND assigned_to = _caller_id;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO _visits FROM public.task_visits WHERE task_id = p_task_id;
  IF _visits = 0 THEN
    RAISE EXCEPTION 'يجب تسجيل زيارة واحدة على الأقل قبل إنهاء المهمة'
      USING ERRCODE = '23514'; -- need >= 1 visit
  END IF;

  UPDATE public.field_tasks
  SET status = 'completed'
  WHERE id = p_task_id AND status <> 'completed';

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (_caller_id, 'field_task_completed', 'field_tasks', p_task_id, NULL,
          jsonb_build_object('visit_count', _visits));
END;
$$;

COMMENT ON FUNCTION public.complete_field_task IS
  'Marks the caller''s field task completed. Rep-only, owns the task, requires at least one logged visit. Separate from record_task_visit so completion is an explicit rep action.';

REVOKE ALL ON FUNCTION public.complete_field_task(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_field_task(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_field_task(uuid) TO authenticated;

-- ============================================================================
-- End of 024_task_visits.sql
-- ============================================================================
