import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/edition_store.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/data/sync.dart';
import 'package:newsapp/models/forex.dart';
import 'package:shared_preferences/shared_preferences.dart';

String feed() => File('test/fixtures/ff_week.json').readAsStringSync();
String edition() => File('test/fixtures/edition.json').readAsStringSync();

void main() {
  test('parses the feed, oldest first, red/orange marked as shown', () {
    final events = parseForexFeeds([feed()]);
    expect(events, hasLength(10));
    expect(events.first.title, 'MI Inflation Gauge m/m'); // Low, earliest
    expect(events.where((e) => e.shown), hasLength(8));
    final cash = events.firstWhere((e) => e.title == 'Cash Rate');
    expect(cash.impact, 'High');
    expect(cash.forecast, '4.85%');
    // 22:30 New York time = 09:00 IST next day.
    expect(cash.date.toUtc(), DateTime.utc(2026, 11, 3, 3, 30));
  });

  test('merges this week and next week without duplicates; skips junk', () {
    final events = parseForexFeeds([feed(), feed(), 'not json', '{"a":1}']);
    expect(events, hasLength(10));
  });

  test('editor results attach to the right event and stay on the phone', () async {
    final dir = await Directory.systemTemp.createTemp('forex_test');
    addTearDown(() => dir.delete(recursive: true));
    final store = EditionStore(dir);
    await store.init();
    await store.save(edition(), parseEdition(edition()));
    await store.saveForexFeeds([feed()]);

    final again = EditionStore(dir);
    await again.init();
    final events = parseForexFeeds(await again.readForexFeeds());
    final ism = events.firstWhere((e) => e.title == 'ISM Manufacturing PMI');
    final r = again.forexResults[ism.key];
    expect(r, isNotNull);
    expect(r!.actual, '55.1');
    expect(r.vsForecast, 'better');
    expect(again.forexResults.length, 1);
  });

  test('all 9 currencies are shown until changed in Settings', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.load();
    expect(s.forexShown, forexCurrencies.toSet());
    s.forexShown = {'USD', 'EUR'};
    expect(s.forexShown, {'USD', 'EUR'});
  });
}
