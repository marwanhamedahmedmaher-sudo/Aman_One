-- ============================================================================
-- 017_supervisor_role_and_location_consent.sql
-- Foundation for location features: the 'supervisor' role + a one-time
-- location-tracking consent gate.
--
-- NOTE: An earlier draft of this migration created an always-on per-rep
-- location table (continuous tracking). That approach was superseded by the
-- per-task check-in model (see 018) after the supervisor clarified the real
-- need: prove a rep was at a *task's* location during the task's time window,
-- not track them continuously. Only the reusable pieces remain here:
--   * the 'supervisor' role (reads check-ins; not a full admin)
--   * is_supervisor() helper
--   * location_consent gate (one deliberate opt-in before any location is sent)
--
-- PDPL note: per-task foreground check-ins are far lower-sensitivity than a
-- movement trail — the rep consciously submits one fix per task. The consent
-- column keeps a clean, auditable, revocable record of that opt-in.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add 'supervisor' to the users.role CHECK constraint
-- ---------------------------------------------------------------------------

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('sales_rep', 'admin', 'supervisor'));

-- ---------------------------------------------------------------------------
-- 2. Consent columns on public.users
-- ---------------------------------------------------------------------------

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS location_consent    boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS location_consent_at timestamptz;

COMMENT ON COLUMN public.users.location_consent IS
  'Rep opt-in to per-task location check-ins. Check-ins are rejected unless true. Revocable from the app.';
COMMENT ON COLUMN public.users.location_consent_at IS
  'Timestamp of the most recent location_consent change. Set by trigger.';

-- ---------------------------------------------------------------------------
-- 3. Helper: is_supervisor() — mirrors is_admin() from 004
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_supervisor()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'supervisor'
  );
$$;

COMMENT ON FUNCTION public.is_supervisor IS
  'Returns true if the authenticated user has the supervisor role. SECURITY DEFINER bypasses RLS for the lookup.';

-- ---------------------------------------------------------------------------
-- 4. Consent change handling: stamp location_consent_at + audit
-- ---------------------------------------------------------------------------

-- BEFORE UPDATE: stamp the timestamp whenever consent flips.
CREATE OR REPLACE FUNCTION public.stamp_location_consent()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.location_consent IS DISTINCT FROM OLD.location_consent THEN
    NEW.location_consent_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_stamp_location_consent ON public.users;
CREATE TRIGGER trg_users_stamp_location_consent
  BEFORE UPDATE OF location_consent ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.stamp_location_consent();

-- AFTER UPDATE: write an audit row on every consent change.
CREATE OR REPLACE FUNCTION public.audit_location_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.location_consent IS DISTINCT FROM OLD.location_consent THEN
    INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
    VALUES (
      COALESCE(auth.uid(), NEW.id),
      CASE WHEN NEW.location_consent THEN 'location_consent_granted'
           ELSE 'location_consent_revoked' END,
      'users',
      NEW.id,
      NULL,
      jsonb_build_object('at', now())
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_audit_location_consent ON public.users;
CREATE TRIGGER trg_users_audit_location_consent
  AFTER UPDATE OF location_consent ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.audit_location_consent();

-- ============================================================================
-- End of 017_supervisor_role_and_location_consent.sql
-- ============================================================================
