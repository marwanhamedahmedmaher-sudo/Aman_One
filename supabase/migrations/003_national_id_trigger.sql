-- ============================================================================
-- 003_national_id_trigger.sql — Egyptian National ID validation & hash
-- P0-16b: Trigger on public.merchants
-- ============================================================================
-- Egyptian 14-digit National ID structural rules:
--   Digit  1:     Century — 2 (1900–1999) or 3 (2000–2099)
--   Digits 2-7:   YYMMDD birthdate
--   Digits 8-9:   Governorate code (01–35 or 88 for foreign-born)
--   Digits 10-13: Serial number (any 4 digits)
--   Digit  14:    Checksum (no public algorithm — accept any digit in V1)
--
-- On valid input:
--   - Compute SHA-256 of the 14-digit string → write to national_id_hash
--   - national_id_hash UNIQUE constraint handles dedup
--
-- Hard-reject invalid input: RAISE EXCEPTION 'رقم القومي غير صحيح'
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_national_id()
RETURNS trigger AS $$
DECLARE
  raw_id      text;
  digits      text;
  century     int;
  yy          int;
  mm          int;
  dd          int;
  gov_code    int;
BEGIN
  raw_id := COALESCE(TRIM(NEW.national_id), '');

  -- -----------------------------------------------------------------------
  -- Step 1: Strip to digits, must be exactly 14
  -- -----------------------------------------------------------------------
  digits := regexp_replace(raw_id, '[^0-9]', '', 'g');

  IF length(digits) != 14 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  -- Also reject if raw input contained non-digit characters (the ID should
  -- be entered as pure digits — no spaces, dashes, or letters allowed).
  IF raw_id != digits THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 2: Century digit — must be 2 or 3
  -- -----------------------------------------------------------------------
  century := substring(digits FROM 1 FOR 1)::int;

  IF century NOT IN (2, 3) THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 3: Birthdate validation (YYMMDD — digits 2-7)
  -- -----------------------------------------------------------------------
  yy := substring(digits FROM 2 FOR 2)::int;   -- 00–99 (year within century)
  mm := substring(digits FROM 4 FOR 2)::int;   -- month
  dd := substring(digits FROM 6 FOR 2)::int;   -- day

  IF mm < 1 OR mm > 12 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  IF dd < 1 OR dd > 31 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 4: Governorate code (digits 8-9) — 01–35 or 88
  -- -----------------------------------------------------------------------
  gov_code := substring(digits FROM 8 FOR 2)::int;

  IF NOT ((gov_code >= 1 AND gov_code <= 35) OR gov_code = 88) THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 5: Store cleaned digits as national_id
  -- -----------------------------------------------------------------------
  NEW.national_id := digits;

  -- -----------------------------------------------------------------------
  -- Step 6: Compute SHA-256 hash for dedup
  -- -----------------------------------------------------------------------
  NEW.national_id_hash := encode(digest(digits, 'sha256'), 'hex');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger on INSERT and UPDATE of national_id
DROP TRIGGER IF EXISTS trg_merchants_validate_national_id ON public.merchants;
CREATE TRIGGER trg_merchants_validate_national_id
  BEFORE INSERT OR UPDATE OF national_id ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.validate_national_id();

-- ============================================================================
-- Test fixtures (run manually in SQL Editor, then discard)
-- ============================================================================
-- Helper function that simulates the trigger logic for testing.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_national_id_test(input_id text)
RETURNS TABLE(national_id text, national_id_hash text) AS $$
DECLARE
  digits    text;
  century   int;
  yy        int;
  mm        int;
  dd        int;
  gov_code  int;
BEGIN
  digits := regexp_replace(COALESCE(TRIM(input_id), ''), '[^0-9]', '', 'g');

  IF length(digits) != 14 THEN
    RAISE EXCEPTION 'رقم القومي غير صحيح';
  END IF;

  IF input_id != digits THEN
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

  national_id := digits;
  national_id_hash := encode(digest(digits, 'sha256'), 'hex');
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Test block (uncomment and run in SQL Editor)
-- ============================================================================

