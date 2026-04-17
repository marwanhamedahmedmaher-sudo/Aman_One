-- Migration 015: Auto-refill RPC — gives a rep new tasks when they finish their batch
-- Assigns pool leads they haven't been assigned today (Cairo time).
-- Idempotent: no-ops if rep still has pending tasks or pool is exhausted.

CREATE OR REPLACE FUNCTION public.refill_rep_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _cairo_today date;
  _rep_id      uuid;
  _lead        record;
BEGIN
  _rep_id := auth.uid();
  IF _rep_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  -- Only refill if rep has 0 pending tasks today
  IF EXISTS (
    SELECT 1 FROM public.task_assignments
    WHERE assigned_to = _rep_id
      AND assigned_date = _cairo_today
      AND status = 'pending'
    LIMIT 1
  ) THEN
    RETURN;
  END IF;

  -- Assign pool leads NOT already given to this rep today
  FOR _lead IN
    SELECT csp.id
    FROM public.cross_sell_pool csp
    WHERE NOT EXISTS (
      SELECT 1 FROM public.task_assignments ta
      WHERE ta.pool_lead_id = csp.id
        AND ta.assigned_to = _rep_id
        AND ta.assigned_date = _cairo_today
    )
    ORDER BY random()
  LOOP
    INSERT INTO public.task_assignments
      (pool_lead_id, assigned_to, assigned_date, status)
    VALUES
      (_lead.id, _rep_id, _cairo_today, 'pending');
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.refill_rep_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.refill_rep_tasks() FROM anon;
GRANT EXECUTE ON FUNCTION public.refill_rep_tasks() TO authenticated;
