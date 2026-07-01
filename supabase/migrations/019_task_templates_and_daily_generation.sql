-- ============================================================================
-- 019_task_templates_and_daily_generation.sql
-- Unified daily field-task schedule — same 3 windows for every rep.
--
-- The schedule is defined ONCE in task_templates and instantiated per rep,
-- per day, into field_tasks (migration 018). Locations differ per rep only by
-- where the rep actually checks in (GPS) — nothing per-rep is modeled here.
-- The specific branch for the 4–5 task is communicated out-of-band
-- (WhatsApp / Google Sheet) as today; the app records the GPS pin and the
-- supervisor compares it to the branch they assigned.
--
-- Schedule (Africa/Cairo local time):
--   1. 10:00–14:00  زيارة المؤسسات الحكومية / المدارس / المستشفيات
--   2. 14:00–16:00  زيارة التجار (ماكينات Acceptance / تمويل Leads)
--   3. 16:00–17:00  زيارة فرع أمان القريب (روتيشن — الفرع يُبلّغ خارج التطبيق)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. task_templates — the unified schedule, defined once
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.task_templates (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              text        UNIQUE NOT NULL,        -- stable code for generation
  title             text        NOT NULL,
  description       text        DEFAULT '',
  window_start_time time        NOT NULL,               -- Cairo-local time of day
  window_end_time   time        NOT NULL,
  sort_order        int         NOT NULL DEFAULT 0,
  requires_checkin  boolean     NOT NULL DEFAULT true,  -- does this task need a GPS check-in?
  active            boolean     NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT task_templates_window_valid CHECK (window_end_time > window_start_time)
);

COMMENT ON TABLE public.task_templates IS
  'The unified daily field-task schedule. One row per recurring task window. Instantiated per rep per day by generate/ensure RPCs.';

ALTER TABLE public.task_templates ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user (reps render the schedule). Writes: admin only.
DROP POLICY IF EXISTS task_templates_select ON public.task_templates;
CREATE POLICY task_templates_select ON public.task_templates
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS task_templates_admin_insert ON public.task_templates;
CREATE POLICY task_templates_admin_insert ON public.task_templates
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS task_templates_admin_update ON public.task_templates;
CREATE POLICY task_templates_admin_update ON public.task_templates
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS task_templates_admin_delete ON public.task_templates;
CREATE POLICY task_templates_admin_delete ON public.task_templates
  FOR DELETE USING (public.is_admin());

-- Seed the 3 windows. Idempotent on slug.
INSERT INTO public.task_templates (slug, title, description, window_start_time, window_end_time, sort_order)
VALUES
  ('gov_schools_hospitals',
   'زيارة المؤسسات الحكومية / المدارس / المستشفيات',
   'زيارة المؤسسات الحكومية والمدارس والمستشفيات في المنطقة.',
   '10:00', '14:00', 1),
  ('merchants_acceptance_finance',
   'زيارة التجار — ماكينات Acceptance / تمويل',
   'زيارة التجار للعمل على إنزال ماكينات Acceptance أو عمل تمويل Leads للعملاء.',
   '14:00', '16:00', 2),
  ('aman_branch_visit',
   'زيارة فرع أمان القريب',
   'زيارة فرع أمان في المنطقة (روتيشن). الفرع المحدد يُبلّغ عبر واتساب / جوجل شيت.',
   '16:00', '17:00', 3)
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Link field_tasks to its template + a task_date, for idempotent generation
-- ---------------------------------------------------------------------------

