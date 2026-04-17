-- ============================================================================
-- 011_product_details_columns.sql — Product-specific detail fields
-- Adds conditional columns for per-product data on the merchants table:
--   microfinance_amount   — required when Microfinance is selected
--   acceptance_device_count — required when Acceptance POS is selected
-- ============================================================================

-- Step 1: Add nullable columns
ALTER TABLE public.merchants
  ADD COLUMN microfinance_amount numeric,
  ADD COLUMN acceptance_device_count integer;

-- Step 2: Backfill existing rows that have these products selected
ALTER TABLE public.merchants DISABLE TRIGGER trg_merchants_audit_update;

UPDATE public.merchants
  SET microfinance_amount = 0
  WHERE 'Microfinance' = ANY(products) AND microfinance_amount IS NULL;

UPDATE public.merchants
  SET acceptance_device_count = 0
  WHERE 'Acceptance POS' = ANY(products) AND acceptance_device_count IS NULL;

ALTER TABLE public.merchants ENABLE TRIGGER trg_merchants_audit_update;

-- Step 3: CHECK — when Microfinance selected, amount must be >= 0
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_microfinance_amount
  CHECK (
    (NOT ('Microfinance' = ANY(products))) OR (microfinance_amount IS NOT NULL AND microfinance_amount >= 0)
  );

-- Step 4: CHECK — when Acceptance POS selected, device count must be >= 0
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_acceptance_device_count
  CHECK (
    (NOT ('Acceptance POS' = ANY(products))) OR (acceptance_device_count IS NOT NULL AND acceptance_device_count >= 0)
  );

-- Step 5: CHECK — when product NOT selected, detail must be NULL (keeps data clean)
ALTER TABLE public.merchants
  ADD CONSTRAINT chk_microfinance_amount_null_when_unselected
  CHECK (
    ('Microfinance' = ANY(products)) OR (microfinance_amount IS NULL)
  );

ALTER TABLE public.merchants
  ADD CONSTRAINT chk_acceptance_device_count_null_when_unselected
  CHECK (
    ('Acceptance POS' = ANY(products)) OR (acceptance_device_count IS NULL)
  );

COMMENT ON COLUMN public.merchants.microfinance_amount
  IS 'Loan/microfinance amount requested. Required when Microfinance product is selected.';

COMMENT ON COLUMN public.merchants.acceptance_device_count
  IS 'Number of POS devices needed. Required when Acceptance POS product is selected.';

-- ============================================================================
-- End of 011_product_details_columns.sql
-- ============================================================================
