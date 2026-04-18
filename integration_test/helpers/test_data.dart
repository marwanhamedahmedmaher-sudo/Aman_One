import 'dart:math';

// Shared run tag. Every merchant row created by this test carries this
// marker in its `notes` field so cleanup can find it unambiguously.
//   [PATROL-TEST-<yyyymmdd-hhmmss-xxxxxx>]
// The random suffix prevents parallel runs (or stuck rows from crashed
// runs) from colliding on the dedup unique constraints.
final String patrolRunTag = _buildRunTag();

String _buildRunTag() {
  final now = DateTime.now().toUtc();
  final ts = '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}'
      '-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  final rand = Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return 'PATROL-TEST-$ts-$rand';
}

// 11-digit Egyptian mobile number, Vodafone prefix 010, last 4 digits random.
// Phone trigger normalizes to +20<10 digits>. Using 010 9999 XXXX bucket
// which is not a live MSISDN allocation so real-merchant collisions are
// extremely unlikely.
String generateTestPhone() {
  final rand = Random.secure();
  final suffix = (rand.nextInt(10000)).toString().padLeft(4, '0');
  return '0109999$suffix';
}

// 14-digit Egyptian National ID that passes migration 003's structural
// trigger (century 2 or 3, valid YYMMDD, governorate 01-35 or 88,
// 4-digit serial, any checksum).
// Fixed prefix 28501010 = century 2 (1900s) + 1985-01-01 + gov 01 (Cairo),
// then 5 random digits (4 serial + 1 checksum). SHA-256 hash + national_id
// unique constraint make collisions vanishingly rare.
String generateTestNationalId() {
  final rand = Random.secure();
  final suffix = List.generate(6, (_) => rand.nextInt(10)).join();
  return '28501010$suffix';
}

// Inject the run tag into every user-visible string the test types so
// cleanup SQL can find the row from any of name, notes, or address.
String taggedName() => 'Patrol Test Merchant - $patrolRunTag';
String taggedNotes() => '[$patrolRunTag] automated regression, safe to delete';
