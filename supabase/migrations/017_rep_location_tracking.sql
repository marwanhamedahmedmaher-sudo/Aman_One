-- ============================================================================
-- 017_rep_location_tracking.sql — Rep last-known location tracking
-- Supervisor feature: "where is the rep right now".
--
-- Scope decisions (see CLAUDE.md session log):
--   * LAST-KNOWN ONLY — one row per rep, upserted in place. No movement trail.
--   * EXPLICIT CONSENT — location writes are rejected unless the rep has
--     granted location_consent. Tracking is opt-in, revocable, audited.
--   * NEW ROLE 'supervisor' — reads all reps' locations, but is not a full
--     admin (cannot write activity_types, cannot read audit_log, etc.).
--
-- PDPL note: continuous employee-location processing is higher-sensitivity
-- than anything else stored in this system. Last-known-only (no trail) +
-- explicit consent + working-hours-only client behavior is the minimal
-- footprint. Legal sign-off gates ENABLING this in production, not the
-- schema itself.
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
  'Rep opt-in to location tracking. Location writes are rejected unless true. Revocable from the app.';
COMMENT ON COLUMN public.users.location_consent_at IS
  'Timestamp of the most recent location_consent change. Set by trigger.';

-- ---------------------------------------------------------------------------
-- 3. rep_locations — ONE ROW PER REP, upserted in place (no history trail)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rep_locations (
  rep_id      uuid             PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat         double precision NOT NULL,
  lng         double precision NOT NULL,
  accuracy_m  real,
  recorded_at timestamptz      NOT NULL,   -- device clock: when the fix was taken
  updated_at  timestamptz      NOT NULL DEFAULT now()  -- server clock: when stored
);

COMMENT ON TABLE public.rep_locations IS
  'Last-known location per rep. Upserted in place — NO movement trail. Written only via record_rep_location() RPC, which enforces consent.';
COMMENT ON COLUMN public.rep_locations.recorded_at IS 'Device timestamp of the GPS fix.';
COMMENT ON COLUMN public.rep_locations.updated_at IS 'Server timestamp the row was last written.';

-- ---------------------------------------------------------------------------
-- 4. Helper: is_supervisor() — mirrors is_admin() from 004
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
-- 5. RLS — table is read-only to supervisors/admins; writes only via RPC
-- ---------------------------------------------------------------------------

ALTER TABLE public.rep_locations ENABLE ROW LEVEL SECURITY;

-- SELECT: a rep may see their own row (so the app can show "tracking on, last
-- sent HH:MM"); supervisors and admins see all rows.
DROP POLICY IF EXISTS rep_locations_select ON public.rep_locations;
CREATE POLICY rep_locations_select ON public.rep_locations
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR public.is_supervisor()
    OR public.is_admin()
  );

-- No INSERT / UPDATE / DELETE policies on purpose. The ONLY write path is the
-- record_rep_location() SECURITY DEFINER RPC below, which enforces consent and
-- own-row constraints in one place. Service role (Dashboard) bypasses RLS.

-- ---------------------------------------------------------------------------
-- 6. record_rep_location() — the only client write path
--    Enforces: authenticated, active, consent granted. Upserts own row.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_rep_location(
  p_lat        double precision,
  p_lng        double precision,
  p_accuracy_m real        DEFAULT NULL,
  p_recorded_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
  _consent   boolean;
  _status    text;
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- Coordinate sanity check (reject obviously-bad fixes before storing).
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat <  -90  OR p_lat >  90
     OR p_lng < -180  OR p_lng > 180 THEN
    RAISE EXCEPTION 'إحداثيات غير صحيحة' USING ERRCODE = '22023'; -- invalid coordinates
  END IF;

  -- Consent + account-status gate.
  SELECT location_consent, status INTO _consent, _status
  FROM public.users
  WHERE id = _caller_id;

  IF _status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'الحساب غير مفعل' USING ERRCODE = '42501'; -- account not active
  END IF;

  IF _consent IS NOT TRUE THEN
    RAISE EXCEPTION 'لم يتم منح إذن تتبع الموقع' USING ERRCODE = '42501'; -- consent not granted
  END IF;

  -- Upsert in place — one row per rep, no trail.
  INSERT INTO public.rep_locations (rep_id, lat, lng, accuracy_m, recorded_at, updated_at)
  VALUES (_caller_id, p_lat, p_lng, p_accuracy_m, p_recorded_at, now())
  ON CONFLICT (rep_id) DO UPDATE
    SET lat         = EXCLUDED.lat,
        lng         = EXCLUDED.lng,
        accuracy_m  = EXCLUDED.accuracy_m,
        recorded_at = EXCLUDED.recorded_at,
        updated_at  = now();
END;
$$;

COMMENT ON FUNCTION public.record_rep_location IS
  'Upserts the caller''s last-known location. Rejects unless the caller is authenticated, active, and has granted location_consent. The only client write path to rep_locations.';

REVOKE ALL ON FUNCTION public.record_rep_location(double precision, double precision, real, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_rep_location(double precision, double precision, real, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_rep_location(double precision, double precision, real, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. Consent change handling: stamp location_consent_at + audit + purge
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

-- AFTER UPDATE: write an audit row and, on revoke, purge the last-known row so
-- no stale location lingers once a rep withdraws consent.
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

    -- Revoking consent removes the stored last-known location immediately.
    IF NEW.location_consent IS NOT TRUE THEN
      DELETE FROM public.rep_locations WHERE rep_id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_audit_location_consent ON public.users;
CREATE TRIGGER trg_users_audit_location_consent
  AFTER UPDATE OF location_consent ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.audit_location_consent();

-- ============================================================================
-- End of 017_rep_location_tracking.sql
-- ============================================================================
