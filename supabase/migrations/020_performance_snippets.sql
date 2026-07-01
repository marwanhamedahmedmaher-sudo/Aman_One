-- ============================================================================
-- 020_performance_snippets.sql — Supervisor performance-tracking queries
-- Field-task check-in compliance, punctuality, location, and output.
-- Copy-paste snippets for Supabase SQL Editor → "Run" → "Download CSV".
-- ============================================================================
--
-- USAGE:
--   1. Open Supabase Dashboard → SQL Editor
--   2. Paste one of the snippets below (without the /* */ comment markers)
--   3. Click "Run"  →  "Download CSV" in the results pane
--
-- Run as the Dashboard (service role) — bypasses RLS, so the supervisor sees
-- all reps. Column headers are Arabic. All times shown in Cairo local.
--
-- "On-time" is STRICT: a check-in counts as on-time only when in_window = true
-- (recorded_at fell between the task's window_start and window_end). A fix
-- taken even one minute after window_end is "خارج الموعد".
-- ============================================================================


-- ============================================================================
-- SNIPPET 1: اليوم — متابعة المناديب (today's compliance board)
-- One row per rep × window for the current Cairo day.
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  u.name          AS "اسم المندوب",
  u.employee_id   AS "رقم الموظف",
  ft.title        AS "المهمة",
  to_char(ft.window_start AT TIME ZONE 'Africa/Cairo', 'HH24:MI')
    || ' - ' ||
  to_char(ft.window_end   AT TIME ZONE 'Africa/Cairo', 'HH24:MI')   AS "الوقت المحدد",
  CASE
    WHEN tc.task_id IS NULL THEN 'لم يسجل'
    WHEN tc.in_window        THEN 'في الموعد'
    ELSE 'خارج الموعد'
  END                                                               AS "الحالة",
  to_char(tc.recorded_at AT TIME ZONE 'Africa/Cairo', 'HH24:MI')    AS "وقت التسجيل"
FROM public.field_tasks ft
JOIN public.users u            ON u.id = ft.assigned_to
LEFT JOIN public.task_checkins tc ON tc.task_id = ft.id
WHERE ft.task_date = (now() AT TIME ZONE 'Africa/Cairo')::date
ORDER BY u.name, ft.window_start;
*/


-- ============================================================================
-- SNIPPET 2: الأسبوع — ملخص الأداء (weekly performance summary, per rep)
-- Coverage %, strict on-time %, missed windows, and leads produced.
-- Covers the last 7 Cairo days.
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  u.name        AS "اسم المندوب",
  u.employee_id AS "رقم الموظف",
  u.region      AS "المنطقة",
  count(ft.id)                                          AS "إجمالي المهام",
  count(tc.task_id)                                     AS "تم التسجيل",
  count(tc.task_id) FILTER (WHERE tc.in_window)         AS "في الموعد",
  count(ft.id) - count(tc.task_id)                      AS "مهام فائتة",
  round(100.0 * count(tc.task_id) / NULLIF(count(ft.id), 0))                      AS "نسبة التغطية %",
  round(100.0 * count(tc.task_id) FILTER (WHERE tc.in_window)
        / NULLIF(count(tc.task_id), 0))                                           AS "نسبة الالتزام بالموعد %",
  (SELECT count(*)
   FROM public.merchants m
   WHERE m.created_by = u.id
     AND m.deleted_at IS NULL
     AND m.created_at >= (now() AT TIME ZONE 'Africa/Cairo')::date - interval '6 days')
                                                         AS "عملاء هذا الأسبوع"
FROM public.field_tasks ft
JOIN public.users u            ON u.id = ft.assigned_to
LEFT JOIN public.task_checkins tc ON tc.task_id = ft.id
WHERE ft.task_date >= (now() AT TIME ZONE 'Africa/Cairo')::date - interval '6 days'
GROUP BY u.id, u.name, u.employee_id, u.region
ORDER BY (count(tc.task_id)::numeric / NULLIF(count(ft.id), 0)) DESC NULLS LAST;
*/


-- ============================================================================
-- SNIPPET 3: سجل المواقع (check-in location log, with map links)
-- Each check-in with a clickable Google Maps link to verify the location.
-- Covers the last 7 Cairo days.
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  to_char(tc.recorded_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM-DD HH24:MI') AS "التاريخ والوقت",
  u.name        AS "اسم المندوب",
  u.employee_id AS "رقم الموظف",
  ft.title      AS "المهمة",
  CASE WHEN tc.in_window THEN 'في الموعد' ELSE 'خارج الموعد' END             AS "الالتزام",
  tc.lat        AS "خط العرض",
  tc.lng        AS "خط الطول",
  'https://maps.google.com/?q=' || tc.lat || ',' || tc.lng                  AS "رابط الخريطة",
  round(tc.accuracy_m)                                                      AS "الدقة (متر)"
FROM public.task_checkins tc
JOIN public.field_tasks ft ON ft.id = tc.task_id
JOIN public.users u        ON u.id = tc.rep_id
WHERE tc.recorded_at >= (now() AT TIME ZONE 'Africa/Cairo')::date - interval '6 days'
ORDER BY tc.recorded_at DESC;
*/


-- ============================================================================
-- SNIPPET 4: المهام الفائتة اليوم (today's missed windows — follow-up list)
-- Reps who did NOT check in for a window whose end time has already passed.
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  u.name          AS "اسم المندوب",
  u.employee_id   AS "رقم الموظف",
  u.region        AS "المنطقة",
  ft.title        AS "المهمة الفائتة",
  to_char(ft.window_start AT TIME ZONE 'Africa/Cairo', 'HH24:MI')
    || ' - ' ||
  to_char(ft.window_end   AT TIME ZONE 'Africa/Cairo', 'HH24:MI')   AS "الوقت المحدد"
FROM public.field_tasks ft
JOIN public.users u ON u.id = ft.assigned_to
LEFT JOIN public.task_checkins tc ON tc.task_id = ft.id
WHERE ft.task_date = (now() AT TIME ZONE 'Africa/Cairo')::date
  AND tc.task_id IS NULL          -- never checked in
  AND ft.window_end < now()       -- and the window has already closed
ORDER BY u.name, ft.window_start;
*/


-- ============================================================================
-- End of 020_performance_snippets.sql
-- ============================================================================
