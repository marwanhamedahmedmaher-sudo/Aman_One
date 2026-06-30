-- ============================================================================
-- 023_aman_branches.sql — Aman branch lookup (mission 3 dropdown source)
--
-- Mission 3 ("زيارة فرع أمان القريب") asks the rep which branch they visited.
-- This is the dropdown source. Admin-managed (Dashboard Table Editor), same
-- posture as activity_types / governorates.
--
-- NOTE: intentionally NOT seeded here — the real branch list is supplied by
-- ops (Marwan) and loaded via the Dashboard or scripts/seed_aman_branches.sh.
-- The mission-3 dropdown is empty until then; the rest of the feature works.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.aman_branches (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar        text        NOT NULL,
  governorate_id smallint    REFERENCES public.governorates(id),
  active         boolean     NOT NULL DEFAULT true,
  sort_order     smallint    NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.aman_branches                IS 'Aman branches for the mission-3 visit dropdown. Admin-managed via Dashboard. Seeded out-of-band by ops.';
COMMENT ON COLUMN public.aman_branches.governorate_id IS 'Optional governorate the branch sits in (FK to governorates).';
COMMENT ON COLUMN public.aman_branches.active         IS 'Only active branches appear in the rep dropdown.';

CREATE INDEX IF NOT EXISTS idx_aman_branches_active ON public.aman_branches(active);

ALTER TABLE public.aman_branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS aman_branches_select ON public.aman_branches;
CREATE POLICY aman_branches_select ON public.aman_branches
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS aman_branches_admin_insert ON public.aman_branches;
CREATE POLICY aman_branches_admin_insert ON public.aman_branches
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS aman_branches_admin_update ON public.aman_branches;
CREATE POLICY aman_branches_admin_update ON public.aman_branches
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS aman_branches_admin_delete ON public.aman_branches;
CREATE POLICY aman_branches_admin_delete ON public.aman_branches
  FOR DELETE USING (public.is_admin());

-- ============================================================================
-- End of 023_aman_branches.sql
-- ============================================================================
