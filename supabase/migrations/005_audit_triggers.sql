-- ============================================================================
-- 005_audit_triggers.sql — Audit log triggers on public.merchants
-- P0-14: Capture INSERT, UPDATE, DELETE (soft-delete) to audit_log
-- ============================================================================

CREATE OR REPLACE FUNCTION public.audit_merchants_change()
RETURNS trigger AS $$
DECLARE
  _action    text;
  _record_id uuid;
  _old_data  jsonb;
  _new_data  jsonb;
BEGIN
  _action := TG_OP;

  IF TG_OP = 'INSERT' THEN
    _record_id := NEW.id;
    _old_data  := NULL;
    _new_data  := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    _record_id := NEW.id;
    _old_data  := to_jsonb(OLD);
    _new_data  := to_jsonb(NEW);

    -- Detect soft-delete: deleted_at changed from NULL to a value
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      _action := 'SOFT_DELETE';
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    _record_id := OLD.id;
    _old_data  := to_jsonb(OLD);
    _new_data  := NULL;
  END IF;

  INSERT INTO public.audit_log (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    _action,
    'merchants',
    _record_id,
    _old_data,
    _new_data
  );

  -- Return appropriate row
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.audit_merchants_change IS 'P0-14: Writes to audit_log on every merchants INSERT/UPDATE/DELETE. Detects soft-delete pattern. SECURITY DEFINER to bypass RLS for audit_log INSERT.';

-- ---------------------------------------------------------------------------
-- Triggers — AFTER so the row is already committed and we capture final state.
-- The phone/national_id triggers (BEFORE) have already normalized the data.
-- ---------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_merchants_audit_insert ON public.merchants;
CREATE TRIGGER trg_merchants_audit_insert
  AFTER INSERT ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.audit_merchants_change();

DROP TRIGGER IF EXISTS trg_merchants_audit_update ON public.merchants;
CREATE TRIGGER trg_merchants_audit_update
  AFTER UPDATE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.audit_merchants_change();

DROP TRIGGER IF EXISTS trg_merchants_audit_delete ON public.merchants;
CREATE TRIGGER trg_merchants_audit_delete
  AFTER DELETE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.audit_merchants_change();

-- ============================================================================
-- End of 005_audit_triggers.sql
-- ============================================================================
