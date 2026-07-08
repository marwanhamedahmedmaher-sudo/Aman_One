-- ============================================================================
-- 033_plan_hardening.sql — two low-severity hardening fixes on 032
--
-- #5  ensure_my_week_field_tasks(p_week_start): the passed date was used
--     verbatim, so a rep calling the RPC directly with a mid-week date could
--     generate an off-week / weekend-spanning block in their own task list.
--     Fix: snap any provided date back to its week's Sunday (DOW 0).
--
-- #6  add_plan_item: no task-status guard, so a rep could add a 'planned' stop
--     to an already-'completed' task. Fix: reject when the task is completed.
--
-- Both are CREATE OR REPLACE (unchanged signatures — no DROP, no dependency
-- churn). Everything else in each function is identical to migration 032.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- #5 — snap p_week_start to Sunday
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_my_week_field_tasks(p_week_start date DEFAULT NULL)
RETURNS date
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

  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = _rep_id AND status = 'active' AND role = 'sales_rep'
  ) THEN
    RETURN NULL;
  END IF;

  _cairo_today := (now() AT TIME ZONE 'Africa/Cairo')::date;

  IF p_week_start IS NOT NULL THEN
    -- Snap any provided date back to its week's Sunday (DOW 0), so a mid-week
    -- arg can't produce an off-week / weekend-spanning block.
    _week_start := p_week_start - EXTRACT(DOW FROM p_week_start)::int;
  ELSE
    _dow := EXTRACT(DOW FROM _cairo_today)::int;
    IF _dow IN (5, 6) THEN            -- Fri / Sat → upcoming Sunday
      _week_start := _cairo_today + (7 - _dow);
    ELSE                             -- Sun..Thu → this week's Sunday
      _week_start := _cairo_today - _dow;
    END IF;
  END IF;

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

-- ---------------------------------------------------------------------------
-- #6 — reject planning against a completed task
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

  SELECT status, role INTO _status, _role
  FROM public.users WHERE id = _caller_id;

  IF _role IS DISTINCT FROM 'sales_rep' THEN
    RAISE EXCEPTION 'التخطيط متاح لمناديب المبيعات فقط' USING ERRCODE = '42501';
  END IF;
  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _task
  FROM public.field_tasks
  WHERE id = p_task_id AND assigned_to = _caller_id;

  IF _task.id IS NULL THEN
    RAISE EXCEPTION 'المهمة غير موجودة أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  -- Don't plan against a task the rep already finished.
  IF _task.status = 'completed' THEN
    RAISE EXCEPTION 'لا يمكن التخطيط لمهمة مكتملة' USING ERRCODE = '23514';
  END IF;

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

-- ============================================================================
-- End of 033_plan_hardening.sql
-- ============================================================================
