-- ============================================================================
-- 007_pin_function_search_paths.sql — Security hardening
-- Pin search_path on all public functions to prevent mutable search-path
-- attacks. Resolves Supabase security advisor WARN: "Function Search Path
-- Mutable" on 8 functions from migrations 001–005.
-- ============================================================================

-- 001_schema.sql
ALTER FUNCTION public.set_updated_at()                SET search_path = public;
ALTER FUNCTION public.set_claim(uuid, text, jsonb)    SET search_path = public;

-- 002_phone_trigger.sql
ALTER FUNCTION public.normalize_phone()               SET search_path = public;
ALTER FUNCTION public.normalize_phone_test(text)      SET search_path = public;

-- 003_national_id_trigger.sql (digest() lives in extensions schema on Supabase)
ALTER FUNCTION public.validate_national_id()          SET search_path = public, extensions;
ALTER FUNCTION public.validate_national_id_test(text) SET search_path = public, extensions;

-- 004_rls_policies.sql
ALTER FUNCTION public.is_admin()                      SET search_path = public;

-- 005_audit_triggers.sql
ALTER FUNCTION public.audit_merchants_change()        SET search_path = public;

-- ============================================================================
-- End of 007_pin_function_search_paths.sql
-- ============================================================================
