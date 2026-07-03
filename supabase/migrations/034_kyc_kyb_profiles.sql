-- ============================================================================
-- 034_kyc_kyb_profiles.sql — KYC (individual) + KYB (business) profiles
-- ============================================================================
-- KYC = identity of the APPLICANT INDIVIDUAL (the owner/signatory). Every
--       merchant has exactly one KYC profile.
-- KYB = identity of the BUSINESS. Only company-track merchants have one.
--
--   Individual track -> 1 kyc_profiles row, no kyb_profiles row.
--   Company track    -> 1 kyc_profiles row (signatory) + 1 kyb_profiles row.
--
-- Identity numbers (national_id / passport) are sensitive: stored here, read in
-- the clear ONLY via the reveal-with-audit RPC at the bottom (mirrors the
-- merchants reveal_national_id / reveal_passport_number pattern, migrations
-- 010 / 019).
--
-- *** REQUIRED MANUAL STEP BEFORE ANY DATA LANDS IN THIS TABLE ***
-- Enable Vault TCE on kyc_profiles.national_id + passport_number in the
-- Supabase Dashboard (same procedure as merchants.national_id, migration 001).
-- CLAUDE.md mandates ciphertext-at-rest for these identifiers; the backfill
-- (migration 037) refuses to run until the TCE labels exist — see its guard.
--
-- Writes are validated: the same validate_national_id() trigger that guards
-- merchants (migrations 003/018) is attached below, so a malformed NID or
-- passport is hard-rejected here too and the dedup hash is always derived
-- server-side — RLS alone would otherwise let reps write unvalidated values.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- KYC — applicant individual
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kyc_profiles (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  application_id      uuid        REFERENCES public.onboarding_applications(id) ON DELETE SET NULL,
  role                text        NOT NULL DEFAULT 'owner'
                                  CHECK (role IN ('owner', 'signatory')),
  first_name          text,
  second_name         text,
  third_name          text,
  family_name         text,
  first_name_en       text,
  family_name_en      text,
  id_document_type    text        NOT NULL DEFAULT 'national_id'
                                  CHECK (id_document_type IN ('national_id', 'passport')),
  national_id         text,                       -- Egyptian NID (enable Vault TCE)
  national_id_hash    text,                       -- SHA-256, for cross-ref / dedup
  passport_number     text,                       -- foreigner (enable Vault TCE)
  nationality         text,                       -- country (for foreigners)
  birth_date          date,
  gender              text,
  address             text,
  verification_status text        NOT NULL DEFAULT 'pending'
                                  CHECK (verification_status IN ('pending','verified','rejected')),
  verified_by         uuid        REFERENCES auth.users(id),
  verified_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (id_document_type = 'national_id' AND national_id     IS NOT NULL) OR
    (id_document_type = 'passport'    AND passport_number IS NOT NULL)
  )
);

COMMENT ON TABLE public.kyc_profiles IS
  'KYC: identity of the applicant individual (owner/signatory) behind a merchant. Identity numbers read in clear only via reveal_kyc_identity().';

CREATE INDEX IF NOT EXISTS idx_kyc_merchant    ON public.kyc_profiles(merchant_id);
CREATE INDEX IF NOT EXISTS idx_kyc_nid_hash    ON public.kyc_profiles(national_id_hash);
CREATE INDEX IF NOT EXISTS idx_kyc_application ON public.kyc_profiles(application_id);

DROP TRIGGER IF EXISTS trg_kyc_updated_at ON public.kyc_profiles;
CREATE TRIGGER trg_kyc_updated_at
  BEFORE UPDATE ON public.kyc_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Hard-reject malformed identity numbers + derive the dedup hash server-side.
-- Reuses validate_national_id() (migrations 003/018): it reads/writes only
-- id_document_type, national_id, national_id_hash, passport_number — all of
-- which exist here under the same names, so the merchants rules apply 1:1.
DROP TRIGGER IF EXISTS trg_kyc_validate_identity ON public.kyc_profiles;
CREATE TRIGGER trg_kyc_validate_identity
  BEFORE INSERT OR UPDATE OF national_id, passport_number, id_document_type
  ON public.kyc_profiles
  FOR EACH ROW EXECUTE FUNCTION public.validate_national_id();

