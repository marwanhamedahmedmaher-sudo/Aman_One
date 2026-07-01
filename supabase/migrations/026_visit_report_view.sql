-- ============================================================================
-- 026_visit_report_view.sql — One-line visit report for supervisors
--
-- v_visit_report flattens task_visits + field_tasks + users + lookups into a
-- single Arabic-headed, ready-to-export view (parity with v_checkin_report,
-- migration 021). The supervisor runs ONE line in the SQL Editor → Download CSV:
--     SELECT * FROM public.v_visit_report ORDER BY recorded_at_utc DESC;
--
-- security_invoker = true → respects base-table RLS:
--   * Dashboard / service role → every rep.
--   * supervisor / admin       → every rep (oversight policy on task_visits).
--   * a sales rep              → only their own visits.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_visit_report
WITH (security_invoker = true) AS
SELECT
  u.name                                                            AS "اسم المندوب",
  u.employee_id                                                     AS "رقم الموظف",
  u.region                                                          AS "المنطقة",
  ft.title                                                          AS "المهمة",
  ft.task_date                                                      AS "التاريخ",
  CASE tv.template_slug
    WHEN 'gov_schools_hospitals'        THEN 'مؤسسات حكومية / مدارس'
    WHEN 'merchants_acceptance_finance' THEN 'تجار — Acceptance / تمويل'
    WHEN 'aman_branch_visit'            THEN 'فرع أمان'
    ELSE tv.template_slug
  END                                                               AS "نوع الزيارة",
  -- mission-specific identity, collapsed into one readable column
  COALESCE(
    tv.place_name,
    NULLIF(concat_ws(' - ', tv.merchant_name, tv.business_name), ''),
    b.name_ar
  )                                                                 AS "الجهة",
  CASE tv.place_kind
    WHEN 'school'          THEN 'مدرسة'
    WHEN 'gov_institution' THEN 'مؤسسة حكومية'
    ELSE NULL
  END                                                               AS "التصنيف",
  array_to_string(
    ARRAY(SELECT CASE p WHEN 'microfinance' THEN 'تمويل'
                        WHEN 'acceptance'  THEN 'Acceptance'
                        ELSE p END
          FROM unnest(tv.products) p), ' + ')                       AS "المنتجات",
  g.name_ar                                                         AS "المحافظة",
  tv.contacted_count                                                AS "عدد المتواصل معهم",
  tv.onboarded_count                                                AS "عدد المسجلين",
  to_char(tv.recorded_at AT TIME ZONE 'Africa/Cairo', 'HH24:MI')    AS "وقت الزيارة",
  CASE WHEN tv.in_window THEN 'في الموعد' ELSE 'خارج الموعد' END     AS "الالتزام",
  'https://maps.google.com/?q=' || tv.lat || ',' || tv.lng          AS "رابط الخريطة",
  tv.notes                                                          AS "ملاحظات",
  tv.photo_path                                                     AS "مسار الصورة",
  tv.recorded_at                                                    AS "recorded_at_utc"
FROM public.task_visits tv
JOIN public.field_tasks ft  ON ft.id = tv.task_id
JOIN public.users u         ON u.id  = tv.rep_id
LEFT JOIN public.governorates g ON g.id = tv.governorate_id
LEFT JOIN public.aman_branches b ON b.id = tv.branch_id;

COMMENT ON VIEW public.v_visit_report IS
  'Supervisor visit report: one row per logged field visit with governorate, counts, in/out-of-window, and a Google Maps link. security_invoker — respects base-table RLS. Supersedes v_checkin_report for the multi-visit flow.';

GRANT SELECT ON public.v_visit_report TO authenticated;

-- ============================================================================
-- End of 026_visit_report_view.sql
-- ============================================================================
