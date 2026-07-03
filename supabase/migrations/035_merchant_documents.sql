-- ============================================================================
-- 035_merchant_documents.sql — Deduped KYC/KYB documents + Storage bucket
-- ============================================================================
-- One row per (merchant, doc_type) — a document needed by several products is
-- captured once. Each row records WHICH evidence it is (owner_kind: kyc | kyb |
-- product | contract), where the file lives in Storage, and its verification
-- status. The binary lives in a PRIVATE Storage bucket with RLS keyed on the
-- merchant id in the object path: `merchant-documents/<merchant_id>/<doc_type>`.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.merchant_documents (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  application_id  uuid        REFERENCES public.onboarding_applications(id) ON DELETE SET NULL,
  doc_type        text        NOT NULL,   -- e.g. national_id_front, passport, doc_commercial_reg, doc_tax_card, doc_contract, doc_shop_photo
  owner_kind      text        NOT NULL DEFAULT 'kyc'
                              CHECK (owner_kind IN ('kyc', 'kyb', 'product', 'contract')),
  storage_path    text,                   -- object path in the merchant-documents bucket
  status          text        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','verified','rejected')),
  uploaded_by     uuid        REFERENCES auth.users(id),
  verified_by     uuid        REFERENCES auth.users(id),
  verified_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, doc_type)          -- deduped by type
);

COMMENT ON TABLE public.merchant_documents IS
  'Deduped onboarding documents (KYC/KYB evidence). One row per (merchant, doc_type); binary in the private merchant-documents Storage bucket at <merchant_id>/<doc_type>.';

-- UNIQUE (merchant_id, doc_type) already indexes merchant_id lookups.
CREATE INDEX IF NOT EXISTS idx_docs_application ON public.merchant_documents(application_id);

DROP TRIGGER IF EXISTS trg_docs_updated_at ON public.merchant_documents;
CREATE TRIGGER trg_docs_updated_at
  BEFORE UPDATE ON public.merchant_documents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS on the metadata rows (scoped through parent merchant ownership).
-- ---------------------------------------------------------------------------
ALTER TABLE public.merchant_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS docs_select ON public.merchant_documents;
CREATE POLICY docs_select ON public.merchant_documents FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND m.deleted_at IS NULL AND (m.created_by = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS docs_write ON public.merchant_documents;
CREATE POLICY docs_write ON public.merchant_documents FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                 AND (m.created_by = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id
                      AND (m.created_by = auth.uid() OR public.is_admin())));

-- ---------------------------------------------------------------------------
-- Private Storage bucket + RLS on the binaries.
-- Path convention: merchant-documents/<merchant_id>/<doc_type>.<ext>
-- so (storage.foldername(name))[1] is the merchant id we authorize against.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-documents', 'merchant-documents', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS merchant_docs_read ON storage.objects;
CREATE POLICY merchant_docs_read ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'merchant-documents'
    AND (
      public.is_admin()
      OR (storage.foldername(name))[1] IN (
        SELECT m.id::text FROM public.merchants m WHERE m.created_by = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS merchant_docs_write ON storage.objects;
CREATE POLICY merchant_docs_write ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'merchant-documents'
    AND (
      public.is_admin()
      OR (storage.foldername(name))[1] IN (
        SELECT m.id::text FROM public.merchants m WHERE m.created_by = auth.uid()
      )
    )
  )
  WITH CHECK (
    bucket_id = 'merchant-documents'
    AND (
      public.is_admin()
      OR (storage.foldername(name))[1] IN (
        SELECT m.id::text FROM public.merchants m WHERE m.created_by = auth.uid()
      )
    )
  );

-- ============================================================================
-- End of 035_merchant_documents.sql
-- ============================================================================
