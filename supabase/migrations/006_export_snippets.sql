-- ============================================================================
-- 006_export_snippets.sql — Admin CSV export queries
-- P0-17: Copy-paste snippets for Supabase SQL Editor → "Run" → "Download CSV"
-- ============================================================================
--
-- USAGE:
--   1. Open Supabase Dashboard → SQL Editor
--   2. Paste one of the snippets below (without the comment markers)
--   3. Click "Run"
--   4. Click "Download CSV" in the results pane
--
-- Column headers are in Arabic for business stakeholders.
-- Queries join with public.users to include rep name.
-- ============================================================================


-- ============================================================================
-- SNIPPET 1: All active leads (not deleted, last 90 days)
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  m.name              AS "اسم التاجر",
  m.phone             AS "رقم الموبايل",
  m.national_id       AS "الرقم القومي",
  m.notes             AS "ملاحظات",
  m.status            AS "الحالة",
  u.name              AS "اسم المندوب",
  u.employee_id       AS "رقم الموظف",
  m.created_at        AS "تاريخ التسجيل"
FROM public.merchants m
JOIN public.users u ON u.id = m.created_by
WHERE m.deleted_at IS NULL
  AND m.created_at >= now() - interval '90 days'
ORDER BY m.created_at DESC;
*/


-- ============================================================================
-- SNIPPET 2: Leads created in the last 30 days
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  m.name              AS "اسم التاجر",
  m.phone             AS "رقم الموبايل",
  m.national_id       AS "الرقم القومي",
  m.notes             AS "ملاحظات",
  m.status            AS "الحالة",
  u.name              AS "اسم المندوب",
  u.employee_id       AS "رقم الموظف",
  m.created_at        AS "تاريخ التسجيل"
FROM public.merchants m
JOIN public.users u ON u.id = m.created_by
WHERE m.deleted_at IS NULL
  AND m.created_at >= now() - interval '30 days'
ORDER BY m.created_at DESC;
*/


-- ============================================================================
-- SNIPPET 3: Leads grouped by rep with counts
-- ============================================================================
-- Copy from here ↓

/*
SELECT
  u.name                          AS "اسم المندوب",
  u.employee_id                   AS "رقم الموظف",
  u.region                        AS "المنطقة",
  count(*)                        AS "إجمالي التجار",
  count(*) FILTER (WHERE m.status = 'lead')       AS "عملاء محتملين",
  count(*) FILTER (WHERE m.status = 'qualified')   AS "مؤهلين",
  count(*) FILTER (WHERE m.status = 'converted')   AS "محولين",
  count(*) FILTER (WHERE m.status = 'rejected')    AS "مرفوضين",
  min(m.created_at)               AS "أول تسجيل",
  max(m.created_at)               AS "آخر تسجيل"
FROM public.merchants m
JOIN public.users u ON u.id = m.created_by
WHERE m.deleted_at IS NULL
GROUP BY u.id, u.name, u.employee_id, u.region
ORDER BY count(*) DESC;
*/


-- ============================================================================
-- SNIPPET 4: Full audit dump for a date range
-- ============================================================================
-- Replace the two dates below before running:
--   $1 = start date (e.g., '2026-04-01')
--   $2 = end date   (e.g., '2026-04-30')
-- Copy from here ↓

/*
SELECT
  a.created_at        AS "التاريخ",
  u.name              AS "اسم المندوب",
  u.employee_id       AS "رقم الموظف",
  a.action            AS "الإجراء",
  a.table_name        AS "الجدول",
  a.record_id         AS "رقم السجل",
  a.old_data          AS "البيانات القديمة",
  a.new_data          AS "البيانات الجديدة"
FROM public.audit_log a
JOIN public.users u ON u.id = a.actor_id
WHERE a.created_at >= '2026-04-01'::timestamptz   -- ← change start date
  AND a.created_at <  '2026-04-30'::timestamptz   -- ← change end date
ORDER BY a.created_at DESC;
*/


-- ============================================================================
-- End of 006_export_snippets.sql
-- ============================================================================
