-- Migration 016: finish Cairo-timezone migration for task_assignments.
-- 014 switched the default and distribute_daily_tasks() to Cairo, but the
-- UPDATE RLS policy still compared assigned_date to CURRENT_DATE (UTC),
-- which would block reps between Cairo midnight and UTC midnight.
-- Also gate the audit trigger so no-op UPDATEs don't write a full-row JSON copy.

-- Rep UPDATE policy: use Cairo date
DROP POLICY IF EXISTS task_assignments_update ON public.task_assignments;

CREATE POLICY task_assignments_update ON public.task_assignments
  FOR UPDATE
  USING (
    (assigned_to = auth.uid()
     AND assigned_date = (now() AT TIME ZONE 'Africa/Cairo')::date)
    OR public.is_admin()
  )
  WITH CHECK (
    (assigned_to = auth.uid()
     AND assigned_date = (now() AT TIME ZONE 'Africa/Cairo')::date)
    OR public.is_admin()
  );

-- Audit trigger: only fire when status or converted_merchant_id actually changes.
-- Reps tap into the screen repeatedly; without this guard every reload can
-- trigger full to_jsonb(OLD/NEW) inserts into audit_log.
DROP TRIGGER IF EXISTS trg_task_assignments_audit_update ON public.task_assignments;

CREATE TRIGGER trg_task_assignments_audit_update
  AFTER UPDATE ON public.task_assignments
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status
        OR OLD.converted_merchant_id IS DISTINCT FROM NEW.converted_merchant_id
        OR OLD.outcome_notes IS DISTINCT FROM NEW.outcome_notes)
  EXECUTE FUNCTION public.audit_task_assignments_change();
