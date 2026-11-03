import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsapp/flash/flash.dart';
import 'package:newsapp/flash/judge.dart';

final _at = DateTime.utc(2026, 11, 3, 3, 30, 40);
final _event = [
  Headline(text: 'RBA RAISES CASH RATE TARGET BY 25BPS TO 4.85%, AS EXPECTED', channel: 'marketfeed', at: _at),
];

Map<String, dynamic> _reply(Map<String, dynamic> answer, {String stop = 'end_turn'}) => {
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'model': judgeModel,
      'stop_reason': stop,
      'content': [
        {'type': 'text', 'text': jsonEncode(answer)}
      ],
      'usage': {
        'input_tokens': 300,
        'output_tokens': 120,
        'cache_read_input_tokens': 900,
        'cache_creation_input_tokens': 0,
      },
    };

void main() {
  test('request: Sonnet 5.5, thinking off, low effort, schema, cached system', () {
    final body = SonnetJudge(apiKey: 'k').requestBody(
        _event,
        JudgeContext(
          now: _at.add(const Duration(seconds: 2)),
          calendar: ['09:00 AUD Cash Rate (forecast 4.85%, previous 4.60%)'],
          prices: ['USD/INR 94.86'],
        ));
    expect(body['model'], 'claude-sonnet-5-5');
    expect(body['thinking'], {'type': 'between_tools'});
    expect((body['output_config'] as Map)['effort'], 'low');
    expect(((body['output_config'] as Map)['format'] as Map)['type'], 'json_schema');
    final system = (body['system'] as List).single as Map;
    expect(system['cache_control'], {'type': 'ephemeral'});
    final user = ((body['messages'] as List).single as Map)['content'] as String;
    expect(user, contains('[09:00:40 marketfeed] RBA RAISES'));
    expect(user, contains('Now: 09:00:42 IST'));
    expect(user, contains('AUD Cash Rate'));
    // The cached part must stay byte-identical between calls.
    expect(judgeSystem.contains(RegExp(r'\d{2}:\d{2}:\d{2}')), isFalse);
  });

  test('parses the answer, costs the call, trims chips', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
          jsonEncode(_reply({
            'verdict': 'WATCH',
            'is_new': false,
            'headline': 'RBA hikes to 4.85%, as expected',
            'why': 'Fully priced in.',
            'chips': [
              {'on': 'currency', 'detail': 'AUD', 'level': 'low', 'dir': 'up'},
              {'on': 'currency', 'detail': 'AUD', 'level': 'low', 'dir': 'up'}, // repeat
              {'on': 'company', 'detail': '', 'level': 'low', 'dir': 'up'}, // no name
            ],
          })),
          200);
    });
    final (j, cost) = await SonnetJudge(apiKey: 'sk-test', client: client)
        .judge(_event, JudgeContext(now: _at));
    expect(sent.headers['x-api-key'], 'sk-test');
    expect(sent.headers['anthropic-version'], '2023-06-01');
    expect(j.verdict, Verdict.watch);
    expect(j.isNew, isFalse);
    expect([for (final c in j.chips) '${c.label} ${c.arrow} ${c.level}'], ['AUD ▲ low']);
    // 300 in x $2 + 120 out x $10 + 900 cached x $0.20, per million.
    expect(cost, closeTo((300 * 2 + 120 * 10 + 900 * 0.2) / 1e6, 1e-12));
  });

  test('errors become short reasons', () async {
    Future<String> reason(http.Response r) async {
      try {
        await SonnetJudge(apiKey: 'k', client: MockClient((_) async => r)).judge(_event, JudgeContext(now: _at));
        return 'ok';
      } on JudgeException catch (e) {
        return e.message;
      }
    }

    expect(await reason(http.Response('{}', 401)), 'API key rejected');
    expect(await reason(http.Response('{"error":{"message":"bad field"}}', 400)), 'Request refused: bad field');
    expect(await reason(http.Response(jsonEncode(_reply({}, stop: 'refusal')), 200)), 'Claude declined this one');
  });

  test('retries once when Claude is overloaded', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) return http.Response('{}', 529);
      return http.Response(
          jsonEncode(_reply({'verdict': 'HOT', 'is_new': true, 'headline': 'x', 'why': 'y', 'chips': []})), 200);
    });
    final (j, _) = await SonnetJudge(apiKey: 'k', client: client).judge(_event, JudgeContext(now: _at));
    expect(calls, 2);
    expect(j.verdict, Verdict.hot);
  });

  test('spend: monthly limit and daily share', () {
    final s = Spend.fresh(DateTime(2026, 11, 3, 9));
    const limit = 200 / 95; // ₹200 at ₹95 per US$
    expect(s.blockedBy(monthlyUsd: limit), isNull);
    s.add(0.2);
    expect(s.blockedBy(monthlyUsd: limit), "Today's share of the limit used");
    s.roll(DateTime(2026, 11, 4, 9));
    expect(s.blockedBy(monthlyUsd: limit), isNull);
    s.add(2.0);
    expect(s.blockedBy(monthlyUsd: limit), 'Monthly limit reached');
    s.roll(DateTime(2026, 12, 1, 0, 5));
    expect(s.usd, 0);
    expect(s.calls, 0);
  });
}
