import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsapp/flash/desk.dart';
import 'package:newsapp/flash/engine.dart';
import 'package:newsapp/flash/flash.dart';
import 'package:newsapp/flash/prices.dart';
import 'package:newsapp/flash/store.dart';

class FakePlatform implements FlashPlatform {
  final secrets = <String, String>{'github_token': 'gh'};
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

http.Response _result(int issue, String verdict, {String headline = 'Checked headline'}) => http.Response(
    jsonEncode({
      'issue': issue,
      'event_id': 'x',
      'verdict': verdict,
      'confirmed': true,
      'headline': headline,
      'why': 'Checked.',
      'impact': [
        {'on': 'currency', 'detail': 'USD', 'level': 'high', 'dir': 'down', 'why': 'Cut.'}
      ],
      'sources': [
        {'name': 'Federal Reserve', 'url': 'https://www.federalreserve.gov/'}
      ],
      'checked_at': '2026-11-04T23:33:00+05:30',
    }),
    200);

/// A fake GitHub: numbers issues from 5 up, answers each after [after] polls.
class FakeGithub {
  FakeGithub(this.answer, {this.after = 1});
  final http.Response? Function(int issue) answer;
  final int after;
  final bodies = <String>[];
  final closed = <int>[];
  final _polls = <int, int>{};

