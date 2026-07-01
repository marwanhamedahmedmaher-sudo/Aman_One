-- ============================================================================
-- 022_governorates.sql — Egyptian governorates lookup (dropdown source)
--
-- Used by the field-visit form's "المحافظة" dropdown (missions 1 & 2). ids are
-- the OFFICIAL Egyptian governorate codes — the same 2-digit codes embedded in
-- the National ID (see 003_national_id_trigger.sql), so a visit's governorate
-- can be cross-checked against a merchant's NID later.
--
-- Posture mirrors activity_types (012): authenticated SELECT, admin-only writes.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.governorates (
  id         smallint    PRIMARY KEY,            -- official governorate code
  name_ar    text        NOT NULL UNIQUE,
  sort_order smallint    NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.governorates         IS 'Egyptian governorates lookup for the field-visit dropdown. id = official governorate code (matches NID).';
COMMENT ON COLUMN public.governorates.id      IS 'Official Egyptian governorate code (same codes used in the National ID).';
COMMENT ON COLUMN public.governorates.name_ar IS 'Arabic display name.';

ALTER TABLE public.governorates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS governorates_select ON public.governorates;
CREATE POLICY governorates_select ON public.governorates
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS governorates_admin_insert ON public.governorates;
CREATE POLICY governorates_admin_insert ON public.governorates
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS governorates_admin_update ON public.governorates;
CREATE POLICY governorates_admin_update ON public.governorates
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS governorates_admin_delete ON public.governorates;
CREATE POLICY governorates_admin_delete ON public.governorates
  FOR DELETE USING (public.is_admin());

-- Seed all 27 governorates with official codes. Idempotent on PK.
INSERT INTO public.governorates (id, name_ar, sort_order) VALUES
  ( 1, 'القاهرة',          1),
  ( 2, 'الإسكندرية',       2),
  ( 3, 'بورسعيد',          3),
  ( 4, 'السويس',           4),
  (11, 'دمياط',            5),
  (12, 'الدقهلية',         6),
  (13, 'الشرقية',          7),
  (14, 'القليوبية',        8),
  (15, 'كفر الشيخ',        9),
  (16, 'الغربية',         10),
  (17, 'المنوفية',        11),
  (18, 'البحيرة',         12),
  (19, 'الإسماعيلية',     13),
  (21, 'الجيزة',          14),
  (22, 'بني سويف',        15),
  (23, 'الفيوم',          16),
  (24, 'المنيا',          17),
  (25, 'أسيوط',           18),
  (26, 'سوهاج',           19),
  (27, 'قنا',             20),
  (28, 'أسوان',           21),
  (29, 'الأقصر',          22),
  (31, 'البحر الأحمر',    23),
  (32, 'الوادي الجديد',   24),
  (33, 'مطروح',           25),
  (34, 'شمال سيناء',      26),
  (35, 'جنوب سيناء',      27)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- End of 022_governorates.sql
-- ============================================================================
