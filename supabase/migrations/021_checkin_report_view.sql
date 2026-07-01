-- ============================================================================
-- 021_checkin_report_view.sql — One-line location report for supervisors
--
-- v_checkin_report flattens task_checkins + field_tasks + users into a single
-- Arabic-headed, ready-to-export view. The supervisor runs ONE line in the
-- Supabase SQL Editor → Download CSV:
--     SELECT * FROM public.v_checkin_report;
-- Each row carries a clickable Google Maps link to the rep's check-in pin.
--
-- security_invoker = true → the view runs with the QUERYING user's RLS, so:
--   * Dashboard / service role → sees all reps (full report).
--   * supervisor / admin       → sees all (oversight policy on the base tables).
--   * a sales rep              → sees only their own check-ins.
-- No data leaks beyond what RLS already allows on the underlying tables.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_checkin_report
WITH (security_invoker = true) AS
SELECT
  u.name                                                            AS "اسم المندوب",
  u.employee_id                                                     AS "رقم الموظف",
  u.region                                                          AS "المنطقة",
  ft.title                                                          AS "المهمة",
  ft.task_date                                                      AS "التاريخ",
  to_char(ft.window_start AT TIME ZONE 'Africa/Cairo', 'HH24:MI')
    || ' - ' ||
  to_char(ft.window_end   AT TIME ZONE 'Africa/Cairo', 'HH24:MI')   AS "الوقت المحدد",
  to_char(tc.recorded_at  AT TIME ZONE 'Africa/Cairo', 'HH24:MI')   AS "وقت التسجيل",
  CASE WHEN tc.in_window THEN 'في الموعد' ELSE 'خارج الموعد' END     AS "الالتزام",
  tc.lat                                                            AS "خط العرض",
  tc.lng                                                            AS "خط الطول",
  'https://maps.google.com/?q=' || tc.lat || ',' || tc.lng          AS "رابط الخريطة",
  round(tc.accuracy_m)                                              AS "الدقة (متر)",
  tc.recorded_at                                                    AS "recorded_at_utc"
FROM public.task_checkins tc
JOIN public.field_tasks ft ON ft.id = tc.task_id
JOIN public.users u        ON u.id = tc.rep_id;

COMMENT ON VIEW public.v_checkin_report IS
  'Supervisor location report: one row per task check-in with a Google Maps link. security_invoker — respects base-table RLS. SELECT * FROM public.v_checkin_report ORDER BY recorded_at_utc DESC;';

-- Readable by authenticated users (RLS on base tables still scopes the rows).
-- Dashboard/service-role bypasses RLS for the full cross-rep report.
GRANT SELECT ON public.v_checkin_report TO authenticated;

-- ============================================================================
-- End of 021_checkin_report_view.sql
-- ============================================================================
