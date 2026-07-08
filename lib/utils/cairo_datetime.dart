/// Cairo-local time helpers, shared across the field-task/visit/plan screens.
///
/// NOTE: Egypt reintroduced DST in 2023, so the true Cairo offset is +2 in
/// winter and +3 in summer. The app has historically assumed a fixed +2; these
/// helpers centralize that assumption so a proper DST fix (or an intl/timezone
/// package) can be applied in ONE place instead of the 8+ copies that existed
/// before. See the DST cleanup ticket. Server-side timestamps are already
/// computed with `AT TIME ZONE 'Africa/Cairo'` (DST-aware) — only client
/// *display* uses this fixed offset.
const Duration kCairoOffset = Duration(hours: 2);

/// Convert a (UTC or local) DateTime to Cairo wall-clock time.
DateTime toCairo(DateTime dt) => dt.toUtc().add(kCairoOffset);

/// `HH:mm` in Cairo time (24h, zero-padded).
String cairoHm(DateTime dt) {
  final c = toCairo(dt);
  return '${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';
}

/// Arabic weekday names, Sunday-first (index 0 = Sunday).
const List<String> kArabicWeekdaysSundayFirst = [
  'الأحد',
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
];

/// Arabic weekday name for a Cairo-local DateTime.
/// Maps Dart's `DateTime.weekday` (Mon=1..Sun=7) to the Sunday-first array.
String cairoWeekdayAr(DateTime dt) {
  final c = toCairo(dt);
  final idx = c.weekday == DateTime.sunday ? 0 : c.weekday;
  return kArabicWeekdaysSundayFirst[idx];
}

/// e.g. "الأحد 12/7" — Arabic weekday + day/month in Cairo time.
String cairoDayLabel(DateTime dt) {
  final c = toCairo(dt);
  return '${cairoWeekdayAr(dt)} ${c.day}/${c.month}';
}
