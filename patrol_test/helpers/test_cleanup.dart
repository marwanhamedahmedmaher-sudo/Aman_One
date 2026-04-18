import 'package:supabase_flutter/supabase_flutter.dart';

// Rep-side cleanup: soft-delete any merchants the authenticated test rep
// owns whose notes contain the given tag. The `merchants` RLS policies
// (see `supabase/migrations/004_rls_policies.sql`) expose UPDATE for
// the creator but have **no DELETE policy** — the design is soft-delete
// via `deleted_at`. A hard `.delete()` here would silently no-op (policy
// violation is rejected without a thrown exception via the Supabase
// client), so we UPDATE `deleted_at` instead. The merchants_select
// policy filters out `deleted_at IS NOT NULL` rows so they disappear
// from future test runs' list views and the `audit_log` keeps its
// forensic record.
//
// Returns the number of merchants soft-deleted. Best-effort: swallows
// errors and returns 0 on failure — a leaked row is recoverable manually
// via the runbook's recovery SQL.
Future<int> cleanupMerchantsByTag(String tag) async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return 0;

  try {
    final rows = await client
        .from('merchants')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .like('notes', '%$tag%')
        .isFilter('deleted_at', null)
        .select('id');
    return rows.length;
  } catch (_) {
    return 0;
  }
}
