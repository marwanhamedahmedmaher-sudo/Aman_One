-- Migration 012: activity_types lookup table + merchant information fields
-- Adds: avg_monthly_sales, business_address, activity_type_id to merchants
-- Creates: activity_types table for configurable dropdown (admin-managed via Dashboard)

-- ============================================================
-- Part A: Create activity_types lookup table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.activity_types (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text        NOT NULL UNIQUE,
  sort_order integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.activity_types           IS 'Lookup table for merchant business activity types. Admin-managed via Supabase Dashboard Table Editor.';
COMMENT ON COLUMN public.activity_types.name       IS 'Arabic display name (e.g. سوبر ماركت, صيدلية).';
COMMENT ON COLUMN public.activity_types.sort_order IS 'Controls dropdown display order. Lower = higher.';

-- ============================================================
-- Part B: RLS on activity_types
-- ============================================================
ALTER TABLE public.activity_types ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read (for dropdown)
CREATE POLICY activity_types_select ON public.activity_types
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Only admins can write (or service role via Dashboard bypasses RLS)
CREATE POLICY activity_types_admin_insert ON public.activity_types
  FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY activity_types_admin_update ON public.activity_types
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY activity_types_admin_delete ON public.activity_types
  FOR DELETE
  USING (public.is_admin());

-- ============================================================
-- Part C: Seed initial activity types
-- ============================================================
INSERT INTO public.activity_types (name, sort_order) VALUES
  ('سوبر ماركت', 1),
  ('صيدلية', 2),
  ('مطعم', 3),
  ('كافيه', 4),
  ('بقالة', 5),
  ('ملابس', 6),
  ('إلكترونيات', 7),
  ('مواد بناء', 8),
  ('خدمات', 9),
  ('أخرى', 99);

-- ============================================================
-- Part D: Add three columns to merchants
-- ============================================================
ALTER TABLE public.merchants
  ADD COLUMN avg_monthly_sales  numeric,
  ADD COLUMN business_address   text,
  ADD COLUMN activity_type_id   uuid REFERENCES public.activity_types(id);

-- All nullable, no backfill needed — existing rows get NULL.

COMMENT ON COLUMN public.merchants.avg_monthly_sales  IS 'Approximate average monthly sales volume in EGP. Optional informational field.';
COMMENT ON COLUMN public.merchants.business_address   IS 'Business street address. Optional free-text informational field.';
COMMENT ON COLUMN public.merchants.activity_type_id   IS 'FK to activity_types lookup table. Optional — indicates the type of business.';

-- ============================================================
-- Part E: Index on FK for join performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_merchants_activity_type_id
  ON public.merchants(activity_type_id);
