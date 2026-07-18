-- ============================================================================
-- 035_weekend_plan_and_window.sql — Weekend planning + Thu-reset planning window
--
-- Supervisor request (2026-07-18):
--   1. The weekly plan now covers WEEKENDS too — a full 7-day cycle, not the
--      old Sun–Thu (5 working days).
--   2. The cycle RESETS every Thursday at 18:00 Cairo. The 7 days it covers are
--      Friday → Thursday (the day after the reset through the next reset).
--   3. Reps may only build/edit the plan inside the PLANNING WINDOW:
--      Thursday 18:00 → Friday 14:00 Cairo. Outside it, add/remove are refused
--      server-side (hard lock).
--
-- Execution (record_task_visit) is deliberately NOT windowed — visits happen
-- all week; only *planning* edits are gated. The daily generator
-- (ensure_my_field_tasks, migration 019) was never DOW-gated, so logging visits
-- on Fri/Sat already worked; this migration only extends the *planning* layer.
--
-- Single-sources the cycle anchor in plan_week_start() so the generator and the
-- window gate can never disagree.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. plan_week_start() — the Friday that begins the current Fri→Thu cycle.
--    The cycle rolls over at Thursday 18:00 Cairo: find the most-recent
--    Thursday 18:00 <= now, the cycle's first day is that Thursday + 1 (Friday).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.plan_week_start(p_now timestamptz DEFAULT now())
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  _ts        timestamp;   -- Cairo wall clock (no tz)
  _last_thu  date;        -- most-recent Thursday on/before today (Cairo)
  _reset     timestamp;   -- that Thursday at 18:00
BEGIN
  _ts := p_now AT TIME ZONE 'Africa/Cairo';
  -- dow: 0=Sun..6=Sat. Thursday = 4. Days since the last Thursday:
  _last_thu := (_ts::date) - (((EXTRACT(DOW FROM _ts)::int - 4 + 7) % 7));
  _reset    := _last_thu::timestamp + interval '18 hours';
  -- If today IS Thursday but before 18:00, the reset hasn't happened yet — we
  -- are still in the previous cycle, so step back a week.
  IF _reset > _ts THEN
    _last_thu := _last_thu - 7;
  END IF;
  RETURN _last_thu + 1;   -- Friday = the cycle's first day
END;
$$;

COMMENT ON FUNCTION public.plan_week_start IS
  'The Friday that begins the current Fri→Thu weekly-plan cycle. Cycle resets Thursday 18:00 Cairo. Single source of truth for the generator and the planning-window gate.';

REVOKE ALL ON FUNCTION public.plan_week_start(timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.plan_week_start(timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.plan_week_start(timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. ensure_my_week_field_tasks() — pre-generate the FULL week (Fri→Thu × 3
--    windows). Anchored on plan_week_start(). Idempotent (same ON CONFLICT as
--    migration 019/032). Returns the week's Friday so the app knows the range.
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

COMMENT ON FUNCTION public.ensure_my_week_field_tasks IS
  'Pre-generates the full weekly cycle (Fri–Thu × 3 windows) of field tasks for the calling active rep. Anchored on plan_week_start() (cycle resets Thu 18:00 Cairo). Idempotent. p_week_start overrides the auto-computed Friday. Returns the week''s Friday. Called when the weekly-planning screen opens.';

REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_my_week_field_tasks(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_week_field_tasks(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Planning-window gate, reused by add_plan_item() and remove_plan_item().
--    Window = Thu 18:00 → Fri 14:00 Cairo = [week_start − 6h, week_start + 14h).
--    RAISEs '42501' with an Arabic message when the window is closed.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_planning_window_open()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  _ws  date;
  _now timestamp;   -- Cairo wall clock
BEGIN
  _ws  := public.plan_week_start();
  _now := (now() AT TIME ZONE 'Africa/Cairo');
  IF _now <  (_ws::timestamp - interval '6 hours')
     OR _now >= (_ws::timestamp + interval '14 hours') THEN
    RAISE EXCEPTION 'التخطيط متاح فقط من الخميس ٦ مساءً حتى الجمعة ٢ ظهراً'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_planning_window_open IS
  'Raises 42501 (Arabic) unless now is within the planning window: Thu 18:00 → Fri 14:00 Cairo, for the current plan_week_start() cycle.';

REVOKE ALL ON FUNCTION public.assert_planning_window_open() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_planning_window_open() FROM anon;
GRANT EXECUTE ON FUNCTION public.assert_planning_window_open() TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. add_plan_item() — now window-gated + cycle-scoped. Body otherwise
--    identical to migration 032 (rep-only, active, owns the task).
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
  _ws        date;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  -- Planning window: Thu 18:00 → Fri 14:00 Cairo (hard lock).
  PERFORM public.assert_planning_window_open();

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

  -- Belt-and-suspenders: only the current cycle's days (Fri..Thu) are plannable.
  _ws := public.plan_week_start();
  IF _task.task_date IS NULL OR _task.task_date < _ws OR _task.task_date > _ws + 6 THEN
    RAISE EXCEPTION 'لا يمكن التخطيط لهذا اليوم خارج الأسبوع الحالي' USING ERRCODE = '23514';
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

REVOKE ALL ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.add_plan_item(uuid, smallint, text, text, text, text[], text, text, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. remove_plan_item() — now window-gated too. Body otherwise identical to
--    migration 032 (owner-only, refuses once executed).
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

  -- Planning window: edits (including deletes) only inside Thu 18:00 → Fri 14:00.
  PERFORM public.assert_planning_window_open();

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
-- End of 035_weekend_plan_and_window.sql
-- ============================================================================
