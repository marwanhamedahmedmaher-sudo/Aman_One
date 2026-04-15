-- ============================================================================
-- 004_rls_policies.sql — Row Level Security
-- P0-9: RLS policies for users, merchants, audit_log
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Enable RLS on all tables
-- ---------------------------------------------------------------------------

ALTER TABLE public.users     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper: is_admin() — checks if current user has admin role
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

COMMENT ON FUNCTION public.is_admin IS 'P0-9: Returns true if the authenticated user has the admin role. SECURITY DEFINER bypasses RLS for the lookup itself.';

-- ============================================================================
-- public.users policies
-- ============================================================================

-- SELECT: own profile or admin sees all
DROP POLICY IF EXISTS users_select_own ON public.users;
CREATE POLICY users_select_own ON public.users
  FOR SELECT
  USING (id = auth.uid() OR public.is_admin());

-- UPDATE: own profile (limited) or admin updates all
-- Reps can only update: name, phone, must_change_password.
-- Role, status, employee_id, business_unit, region are admin-only.
DROP POLICY IF EXISTS users_update_own ON public.users;
CREATE POLICY users_update_own ON public.users
  FOR UPDATE
  USING (id = auth.uid() OR public.is_admin())
  WITH CHECK (
    -- Admin can change anything
    public.is_admin()
    OR (
      -- Non-admin: can only update own row, and cannot change protected fields
      id = auth.uid()
      AND role        = (SELECT u.role        FROM public.users u WHERE u.id = auth.uid())
      AND status      = (SELECT u.status      FROM public.users u WHERE u.id = auth.uid())
      AND employee_id = (SELECT u.employee_id FROM public.users u WHERE u.id = auth.uid())
    )
  );

-- INSERT: only via service role (admin provisioning in Dashboard).
-- No policy = blocked for authenticated users. Service role bypasses RLS.

-- DELETE: not allowed (no policy).

-- ============================================================================
-- public.merchants policies
-- ============================================================================

-- SELECT: own leads (created_by = me) or admin sees all. Exclude soft-deleted.
DROP POLICY IF EXISTS merchants_select ON public.merchants;
CREATE POLICY merchants_select ON public.merchants
  FOR SELECT
  USING (
    (deleted_at IS NULL)
    AND (created_by = auth.uid() OR public.is_admin())
  );

-- INSERT: any authenticated rep. created_by must match auth.uid().
DROP POLICY IF EXISTS merchants_insert ON public.merchants;
CREATE POLICY merchants_insert ON public.merchants
  FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND created_by = auth.uid()
  );

-- UPDATE: own leads (unless converted) or admin updates all.
DROP POLICY IF EXISTS merchants_update ON public.merchants;
CREATE POLICY merchants_update ON public.merchants
  FOR UPDATE
  USING (
    (created_by = auth.uid() AND status != 'converted')
    OR public.is_admin()
  )
  WITH CHECK (
    (created_by = auth.uid() AND status != 'converted')
    OR public.is_admin()
  );

-- No DELETE policy — use soft delete (UPDATE deleted_at). Admin can soft-delete
-- any record via the UPDATE policy above.

-- ============================================================================
-- public.audit_log policies
-- ============================================================================

-- INSERT: any authenticated user (triggers run as the user context).
DROP POLICY IF EXISTS audit_log_insert ON public.audit_log;
CREATE POLICY audit_log_insert ON public.audit_log
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- SELECT: admins only.
DROP POLICY IF EXISTS audit_log_select ON public.audit_log;
CREATE POLICY audit_log_select ON public.audit_log
  FOR SELECT
  USING (public.is_admin());

-- No UPDATE or DELETE — audit log is immutable.

-- ============================================================================
-- End of 004_rls_policies.sql
-- ============================================================================
