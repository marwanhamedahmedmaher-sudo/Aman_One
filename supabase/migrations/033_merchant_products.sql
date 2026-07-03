-- ============================================================================
-- 033_merchant_products.sql — Per-product enrollment with its own status
-- ============================================================================
-- One row per (merchant, product). Each enrollment carries its OWN lifecycle
-- status (pending -> approved -> active | rejected | suspended) and the
-- product-specific fields as TYPED columns (handover-friendly: the receiving
-- team can read the schema and report/risk-model on real columns). Product-
-- appropriateness is enforced by CHECKs that null out fields that don't apply.
--
-- Supersedes (keep during transition, deprecate after backfill):
--   merchants.products text[]              -> one merchant_products row/product
--   merchants.microfinance_amount          -> merchant_products.amount
--   merchants.acceptance_device_count      -> merchant_products.device_count
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.merchant_products (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  application_id  uuid        REFERENCES public.onboarding_applications(id) ON DELETE SET NULL,
  product         text        NOT NULL
                              CHECK (product IN ('Microfinance', 'Acceptance POS', 'BP POS')),
  status          text        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','approved','active','rejected','suspended')),

  -- Microfinance (a.k.a. "business financing" / تمويل المشروعات) fields
  amount          numeric     CHECK (amount IS NULL OR amount >= 0),
  loan_purpose    text,

  -- POS fields (shared by Acceptance POS + BP POS)
  device_type     text,
  device_count    int         CHECK (device_count IS NULL OR device_count >= 0),
  device_id       text,
  payment_service text,       -- Acceptance POS only (دفع / تقسيط)
  bill_service    text,       -- BP POS only (كهرباء / مياه / ...)

  decided_by      uuid        REFERENCES auth.users(id),
  decided_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (merchant_id, product)   -- one enrollment per product per merchant
);

COMMENT ON TABLE  public.merchant_products IS
  'Per-product enrollment for a merchant, each with an independent status. Replaces merchants.products[] and the per-product detail columns.';
COMMENT ON COLUMN public.merchant_products.status IS 'Independent product lifecycle: pending -> approved -> active | rejected | suspended.';

-- Keep product-irrelevant fields NULL (data hygiene + self-documenting shape).
ALTER TABLE public.merchant_products
  DROP CONSTRAINT IF EXISTS chk_mp_field_applicability;
ALTER TABLE public.merchant_products
  ADD CONSTRAINT chk_mp_field_applicability CHECK (
    CASE product
      WHEN 'Microfinance'   THEN device_type IS NULL AND device_count IS NULL
                              AND device_id IS NULL AND payment_service IS NULL
                              AND bill_service IS NULL
      WHEN 'Acceptance POS' THEN amount IS NULL AND loan_purpose IS NULL
                              AND bill_service IS NULL
      WHEN 'BP POS'         THEN amount IS NULL AND loan_purpose IS NULL
                              AND payment_service IS NULL
      ELSE true
    END
  );

-- UNIQUE (merchant_id, product) already indexes merchant_id lookups.
CREATE INDEX IF NOT EXISTS idx_mp_status      ON public.merchant_products(status);
CREATE INDEX IF NOT EXISTS idx_mp_application ON public.merchant_products(application_id);

DROP TRIGGER IF EXISTS trg_mp_updated_at ON public.merchant_products;
CREATE TRIGGER trg_mp_updated_at
  BEFORE UPDATE ON public.merchant_products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: scoped through the parent merchant's ownership.
-- ---------------------------------------------------------------------------
ALTER TABLE public.merchant_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mp_select ON public.merchant_products;
CREATE POLICY mp_select ON public.merchant_products
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m
                 WHERE m.id = merchant_id AND m.deleted_at IS NULL
                   AND (m.created_by = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS mp_insert ON public.merchant_products;
CREATE POLICY mp_insert ON public.merchant_products
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants m
                      WHERE m.id = merchant_id
                        AND (m.created_by = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS mp_update ON public.merchant_products;
CREATE POLICY mp_update ON public.merchant_products
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m
                 WHERE m.id = merchant_id
                   AND (m.created_by = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants m
                      WHERE m.id = merchant_id
                        AND (m.created_by = auth.uid() OR public.is_admin())));

-- (No DELETE policy: enrollments are cancelled via status='rejected'/'suspended',
--  not hard-deleted — preserves history. Add one if hard delete is ever needed.)

-- ============================================================================
-- End of 033_merchant_products.sql
-- ============================================================================
