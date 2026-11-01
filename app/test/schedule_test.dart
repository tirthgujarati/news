import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/background/schedule.dart';

/// IST wall-clock time as a UTC DateTime, for readable tests.
DateTime istTime(int y, int m, int d, int h, int min) =>
    DateTime.utc(y, m, d, h, min).subtract(ist);

void main() {
  test('checks at 8:00 AM, 2:00 PM and 9:00 PM IST', () {
    expect(nextCheckUtc(istTime(2026, 11, 2, 1, 55)), istTime(2026, 11, 2, 8, 0));
    expect(nextCheckUtc(istTime(2026, 11, 2, 8, 0)), istTime(2026, 11, 2, 14, 0));
    expect(nextCheckUtc(istTime(2026, 11, 2, 13, 59)), istTime(2026, 11, 2, 14, 0));
    expect(nextCheckUtc(istTime(2026, 11, 2, 14, 30)), istTime(2026, 11, 2, 21, 0));
  });

  test('after 9 PM the next check is 8 AM tomorrow, across months', () {
    expect(nextCheckUtc(istTime(2026, 11, 2, 21, 0)), istTime(2026, 11, 3, 8, 0));
    expect(nextCheckUtc(istTime(2026, 11, 30, 23, 10)), istTime(2026, 12, 1, 8, 0));
  });

  test('works from any phone time zone', () {
    final fromLocal = nextCheckUtc(istTime(2026, 11, 2, 9, 0).toLocal());
    expect(fromLocal, istTime(2026, 11, 2, 14, 0));
  });
}
