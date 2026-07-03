-- ============================================================================
-- 037_backfill_normalized_model.sql — Migrate existing merchants into the
-- normalized KYC/KYB/products/documents model (migrations 032–036).
-- ============================================================================
-- Idempotent: every INSERT is guarded (NOT EXISTS / ON CONFLICT DO NOTHING), so
-- this can be re-run safely. Reads from the existing merchants columns + the
-- onboarding_application JSONB (where present). Touches only the NEW tables —
-- merchants is read-only here, so the merchants audit trigger never fires.
--
-- RUN AFTER 032–036 are applied. VALIDATE on a restored dev project before prod.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- GUARD: refuse to run until Vault TCE covers the kyc_profiles identity
-- columns. Step 1 below decrypts merchants.national_id (transparent read) and
-- materializes it into kyc_profiles for the WHOLE merchant book — without TCE
-- labels that means plaintext-at-rest, violating the CLAUDE.md security
-- posture. Enable TCE first (Dashboard, migration 034 header), then re-run.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(DISTINCT a.attname)
      FROM pg_seclabel s
      JOIN pg_class     c ON c.oid = s.objoid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = s.objsubid
      WHERE s.provider = 'pgsodium'
        AND n.nspname = 'public' AND c.relname = 'kyc_profiles'
        AND a.attname IN ('national_id', 'passport_number')) < 2 THEN
    RAISE EXCEPTION 'ABORTED: Vault TCE is not enabled on kyc_profiles.national_id / passport_number — this backfill would store decrypted National IDs plaintext-at-rest. Enable TCE (see migration 034 header), then re-run.';
  END IF;
END $$;

-- 1) KYC profile per merchant (prefer the JSONB breakdown; else split name) ---
INSERT INTO public.kyc_profiles (merchant_id, role, first_name, second_name, third_name,
          family_name, first_name_en, family_name_en, id_document_type, national_id,
          national_id_hash, passport_number, address, verification_status)
SELECT m.id, 'owner',
       COALESCE(NULLIF(m.onboarding_application -> 'kyc' ->> 'first_name', ''), split_part(m.name, ' ', 1)),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'second_name', ''),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'third_name', ''),
       COALESCE(NULLIF(m.onboarding_application -> 'kyc' ->> 'family_name', ''),
                NULLIF(regexp_replace(m.name, '^\S+\s*', ''), '')),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'first_name_en', ''),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'family_name_en', ''),
       COALESCE(m.id_document_type, 'national_id'),
       m.national_id, m.national_id_hash, m.passport_number,
       COALESCE(NULLIF(m.onboarding_application -> 'kyc' ->> 'address', ''), m.business_address),
       'verified'   -- existing live merchants are already onboarded
FROM public.merchants m
WHERE m.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM public.kyc_profiles k WHERE k.merchant_id = m.id);

-- 2) KYB profile for company-track merchants -------------------------------
INSERT INTO public.kyb_profiles (merchant_id, legal_name, trade_name, commercial_reg,
          tax_card, activity_type_id, business_address, verification_status)
SELECT m.id,
       NULLIF(m.onboarding_application -> 'kyc' ->> 'shop_name', ''),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'shop_name', ''),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'commercial_reg', ''),
       NULLIF(m.onboarding_application -> 'kyc' ->> 'tax_card', ''),
       m.activity_type_id,
       COALESCE(NULLIF(m.onboarding_application -> 'kyc' ->> 'branch_address_ar', ''), m.business_address),
       'verified'
FROM public.merchants m
WHERE m.deleted_at IS NULL
  AND m.onboarding_application ->> 'track' = 'company'
ON CONFLICT (merchant_id) DO NOTHING;

-- 3) merchant_products from products[] + the legacy detail columns ----------
INSERT INTO public.merchant_products (merchant_id, product, status, amount, device_count)
SELECT m.id, p,
       CASE m.status WHEN 'converted' THEN 'active'
                     WHEN 'rejected'  THEN 'rejected'
                     ELSE 'pending' END,
       CASE WHEN p = 'Microfinance'   THEN m.microfinance_amount END,
       CASE WHEN p = 'Acceptance POS' THEN m.acceptance_device_count END
FROM public.merchants m
CROSS JOIN LATERAL unnest(m.products) AS p
WHERE m.deleted_at IS NULL
ON CONFLICT (merchant_id, product) DO NOTHING;

-- 4) merchant_documents from the JSONB documents array ----------------------
INSERT INTO public.merchant_documents (merchant_id, doc_type, owner_kind, status)
SELECT m.id, d ->> 'type',
       CASE WHEN (d ->> 'type') IN ('doc_commercial_reg','doc_tax_card') THEN 'kyb'
            WHEN (d ->> 'type') = 'doc_contract' THEN 'contract'
            ELSE 'kyc' END,
       'pending'
FROM public.merchants m
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(m.onboarding_application -> 'documents', '[]'::jsonb)) AS d
WHERE m.deleted_at IS NULL
  AND COALESCE((d ->> 'captured')::boolean, false)
ON CONFLICT (merchant_id, doc_type) DO NOTHING;

-- ============================================================================
-- VERIFY (run manually after applying):
--   SELECT (SELECT count(*) FROM merchants WHERE deleted_at IS NULL) AS merchants,
--          (SELECT count(*) FROM kyc_profiles)      AS kyc,
--          (SELECT count(*) FROM kyb_profiles)      AS kyb,
--          (SELECT count(*) FROM merchant_products) AS products;
-- Expect: kyc == merchants; products >= merchants; kyb == #company merchants.
-- ============================================================================
-- End of 037_backfill_normalized_model.sql
-- ============================================================================
