-- ============================================================================
-- 008_add_products_column.sql — Product selection for lead registration
-- Adds a text[] column to store selected products per merchant.
-- Valid values: 'Microfinance', 'BP POS', 'Acceptance POS'
-- ============================================================================

-- Step 1: Add column (empty array default so ALTER succeeds on existing rows)
ALTER TABLE public.merchants
  ADD COLUMN products text[] NOT NULL DEFAULT '{}';

-- Step 2: Backfill existing rows — disable audit trigger to avoid FK error
--         (migrations run without an auth.uid(), so audit_log.actor_id would fail)
ALTER TABLE public.merchants DISABLE TRIGGER trg_merchants_audit_update;

UPDATE public.merchants
  SET products = ARRAY['Microfinance']
  WHERE products = '{}';

ALTER TABLE public.merchants ENABLE TRIGGER trg_merchants_audit_update;

-- Step 3: Enforce at least one valid product at the DB level
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_merchants_products_valid
  CHECK (
    array_length(products, 1) >= 1
    AND products <@ ARRAY['Microfinance', 'BP POS', 'Acceptance POS']::text[]
  );

COMMENT ON COLUMN public.merchants.products
  IS 'Selected product interests. At least one required. Values: Microfinance, BP POS, Acceptance POS.';

-- Pin search_path for security (consistent with migration 007)
-- No new functions introduced — column only.

-- ============================================================================
-- End of 008_add_products_column.sql
-- ============================================================================
