/// Backup for when Telegram's notifications aren't available: reads the
/// channels' public pages (`t.me/s/<name>`) every 15 seconds. Slower than
/// Telegram's own push (the page lags 2-50 s), but needs nothing installed.
library;

import 'package:http/http.dart' as http;

import 'flash.dart';

/// One post on a channel's public page.
class PagePost {
  final int id;
  final String text;
  final DateTime at;
  const PagePost(this.id, this.text, this.at);
}

String _unescape(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>'), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Parses a `t.me/s/<channel>` page, oldest first.
List<PagePost> parseChannelPage(String html) {
  final out = <PagePost>[];
  for (final block in html.split('tgme_widget_message_wrap').skip(1)) {
    final id = RegExp(r'data-post="[^/"]+/(\d+)"').firstMatch(block);
    final at = RegExp(r'datetime="([^"]+)"').firstMatch(block);
    final text = RegExp(r'tgme_widget_message_text[^>]*>(.*?)</div>', dotAll: true).firstMatch(block);
    if (id == null || at == null || text == null) continue;
    final t = _unescape(text[1]!);
    final when = DateTime.tryParse(at[1]!);
    if (t.isEmpty || when == null) continue;
    out.add(PagePost(int.parse(id[1]!), t, when));
  }
  return out;
}

/// The page name for a channel ("FinancialJuice" -> "financialjuice").
String pageName(String channel) => channel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

class ChannelWatcher {
  ChannelWatcher([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;
  final _lastId = <String, int>{};

  /// New posts since the last call. The first call per channel only passes
  /// on posts from the last 2 minutes.
  Future<List<Headline>> poll(String channel, DateTime now) async {
    final res = await _client
        .get(Uri.parse('https://t.me/s/${pageName(channel)}'), headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final posts = parseChannelPage(res.body);
    final last = _lastId[channel];
    final fresh = [
      for (final p in posts)
        if (last == null ? now.difference(p.at).inMinutes < 2 : p.id > last) p
    ];
    if (posts.isNotEmpty) _lastId[channel] = posts.map((p) => p.id).reduce((a, b) => a > b ? a : b);
    return [for (final p in fresh) Headline(text: p.text, channel: channel, at: p.at)];
  }

  void close() => _client.close();
}
