import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;

import 'package:http/http.dart' as http;

/// Where the scheduled news task publishes editions.
const dataBaseUrl =
    'https://raw.githubusercontent.com/tirthgujarati/news/main/data/';

/// Forex Factory's public weekly calendar feeds (red/orange/low events).
const forexThisWeekUrl = 'https://nfs.faireconomy.media/ff_calendar_thisweek.json';
const forexNextWeekUrl = 'https://nfs.faireconomy.media/ff_calendar_nextweek.json';

/// Myfxbook's public calendar RSS: has actual results right after release.
const liveCalendarUrl = 'https://www.myfxbook.com/rss/forex-economic-calendar-events';

/// Some photo and data servers refuse requests that don't say who they are.
const userAgent = 'apex-news/1.0 (Android; personal news reader)';

const _timeout = Duration(seconds: 20);

class RemoteIndexEntry {
  final String editionId;
  final String path;
  const RemoteIndexEntry({required this.editionId, required this.path});
}

/// Reads the public data files from GitHub. No login or keys are needed.
class Remote {
  Remote([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  /// Editions still in the repo (last 7 days), newest first.
  Future<List<RemoteIndexEntry>> fetchIndex() async {
    // A changing query string skips GitHub's few-minute cache.
    final bust = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final body = await _get('${dataBaseUrl}index.json?t=$bust');
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['editions'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteIndexEntry(
        editionId: m['edition_id'] as String,
        path: m['path'] as String,
      );
    }).toList();
  }

  /// The edition's JSON text. [path] is relative to data/.
  Future<String> fetchEdition(String path) => _get('$dataBaseUrl$path');

  /// Forex Factory's public calendar: this week, plus next week once it's
  /// published (it may not exist yet early in the week).
  Future<List<String>> fetchForexFeeds() async {
    final thisWeek = await _get(forexThisWeekUrl);
    String? nextWeek;
    try {
      nextWeek = await _get(forexNextWeekUrl);
    } catch (_) {
      nextWeek = null;
    }
    return [thisWeek, ?nextWeek];
  }

  /// Myfxbook's calendar, which has actual results seconds after release,
  /// plus the server's clock (to correct a phone clock that is off).
  /// Uses the same kept-alive connection every time, so each check is just
  /// a ~5 KB gzip transfer with no new handshake.
  Future<(String, DateTime?)> fetchLiveCalendar() async {
    final res = await _client
        .get(Uri.parse(liveCalendarUrl), headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(liveCalendarUrl));
    }
    final date = res.headers['date'];
    DateTime? server;
    try {
      server = date == null ? null : HttpDate.parse(date);
    } on HttpException {
      server = null;
    }
    return (utf8.decode(res.bodyBytes), server);
  }

  Future<String> _get(String url) async {
    final res = await _client
        .get(Uri.parse(url), headers: {'User-Agent': userAgent})
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
    }
    return utf8.decode(res.bodyBytes);
  }

  void close() => _client.close();
}
