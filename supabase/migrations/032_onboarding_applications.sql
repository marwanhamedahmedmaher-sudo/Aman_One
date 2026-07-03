-- ============================================================================
-- 032_onboarding_applications.sql — Resumable onboarding (draft + autosave)
-- ============================================================================
-- The in-progress onboarding wizard is a first-class, RESUMABLE object that is
-- decoupled from the committed `merchants` row. A draft is, by nature, messy
-- and invalid (no NID yet, no products chosen) — it must NOT live in
-- `merchants`, whose triggers hard-reject incomplete identity. So the live
-- wizard state lives here as JSONB and is only materialized into normalized
-- rows (merchant + kyc/kyb + products + documents) on submit (see migration 036).
--
-- LIFECYCLE: draft -> submitted -> in_review -> approved | rejected (| cancelled)
-- AUTOSAVE:  the app UPSERTs `payload` + `current_step` on every wizard step,
--            so a rep can exit and resume exactly where they left off (a
--            "drafts" list on home loads status='draft' rows for the rep).
--
-- Additive + self-contained -> safe to apply to a live database.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.onboarding_applications (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by    uuid        NOT NULL REFERENCES auth.users(id),
  merchant_id   uuid        REFERENCES public.merchants(id) ON DELETE SET NULL,
  track         text        NOT NULL DEFAULT 'individual'
                            CHECK (track IN ('individual', 'company')),
  nationality   text        NOT NULL DEFAULT 'egyptian'
                            CHECK (nationality IN ('egyptian', 'foreigner')),
  status        text        NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','submitted','in_review','approved','rejected','cancelled')),
  current_step  int         NOT NULL DEFAULT 0,        -- resume point
  payload       jsonb       NOT NULL DEFAULT '{}'::jsonb, -- live wizard working state
  submitted_at  timestamptz,
  decided_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

COMMENT ON TABLE  public.onboarding_applications IS
  'Resumable onboarding wizard state. One row per onboarding attempt. Draft rows hold the live JSONB payload + current_step for exit/resume; finalized rows link to the materialized merchant_id (see submit_application, migration 036).';
COMMENT ON COLUMN public.onboarding_applications.current_step IS 'Wizard step the rep last reached — the resume point.';
COMMENT ON COLUMN public.onboarding_applications.payload IS 'Live wizard state (track, kyc, products[], documents[]). Source of truth ONLY while status=draft; after submit the normalized tables are authoritative.';

-- Composite serves the only documented query (rep's own drafts list) — a bare
-- status index over all reps' rows would never beat it and is pure write cost.
CREATE INDEX IF NOT EXISTS idx_onb_app_owner_status ON public.onboarding_applications(created_by, status);
CREATE INDEX IF NOT EXISTS idx_onb_app_merchant     ON public.onboarding_applications(merchant_id);

DROP TRIGGER IF EXISTS trg_onb_app_updated_at ON public.onboarding_applications;
CREATE TRIGGER trg_onb_app_updated_at
  BEFORE UPDATE ON public.onboarding_applications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: a rep owns their own applications; admins see all.
-- ---------------------------------------------------------------------------
ALTER TABLE public.onboarding_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS onb_app_select ON public.onboarding_applications;
CREATE POLICY onb_app_select ON public.onboarding_applications
  FOR SELECT TO authenticated
  USING (deleted_at IS NULL AND (created_by = auth.uid() OR public.is_admin()));

DROP POLICY IF EXISTS onb_app_insert ON public.onboarding_applications;
CREATE POLICY onb_app_insert ON public.onboarding_applications
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Reps may edit ONLY their own DRAFT rows, and cannot move a row out of
-- 'draft' via direct UPDATE (WITH CHECK pins status). Every lifecycle
-- transition (draft -> submitted, decisions) goes through the SECURITY
-- DEFINER RPC (submit_application, migration 036) or an admin — otherwise a
-- rep could PATCH status='approved' / decided_at on their own application.
DROP POLICY IF EXISTS onb_app_update ON public.onboarding_applications;
CREATE POLICY onb_app_update ON public.onboarding_applications
  FOR UPDATE TO authenticated
  USING (public.is_admin() OR (created_by = auth.uid() AND status = 'draft'))
  WITH CHECK (public.is_admin() OR (created_by = auth.uid() AND status = 'draft'));

-- Reps may hard-delete only abandoned DRAFTS; submitted/decided applications
-- are part of the review record and can only be removed by an admin.
DROP POLICY IF EXISTS onb_app_delete ON public.onboarding_applications;
CREATE POLICY onb_app_delete ON public.onboarding_applications
  FOR DELETE TO authenticated
  USING (public.is_admin() OR (created_by = auth.uid() AND status = 'draft'));

-- ============================================================================
-- End of 032_onboarding_applications.sql
-- ============================================================================
