import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsapp/flash/desk.dart';
import 'package:newsapp/flash/flash.dart';
import 'package:newsapp/flash/prices.dart';
import 'package:newsapp/models/edition.dart' show ImpactTag;

FlashEvent _event() => FlashEvent(
      id: 'ev-20261103-033040',
      headlines: [
        Headline(
            text: 'RBA RAISES CASH RATE TARGET BY 25BPS TO 4.85%, AS EXPECTED ...',
            channel: 'marketfeed',
            at: DateTime.utc(2026, 11, 3, 3, 30, 40)),
      ],
      topic: 'rates',
      score: 6,
      ruleChips: const [ImpactTag(on: 'currency', detail: 'AUD', level: 'high', dir: 'up', why: 'r')],
    );

void main() {
  test('desk issue carries the headlines and the quick call as JSON', () {
    final i = deskIssue(_event());
    expect(i.title, startsWith('flash: RBA RAISES CASH RATE'));
    final json = RegExp(r'```json\n(.*)\n```', dotAll: true).firstMatch(i.body)![1]!;
    final m = jsonDecode(json) as Map;
    expect(m['event_id'], 'ev-20261103-033040');
    expect((m['headlines'] as List).single['channel'], 'marketfeed');
    expect((m['quick_judge'] as Map)['chips'], [
      {'on': 'currency', 'detail': 'AUD', 'level': 'high', 'dir': 'up'}
    ]);
  });

  test('desk: opens the issue, reads the result when it exists', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      expect(req.headers['Authorization'], 'Bearer gh-test');
      if (req.method == 'POST') {
        expect((jsonDecode(req.body) as Map)['labels'], ['flash']);
        return http.Response('{"number": 12}', 201);
      }
      if (req.url.path.endsWith('/12.json')) {
        return http.Response(
            jsonEncode({
              'issue': 12,
              'event_id': 'ev-20261103-033040',
              'verdict': 'WATCH',
              'confirmed': true,
              'headline': 'RBA hikes to 4.85%, as expected',
              'why': 'Priced in.',
              'impact': [
                {'on': 'currency', 'detail': 'AUD', 'level': 'low', 'dir': 'down', 'why': 'Split vote.'}
              ],
              'sources': [
                {'name': 'RBA', 'url': 'https://www.rba.gov.au/'}
              ],
              'checked_at': '2026-11-03T13:04:41+05:30',
            }),
            200);
      }
      return http.Response('Not Found', 404);
    });
    final desk = FlashDesk(token: 'gh-test', client: client);
    expect(await desk.open(_event()), 12);
    expect(await desk.result(11), isNull);
    final r = (await desk.result(12))!;
    expect(r.verdict, Verdict.watch);
    expect(r.confirmed, isTrue);
    expect(r.sources.single.name, 'RBA');
    expect(calls.first, 'POST /repos/tirthgujarati/news/issues');
  });

  test('prices: parses minute bars, skips empty minutes', () {
    final b = parseBars(File('test/fixtures/yahoo_inr.json').readAsStringSync());
    expect(b.closes, isNotEmpty);
    expect(b.closes.length, b.times.length);
    expect(b.previousClose, 94.89);
    expect(b.dayChange, isNotNull);
    expect(b.at(b.times.first.subtract(const Duration(minutes: 1))), isNull);
    expect(b.at(b.times.last), b.last);
  });

  test('market check: chips vs how prices moved', () {
    const chips = [
      ImpactTag(on: 'rupee', detail: null, level: 'high', dir: 'down', why: ''),
      ImpactTag(on: 'gold', detail: null, level: 'high', dir: 'up', why: ''),
    ];
    // Rupee weaker = USD/INR up.
    expect(marketVerdict(chips, [const Move(name: 'USD/INR', pct: 0.2, after: 5)]), 'agrees');
    expect(marketVerdict(chips, [const Move(name: 'USD/INR', pct: -0.2, after: 5)]), 'disagrees');
    expect(marketVerdict(chips, [const Move(name: 'USD/INR', pct: 0.01, after: 5)]), 'quiet');

    final news = DateTime.utc(2026, 11, 3, 9);
    final bars = {
      'USD/INR': Bars([news.subtract(const Duration(minutes: 1)), news.add(const Duration(minutes: 5))],
          [94.0, 94.188], 94.0),
    };
    final moves = movesSince(news, 5, bars, chips);
    expect(moves.single.name, 'USD/INR');
    expect(moves.single.pct, closeTo(0.2, 1e-9));
  });
}
