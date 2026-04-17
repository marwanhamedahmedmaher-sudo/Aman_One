-- ============================================================================
-- 009_audit_skip_no_auth.sql — Skip audit_log insert when no auth.uid()
-- Dashboard/service-role operations have no app user context. Attempting to
-- log them hits the audit_log.actor_id FK (nil UUID not in auth.users).
-- Admin actions are already captured by Supabase Dashboard audit trail (V1).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.audit_merchants_change()
RETURNS trigger AS $$
DECLARE
  _action    text;
  _record_id uuid;
  _old_data  jsonb;
  _new_data  jsonb;
  _actor     uuid;
BEGIN
  -- Skip audit when there is no authenticated app user (Dashboard / migration)
  _actor := auth.uid();
  IF _actor IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  _action := TG_OP;

  IF TG_OP = 'INSERT' THEN
    _record_id := NEW.id;
    _old_data  := NULL;
    _new_data  := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    _record_id := NEW.id;
    _old_data  := to_jsonb(OLD);
    _new_data  := to_jsonb(NEW);

    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      _action := 'SOFT_DELETE';
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    _record_id := OLD.id;
    _old_data  := to_jsonb(OLD);
    _new_data  := NULL;
  END IF;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (_actor, _action, 'merchants', _record_id, _old_data, _new_data);

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

-- ============================================================================
-- End of 009_audit_skip_no_auth.sql
-- ============================================================================
