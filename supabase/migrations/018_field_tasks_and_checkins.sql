-- ============================================================================
-- 018_field_tasks_and_checkins.sql — Location-based field tasks + check-ins
--
-- Supervisor feature: tasks are assigned per location with a time window
-- (currently in a Google Sheet). Reps open the tasks page, and each task has
-- a "submit location" button. Tapping it captures one GPS fix (foreground —
-- no background tracking) and records whether the check-in fell inside the
-- task's time window.
--
-- Scope decisions (from supervisor conversation, see CLAUDE.md):
--   * SOURCE: admin bulk-imports the Google Sheet into field_tasks
--     (CSV upload / Table Editor). DB is the source of truth.
--   * WINDOW: soft — the check-in always succeeds; the server records
--     in_window = (recorded_at BETWEEN window_start AND window_end).
--     Supervisor flags out-of-window check-ins.
--   * PROXIMITY: V1 captures the rep's coordinates only. target_lat/target_lng
--     are nullable columns reserved for a future distance check — not enforced.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. field_tasks — one row per assigned field visit (imported from the sheet)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.field_tasks (
  id            uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text             NOT NULL,
  description   text             DEFAULT '',
  address       text             DEFAULT '',
  target_lat    double precision,   -- reserved for future proximity check
  target_lng    double precision,   -- reserved for future proximity check
  window_start  timestamptz      NOT NULL,
  window_end    timestamptz      NOT NULL,
  assigned_to   uuid             NOT NULL REFERENCES auth.users(id),
  status        text             NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'completed', 'skipped')),
  created_at    timestamptz      NOT NULL DEFAULT now(),
  updated_at    timestamptz      NOT NULL DEFAULT now(),

  CONSTRAINT field_tasks_window_valid CHECK (window_end > window_start)
);

COMMENT ON TABLE public.field_tasks IS
  'Location-based field-visit tasks, imported from the supervisor''s Google Sheet. One row per assigned visit. Reps check in against these.';
COMMENT ON COLUMN public.field_tasks.window_start IS 'Start of the task time window (tz-aware; store Cairo-local moments).';
COMMENT ON COLUMN public.field_tasks.window_end   IS 'End of the task time window.';
COMMENT ON COLUMN public.field_tasks.target_lat   IS 'Optional task location latitude. Reserved for a future proximity check; not enforced in V1.';

CREATE INDEX IF NOT EXISTS idx_field_tasks_assigned_to   ON public.field_tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_field_tasks_window_start  ON public.field_tasks(window_start);

DROP TRIGGER IF EXISTS trg_field_tasks_updated_at ON public.field_tasks;
CREATE TRIGGER trg_field_tasks_updated_at
  BEFORE UPDATE ON public.field_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. task_checkins — ONE check-in per task (the location proof)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.task_checkins (
  task_id     uuid             PRIMARY KEY REFERENCES public.field_tasks(id) ON DELETE CASCADE,
  rep_id      uuid             NOT NULL REFERENCES auth.users(id),
  lat         double precision NOT NULL,
  lng         double precision NOT NULL,
  accuracy_m  real,
  recorded_at timestamptz      NOT NULL,   -- device clock: when the fix was taken
  in_window   boolean          NOT NULL,   -- computed server-side at check-in
  created_at  timestamptz      NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.task_checkins IS
  'Per-task location check-in. One row per field task (PK = task_id; re-submission overwrites). Written only via record_task_checkin().';
COMMENT ON COLUMN public.task_checkins.in_window IS
  'True if recorded_at fell within the task window. Computed server-side, not client-trusted.';

CREATE INDEX IF NOT EXISTS idx_task_checkins_rep_id ON public.task_checkins(rep_id);

-- ---------------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------------

ALTER TABLE public.field_tasks   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_checkins ENABLE ROW LEVEL SECURITY;

-- field_tasks SELECT: assignee, supervisor, or admin.
DROP POLICY IF EXISTS field_tasks_select ON public.field_tasks;
CREATE POLICY field_tasks_select ON public.field_tasks
  FOR SELECT
  USING (
    assigned_to = auth.uid()
    OR public.is_supervisor()
    OR public.is_admin()
  );

-- field_tasks writes (import / management): admin only. Service role (Dashboard
-- CSV import) bypasses RLS. Status changes by reps happen via the check-in RPC.
DROP POLICY IF EXISTS field_tasks_admin_insert ON public.field_tasks;
CREATE POLICY field_tasks_admin_insert ON public.field_tasks
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS field_tasks_admin_update ON public.field_tasks;
CREATE POLICY field_tasks_admin_update ON public.field_tasks
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS field_tasks_admin_delete ON public.field_tasks;
CREATE POLICY field_tasks_admin_delete ON public.field_tasks
  FOR DELETE USING (public.is_admin());

-- task_checkins SELECT: the rep who checked in, supervisor, or admin.
DROP POLICY IF EXISTS task_checkins_select ON public.task_checkins;
CREATE POLICY task_checkins_select ON public.task_checkins
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR public.is_supervisor()
    OR public.is_admin()
  );

