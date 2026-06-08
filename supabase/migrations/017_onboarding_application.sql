-- ============================================================================
-- 017_onboarding_application.sql
-- Unified merchant-onboarding payload (multi-step wizard covering all products:
-- Microfinance, Acceptance POS, BP POS).
-- ============================================================================
-- The wizard collects the merchant's KYC core ONCE (identity, business,
-- settlement) and appends per-product deltas + a deduped document set. The full
-- structured payload is stored as JSONB next to the merchant row:
--   {
--     "track": "individual|company",
--     "kyc":   { ...shared identity / business / settlement fields... },
--     "products": [ { "product": "...", "label": "...", "data": { ...deltas... } } ],
--     "documents": [ { "type": "...", "captured": true }, ... ]
--   }
-- KYC lives once (not per product) and a document needed by several products is
-- listed once — no duplication.
--
-- Core, validated, dedup-critical fields STILL live in their typed columns and
-- triggers (name, phone, national_id + hash, products, microfinance_amount,
-- acceptance_device_count, business_address). This column holds the rich body.
--
-- PRODUCTION NORMALIZATION (handed to the tech team) — the JSONB above maps 1:1
-- onto:
--   merchant_products(merchant_id, product, data jsonb, status)        -- one row/product
--   merchant_documents(merchant_id, doc_type, storage_path, product)   -- deduped by type
-- backed by a Supabase Storage bucket with RLS (rep sees only their merchant's
-- documents). Documents are capture-and-stub in the pilot app; wiring real
-- uploads to Storage is the documented next step.
--
-- Additive + nullable → safe to apply to a live database with zero downtime.
-- ============================================================================

ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS onboarding_application jsonb;

COMMENT ON COLUMN public.merchants.onboarding_application IS
  'Full unified onboarding payload: KYC core (once) + per-product deltas + deduped documents. '
  'Nullable; present only for merchants who completed the onboarding wizard.';