ALTER TABLE public.field_tasks
  ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.task_templates(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS task_date   date;

COMMENT ON COLUMN public.field_tasks.template_id IS 'Source template, if this task was generated from the unified schedule (NULL for ad-hoc tasks).';
COMMENT ON COLUMN public.field_tasks.task_date   IS 'Cairo-local date this task instance belongs to.';

-- One task per (template, rep, day). Partial — only applies to generated rows.
CREATE UNIQUE INDEX IF NOT EXISTS uq_field_tasks_template_rep_date
  ON public.field_tasks (template_id, assigned_to, task_date)
  WHERE template_id IS NOT NULL AND task_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_field_tasks_task_date ON public.field_tasks(task_date);

-- ---------------------------------------------------------------------------
-- 3. ensure_my_field_tasks() — app calls this on tasks-page load.
--    Generates today's (Cairo) tasks for the CALLING rep if missing.
--    Mirrors refill_rep_tasks(): self-service, idempotent, no cron needed.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_my_field_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _rep_id      uuid;
  _cairo_today date;
BEGIN
  _rep_id := auth.uid();
  IF _rep_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Only generate for active sales reps.
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = _rep_id AND status = 'active' AND role = 'sales_rep'
  ) THEN
    RETURN;
  END IF;

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  INSERT INTO public.field_tasks
    (template_id, task_date, title, description, address,
     window_start, window_end, assigned_to, status)
  SELECT
    t.id,
    _cairo_today,
    t.title,
    t.description,
    '',
    ((_cairo_today::timestamp + t.window_start_time) AT TIME ZONE 'Africa/Cairo'),
    ((_cairo_today::timestamp + t.window_end_time)   AT TIME ZONE 'Africa/Cairo'),
    _rep_id,
    'pending'
  FROM public.task_templates t
  WHERE t.active
  ON CONFLICT (template_id, assigned_to, task_date)
    WHERE template_id IS NOT NULL AND task_date IS NOT NULL
    DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.ensure_my_field_tasks IS
  'Generates today''s (Cairo) unified field tasks for the calling active rep if not already present. Idempotent. Called by the app on tasks-page load.';

REVOKE ALL ON FUNCTION public.ensure_my_field_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_my_field_tasks() FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_field_tasks() TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. generate_daily_field_tasks() — bulk generator for ALL active reps.
--    For an admin/cron trigger. Idempotent + race-safe via advisory lock,
--    same pattern as distribute_daily_tasks().
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_daily_field_tasks()
RETURNS integer   -- number of task rows created
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _cairo_today date;
  _created     integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Advisory lock so concurrent triggers don't double-insert.
  PERFORM pg_advisory_xact_lock(1019);

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  INSERT INTO public.field_tasks
    (template_id, task_date, title, description, address,
     window_start, window_end, assigned_to, status)
  SELECT
    t.id,
    _cairo_today,
    t.title,
    t.description,
    '',
    ((_cairo_today::timestamp + t.window_start_time) AT TIME ZONE 'Africa/Cairo'),
    ((_cairo_today::timestamp + t.window_end_time)   AT TIME ZONE 'Africa/Cairo'),
    u.id,
    'pending'
  FROM public.users u
  CROSS JOIN public.task_templates t
  WHERE u.role = 'sales_rep' AND u.status = 'active' AND t.active
  ON CONFLICT (template_id, assigned_to, task_date)
    WHERE template_id IS NOT NULL AND task_date IS NOT NULL
    DO NOTHING;

  GET DIAGNOSTICS _created = ROW_COUNT;
  RETURN _created;
END;
$$;

COMMENT ON FUNCTION public.generate_daily_field_tasks IS
  'Bulk-generates today''s (Cairo) unified field tasks for every active sales rep. Idempotent, advisory-locked. For an admin or pg_cron daily trigger.';

REVOKE ALL ON FUNCTION public.generate_daily_field_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_daily_field_tasks() FROM anon;
REVOKE ALL ON FUNCTION public.generate_daily_field_tasks() FROM authenticated;
-- Intentionally NOT granted to authenticated — call as service role (Dashboard)
-- or wire to pg_cron. Reps use ensure_my_field_tasks() instead.

-- ---------------------------------------------------------------------------
-- Optional: schedule daily generation server-side (requires pg_cron extension).
-- Runs at 09:30 Cairo (07:30 UTC) so tasks exist before the 10:00 window.
-- ---------------------------------------------------------------------------
-- SELECT cron.schedule(
--   'generate-daily-field-tasks',
--   '30 7 * * *',
--   $cron$ SELECT public.generate_daily_field_tasks(); $cron$
-- );

-- ============================================================================
-- End of 019_task_templates_and_daily_generation.sql
-- ============================================================================
