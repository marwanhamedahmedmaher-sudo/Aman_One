-- ============================================================================
-- 038_rep_location_tracking.sql — Story A: Rep location tracking foundation
-- Supervisor role + team mapping + latest-only location store + RLS + RPCs.
--
-- Posture (locked 2026-06-15): foreground-only periodic capture, latest-only
-- storage (one upserted row per rep), refusable consent. Location is PII —
-- writes go through a SECURITY DEFINER RPC that forces rep_id := auth.uid();
-- there is NO direct authenticated INSERT/UPDATE policy on rep_locations.
--
-- Idempotent: guarded DROP ... IF EXISTS + CREATE OR REPLACE throughout.
-- Ordered after 037. Mirrors 004 (RLS), 010 (secure RPC), 007 (search_path).
--
-- *** OWNERSHIP NOTE (prod collision) *** The 'supervisor' role, the
-- users_role_check constraint, and is_supervisor() are OWNED by the
-- feat/field-visit-logging line and are ALREADY LIVE in prod (its migration
-- 017+; prod is at 031). Parts A and B below therefore create them ONLY IF
-- ABSENT — an unconditional DROP/CREATE OR REPLACE here would clobber the
-- shipped definitions (and undo the planned P1-19 REVOKE hardening) out from
-- under the live field-visits build. On a fresh dev DB built from this
-- branch's migrations they don't exist yet, so the guards keep this file
-- reproducible-from-empty.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Part A: Role — ensure 'supervisor' is allowed by users_role_check.
-- Touches the constraint ONLY if it doesn't already admit 'supervisor'.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass
      AND conname  = 'users_role_check'
      AND pg_get_constraintdef(oid) LIKE '%supervisor%'
  ) THEN
    ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
    ALTER TABLE public.users
      ADD CONSTRAINT users_role_check
      CHECK (role IN ('sales_rep', 'admin', 'supervisor'));
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Part B: is_supervisor() helper — mirrors is_admin() (004:18), search_path
-- pinned. Created ONLY IF ABSENT: prod's live definition (field-visits line)
-- must not be replaced.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF to_regprocedure('public.is_supervisor()') IS NULL THEN
    EXECUTE $fn$
      CREATE FUNCTION public.is_supervisor()
      RETURNS boolean
      LANGUAGE sql
      SECURITY DEFINER
      STABLE
      SET search_path = public
      AS $body$
        SELECT EXISTS (
          SELECT 1 FROM public.users
          WHERE id = auth.uid() AND role = 'supervisor'
        );
      $body$;

      COMMENT ON FUNCTION public.is_supervisor IS
        'Story A: Returns true if the authenticated user has the supervisor role. '
        'SECURITY DEFINER bypasses RLS for the lookup itself. Mirrors is_admin().';
    $fn$;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Part C: rep_teams — supervisor → reps mapping (admin-managed, like activity_types)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rep_teams (
  rep_id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  supervisor_id uuid NOT NULL    REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rep_teams IS
  'Story A: Maps each rep to their supervisor. Admin-managed via Supabase '
  'Dashboard Table Editor (same posture as activity_types). Seeding is an ops '
  'concern (Story E), not part of this migration.';

CREATE INDEX IF NOT EXISTS rep_teams_supervisor_idx
  ON public.rep_teams (supervisor_id);

ALTER TABLE public.rep_teams ENABLE ROW LEVEL SECURITY;

-- SELECT: the rep themselves, their supervisor, or admin.
DROP POLICY IF EXISTS rep_teams_select ON public.rep_teams;
CREATE POLICY rep_teams_select ON public.rep_teams
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR supervisor_id = auth.uid()
    OR public.is_admin()
  );

-- No authenticated INSERT/UPDATE/DELETE policy — writes are service-role/admin
-- only (Dashboard Table Editor bypasses RLS). Mirrors activity_types admin posture.

-- ---------------------------------------------------------------------------
-- Part D: rep_locations — latest-only store (one row per rep, upserted)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rep_locations (
  rep_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat         double precision NOT NULL,
  lng         double precision NOT NULL,
  accuracy_m  real,
  captured_at timestamptz NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rep_locations IS
  'Story A: Latest-only rep location (PK rep_id, upserted). No history table '
  'for the pilot. Writes only via upsert_my_location() — no direct authenticated '
  'INSERT/UPDATE policy. Location is PII; never log lat/lng.';

ALTER TABLE public.rep_locations ENABLE ROW LEVEL SECURITY;

-- SELECT: rep sees own row; supervisor sees mapped team rows; admin sees all.
DROP POLICY IF EXISTS rep_locations_select ON public.rep_locations;
CREATE POLICY rep_locations_select ON public.rep_locations
  FOR SELECT
  USING (
    rep_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.rep_teams t
      WHERE t.rep_id = rep_locations.rep_id
        AND t.supervisor_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policy — all writes go through upsert_my_location().

-- ---------------------------------------------------------------------------
-- Part E: upsert_my_location() — rep writes own row, id forced server-side
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upsert_my_location(
  p_lat        double precision,
  p_lng        double precision,
  p_accuracy_m real,
  p_captured_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- rep_id is forced to auth.uid() — any client-supplied id is irrelevant
  -- because the function signature carries no id parameter.
  INSERT INTO public.rep_locations (rep_id, lat, lng, accuracy_m, captured_at, updated_at)
  VALUES (_caller_id, p_lat, p_lng, p_accuracy_m, p_captured_at, now())
  ON CONFLICT (rep_id) DO UPDATE
    SET lat         = EXCLUDED.lat,
        lng         = EXCLUDED.lng,
        accuracy_m  = EXCLUDED.accuracy_m,
        captured_at = EXCLUDED.captured_at,
        updated_at  = now();
END;
$$;

COMMENT ON FUNCTION public.upsert_my_location IS
  'Story A: Upserts the calling rep''s latest location. rep_id forced to '
  'auth.uid() (no id parameter) — a client cannot write another rep''s row. '
  'SECURITY DEFINER bypasses the no-write RLS on rep_locations.';

REVOKE ALL ON FUNCTION public.upsert_my_location(double precision, double precision, real, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_my_location(double precision, double precision, real, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.upsert_my_location(double precision, double precision, real, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- Part F: get_team_locations() — supervisor reads their team; admin reads all
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_team_locations()
RETURNS TABLE (
  rep_id      uuid,
  rep_name    text,
  lat         double precision,
  lng         double precision,
  accuracy_m  real,
  captured_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller_id uuid;
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- SECURITY DEFINER bypasses RLS, so scoping is enforced manually here:
  -- admin sees every rep; supervisor sees only reps mapped to them in rep_teams.
  RETURN QUERY
  SELECT l.rep_id, u.name, l.lat, l.lng, l.accuracy_m, l.captured_at
  FROM public.rep_locations l
  JOIN public.users u ON u.id = l.rep_id
  WHERE public.is_admin()
     OR EXISTS (
       SELECT 1 FROM public.rep_teams t
       WHERE t.rep_id = l.rep_id
         AND t.supervisor_id = _caller_id
     );
END;
$$;

COMMENT ON FUNCTION public.get_team_locations IS
  'Story A: Returns latest locations for the caller''s team. Supervisor → reps '
  'mapped in rep_teams; admin → all reps. SECURITY DEFINER; scoping enforced '
  'in-body. Joins public.users.name.';

REVOKE ALL ON FUNCTION public.get_team_locations() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_team_locations() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_team_locations() TO authenticated;

-- ============================================================================
-- End of 038_rep_location_tracking.sql
-- ============================================================================