  late final client = MockClient((req) async {
    if (req.method == 'POST') {
      bodies.add((jsonDecode(req.body) as Map)['body'] as String);
      return http.Response('{"number": ${4 + bodies.length}}', 201);
    }
    final n = int.parse(RegExp(r'(\d+)(\.json)?$').firstMatch(req.url.path)![1]!);
    if (req.method == 'PATCH') {
      closed.add(n);
      return http.Response('{}', 200);
    }
    _polls[n] = (_polls[n] ?? 0) + 1;
    if (_polls[n]! <= after) return http.Response('', 404);
    return answer(n) ?? http.Response('', 404);
  });
}

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 18, 0, 0);
  late Directory dir;
  late DateTime clock;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fl');
    clock = t0.add(const Duration(seconds: 1));
  });
  tearDown(() async {
    // Timers of the last test may still be finishing a write.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Left for the OS to clean up.
    }
  });

  FlashEngine engine(FakePlatform p,
          {FakeGithub? github,
          FlashConfig cfg = const FlashConfig(),
          String sub = 'a',
          Duration deskTimeout = const Duration(minutes: 12),
          Duration deskPoll = const Duration(milliseconds: 30)}) =>
      FlashEngine(
        store: FlashStore(Directory('${dir.path}/$sub')..createSync()),
        platform: p,
        config: () async => cfg,
        deskFor: (t) => FlashDesk(token: t, client: (github ?? FakeGithub((_) => null)).client),
        prices: Prices(MockClient((_) async => http.Response('', 500))),
        clock: () => clock,
        gather: const Duration(milliseconds: 300),
        deskPoll: deskPoll,
        deskTimeout: deskTimeout,
        checkAfter: const [],
      );

  /// Waits (up to 10 s) for timers and fake network calls to get there.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: 'timed out waiting');
  }

  Headline h(String text, {String ch = 'marketfeed', int s = 0}) =>
      Headline(text: text, channel: ch, at: t0.add(Duration(seconds: s)));

  test('a burst is one event; echoes are dropped; HOT is loud at once, then Opus checks it', () async {
    final p = FakePlatform();
    final gh = FakeGithub((n) => _result(n, 'HOT', headline: 'Fed cuts 50 bp in surprise move'));
    final e = engine(p, github: gh);
    await e.start();
    final ev = await e.ingest(h('FED UNEXPECTEDLY CUTS RATES BY 50 BPS'));
    await e.ingest(h('Fed unexpectedly cuts rates by 50 bps| FJ', ch: 'FinancialJuice')); // echo
    await e.ingest(h('POWELL: FED RATE DECISION WAS UNANIMOUS', s: 1));
    expect(ev!.headlines.length, 2);
    // Loud straight away, from the rules.
    expect(p.alerts.first.loud, isTrue);
    expect(p.alerts.first.title, 'HOT · FED UNEXPECTEDLY CUTS RATES BY 50 BPS');

    await until(() => gh.closed.isNotEmpty);
    // One issue for the whole burst, after the gather window.
    expect(gh.bodies.length, 1);
    expect(gh.bodies.single, contains('POWELL: FED RATE DECISION'));
    expect(gh.bodies.single, contains('"rules"'));
    expect(e.store.deskCount, 1);
    expect(e.store.events.single.desk?.confirmed, isTrue);
    expect(gh.closed, [5]);

    // Loud once; the Opus update is silent.
    expect(p.alerts.where((a) => a.loud).length, 1);
    expect(p.alerts.last.title, 'HOT · Fed cuts 50 bp in surprise move');
    expect(p.alerts.last.text, contains('Opus checked ✓ confirmed'));

    // Saved and readable by the app.
    final again = FlashStore(Directory('${dir.path}/a'));
    await again.load();
    expect(again.events.single.desk!.verdict, Verdict.hot);
    expect(again.tape.length, 2); // the echo was skipped
  });

  test('strong WATCH is silent until Opus calls it HOT; NOISE clears it; weak stays in the app', () async {
    final p = FakePlatform();
    final gh = FakeGithub((n) => n == 5 ? _result(n, 'HOT') : _result(n, 'NOISE'));
    final e = engine(p, github: gh);
    await e.start();
    await e.ingest(h('RBI CUTS REPO RATE BY 25 BPS'));
    expect(p.alerts.single.loud, isFalse);
    expect(p.alerts.single.title, startsWith('WATCH'));
    expect(p.alerts.single.text, contains('Rules'));
    await until(() => p.alerts.any((a) => a.loud));
    expect(p.alerts.where((a) => a.loud).length, 1);
    expect(p.alerts.last.title, startsWith('HOT'));

    await e.ingest(h('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ', s: 600));
    await until(() => p.cancelled.isNotEmpty);
    expect(p.cancelled, isNotEmpty); // NOISE removes the alert

    final before = p.alerts.length;
    await e.ingest(h('ECB HOLDS RATES UNCHANGED, AS EXPECTED', s: 1200));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(p.alerts.length, before); // no alert
    expect(gh.bodies.length, 2); // not sent to Opus
    expect(e.store.events.first.calledBy, 'Rules');
  });

  test('without a GitHub token, rules alone', () async {
    final p = FakePlatform()..secrets.clear();
    final e = engine(p);
    await e.start();
    await e.ingest(h('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ'));
    await until(() => e.store.events.single.deskError != null);
    expect(e.store.events.single.deskError, 'No GitHub token');
    expect(p.alerts.last.text, contains('Rules (No GitHub token)'));
  });

  test('daily limit, one run per running story, and a desk that never answers', () async {
    final p = FakePlatform();
    final gh = FakeGithub((_) => null);
    final e = engine(p, github: gh, deskTimeout: const Duration(milliseconds: 100));
    await e.start();
    e.store.deskDay = deskDayOf(t0);
    e.store.deskCount = 14;

    await e.ingest(h('RBI CUTS REPO RATE BY 25 BPS'));
    await until(() => e.store.deskCount == 15);
    expect(gh.bodies.length, 1);
    expect(e.store.deskCount, 15);

    // Same story 4 minutes later: a new event, but Opus isn't asked again.
    clock = t0.add(const Duration(minutes: 4));
    await e.ingest(h('RBI GOVERNOR: RATE CUT TO SUPPORT GROWTH, POLICY STANCE NEUTRAL', s: 240));
    await until(() => e.store.events.first.deskError != null);
    expect(gh.bodies.length, 1);
    expect(e.store.events.first.deskError, 'Opus checked this story already');

    // A different story: the day's limit is used up.
    clock = t0.add(const Duration(minutes: 5));
    await e.ingest(h('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ', s: 300));
    await until(() => e.store.events.first.deskError != null);
    expect(gh.bodies.length, 1);
    expect(e.store.events.first.deskError, 'Daily Opus limit (15) reached');

    // The first one timed out.
    await until(() => e.store.events.last.deskError != null);
    expect(e.store.events.last.deskError, startsWith("Opus didn't answer"));
  });

  test('a push reads the answer at once; a restarted engine picks up waiting events', () async {
    final p = FakePlatform();
    final gh = FakeGithub((n) => _result(n, 'HOT'), after: 0);
    final slow = engine(p, github: gh, deskPoll: const Duration(hours: 1));
    await slow.start();
    await slow.ingest(h('RBI CUTS REPO RATE BY 25 BPS'));
    await until(() => slow.store.events.single.issue == 5);
    expect(slow.store.events.single.desk, isNull); // next check is an hour away
    await slow.deskReady(5);
    expect(slow.store.events.single.desk!.verdict, Verdict.hot);
    expect(p.alerts.last.title, startsWith('HOT'));

    // An engine that stopped while Opus was working checks again on start.
    final store = FlashStore(Directory('${dir.path}/a'));
    await store.load();
    store.events.single
      ..desk = null
      ..issue = 6;
    await store.save(clock);
    final again = engine(FakePlatform(), github: gh);
    await again.start();
    await until(() => gh.closed.contains(6));
    expect(again.store.events.single.desk!.verdict, Verdict.hot);
  });

  test('channel filter and Telegram take-over', () async {
    final p = FakePlatform();
    final e = engine(p, cfg: const FlashConfig(hideTelegram: true));
    await e.start();
    await e.onTelegram(title: 'Some Group', text: 'FED CUTS RATES', at: t0, key: 'k1');
    expect(e.store.tape, isEmpty);
    await e.onTelegram(title: 'Market Feed 📈', text: 'FED HIKES RATES BY 25 BPS', at: t0, key: 'k2');
    expect(e.store.tape.single.headline.channel, 'marketfeed');
    expect(p.dismissed, ['k2']);
  });
}
