-- ============================================================================
-- 036_submit_application.sql — Atomically materialize a draft into entities
-- ============================================================================
-- One RPC turns a draft onboarding_applications.payload into the normalized
-- rows, all in a single transaction (partial failure rolls everything back —
-- no orphans):
--   merchants            (identity validated + hashed by its trigger)
--   kyc_profiles         (applicant individual)
--   kyb_profiles         (company track only)
--   merchant_products    (one per product, status='pending')
--   merchant_documents   (one per captured document, status='pending')
-- then flips the application to 'submitted' and links merchant_id.
--
-- Expected payload shape (produced by the wizard):
--   { track, nationality, id_document_type,
--     kyc: { first_name.. family_name, *_en, national_id|passport_number,
--            nationality_country, birth_date, address, shop_name, legal_name_en,
--            commercial_reg, tax_card, activity_type(name), governorate, city,
--            branch_address_ar, merchant_mobile, ... },
--     products: [ { product, data: { mf_amount, mf_purpose,
--                    acc_device_type, acc_device_count, acc_device_id, acc_payment_service,
--                    bp_device_type, bp_device_count, bp_device_id, bp_bill_service } } ],
--     documents: [ { type, captured } ] }
--
-- SECURITY DEFINER: writes across tables; enforces caller ownership manually.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_application(p_application_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _caller   uuid := auth.uid();
  _app      public.onboarding_applications%ROWTYPE;
  _kyc      jsonb;
  _is_company boolean;
  _is_passport boolean;
  _merchant_id uuid;
  _name     text;
  _act_id   uuid;
  _prod     jsonb;
  _doc      jsonb;
  -- Legacy columns kept in sync during the transition (existing list/profile
  -- screens still read merchants.products[] / *_amount / *_device_count).
  _products text[];
  _mf_amount numeric;
  _acc_count int;
BEGIN
  IF _caller IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO _app FROM public.onboarding_applications
   WHERE id = p_application_id AND deleted_at IS NULL
     AND (created_by = _caller OR public.is_admin());
  IF _app.id IS NULL THEN
    RAISE EXCEPTION 'الطلب غير موجود أو غير مصرح بالوصول' USING ERRCODE = '42501';
  END IF;
  IF _app.status <> 'draft' THEN
    RAISE EXCEPTION 'تم إرسال هذا الطلب من قبل' USING ERRCODE = '22023'; -- already submitted
  END IF;

  _kyc         := COALESCE(_app.payload -> 'kyc', '{}'::jsonb);
  _is_company  := (_app.track = 'company');
  _is_passport := (_app.nationality = 'foreigner'
                   OR _app.payload ->> 'id_document_type' = 'passport');

  -- Assembled display name: full personal name, else shop name.
  _name := NULLIF(trim(concat_ws(' ',
             NULLIF(_kyc ->> 'first_name',  ''), NULLIF(_kyc ->> 'second_name', ''),
             NULLIF(_kyc ->> 'third_name',  ''), NULLIF(_kyc ->> 'family_name', ''))), '');
  _name := COALESCE(_name, NULLIF(_kyc ->> 'shop_name', ''), 'بدون اسم');

  -- Derive legacy columns from the products payload (transition dual-write).
  SELECT array_agg(p ->> 'product'),
         (max(NULLIF(p -> 'data' ->> 'mf_amount', ''))
           FILTER (WHERE p ->> 'product' = 'Microfinance'))::numeric,
         (max(NULLIF(p -> 'data' ->> 'acc_device_count', ''))
           FILTER (WHERE p ->> 'product' = 'Acceptance POS'))::int
    INTO _products, _mf_amount, _acc_count
  FROM jsonb_array_elements(COALESCE(_app.payload -> 'products', '[]'::jsonb)) AS p;

  -- 1) merchants — its BEFORE trigger validates + hashes NID/passport.
  --    products[]/*_amount/*_device_count populated for legacy screens; the
  --    merchant_products rows below are the new source of truth.
  INSERT INTO public.merchants (name, phone, id_document_type, national_id,
                                passport_number, products, microfinance_amount,
                                acceptance_device_count, status, created_by)
  VALUES (_name,
          COALESCE(NULLIF(_kyc ->> 'merchant_mobile', ''), NULLIF(_kyc ->> 'mobile', '')),
          CASE WHEN _is_passport THEN 'passport' ELSE 'national_id' END,
          CASE WHEN _is_passport THEN NULL ELSE NULLIF(_kyc ->> 'national_id', '') END,
          CASE WHEN _is_passport THEN NULLIF(_kyc ->> 'passport_number', '') ELSE NULL END,
          COALESCE(_products, ARRAY[]::text[]),
          CASE WHEN 'Microfinance'   = ANY(_products) THEN _mf_amount END,
          CASE WHEN 'Acceptance POS' = ANY(_products) THEN _acc_count END,
          'lead', _caller)
  RETURNING id INTO _merchant_id;

  -- 2) kyc_profiles — applicant individual.
  INSERT INTO public.kyc_profiles (merchant_id, application_id, role,
            first_name, second_name, third_name, family_name, first_name_en, family_name_en,
            id_document_type, national_id, passport_number, nationality, birth_date, address)
  VALUES (_merchant_id, _app.id, 'owner',
          NULLIF(_kyc ->> 'first_name', ''),  NULLIF(_kyc ->> 'second_name', ''),
          NULLIF(_kyc ->> 'third_name', ''),  NULLIF(_kyc ->> 'family_name', ''),
          NULLIF(_kyc ->> 'first_name_en', ''), NULLIF(_kyc ->> 'family_name_en', ''),
          CASE WHEN _is_passport THEN 'passport' ELSE 'national_id' END,
          CASE WHEN _is_passport THEN NULL ELSE NULLIF(_kyc ->> 'national_id', '') END,
          CASE WHEN _is_passport THEN NULLIF(_kyc ->> 'passport_number', '') ELSE NULL END,
          NULLIF(_kyc ->> 'nationality_country', ''),
          NULLIF(_kyc ->> 'birth_date', '')::date,
          NULLIF(_kyc ->> 'address', ''));

  -- 3) kyb_profiles — company track only.
  IF _is_company THEN
    SELECT id INTO _act_id FROM public.activity_types
      WHERE name = NULLIF(_kyc ->> 'activity_type', '') LIMIT 1;
    INSERT INTO public.kyb_profiles (merchant_id, application_id, legal_name, legal_name_en,
              trade_name, commercial_reg, tax_card, activity_type_id, governorate, city, business_address)
    VALUES (_merchant_id, _app.id,
            NULLIF(_kyc ->> 'shop_name', ''), NULLIF(_kyc ->> 'legal_name_en', ''),
            NULLIF(_kyc ->> 'shop_name', ''), NULLIF(_kyc ->> 'commercial_reg', ''),
            NULLIF(_kyc ->> 'tax_card', ''), _act_id,
            NULLIF(_kyc ->> 'governorate', ''), NULLIF(_kyc ->> 'city', ''),
            NULLIF(_kyc ->> 'branch_address_ar', ''));
  END IF;

  -- 4) merchant_products — one per product, status='pending'.
  FOR _prod IN SELECT * FROM jsonb_array_elements(COALESCE(_app.payload -> 'products', '[]'::jsonb))
  LOOP
    INSERT INTO public.merchant_products (merchant_id, application_id, product, status,
              amount, loan_purpose, device_type, device_count, device_id, payment_service, bill_service)
    VALUES (_merchant_id, _app.id, _prod ->> 'product', 'pending',
      CASE WHEN _prod ->> 'product' = 'Microfinance'   THEN NULLIF(_prod -> 'data' ->> 'mf_amount', '')::numeric END,
      CASE WHEN _prod ->> 'product' = 'Microfinance'   THEN NULLIF(_prod -> 'data' ->> 'mf_purpose', '') END,
      CASE WHEN _prod ->> 'product' = 'Acceptance POS' THEN NULLIF(_prod -> 'data' ->> 'acc_device_type', '')
           WHEN _prod ->> 'product' = 'BP POS'         THEN NULLIF(_prod -> 'data' ->> 'bp_device_type', '') END,
      CASE WHEN _prod ->> 'product' = 'Acceptance POS' THEN NULLIF(_prod -> 'data' ->> 'acc_device_count', '')::int
           WHEN _prod ->> 'product' = 'BP POS'         THEN NULLIF(_prod -> 'data' ->> 'bp_device_count', '')::int END,
      CASE WHEN _prod ->> 'product' = 'Acceptance POS' THEN NULLIF(_prod -> 'data' ->> 'acc_device_id', '')
           WHEN _prod ->> 'product' = 'BP POS'         THEN NULLIF(_prod -> 'data' ->> 'bp_device_id', '') END,
      CASE WHEN _prod ->> 'product' = 'Acceptance POS' THEN NULLIF(_prod -> 'data' ->> 'acc_payment_service', '') END,
      CASE WHEN _prod ->> 'product' = 'BP POS'         THEN NULLIF(_prod -> 'data' ->> 'bp_bill_service', '') END);
  END LOOP;

  -- 5) merchant_documents — one per captured document (capture-and-stub: no path yet).
  FOR _doc IN SELECT * FROM jsonb_array_elements(COALESCE(_app.payload -> 'documents', '[]'::jsonb))
  LOOP
    IF COALESCE((_doc ->> 'captured')::boolean, false) THEN
      INSERT INTO public.merchant_documents (merchant_id, application_id, doc_type, owner_kind, status, uploaded_by)
      VALUES (_merchant_id, _app.id, _doc ->> 'type',
              CASE WHEN (_doc ->> 'type') IN ('doc_commercial_reg','doc_tax_card') THEN 'kyb'
                   WHEN (_doc ->> 'type') = 'doc_contract' THEN 'contract'
                   ELSE 'kyc' END,
              'pending', _caller)
      ON CONFLICT (merchant_id, doc_type) DO NOTHING;
    END IF;
  END LOOP;

  -- 6) Finalize the application.
  UPDATE public.onboarding_applications
     SET status = 'submitted', merchant_id = _merchant_id, submitted_at = now()
   WHERE id = _app.id;

  RETURN _merchant_id;
END;
$$;

COMMENT ON FUNCTION public.submit_application IS
  'Atomically materializes a draft onboarding_applications.payload into merchants + kyc_profiles + kyb_profiles (company) + merchant_products (pending) + merchant_documents, then marks the application submitted. SECURITY DEFINER; enforces caller ownership.';

REVOKE ALL ON FUNCTION public.submit_application(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_application(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_application(uuid) TO authenticated;

-- ============================================================================
-- End of 036_submit_application.sql
-- ============================================================================
