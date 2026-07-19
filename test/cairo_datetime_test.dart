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

  // Planning window: Thu 18:00 → Fri 14:00 Cairo (hard), soft-close Fri 12:00.
  // July = Egypt DST (+3), so Cairo wall-clock = UTC + 3h.
  // 2026-07-16 is Thursday, 2026-07-17 is Friday.
  group('planning window', () {
    test('closed before Thu 18:00', () {
      // Thu 17:59 Cairo = 14:59 UTC.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 7, 16, 14, 59)), isFalse);
    });
    test('opens at Thu 18:00', () {
      // Thu 18:00 Cairo = 15:00 UTC.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 7, 16, 15, 0)), isTrue);
    });
    test('open Fri before noon, not yet closing-soon', () {
      // Fri 11:59 Cairo = 08:59 UTC.
      final t = DateTime.utc(2026, 7, 17, 8, 59);
      expect(cairoPlanningWindowOpen(t), isTrue);
      expect(cairoPlanningWindowClosingSoon(t), isFalse);
    });
    test('closing-soon from Fri 12:00 (still open)', () {
      // Fri 12:00 Cairo = 09:00 UTC.
      final t = DateTime.utc(2026, 7, 17, 9, 0);
      expect(cairoPlanningWindowOpen(t), isTrue);
      expect(cairoPlanningWindowClosingSoon(t), isTrue);
    });
    test('still open at Fri 13:59', () {
      // Fri 13:59 Cairo = 10:59 UTC.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 7, 17, 10, 59)), isTrue);
    });
    test('hard close at Fri 14:00', () {
      // Fri 14:00 Cairo = 11:00 UTC.
      final t = DateTime.utc(2026, 7, 17, 11, 0);
      expect(cairoPlanningWindowOpen(t), isFalse);
      expect(cairoPlanningWindowClosingSoon(t), isFalse);
    });
    test('closed on Saturday', () {
      // Sat 10:00 Cairo = 07:00 UTC.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 7, 18, 7, 0)), isFalse);
    });

    // Winter = Egypt standard time (+2). Exercises the Thu/Fri cutoffs off the
    // DST branch so the window logic isn't only proven in summer.
    // 2026-01-15 is Thursday, 2026-01-16 is Friday.
    test('winter (+2): opens at Thu 18:00', () {
      // Thu 18:00 Cairo = 16:00 UTC (+2).
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 1, 15, 16, 0)), isTrue);
      // Thu 17:59 Cairo = 15:59 UTC → still closed.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 1, 15, 15, 59)), isFalse);
    });
    test('winter (+2): closing-soon Fri 12:00, hard close Fri 14:00', () {
      // Fri 12:00 Cairo = 10:00 UTC.
      final soft = DateTime.utc(2026, 1, 16, 10, 0);
      expect(cairoPlanningWindowOpen(soft), isTrue);
      expect(cairoPlanningWindowClosingSoon(soft), isTrue);
      // Fri 14:00 Cairo = 12:00 UTC → closed.
      expect(cairoPlanningWindowOpen(DateTime.utc(2026, 1, 16, 12, 0)), isFalse);
    });
  });
}