-- No INSERT/UPDATE/DELETE policies — the only write path is the
-- record_task_checkin() SECURITY DEFINER RPC below.

-- ---------------------------------------------------------------------------
-- 4. record_task_checkin() — the only client write path for a check-in
--    Enforces: authenticated, active, consent granted, task is the caller's.
--    Window is NOT enforced — it is recorded (in_window) for the supervisor.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_task_checkin(
  p_task_id     uuid,
  p_lat         double precision,
  p_lng         double precision,
  p_accuracy_m  real        DEFAULT NULL,
  p_recorded_at timestamptz DEFAULT now()
)
RETURNS boolean   -- returns in_window so the app can confirm "on time" vs "outside window"
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
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- Coordinate sanity check.
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat <  -90  OR p_lat >  90
     OR p_lng < -180  OR p_lng > 180 THEN
    RAISE EXCEPTION 'إحداثيات غير صحيحة' USING ERRCODE = '22023'; -- invalid coordinates
  END IF;

  -- Role + consent + account-status gate. Check-ins are SALES REP ONLY.
  SELECT location_consent, status, role INTO _consent, _status, _role
  FROM public.users
  WHERE id = _caller_id;

  IF _role IS DISTINCT FROM 'sales_rep' THEN
    RAISE EXCEPTION 'تسجيل الموقع متاح لمناديب المبيعات فقط'
      USING ERRCODE = '42501'; -- check-in is sales-rep-only
  END IF;

  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501'; -- account not active
  END IF;

  IF _consent IS NOT TRUE THEN
    RAISE EXCEPTION 'لم يتم منح إذن تسجيل الموقع' USING ERRCODE = '42501'; -- consent not granted
  END IF;

  -- Task must exist and belong to the calling rep. No admin/supervisor bypass —
  -- only the assigned rep can submit their own check-in.
  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id
    AND assigned_to = _caller_id;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول'
      USING ERRCODE = '42501'; -- task not found or not authorized
  END IF;

  -- Soft window: record whether the fix fell inside the task window.
  _in_window := (p_recorded_at >= _task.window_start
                 AND p_recorded_at <= _task.window_end);

  -- Upsert the check-in (one per task; re-submission overwrites a bad fix).
  INSERT INTO public.task_checkins
    (task_id, rep_id, lat, lng, accuracy_m, recorded_at, in_window)
  VALUES
    (p_task_id, _caller_id, p_lat, p_lng, p_accuracy_m, p_recorded_at, _in_window)
  ON CONFLICT (task_id) DO UPDATE
    SET rep_id      = EXCLUDED.rep_id,
        lat         = EXCLUDED.lat,
        lng         = EXCLUDED.lng,
        accuracy_m  = EXCLUDED.accuracy_m,
        recorded_at = EXCLUDED.recorded_at,
        in_window   = EXCLUDED.in_window,
        created_at  = now();

  -- Checking in completes the visit task.
  UPDATE public.field_tasks
  SET status = 'completed'
  WHERE id = p_task_id AND status <> 'completed';

  -- Forensic record (parity with reveal_national_id / merchants audit).
  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id,
    'task_checked_in',
    'task_checkins',
    p_task_id,
    NULL,
    jsonb_build_object('in_window', _in_window, 'recorded_at', p_recorded_at)
  );

  RETURN _in_window;
END;
$$;

COMMENT ON FUNCTION public.record_task_checkin IS
  'Records the caller''s location check-in for one of their field tasks and marks the task completed. Rejects unless authenticated, active, and consented. Returns in_window. The only client write path to task_checkins.';

REVOKE ALL ON FUNCTION public.record_task_checkin(uuid, double precision, double precision, real, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_task_checkin(uuid, double precision, double precision, real, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_task_checkin(uuid, double precision, double precision, real, timestamptz) TO authenticated;

-- ============================================================================
-- End of 018_field_tasks_and_checkins.sql
-- ============================================================================
