import 'package:flutter_test/flutter_test.dart';
import 'package:aman_sales_app/utils/cairo_datetime.dart';

void main() {
  test('Cairo DST: summer UTC noon -> 15:00 (+3)', () {
    // 2026-07-15 is outside Ramadan and within Egypt DST (last Fri Apr–Oct).
    expect(cairoHm(DateTime.utc(2026, 7, 15, 12, 0)), '15:00');
  });
  test('Cairo standard: winter UTC noon -> 14:00 (+2)', () {
    expect(cairoHm(DateTime.utc(2026, 1, 15, 12, 0)), '14:00');
  });
  test('weekday label is Cairo-local', () {
    // 2026-07-15 12:00 UTC = 15:00 Cairo, a Wednesday.
    expect(cairoDayLabel(DateTime.utc(2026, 7, 15, 12, 0)), contains('الأربعاء'));
  });
}