/*
DO $$
DECLARE
  _id   text;
  _hash text;
BEGIN
  RAISE NOTICE '--- National ID validation tests ---';

  -- -----------------------------------------------------------------------
  -- Valid cases
  -- -----------------------------------------------------------------------

  -- Test 1: Born 1990-01-01, Cairo gov 01
  BEGIN
    SELECT t.national_id, t.national_id_hash
      INTO _id, _hash
      FROM public.validate_national_id_test('29001011234567') t;
    ASSERT _id = '29001011234567', 'Test 1 ID mismatch';
    ASSERT length(_hash) = 64, 'Test 1 hash length wrong';
    RAISE NOTICE 'PASS  Test 1: 29001011234567 → hash=%', left(_hash, 16) || '...';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 1: %', SQLERRM;
  END;

  -- Test 2: Born 2005-01-15, gov 15
  BEGIN
    SELECT t.national_id, t.national_id_hash
      INTO _id, _hash
      FROM public.validate_national_id_test('30501151234567') t;
    ASSERT _id = '30501151234567', 'Test 2 ID mismatch';
    RAISE NOTICE 'PASS  Test 2: 30501151234567 → hash=%', left(_hash, 16) || '...';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 2: %', SQLERRM;
  END;

  -- Test 3: Foreign-born (gov 88)
  BEGIN
    SELECT t.national_id, t.national_id_hash
      INTO _id, _hash
      FROM public.validate_national_id_test('28506158812345') t;
    ASSERT _id = '28506158812345', 'Test 3 ID mismatch';
    RAISE NOTICE 'PASS  Test 3: gov 88 (foreign-born) accepted → hash=%', left(_hash, 16) || '...';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 3: %', SQLERRM;
  END;

  -- -----------------------------------------------------------------------
  -- Invalid cases (should all raise exception)
  -- -----------------------------------------------------------------------

  -- Test 4: Contains non-digit character
  BEGIN
    PERFORM public.validate_national_id_test('1234567890123X');
    RAISE NOTICE 'FAIL  Test 4: should reject non-digit character';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 4: non-digit rejected — %', SQLERRM;
  END;

  -- Test 5: Century digit 4 (invalid)
  BEGIN
    PERFORM public.validate_national_id_test('49001011234567');
    RAISE NOTICE 'FAIL  Test 5: should reject century 4';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 5: century 4 rejected — %', SQLERRM;
  END;

  -- Test 6: Month 13 (invalid)
  BEGIN
    PERFORM public.validate_national_id_test('29013011234567');
    RAISE NOTICE 'FAIL  Test 6: should reject month 13';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 6: month 13 rejected — %', SQLERRM;
  END;

  -- Test 7: Day 00 (invalid)
  BEGIN
    PERFORM public.validate_national_id_test('29001001234567');
    RAISE NOTICE 'FAIL  Test 7: should reject day 00';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 7: day 00 rejected — %', SQLERRM;
  END;

  -- Test 8: Governorate 40 (invalid — max is 35 or 88)
  BEGIN
    PERFORM public.validate_national_id_test('29001014012345');
    RAISE NOTICE 'FAIL  Test 8: should reject gov code 40';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 8: gov 40 rejected — %', SQLERRM;
  END;

  -- Test 9: Only 13 digits (too short)
  BEGIN
    PERFORM public.validate_national_id_test('2900101123456');
    RAISE NOTICE 'FAIL  Test 9: should reject 13-digit ID';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 9: 13 digits rejected — %', SQLERRM;
  END;

  -- Test 10: 15 digits (too long)
  BEGIN
    PERFORM public.validate_national_id_test('290010112345678');
    RAISE NOTICE 'FAIL  Test 10: should reject 15-digit ID';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 10: 15 digits rejected — %', SQLERRM;
  END;

  -- Test 11: Century digit 1 (invalid — too old)
  BEGIN
    PERFORM public.validate_national_id_test('19001011234567');
    RAISE NOTICE 'FAIL  Test 11: should reject century 1';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 11: century 1 rejected — %', SQLERRM;
  END;

  -- Test 12: Gov code 00 (invalid — minimum is 01)
  BEGIN
    PERFORM public.validate_national_id_test('29001010012345');
    RAISE NOTICE 'FAIL  Test 12: should reject gov code 00';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 12: gov 00 rejected — %', SQLERRM;
  END;

  RAISE NOTICE '--- National ID tests complete ---';
END;
$$;
*/

-- ============================================================================
-- End of 003_national_id_trigger.sql
-- ============================================================================
