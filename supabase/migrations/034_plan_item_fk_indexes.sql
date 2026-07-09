-- ============================================================================
-- 034_plan_item_fk_indexes.sql — supporting indexes for task_plan_items FKs
--
-- task_plan_items already indexes task_id / rep_id / status (migration 032).
-- Its three remaining foreign keys were unindexed:
--   * governorate_id → governorates   (joined by the fetchPlanItems embed)
--   * branch_id      → aman_branches   (joined by the fetchPlanItems embed)
--   * visit_id       → task_visits (ON DELETE SET NULL) — without this index a
--     delete of a task_visits row seq-scans task_plan_items to null the FK.
-- Matches the project guideline: new FK columns get supporting indexes, and
-- keeps Supabase's "unindexed foreign keys" performance advisor clean.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_task_plan_items_governorate_id
  ON public.task_plan_items(governorate_id);

CREATE INDEX IF NOT EXISTS idx_task_plan_items_branch_id
  ON public.task_plan_items(branch_id);

CREATE INDEX IF NOT EXISTS idx_task_plan_items_visit_id
  ON public.task_plan_items(visit_id);

-- ============================================================================
-- End of 034_plan_item_fk_indexes.sql
-- ============================================================================
