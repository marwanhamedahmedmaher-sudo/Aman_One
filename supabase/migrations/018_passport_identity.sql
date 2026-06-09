-- ============================================================================
-- 018_passport_identity.sql — Foreigner support: passport as an alternate ID
-- ============================================================================
-- V1 was Egyptian-individuals-only: merchants.national_id NOT NULL guarded by a
-- strict 14-digit trigger (migration 003). To onboard foreigners we add a
-- parallel identity document:
--
--   id_document_type  'national_id' (Egyptian, default) | 'passport' (foreigner)
--   passport_number   the foreign passport — mandatory ONLY for foreigners
--
-- Exactly one identifier is populated per merchant, enforced by a CHECK and by
-- the (rewritten) validate_national_id() trigger:
--   - Egyptian  -> national_id validated (14-digit rules), passport_number NULL
--   - Foreigner -> passport_number validated (alphanumeric), national_id NULL
--
-- DEDUP stays on the single UNIQUE national_id_hash column. For passports the
-- hash is namespaced ('passport:' || normalized) so a passport can never
-- collide with a 14-digit-NID hash — one UNIQUE index still guards both.
--
-- Additive + nullable + back-compatible default -> safe to apply to a live DB.
-- Existing rows default to id_document_type = 'national_id' and are unaffected.
-- ============================================================================

-- 1) New columns -------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS id_document_type text NOT NULL DEFAULT 'national_id',
  ADD COLUMN IF NOT EXISTS passport_number  text;

ALTER TABLE public.merchants
  DROP CONSTRAINT IF EXISTS chk_id_document_type;
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_id_document_type
  CHECK (id_document_type IN ('national_id', 'passport'));

COMMENT ON COLUMN public.merchants.id_document_type IS
  'Identity document this merchant was onboarded with: national_id (Egyptian) or passport (foreigner).';
COMMENT ON COLUMN public.merchants.passport_number IS
  'Foreign passport number. Mandatory only when id_document_type = passport. '
  'PII — enable Vault TCE on this column in the Dashboard alongside national_id.';

-- 2) national_id is no longer mandatory (foreigners carry none) ---------------
ALTER TABLE public.merchants
  ALTER COLUMN national_id DROP NOT NULL;

-- 3) Exactly the right identifier present for the chosen document type --------
ALTER TABLE public.merchants
  DROP CONSTRAINT IF EXISTS chk_identity_document;
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_identity_document
  CHECK (
    (id_document_type = 'national_id' AND national_id    IS NOT NULL) OR
    (id_document_type = 'passport'    AND passport_number IS NOT NULL)
  );

-- 4) Rewrite the validation/hash trigger to branch on document type ----------
-- search_path pinned (public, extensions) so digest() resolves and the function
-- is not vulnerable to a mutable-search-path attack (consistent with mig. 007).
CREATE OR REPLACE FUNCTION public.validate_national_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  raw_id    text;
  digits    text;
  century   int;
  yy        int;
  mm        int;
  dd        int;
  gov_code  int;
  pp        text;
BEGIN
  -- ----- Foreigner branch: validate passport, namespace the dedup hash ------
  IF NEW.id_document_type = 'passport' THEN
    pp := upper(regexp_replace(COALESCE(TRIM(NEW.passport_number), ''), '\s', '', 'g'));

    -- Alphanumeric, 5–20 chars — covers every national passport format.
    IF pp !~ '^[A-Z0-9]{5,20}$' THEN
      RAISE EXCEPTION 'رقم جواز السفر غير صحيح';  -- passport number invalid
    END IF;

    NEW.passport_number  := pp;
    NEW.national_id      := NULL;  -- foreigners carry no Egyptian NID
    NEW.national_id_hash := encode(digest('passport:' || pp, 'sha256'), 'hex');
    RETURN NEW;
  END IF;

  -- ----- Egyptian branch: existing 14-digit National ID rules ---------------
  NEW.passport_number := NULL;  -- keep the unused identifier clean
  raw_id := COALESCE(TRIM(NEW.national_id), '');
  digits := regexp_replace(raw_id, '[^0-9]', '', 'g');

  IF length(digits) != 14 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  IF raw_id != digits THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  century := substring(digits FROM 1 FOR 1)::int;
  IF century NOT IN (2, 3) THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  yy := substring(digits FROM 2 FOR 2)::int;
  mm := substring(digits FROM 4 FOR 2)::int;
  dd := substring(digits FROM 6 FOR 2)::int;

  IF mm < 1 OR mm > 12 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  IF dd < 1 OR dd > 31 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  gov_code := substring(digits FROM 8 FOR 2)::int;
  IF NOT ((gov_code >= 1 AND gov_code <= 35) OR gov_code = 88) THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  NEW.national_id      := digits;
  NEW.national_id_hash := encode(digest(digits, 'sha256'), 'hex');
  RETURN NEW;
END;
$$;

-- 5) Trigger must also fire when the passport / document type changes ---------
DROP TRIGGER IF EXISTS trg_merchants_validate_national_id ON public.merchants;
CREATE TRIGGER trg_merchants_validate_national_id
  BEFORE INSERT OR UPDATE OF national_id, passport_number, id_document_type
  ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.validate_national_id();

-- ============================================================================
-- End of 018_passport_identity.sql
-- ============================================================================
