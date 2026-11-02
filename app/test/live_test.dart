import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/models/forex.dart';
import 'package:newsapp/models/live.dart';

List<LiveRow> rows() =>
    parseMyfxbookRss(File('test/fixtures/myfxbook.xml').readAsStringSync());

ForexEvent ev(String ccy, String title, DateTime utc, {String impact = 'High', String forecast = ''}) =>
    ForexEvent(country: ccy, title: title, date: utc, impact: impact, forecast: forecast, previous: '');

void main() {
  test('reads Myfxbook rows: currency, time, previous, consensus, actual', () {
    final r = rows();
    final ism = r.firstWhere((x) => x.title == 'ISM Manufacturing PMI');
    expect(ism.country, 'USD');
    expect(ism.date, DateTime.utc(2026, 11, 2, 15, 0));
    expect(ism.consensus, '54.6');
    expect(ism.released, isFalse);

    final de = r.firstWhere((x) => x.title.contains('Germany Retail Sales MoM'));
    expect(de.country, 'EUR');
    expect(de.actual, '-2.0%');
    expect(r.firstWhere((x) => x.title.contains('Angola')).country, isNull);
  });

  test("matches Forex Factory names to Myfxbook's", () {
    final r = rows();
    final ism = matchLive(
        ev('USD', 'ISM Manufacturing PMI', DateTime.utc(2026, 11, 2, 15, 0), impact: 'Medium'), r);
    expect(ism?.consensus, '54.6');

    final de = matchLive(ev('EUR', 'German Retail Sales m/m', DateTime.utc(2026, 11, 2, 7, 0)), r);
    expect(de?.actual, '-2.0%');

    // Same name, wrong time: no match.
    expect(matchLive(ev('USD', 'ISM Manufacturing PMI', DateTime.utc(2026, 11, 2, 16, 0)), r), isNull);
    // Speech with no numbers still matches by name and time.
    expect(matchLive(ev('USD', 'FOMC Member Goolsbee Speaks', DateTime.utc(2026, 11, 2, 16, 15)), r),
        isNotNull);
  });

  test('better or worse for the currency, units and "lower is better"', () {
    expect(verdict('ISM Manufacturing PMI', '55.1', '54.6'), 'better');
    expect(verdict('Retail Sales m/m', '-2.0%', '0.4%'), 'worse');
    expect(verdict('Unemployment Rate', '7.3%', '7.7%'), 'better');
    expect(verdict('Unemployment Claims', '231K', '225K'), 'worse');
    expect(verdict('JOLTS Job Openings', '7.20M', '7.11M'), 'better');
    expect(verdict('Trade Balance', '-\$3.2B', '-\$3.5B'), 'better');
    expect(verdict('CPI m/m', '0.3%', '0.3%'), 'in_line');
    expect(verdict('Fed Chair Speaks', 'n/a', ''), 'no_forecast');
    expect(parseFigure('7.11M'), 7110000);
    expect(parseFigure('4.85%'), 4.85);
  });

  test('instant chips: weak US data -> USD down, gold and rupee up, in red', () {
    final e = ev('USD', 'ISM Manufacturing PMI', DateTime.utc(2026, 11, 2, 15));
    final chips = instantChips(e, '52.1', '54.6', 'worse');
    expect(chips.map((c) => '${c.label} ${c.arrow} ${c.level}'),
        ['USD ▼ high', 'Gold ▲ high', 'Rupee ▲ high']);

    final eur = ev('EUR', 'German Retail Sales m/m', DateTime.utc(2026, 11, 2, 7), impact: 'Medium');
    expect(instantChips(eur, '1.0%', '0.4%', 'better').map((c) => '${c.label} ${c.arrow} ${c.level}'),
        ['EUR ▲ medium']);
    expect(instantChips(eur, '0.4%', '0.4%', 'in_line'), isEmpty);
  });

  test('checks every second around a release, once a minute otherwise', () {
    final release = DateTime.utc(2026, 11, 2, 15);
    final events = [ev('USD', 'ISM Manufacturing PMI', release)];
    bool none(ForexEvent _) => false;
    bool got(ForexEvent _) => true;

    expect(nextPollDelay(release.subtract(const Duration(hours: 2)), events, none),
        const Duration(minutes: 1));
    // 50 s before: wake 30 s later, at the 20 s lead.
    expect(nextPollDelay(release.subtract(const Duration(seconds: 50)), events, none),
        const Duration(seconds: 30));
    expect(nextPollDelay(release.subtract(const Duration(seconds: 10)), events, none),
        const Duration(seconds: 1));
    expect(nextPollDelay(release.add(const Duration(seconds: 3)), events, none),
        const Duration(seconds: 1));
    expect(isHot(release.add(const Duration(seconds: 3)), events, none), isTrue);
    // Actual arrived: back to quiet.
    expect(nextPollDelay(release.add(const Duration(seconds: 3)), events, got),
        const Duration(minutes: 1));
    // Gave up 5 minutes after release.
    expect(nextPollDelay(release.add(const Duration(minutes: 6)), events, none),
        const Duration(minutes: 1));
    // Low-impact events never trigger fast checks.
    final low = [ev('USD', 'Something', release, impact: 'Low')];
    expect(nextPollDelay(release, low, none), const Duration(minutes: 1));
  });
}
