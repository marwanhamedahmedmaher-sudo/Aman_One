import 'package:supabase_flutter/supabase_flutter.dart';

// Rep-side cleanup: delete any merchants the authenticated test rep owns
// whose notes contain the given tag. RLS restricts this to the rep's own
// rows (can't touch anyone else's), so the service-role key is not needed
// in CI. `audit_log` rows are retained by design (V1 forensic record).
//
// Returns the number of merchants deleted. If the rep is not logged in or
// the delete fails, swallows the error and returns 0 — cleanup is
// best-effort, a leaked row is recoverable manually via runbook SQL.
Future<int> cleanupMerchantsByTag(String tag) async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return 0;

  try {
    final rows = await client
        .from('merchants')
        .delete()
        .like('notes', '%$tag%')
        .select('id');
    return rows.length;
  } catch (_) {
    return 0;
  }
}
