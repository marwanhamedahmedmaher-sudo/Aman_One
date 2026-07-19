-- ============================================================================
-- 036_plan_review_fixes.sql — CodeRabbit review follow-ups on 035 (PR #28).
--
--   1. ensure_my_week_field_tasks(p_week_start): the client override let any
--      authenticated rep generate field_tasks for an ARBITRARY week. Guard it —
--      a non-NULL p_week_start must equal the current cycle's plan_week_start().
--   2. remove_plan_item(): add the role='sales_rep' + status='active' checks
--      that add_plan_item already has (a deactivated rep could still delete
--      their planned stops). Parity with add_plan_item / record_task_visit.
--
-- Forward-only correction — 035 stays as-applied; this supersedes both funcs.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ensure_my_week_field_tasks() — reject an out-of-cycle p_week_start.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_my_week_field_tasks(p_week_start date DEFAULT NULL)
RETURNS date   -- the Friday the generated week starts on
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _rep_id      uuid;
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

  -- The override is only allowed to name the CURRENT cycle's Friday — reps
  -- cannot pre-generate tasks for arbitrary past/future weeks.
  IF p_week_start IS NOT NULL AND p_week_start <> public.plan_week_start() THEN
    RAISE EXCEPTION 'لا يمكن توليد مهام لأسبوع آخر' USING ERRCODE = '42501';
  END IF;

  _week_start := COALESCE(p_week_start, public.plan_week_start());

  -- Generate Fri..Thu (7 days) × the 3 windows. Idempotent per day.
  FOR _i IN 0..6 LOOP
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

REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_week_field_tasks(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. remove_plan_item() — add role/active parity with add_plan_item().
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.remove_plan_item(p_plan_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _status    text;
  _role      text;
  _item      record;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Planning window: edits (including deletes) only inside Thu 18:00 → Fri 14:00.
  PERFORM public.assert_planning_window_open();

  -- Sales-rep-only, active (parity with add_plan_item / record_task_visit).
  SELECT status, role INTO _status, _role
  FROM public.users WHERE id = _caller_id;

  IF _role IS DISTINCT FROM 'sales_rep' THEN
    RAISE EXCEPTION 'التخطيط متاح لمناديب المبيعات فقط' USING ERRCODE = '42501';
  END IF;
  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501';
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

REVOKE ALL ON FUNCTION public.remove_plan_item(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_plan_item(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_plan_item(uuid) TO authenticated;

-- ============================================================================
-- End of 036_plan_review_fixes.sql
-- ============================================================================
