/// The flash desk: for a HOT event the phone opens a GitHub issue labelled
/// `flash`; that fires the plan's Opus routine, which checks the news and
/// writes `data/flash/<issue>.json` (a few minutes later).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'flash.dart';

const _repo = 'tirthgujarati/news';
const _api = 'https://api.github.com/repos/$_repo';

/// At most this many flash desk runs a day (each uses a plan routine run).
const deskDailyLimit = 6;

class DeskException implements Exception {
  DeskException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

/// The issue the desk reads: the squawk headlines and the quick judge's call.
({String title, String body}) deskIssue(FlashEvent e) {
  final j = e.judgement;
  final payload = {
    'event_id': e.id,
    'headlines': [for (final h in e.headlines.take(10)) h.toJson()],
    'quick_judge': {
      'model': 'claude-sonnet-5-5',
      'verdict': e.verdict.label,
      'chips': [for (final c in e.chips) c.toJson()..remove('why')],
      'why': j?.why ?? '',
    },
  };
  return (
    title: 'flash: ${_clip(e.headlines.first.text.replaceAll(RegExp(r'\s+'), ' '), 90)}',
    body: 'Opened by the apex app for the flash desk. The headlines come from news squawk '
        'channels: check them before trusting.\n\n```json\n'
        '${const JsonEncoder.withIndent('  ').convert(payload)}\n```\n',
  );
}

class FlashDesk {
  FlashDesk({required this.token, http.Client? client}) : _client = client ?? http.Client();

  /// A GitHub fine-grained token limited to this repo's issues (and
  /// contents read).
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'apex-news',
      };

  /// Opens the issue; returns its number.
  Future<int> open(FlashEvent e) async {
    final issue = deskIssue(e);
    final res = await _client
        .post(Uri.parse('$_api/issues'),
            headers: _headers,
            body: jsonEncode({'title': issue.title, 'body': issue.body, 'labels': ['flash']}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) throw DeskException('GitHub token rejected');
    if (res.statusCode == 403 || res.statusCode == 404) {
      throw DeskException('GitHub token can\'t open issues on the news repo');
    }
    if (res.statusCode != 201) throw DeskException('GitHub error ${res.statusCode}');
    return (jsonDecode(res.body) as Map)['number'] as int;
  }

  /// The desk's result, or null while it's still working.
  Future<DeskResult?> result(int issue) async {
    final res = await _client
        .get(Uri.parse('$_api/contents/data/flash/$issue.json'),
            headers: {..._headers, 'Accept': 'application/vnd.github.raw+json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw DeskException('GitHub error ${res.statusCode}');
    return DeskResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Closes the issue once its result is read.
  Future<void> close(int issue) async {
    await _client
        .patch(Uri.parse('$_api/issues/$issue'), headers: _headers, body: jsonEncode({'state': 'closed'}))
        .timeout(const Duration(seconds: 15));
  }

  void dispose() => _client.close();
}
