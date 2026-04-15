-- ============================================================================
-- 001_schema.sql — Core schema for Aman Sales App (أمان)
-- P0-2: Tables (users, merchants, audit_log)
-- P0-3: Custom claims function for role management
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS pgsodium;    -- Supabase Vault / TCE for national_id

-- ---------------------------------------------------------------------------
-- Vault / TCE setup note (manual step in Supabase Dashboard)
-- ---------------------------------------------------------------------------
-- Supabase Vault uses pgsodium Transparent Column Encryption (TCE).
-- After running this migration, configure TCE for merchants.national_id:
--
-- 1. Go to Supabase Dashboard → Database → Vault → Secrets.
-- 2. Create a new encryption key (or use the project default).
-- 3. In the Vault "Encrypted Columns" tab, add:
--      Table:  public.merchants
--      Column: national_id
--      Key:    <the key you created>
--
-- Once enabled, national_id is stored as ciphertext at rest and decrypted
-- transparently for queries executed by roles with SELECT permission.
-- The companion column national_id_hash (plaintext SHA-256) handles dedup
-- via a UNIQUE constraint without exposing the raw ID.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- P0-2: public.users — Sales rep profile, linked to auth.users
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.users (
  id                    uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name                  text        NOT NULL,
  phone                 text        NOT NULL,
  employee_id           text        NOT NULL,
  business_unit         text        NOT NULL DEFAULT '',
  region                text        NOT NULL DEFAULT '',
  role                  text        NOT NULL DEFAULT 'sales_rep'
                                    CHECK (role IN ('sales_rep', 'admin')),
  status                text        NOT NULL DEFAULT 'active'
                                    CHECK (status IN ('active', 'suspended')),
  must_change_password  boolean     NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.users IS 'Sales rep profiles. One row per auth.users entry. Role determines RLS access.';
COMMENT ON COLUMN public.users.must_change_password IS 'Set true on provisioning / admin reset. Rep must rotate password before proceeding.';

-- ---------------------------------------------------------------------------
-- P0-2: public.merchants — Lead records captured by sales reps
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.merchants (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text        NOT NULL,
  phone             text        NOT NULL,
  national_id       text        NOT NULL,           -- Vault TCE encrypts at rest
  national_id_hash  text        UNIQUE NOT NULL,    -- SHA-256 for dedup
  notes             text        DEFAULT '',
  status            text        NOT NULL DEFAULT 'lead'
                                CHECK (status IN ('lead', 'qualified', 'rejected', 'converted')),
  created_by        uuid        NOT NULL REFERENCES auth.users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

COMMENT ON TABLE public.merchants IS 'Lead-capture records. national_id encrypted via Vault TCE; national_id_hash (SHA-256) used for dedup.';
COMMENT ON COLUMN public.merchants.national_id_hash IS 'SHA-256 hex digest of the normalized (digits-only) National ID. Populated by trigger.';
COMMENT ON COLUMN public.merchants.deleted_at IS 'Soft-delete timestamp. Non-null means logically deleted; preserves dedup history.';

-- ---------------------------------------------------------------------------
-- P0-14: public.audit_log — Rep action audit trail
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.audit_log (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid        NOT NULL REFERENCES auth.users(id),
  action      text        NOT NULL,
  table_name  text        NOT NULL,
  record_id   uuid,
  old_data    jsonb,
  new_data    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_log IS 'Immutable audit trail. Rep actions captured by triggers. Admin actions logged by Supabase Dashboard (V1).';

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_merchants_created_by ON public.merchants(created_by);
CREATE INDEX IF NOT EXISTS idx_merchants_status     ON public.merchants(status);
CREATE INDEX IF NOT EXISTS idx_merchants_deleted_at ON public.merchants(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_id   ON public.audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at);

-- ---------------------------------------------------------------------------
-- updated_at auto-update trigger function
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to users
DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Apply to merchants
DROP TRIGGER IF EXISTS trg_merchants_updated_at ON public.merchants;
CREATE TRIGGER trg_merchants_updated_at
  BEFORE UPDATE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- P0-3: Custom claims helper — set_claim(uid, claim, value)
-- ---------------------------------------------------------------------------
-- Usage (from SQL Editor or Edge Function):
--   SELECT public.set_claim('some-uuid', 'role', '"admin"');
--
-- The value must be valid JSON (hence the double-quotes for strings).
-- Claims are stored in auth.users.raw_app_meta_data and are included
-- in the JWT on next token refresh.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_claim(
  uid   uuid,
  claim text,
  value jsonb
)
RETURNS void AS $$
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data =
    COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(claim, value)
  WHERE id = uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.set_claim IS 'P0-3: Set a custom claim on an auth user. Used for role management. Must be called by a service-role or admin context.';

-- Restrict execute to service role only (admin context)
REVOKE ALL ON FUNCTION public.set_claim FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_claim FROM anon;
REVOKE ALL ON FUNCTION public.set_claim FROM authenticated;

-- ---------------------------------------------------------------------------
-- End of 001_schema.sql
-- ---------------------------------------------------------------------------
