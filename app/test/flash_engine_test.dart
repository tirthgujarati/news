import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsapp/flash/desk.dart';
import 'package:newsapp/flash/engine.dart';
import 'package:newsapp/flash/flash.dart';
import 'package:newsapp/flash/judge.dart';
import 'package:newsapp/flash/prices.dart';
import 'package:newsapp/flash/store.dart';

class FakePlatform implements FlashPlatform {
  final secrets = <String, String>{'anthropic_key': 'sk', 'github_token': 'gh'};
  final alerts = <FlashAlert>[];
  final cancelled = <int>[];
  final dismissed = <String>[];
  int changes = 0;

  @override
  Future<String?> secret(String name) async => secrets[name];
  @override
  Future<void> alert(FlashAlert a) async => alerts.add(a);
  @override
  Future<void> cancelAlert(int id) async => cancelled.add(id);
  @override
  Future<void> dismissSource(String key) async => dismissed.add(key);
  @override
  void changed() => changes++;
}

http.Response _sonnet(String verdict, {List chips = const []}) => http.Response(
    jsonEncode({
      'stop_reason': 'end_turn',
      'content': [
        {
          'type': 'text',
          'text': jsonEncode({
            'verdict': verdict,
            'is_new': true,
            'headline': 'Fed cuts rates by 50 bps in surprise move',
            'why': 'A surprise cut weakens the dollar.',
            'chips': chips,
          })
        }
      ],
      'usage': {'input_tokens': 400, 'output_tokens': 100, 'cache_read_input_tokens': 700},
    }),
    200);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('fl'));
  tearDown(() async {
    // Timers of the last test may still be finishing a write.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Left for the OS to clean up.
    }
  });

  final t0 = DateTime.utc(2026, 11, 4, 18, 0, 0);

  FlashEngine engine(FakePlatform p,
          {required http.Client claude, http.Client? github, FlashConfig cfg = const FlashConfig(), String sub = 'a'}) =>
      FlashEngine(
        store: FlashStore(Directory('${dir.path}/$sub')..createSync()),
        platform: p,
        config: () async => cfg,
        calendar: () async => const [],
        judgeFor: (k) => SonnetJudge(apiKey: k, client: claude),
        deskFor: (t) => FlashDesk(token: t, client: github ?? MockClient((_) async => http.Response('', 404))),
        prices: Prices(MockClient((_) async => http.Response('', 500))),
        clock: () => t0.add(const Duration(seconds: 1)),
        gather: const Duration(milliseconds: 500),
        deskPoll: const Duration(milliseconds: 30),
        checkAfter: const [],
      );

  Headline h(String text, {String ch = 'marketfeed', int s = 0}) =>
      Headline(text: text, channel: ch, at: t0.add(Duration(seconds: s)));

  test('a burst is one event, judged once; echoes are dropped; HOT goes to the desk', () async {
    final p = FakePlatform();
    var claudeCalls = 0;
    final claude = MockClient((req) async {
      claudeCalls++;
      final body = jsonDecode(req.body) as Map;
      final user = ((body['messages'] as List).single as Map)['content'] as String;
      // Both burst headlines are in the one call.
      expect(user, contains('FED UNEXPECTEDLY CUTS RATES BY 50 BPS'));
      expect(user, contains('POWELL'));
      return _sonnet('HOT', chips: [
        {'on': 'currency', 'detail': 'USD', 'level': 'high', 'dir': 'down'},
        {'on': 'gold', 'detail': '', 'level': 'high', 'dir': 'up'},
      ]);
    });
    var opened = 0;
    var polls = 0;
    final github = MockClient((req) async {
      if (req.method == 'POST') {
        opened++;
        return http.Response('{"number": 5}', 201);
      }
      if (req.method == 'PATCH') return http.Response('{}', 200);
      polls++;
      if (polls < 2) return http.Response('', 404);
      return http.Response(
          jsonEncode({
            'issue': 5,
            'event_id': 'x',
            'verdict': 'HOT',
            'confirmed': true,
            'headline': 'Fed cuts 50 bp in surprise move',
            'why': 'Dollar falls.',
            'impact': [
              {'on': 'currency', 'detail': 'USD', 'level': 'high', 'dir': 'down', 'why': 'Cut.'}
            ],
            'sources': [
              {'name': 'Federal Reserve', 'url': 'https://www.federalreserve.gov/'}
            ],
            'checked_at': '2026-11-04T23:33:00+05:30',
          }),
          200);
    });
    final e = engine(p, claude: claude, github: github);
    await e.start();
    final ev = await e.ingest(h('FED UNEXPECTEDLY CUTS RATES BY 50 BPS'));
    await e.ingest(h('Fed unexpectedly cuts rates by 50 bps| FJ', ch: 'FinancialJuice')); // echo
    await e.ingest(h('POWELL: FED RATE DECISION WAS UNANIMOUS', s: 1));
    expect(ev, isNotNull);
    expect(ev!.headlines.length, 2);

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(claudeCalls, 1);
    expect(e.store.events.single.judgement!.verdict, Verdict.hot);
    expect(opened, 1);
    expect(e.store.events.single.issue, 5);
    expect(e.store.deskCount, 1);
    expect(e.store.events.single.desk?.confirmed, isTrue);
    expect(e.store.spend!.calls, 1);

    // Rules alone were already HOT-strong: one loud alert, then silent updates.
    expect(p.alerts.where((a) => a.loud).length, 1);
    expect(p.alerts.last.title, 'HOT · Fed cuts 50 bp in surprise move');
    expect(p.alerts.last.text, contains('Opus checked ✓ confirmed'));

    // Saved and readable by the app.
    final again = FlashStore(Directory('${dir.path}/a'));
    await again.load();
    expect(again.events.single.desk!.verdict, Verdict.hot);
    expect(again.tape.length, 2); // the echo was skipped
  });

  test('NOISE clears the alert; WATCH is silent; no key falls back to rules', () async {
    final p = FakePlatform();
    final e = engine(p, claude: MockClient((_) async => _sonnet('WATCH')));
    await e.start();
    await e.ingest(h('ECB HOLDS RATES UNCHANGED, AS EXPECTED'));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(p.alerts.single.loud, isFalse);
    expect(p.alerts.single.title, startsWith('WATCH'));

    final p2 = FakePlatform()..secrets.remove('anthropic_key');
    final e2 = engine(p2, claude: MockClient((_) async => _sonnet('HOT')), sub: 'b');
    await e2.start();
    await e2.ingest(h('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ'));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(e2.store.events.single.judgeError, 'No Claude API key');
    expect(p2.alerts.last.text, contains('Rules (No Claude API key)'));
  });

  test('channel filter and Telegram take-over', () async {
    final p = FakePlatform();
    final e = engine(p,
        claude: MockClient((_) async => _sonnet('NOISE')),
        cfg: const FlashConfig(hideTelegram: true));
    await e.start();
    await e.onTelegram(title: 'Some Group', text: 'FED CUTS RATES', at: t0, key: 'k1');
    expect(e.store.tape, isEmpty);
    await e.onTelegram(title: 'Market Feed 📈', text: 'FED HIKES RATES BY 25 BPS', at: t0, key: 'k2');
    expect(e.store.tape.single.headline.channel, 'marketfeed');
    expect(p.dismissed, ['k2']);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(p.cancelled, isNotEmpty); // NOISE removes the alert
  });

  test('monthly limit stops Claude calls', () async {
    final p = FakePlatform();
    var calls = 0;
    final e = engine(p, claude: MockClient((_) async {
      calls++;
      return _sonnet('WATCH');
    }));
    await e.start();
    e.store.spend!.usd = 5; // over ₹200
    await e.ingest(h('RBI CUTS REPO RATE BY 25 BPS'));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(calls, 0);
    expect(e.store.events.single.judgeError, 'Monthly limit reached');
  });
}
