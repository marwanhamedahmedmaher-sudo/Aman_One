import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Cairo-local time helpers, shared across the field-task/visit/plan screens.
///
/// Uses the IANA `Africa/Cairo` zone via the `timezone` package, so display
/// matches the server's `AT TIME ZONE 'Africa/Cairo'` exactly — DST-correct
/// (Egypt reintroduced DST in 2023: +2 winter / +3 summer, incl. the Ramadan
/// suspensions) and independent of the device's own timezone setting. The tz
/// database is loaded lazily on first use, so no explicit init is needed in
/// main() (calling it again is a cheap no-op guarded below).
tz.Location? _cairo;
tz.Location get _cairoLocation {
  if (_cairo == null) {
    tzdata.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
  }
  return _cairo!;
}

/// Convert any DateTime (UTC or local) to Cairo wall-clock time.
/// `TZDateTime` is a `DateTime`, so `.hour`/`.weekday`/`.day` read as Cairo-local.
DateTime toCairo(DateTime dt) => tz.TZDateTime.from(dt, _cairoLocation);

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

/// Today's date in Cairo, as `yyyy-MM-dd` (matches server `task_date`).
String cairoTodayIso() {
  final c = toCairo(DateTime.now());
  return '${c.year.toString().padLeft(4, '0')}-'
      '${c.month.toString().padLeft(2, '0')}-'
      '${c.day.toString().padLeft(2, '0')}';
}
