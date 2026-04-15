-- ============================================================================
-- 002_phone_trigger.sql — Phone normalization & validation
-- P0-16a: Trigger on public.merchants
-- ============================================================================
-- Rules:
--   1. Strip all non-digit characters (except leading +).
--   2. If starts with +20, strip prefix and validate 10 remaining digits.
--   3. Egyptian mobile: 11 digits starting with 01 (prefixes 010, 011, 012, 015).
--   4. Store as E.164: +20 followed by 10 digits (leading 0 dropped).
--   5. Hard-reject invalid input with Arabic error.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.normalize_phone()
RETURNS trigger AS $$
DECLARE
  raw_phone text;
  digits    text;
BEGIN
  raw_phone := COALESCE(TRIM(NEW.phone), '');

  -- -----------------------------------------------------------------------
  -- Step 1: Handle +20 prefix, then strip to digits only
  -- -----------------------------------------------------------------------
  IF raw_phone LIKE '+20%' THEN
    -- Remove '+20' prefix, then strip non-digits from remainder
    digits := regexp_replace(substring(raw_phone FROM 4), '[^0-9]', '', 'g');
    -- The remaining should be 10 digits (without leading 0) or 11 digits (with leading 0)
    IF length(digits) = 11 AND left(digits, 1) = '0' THEN
      digits := substring(digits FROM 2);  -- drop the leading 0
    ELSIF length(digits) != 10 THEN
      RAISE EXCEPTION 'رقم الموبايل غير صحيح';
    END IF;
  ELSE
    -- Strip all non-digit characters
    digits := regexp_replace(raw_phone, '[^0-9]', '', 'g');

    -- Must be 11 digits starting with 0
    IF length(digits) != 11 OR left(digits, 1) != '0' THEN
      RAISE EXCEPTION 'رقم الموبايل غير صحيح';
    END IF;

    -- Drop the leading 0 → 10 digits
    digits := substring(digits FROM 2);
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 2: Validate Egyptian mobile prefix (10, 11, 12, 15)
  -- -----------------------------------------------------------------------
  IF left(digits, 2) NOT IN ('10', '11', '12', '15') THEN
    RAISE EXCEPTION 'رقم الموبايل غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 3: Final length check (must be exactly 10 digits after normalization)
  -- -----------------------------------------------------------------------
  IF length(digits) != 10 THEN
    RAISE EXCEPTION 'رقم الموبايل غير صحيح';
  END IF;

  -- -----------------------------------------------------------------------
  -- Step 4: Store as E.164
  -- -----------------------------------------------------------------------
  NEW.phone := '+20' || digits;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger on INSERT and UPDATE
DROP TRIGGER IF EXISTS trg_merchants_normalize_phone ON public.merchants;
CREATE TRIGGER trg_merchants_normalize_phone
  BEFORE INSERT OR UPDATE OF phone ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.normalize_phone();

-- ============================================================================
-- Test fixtures (run manually in SQL Editor, then discard)
-- ============================================================================
-- Wrapped in a DO block. Each test uses a savepoint so failures don't abort
-- the whole block.
-- ============================================================================

/*
DO $$
DECLARE
  _result text;
BEGIN
  RAISE NOTICE '--- Phone normalization tests ---';

  -- -----------------------------------------------------------------------
  -- Valid cases
  -- -----------------------------------------------------------------------

  -- Test 1: Standard 11-digit mobile
  BEGIN
    SELECT public.normalize_phone_test('01012345678') INTO _result;
    ASSERT _result = '+201012345678', 'Test 1 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 1: 01012345678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 1: %', SQLERRM;
  END;

  -- Test 2: With +20 country code
  BEGIN
    SELECT public.normalize_phone_test('+201012345678') INTO _result;
    ASSERT _result = '+201012345678', 'Test 2 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 2: +201012345678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 2: %', SQLERRM;
  END;

  -- Test 3: With spaces
  BEGIN
    SELECT public.normalize_phone_test('010 1234 5678') INTO _result;
    ASSERT _result = '+201012345678', 'Test 3 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 3: 010 1234 5678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 3: %', SQLERRM;
  END;

  -- Test 4: Prefix 011
  BEGIN
    SELECT public.normalize_phone_test('01112345678') INTO _result;
    ASSERT _result = '+201112345678', 'Test 4 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 4: 01112345678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 4: %', SQLERRM;
  END;

  -- Test 5: Prefix 012
  BEGIN
    SELECT public.normalize_phone_test('01212345678') INTO _result;
    ASSERT _result = '+201212345678', 'Test 5 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 5: 01212345678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 5: %', SQLERRM;
  END;

  -- Test 6: Prefix 015
  BEGIN
    SELECT public.normalize_phone_test('01512345678') INTO _result;
    ASSERT _result = '+201512345678', 'Test 6 failed: got ' || _result;
    RAISE NOTICE 'PASS  Test 6: 01512345678 → %', _result;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL  Test 6: %', SQLERRM;
  END;

  -- -----------------------------------------------------------------------
  -- Invalid cases (should raise exception)
  -- -----------------------------------------------------------------------

  -- Test 7: Landline (02)
  BEGIN
    PERFORM public.normalize_phone_test('0212345678');
    RAISE NOTICE 'FAIL  Test 7: should have rejected landline 0212345678';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 7: landline rejected — %', SQLERRM;
  END;

  -- Test 8: Too short
  BEGIN
    PERFORM public.normalize_phone_test('123456');
    RAISE NOTICE 'FAIL  Test 8: should have rejected short number';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 8: short number rejected — %', SQLERRM;
  END;

  -- Test 9: Bad prefix 016
  BEGIN
    PERFORM public.normalize_phone_test('01612345678');
    RAISE NOTICE 'FAIL  Test 9: should have rejected prefix 016';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 9: prefix 016 rejected — %', SQLERRM;
  END;

  -- Test 10: +20 with bad prefix
  BEGIN
    PERFORM public.normalize_phone_test('+200912345678');
    RAISE NOTICE 'FAIL  Test 10: should have rejected +20 with prefix 09';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS  Test 10: +20 bad prefix rejected — %', SQLERRM;
  END;

  RAISE NOTICE '--- Phone tests complete ---';
END;
$$;
*/

-- ---------------------------------------------------------------------------
-- Helper function for running tests without a real insert.
-- Simulates the trigger logic and returns the normalized phone.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_phone_test(input_phone text)
RETURNS text AS $$
DECLARE
  digits text;
  raw_phone text;
BEGIN
  raw_phone := COALESCE(TRIM(input_phone), '');

  IF raw_phone LIKE '+20%' THEN
    digits := regexp_replace(substring(raw_phone FROM 4), '[^0-9]', '', 'g');
    IF length(digits) = 11 AND left(digits, 1) = '0' THEN
      digits := substring(digits FROM 2);
    ELSIF length(digits) != 10 THEN
      RAISE EXCEPTION 'رقم الموبايل غير صحيح';
    END IF;
  ELSE
    digits := regexp_replace(raw_phone, '[^0-9]', '', 'g');
    IF length(digits) != 11 OR left(digits, 1) != '0' THEN
      RAISE EXCEPTION 'رقم الموبايل غير صحيح';
    END IF;
    digits := substring(digits FROM 2);
  END IF;

  IF left(digits, 2) NOT IN ('10', '11', '12', '15') THEN
    RAISE EXCEPTION 'رقم الموبايل غير صحيح';
  END IF;

  IF length(digits) != 10 THEN
    RAISE EXCEPTION 'رقم الموبايل غير صحيح';
  END IF;

  RETURN '+20' || digits;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- End of 002_phone_trigger.sql
-- ============================================================================
