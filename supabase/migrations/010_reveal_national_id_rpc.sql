-- ============================================================================
-- 010_reveal_national_id_rpc.sql — P1-9: Secure NID reveal with audit trail
-- SECURITY DEFINER: returns plaintext national_id AND writes audit row
-- in one transaction. This is the ONLY client path to plaintext NID.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reveal_national_id(p_merchant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _nid       text;
  _caller_id uuid;
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- Fetch NID only if caller owns the merchant or is admin.
  -- RLS is bypassed (SECURITY DEFINER), so we enforce access manually.
  SELECT m.national_id INTO _nid
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.deleted_at IS NULL
    AND (m.created_by = _caller_id OR public.is_admin());

  IF _nid IS NULL THEN
    RAISE EXCEPTION 'العميل غير موجود أو غير مصرح بالوصول'
      USING ERRCODE = '42501'; -- merchant not found or access denied
  END IF;

  -- Write audit row — non-bypassable, same transaction
  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id,
    'national_id_revealed',
    'merchants',
    p_merchant_id,
    NULL,
    jsonb_build_object('revealed_at', now())
  );

  RETURN _nid;
END;
$$;

COMMENT ON FUNCTION public.reveal_national_id IS
  'P1-9: Returns plaintext national_id for a merchant the caller owns (or admin). '
  'Writes national_id_revealed audit row in the same transaction. '
  'SECURITY DEFINER — bypasses RLS to read NID and write audit_log atomically.';

-- Grant to authenticated users only (anon cannot call)
REVOKE ALL ON FUNCTION public.reveal_national_id(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reveal_national_id(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reveal_national_id(uuid) TO authenticated;

-- ============================================================================
-- End of 010_reveal_national_id_rpc.sql
-- ============================================================================
