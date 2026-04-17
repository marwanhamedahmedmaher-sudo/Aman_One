-- Migration 014: Pin task distribution to Cairo timezone (UTC+2)
-- Supabase uses UTC for CURRENT_DATE; Egypt reps need day boundaries at midnight Cairo time.

-- Update assigned_date default to Cairo date
ALTER TABLE public.task_assignments
  ALTER COLUMN assigned_date SET DEFAULT (now() AT TIME ZONE 'Africa/Cairo')::date;

-- Replace distribute_daily_tasks() to use Cairo timezone throughout
CREATE OR REPLACE FUNCTION public.distribute_daily_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _cairo_today date;
  _reps        uuid[];
  _rep_count   int;
  _lead        record;
  _idx         int := 0;
BEGIN
  -- Must be authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  -- Fast path: already distributed today (Cairo)?
  IF EXISTS (
    SELECT 1 FROM public.task_assignments
    WHERE assigned_date = _cairo_today
    LIMIT 1
  ) THEN
    RETURN;
  END IF;

  -- Advisory lock to prevent race conditions
  PERFORM pg_advisory_xact_lock(8675309);

  -- Re-check after lock (double-checked locking)
  IF EXISTS (
    SELECT 1 FROM public.task_assignments
    WHERE assigned_date = _cairo_today
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
      (_lead.id, _reps[(_idx % _rep_count) + 1], _cairo_today, 'pending');
    _idx := _idx + 1;
  END LOOP;
END;
$$;
