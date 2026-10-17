import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/pages/main/simple_home_logic.dart';

void main() {
  group('homeMonthlyTotalsParams', () {
    test('startDay=10 且日期在月初时归入上一个周期', () {
      final params = homeMonthlyTotalsParams(
        ledgerId: 7,
        now: DateTime(2026, 10, 5),
        startDay: 10,
      );

      expect(params.ledgerId, 7);
      expect(params.month, DateTime(2026, 9, 1));
    });

    test('startDay=1 时保持自然月', () {
      final params = homeMonthlyTotalsParams(
        ledgerId: 1,
        now: DateTime(2026, 10, 5),
        startDay: 1,
      );

      expect(params.month, DateTime(2026, 10, 1));
    });

    test('起始日当天归入新周期', () {
      final params = homeMonthlyTotalsParams(
        ledgerId: 1,
        now: DateTime(2026, 10, 10),
        startDay: 10,
      );

      expect(params.month, DateTime(2026, 10, 1));
    });
  });
}
