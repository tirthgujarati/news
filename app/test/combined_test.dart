import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/models/combined.dart';
import 'package:newsapp/models/forex.dart';

final _at = DateTime.utc(2026, 11, 3, 3, 30);

ForexEvent ev(String title, {String ccy = 'AUD', String impact = 'High'}) =>
    ForexEvent(country: ccy, title: title, date: _at, impact: impact, forecast: '', previous: '');

List<String> show(List chips) => [for (final c in chips) '${c.label} ${c.arrow} ${c.level}'];

void main() {
  final rba = [ev('Cash Rate'), ev('RBA Monetary Policy Statement'), ev('RBA Rate Statement')];

  test('spots rate decisions', () {
    expect(isRateDecision('Cash Rate'), isTrue);
    expect(isRateDecision('Federal Funds Rate'), isTrue);
    expect(isRateDecision('BOJ Policy Rate'), isTrue);
    expect(isRateDecision('Official Bank Rate'), isTrue);
    expect(isRateDecision('Unemployment Rate'), isFalse);
    expect(isRateDecision('RBA Rate Statement'), isFalse);
  });

  test('before release: hawkish and dovish scenarios', () {
    final f = combine(rba, (_) => null);
    expect(f.released, isFalse);
    expect(f.rateDecision, isTrue);
    expect(show(f.ifStronger), ['AUD ▲ high', 'Gold ▲ low', 'Silver ▲ low']);
    expect(show(f.ifWeaker), ['AUD ▼ high', 'Gold ▼ low', 'Silver ▼ low']);
    expect(f.waiting, hasLength(3));
  });

  test('the rate decision outweighs two dovish statements', () {
    final v = {'Cash Rate': 'better', 'RBA Monetary Policy Statement': 'worse', 'RBA Rate Statement': 'worse'};
    final f = combine(rba, (e) => v[e.title]);
    expect(show(f.chips).first, 'AUD ▲ high');
    expect(f.flat, isFalse);
  });

  test('decision in line: statements decide; still waiting shows', () {
    final f = combine(rba, (e) => e.title == 'Cash Rate' ? 'in_line' : null);
    expect(f.released, isTrue);
    expect(f.flat, isTrue);
    expect(f.chips, isEmpty);
    expect(f.waiting.map((e) => e.title), ['RBA Monetary Policy Statement', 'RBA Rate Statement']);

    final g = combine(rba, (e) => e.title == 'Cash Rate' ? 'in_line' : 'worse');
    expect(show(g.chips).first, 'AUD ▼ high');
  });

  test('US data: red counts double, dollar moves everything else', () {
    final us = [
      ev('Non-Farm Employment Change', ccy: 'USD'),
      ev('Unemployment Rate', ccy: 'USD'),
      ev('Average Hourly Earnings m/m', ccy: 'USD', impact: 'Medium'),
    ];
    final v = {'Non-Farm Employment Change': 'worse', 'Unemployment Rate': 'worse', 'Average Hourly Earnings m/m': 'better'};
    final f = combine(us, (e) => v[e.title]);
    expect(show(f.chips), [
      'USD ▼ high', 'Gold ▲ high', 'Silver ▲ high', 'Rupee ▲ high',
      'Indian stocks ▲ medium', 'Oil ▲ medium', 'Crypto ▲ medium', 'US stocks ± medium',
    ]);

    // Equal and opposite: mixed.
    final tie = combine(us.take(2).toList(),
        (e) => e.title == 'Unemployment Rate' ? 'better' : 'worse');
    expect(tie.flat, isTrue);
    expect(show(tie.chips), ['USD ± high']);
  });

  test('a Fed hike moves US stocks down', () {
    final fed = [ev('Federal Funds Rate', ccy: 'USD'), ev('FOMC Statement', ccy: 'USD')];
    final f = combine(fed, (e) => e.title == 'Federal Funds Rate' ? 'better' : null);
    expect(show(f.chips).last, 'US stocks ▼ medium');
  });
}
