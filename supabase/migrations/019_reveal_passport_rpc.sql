-- ============================================================================
-- 019_reveal_passport_rpc.sql — Foreigner counterpart to reveal_national_id
-- ============================================================================
-- Migration 018 lets foreigners onboard with a passport (national_id NULL,
-- passport_number set). The reveal-with-audit path (migration 010) only knew
-- about the National ID, so a foreigner's masked identity could never be
-- revealed. This adds the symmetric RPC: same SECURITY DEFINER + ownership
-- check + atomic audit-row pattern, but for passport_number and with its own
-- audit action ('passport_revealed') so the audit trail stays unambiguous.
--
-- The Flutter merchant profile picks reveal_national_id vs reveal_passport_number
-- based on the merchant's id_document_type.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reveal_passport_number(p_merchant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _pp        text;
  _caller_id uuid;
BEGIN
  _caller_id := auth.uid();

  IF _caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح' USING ERRCODE = '42501'; -- not authorized
  END IF;

  -- Fetch passport only if caller owns the merchant or is admin.
  -- RLS is bypassed (SECURITY DEFINER), so we enforce access manually.
  SELECT m.passport_number INTO _pp
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.deleted_at IS NULL
    AND (m.created_by = _caller_id OR public.is_admin());

  IF _pp IS NULL THEN
    RAISE EXCEPTION 'العميل غير موجود أو غير مصرح بالوصول'
      USING ERRCODE = '42501'; -- merchant not found / access denied / not a passport merchant
  END IF;

  -- Write audit row — non-bypassable, same transaction.
  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    _caller_id,
    'passport_revealed',
    'merchants',
    p_merchant_id,
    NULL,
    jsonb_build_object('revealed_at', now())
  );

  RETURN _pp;
END;
$$;

COMMENT ON FUNCTION public.reveal_passport_number IS
  'Foreigner counterpart to reveal_national_id (mig. 010): returns plaintext '
  'passport_number for a merchant the caller owns (or admin), writing a '
  'passport_revealed audit row in the same transaction. SECURITY DEFINER.';

-- Grant to authenticated users only (anon cannot call).
REVOKE ALL ON FUNCTION public.reveal_passport_number(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reveal_passport_number(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reveal_passport_number(uuid) TO authenticated;

-- ============================================================================
-- End of 019_reveal_passport_rpc.sql
-- ============================================================================
