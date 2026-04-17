-- Migration 013: Cross-sell daily task assignment system
-- Tables: cross_sell_pool (admin-managed), task_assignments (daily distribution)
-- RPC: distribute_daily_tasks() — idempotent, race-safe via advisory lock

-- ============================================================
-- Table A: cross_sell_pool — admin-managed lead pool
-- ============================================================

CREATE TABLE IF NOT EXISTS public.cross_sell_pool (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text        NOT NULL,
  phone       text        NOT NULL,
  notes       text        DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cross_sell_pool IS
  'Cross-sell lead pool. Admin-managed via Dashboard Table Editor. Redistributed daily to active reps.';

ALTER TABLE public.cross_sell_pool ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user (reps need to read joined pool data)
CREATE POLICY cross_sell_pool_select ON public.cross_sell_pool
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- INSERT/UPDATE/DELETE: admin only
CREATE POLICY cross_sell_pool_admin_insert ON public.cross_sell_pool
  FOR INSERT WITH CHECK (public.is_admin());

CREATE POLICY cross_sell_pool_admin_update ON public.cross_sell_pool
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY cross_sell_pool_admin_delete ON public.cross_sell_pool
  FOR DELETE USING (public.is_admin());


-- ============================================================
-- Table B: task_assignments — daily assignment records
-- ============================================================

CREATE TABLE IF NOT EXISTS public.task_assignments (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_lead_id          uuid        NOT NULL REFERENCES public.cross_sell_pool(id) ON DELETE CASCADE,
  assigned_to           uuid        NOT NULL REFERENCES auth.users(id),
  assigned_date         date        NOT NULL DEFAULT CURRENT_DATE,
  status                text        NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'completed', 'skipped')),
  outcome_notes         text        DEFAULT '',
  converted_merchant_id uuid        REFERENCES public.merchants(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),

  UNIQUE (pool_lead_id, assigned_to, assigned_date)
);

COMMENT ON TABLE public.task_assignments IS
  'Daily cross-sell task assignments. Created by distribute_daily_tasks() RPC. Reps update status.';
COMMENT ON COLUMN public.task_assignments.converted_merchant_id IS
  'FK to merchants — set when rep registers the lead as a new merchant.';

-- Indexes
CREATE INDEX idx_task_assignments_assigned_to_date
  ON public.task_assignments(assigned_to, assigned_date);

CREATE INDEX idx_task_assignments_assigned_date
  ON public.task_assignments(assigned_date);

CREATE INDEX idx_task_assignments_pool_lead_id
  ON public.task_assignments(pool_lead_id);

-- RLS
ALTER TABLE public.task_assignments ENABLE ROW LEVEL SECURITY;

-- SELECT: own rows or admin sees all
CREATE POLICY task_assignments_select ON public.task_assignments
  FOR SELECT
  USING (assigned_to = auth.uid() OR public.is_admin());

-- UPDATE: rep can update own today's tasks only; admin can update all
CREATE POLICY task_assignments_update ON public.task_assignments
  FOR UPDATE
  USING (
    (assigned_to = auth.uid() AND assigned_date = CURRENT_DATE)
    OR public.is_admin()
  )
  WITH CHECK (
    (assigned_to = auth.uid() AND assigned_date = CURRENT_DATE)
    OR public.is_admin()
  );

-- INSERT: NO client policy — distribution function uses SECURITY DEFINER

-- Triggers
CREATE TRIGGER trg_task_assignments_updated_at
  BEFORE UPDATE ON public.task_assignments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- Audit trigger for task_assignments
-- ============================================================

CREATE OR REPLACE FUNCTION public.audit_task_assignments_change()
RETURNS trigger AS $$
DECLARE
  _actor uuid;
BEGIN
  _actor := auth.uid();
  IF _actor IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _actor,
    TG_OP,
    'task_assignments',
    CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END,
    CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
    CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

CREATE TRIGGER trg_task_assignments_audit_update
  AFTER UPDATE ON public.task_assignments
  FOR EACH ROW EXECUTE FUNCTION public.audit_task_assignments_change();


-- ============================================================
-- RPC: distribute_daily_tasks()
-- Idempotent, race-safe via advisory lock + double-checked locking
-- ============================================================

CREATE OR REPLACE FUNCTION public.distribute_daily_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _reps       uuid[];
  _rep_count  int;
  _lead       record;
  _idx        int := 0;
BEGIN
  -- Must be authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Fast path: already distributed today?
  IF EXISTS (
    SELECT 1 FROM public.task_assignments
    WHERE assigned_date = CURRENT_DATE
    LIMIT 1
  ) THEN
    RETURN;
  END IF;

  -- Advisory lock to prevent race conditions
  PERFORM pg_advisory_xact_lock(8675309);

  -- Re-check after lock (double-checked locking)
  IF EXISTS (
    SELECT 1 FROM public.task_assignments
    WHERE assigned_date = CURRENT_DATE
    LIMIT 1
  ) THEN
    RETURN;
  END IF;

  -- Get active reps
  SELECT array_agg(id ORDER BY id)
  INTO _reps
  FROM public.users
  WHERE role = 'sales_rep' AND status = 'active';

  IF _reps IS NULL OR array_length(_reps, 1) = 0 THEN
    RETURN;
  END IF;

  _rep_count := array_length(_reps, 1);

  -- Distribute shuffled leads round-robin
  FOR _lead IN
    SELECT id FROM public.cross_sell_pool ORDER BY random()
  LOOP
    INSERT INTO public.task_assignments
      (pool_lead_id, assigned_to, assigned_date, status)
    VALUES
      (_lead.id, _reps[(_idx % _rep_count) + 1], CURRENT_DATE, 'pending');
    _idx := _idx + 1;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.distribute_daily_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.distribute_daily_tasks() FROM anon;
GRANT EXECUTE ON FUNCTION public.distribute_daily_tasks() TO authenticated;