-- ---------------------------------------------------------------------------
-- KYB — business (company track only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kyb_profiles (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  application_id      uuid        REFERENCES public.onboarding_applications(id) ON DELETE SET NULL,
  legal_name          text,
  legal_name_en       text,
  trade_name          text,                       -- shop / commercial name
  commercial_reg      text,                       -- رقم السجل التجاري
  tax_card            text,                       -- رقم البطاقة الضريبية
  legal_form          text,
  establishment_date  date,
  activity_type_id    uuid        REFERENCES public.activity_types(id),
  governorate         text,
  city                text,
  business_address    text,
  verification_status text        NOT NULL DEFAULT 'pending'
                                  CHECK (verification_status IN ('pending','verified','rejected')),
  verified_by         uuid        REFERENCES auth.users(id),
  verified_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id)                            -- at most one business per merchant
);

COMMENT ON TABLE public.kyb_profiles IS
  'KYB: business identity (legal name, commercial register, tax card, activity). Present only for company-track merchants.';

-- UNIQUE (merchant_id) already indexes merchant_id lookups.
CREATE INDEX IF NOT EXISTS idx_kyb_application ON public.kyb_profiles(application_id);

DROP TRIGGER IF EXISTS trg_kyb_updated_at ON public.kyb_profiles;
CREATE TRIGGER trg_kyb_updated_at
  BEFORE UPDATE ON public.kyb_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: both scoped through the parent merchant's ownership.
-- ---------------------------------------------------------------------------
ALTER TABLE public.kyc_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyb_profiles ENABLE ROW LEVEL SECURITY;

-- kyc
DROP POLICY IF EXISTS kyc_select ON public.kyc_profiles;
CREATE POLICY kyc_select ON public.kyc_profiles FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND m.deleted_at IS NULL AND (m.created_by = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS kyc_write ON public.kyc_profiles;
CREATE POLICY kyc_write ON public.kyc_profiles FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND (m.created_by = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                      AND (m.created_by = auth.uid() OR public.is_admin())));

-- kyb
DROP POLICY IF EXISTS kyb_select ON public.kyb_profiles;
CREATE POLICY kyb_select ON public.kyb_profiles FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND m.deleted_at IS NULL AND (m.created_by = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS kyb_write ON public.kyb_profiles;
CREATE POLICY kyb_write ON public.kyb_profiles FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND (m.created_by = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                      AND (m.created_by = auth.uid() OR public.is_admin())));

-- ---------------------------------------------------------------------------
-- reveal_kyc_identity — clear-text identity number + audit row, atomically.
-- Returns the NID for national_id profiles, the passport for passport profiles.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reveal_kyc_identity(p_kyc_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _val       text;
  _doc_type  text;
  _caller_id uuid;
BEGIN
  _caller_id := auth.uid();
  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  SELECT k.id_document_type,
         CASE WHEN k.id_document_type = 'passport' THEN k.passport_number ELSE k.national_id END
    INTO _doc_type, _val
  FROM public.kyc_profiles k
  JOIN public.merchants m ON m.id = k.merchant_id
  WHERE k.id = p_kyc_id
    AND m.deleted_at IS NULL
    AND (m.created_by = _caller_id OR public.is_admin());

  IF _val IS NULL THEN
    RAISE EXCEPTION 'العميل غير موجود أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (_caller_id,
          CASE WHEN _doc_type = 'passport' THEN 'passport_revealed' ELSE 'national_id_revealed' END,
          'kyc_profiles', p_kyc_id, NULL,
          jsonb_build_object('revealed_at', now(), 'doc_type', _doc_type));

  RETURN _val;
END;
$$;

COMMENT ON FUNCTION public.reveal_kyc_identity IS
  'Returns clear-text identity number (NID or passport) for a KYC profile the caller owns (or admin), writing the matching reveal audit row in the same transaction. SECURITY DEFINER.';

REVOKE ALL ON FUNCTION public.reveal_kyc_identity(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reveal_kyc_identity(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reveal_kyc_identity(uuid) TO authenticated;

-- ============================================================================
-- End of 034_kyc_kyb_profiles.sql
-- ============================================================================
