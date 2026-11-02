/// Live actual results from Myfxbook's public calendar RSS, matched to
/// Forex Factory events, and the instant read-out (better/worse, chips).
library;

import 'edition.dart' show ImpactTag;
import 'forex.dart';

/// One row of Myfxbook's calendar feed.
class LiveRow {
  /// Currency code (USD, EUR, ...), or null for countries we don't follow.
  final String? country;

  /// Event name without the country, e.g. "ISM Manufacturing PMI".
  final String title;
  final DateTime date;
  final String previous;
  final String consensus;
  final String actual;

  const LiveRow({
    required this.country,
    required this.title,
    required this.date,
    required this.previous,
    required this.consensus,
    required this.actual,
  });

  bool get released => actual.isNotEmpty;
}

/// Myfxbook country name -> currency. Euro-area members report in EUR.
const _countryCurrency = {
  'United States': 'USD',
  'Euro Area': 'EUR',
  'European Union': 'EUR',
  'Germany': 'EUR',
  'France': 'EUR',
  'Italy': 'EUR',
  'Spain': 'EUR',
  'United Kingdom': 'GBP',
  'Japan': 'JPY',
  'Australia': 'AUD',
  'Canada': 'CAD',
  'Switzerland': 'CHF',
  'New Zealand': 'NZD',
  'China': 'CNY',
};

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

String _unescape(String s) => s
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Parses Myfxbook's calendar RSS. Rows it can't read are skipped.
List<LiveRow> parseMyfxbookRss(String xml) {
  final rows = <LiveRow>[];
  for (final m in RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml)) {
    final item = m[1]!;
    final rawTitle = _unescape(
        RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?[1]?.trim() ?? '');
    final pub = RegExp(r'<pubDate>\w+, (\d+) (\w+) (\d+) (\d+):(\d+) GMT</pubDate>')
        .firstMatch(item);
    final desc = _unescape(
        RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(item)?[1] ?? '');
    final cells = RegExp(r'<td>(.*?)</td>', dotAll: true)
        .allMatches(desc)
        .map((c) => c[1]!.replaceAll(RegExp(r'<[^>]+>'), '').trim())
        .toList();
    final month = pub == null ? null : _months[pub[2]];
    if (pub == null || month == null || cells.length < 5 || rawTitle.isEmpty) continue;

    String? country;
    var title = rawTitle;
    for (final MapEntry(key: name, value: ccy) in _countryCurrency.entries) {
      if (rawTitle.startsWith('$name ')) {
        country = ccy;
        // Keep the member state in the title ("Germany ...") so it can match
        // Forex Factory's "German ..." events.
        title = ccy == 'EUR' && !name.startsWith('Euro')
            ? rawTitle
            : rawTitle.substring(name.length + 1);
        break;
      }
    }
    rows.add(LiveRow(
      country: country,
      title: title,
      date: DateTime.utc(int.parse(pub[3]!), month, int.parse(pub[1]!),
          int.parse(pub[4]!), int.parse(pub[5]!)),
      previous: cells[cells.length - 3],
      consensus: cells[cells.length - 2],
      actual: cells[cells.length - 1],
    ));
  }
  return rows;
}

const _noise = {
  'the', 'and', 's', 'p', 'hcob', 'global', 'spglobal', 'jibun', 'bank', 'au',
  'nsa', 'sa', 'final', 'prel', 'prelim', 'preliminary', 'adv', 'advance',
};

Set<String> _tokens(String title) {
  var t = title.toLowerCase()
      .replaceAll('m/m', ' mom ')
      .replaceAll('y/y', ' yoy ')
      .replaceAll('q/q', ' qoq ')
      .replaceAll(RegExp(r'\bgerman\b'), 'germany')
      .replaceAll(RegExp(r'\bfrench\b'), 'france')
      .replaceAll(RegExp(r'\bitalian\b'), 'italy')
      .replaceAll(RegExp(r'\bspanish\b'), 'spain');
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_noise.contains(w)).toSet();
}

/// How alike two event names are, 0..1.
double titleScore(String a, String b) {
  final ta = _tokens(a), tb = _tokens(b);
  if (ta.isEmpty || tb.isEmpty) return 0;
  final common = ta.intersection(tb).length;
  final smaller = ta.length < tb.length ? ta.length : tb.length;
  return common / smaller;
}

/// The Myfxbook row for a Forex Factory event: same currency, same minute,
/// most similar name. Null when nothing matches well enough.
LiveRow? matchLive(ForexEvent e, List<LiveRow> rows) {
  final same = [
    for (final r in rows)
      if (r.country == e.country && r.date.difference(e.date).inSeconds.abs() <= 60) r
  ];
  if (same.isEmpty) return null;
  LiveRow? best;
  var bestScore = 0.0;
  for (final r in same) {
    final s = titleScore(e.title, r.title);
    if (s > bestScore) {
      best = r;
      bestScore = s;
    }
  }
  if (bestScore >= 0.5) return best;
  return same.length == 1 && bestScore > 0 ? same.single : null;
}

/// "4.85%", "7.11M", "-$3.2B" -> number (units scaled). Null if not a number.
double? parseFigure(String s) {
  var t = s.trim().replaceAll(RegExp(r'[\$€£¥,%\s]'), '');
  if (t.isEmpty) return null;
  var scale = 1.0;
  final unit = t[t.length - 1].toUpperCase();
  const scales = {'K': 1e3, 'M': 1e6, 'B': 1e9, 'T': 1e12};
  if (scales.containsKey(unit)) {
    scale = scales[unit]!;
    t = t.substring(0, t.length - 1);
  }
  final v = double.tryParse(t);
  return v == null ? null : v * scale;
}

/// For these, a lower number is better for the currency.
bool _lowerIsBetter(String title) {
  final t = title.toLowerCase();
  return t.contains('unemployment') ||
      t.contains('jobless') ||
      t.contains('claimant') ||
      t.contains('claims');
}

/// better / worse / in_line for the currency, or no_forecast when there is
/// nothing to compare (speeches, statements).
String verdict(String title, String actual, String forecast) {
  final a = parseFigure(actual), f = parseFigure(forecast);
  if (a == null || f == null) return 'no_forecast';
  if ((a - f).abs() < 1e-9) return 'in_line';
  final higher = a > f;
  return higher != _lowerIsBetter(title) ? 'better' : 'worse';
}

/// The instant chips for a released result: the currency, plus Gold and the
/// Rupee (both the other way) for US events. Red for High, orange for Medium.
List<ImpactTag> instantChips(ForexEvent e, String actual, String forecast, String v) {
  if (v != 'better' && v != 'worse') return const [];
  final level = e.impact == 'High' ? 'high' : 'medium';
  final up = v == 'better';
  final why = '${e.title}: $actual vs $forecast forecast';
  return [
    ImpactTag(on: 'currency', detail: e.country, level: level, dir: up ? 'up' : 'down', why: why),
    if (e.country == 'USD') ...[
      ImpactTag(on: 'gold', detail: null, level: level, dir: up ? 'down' : 'up',
          why: 'Gold usually moves against the dollar.'),
      ImpactTag(on: 'rupee', detail: null, level: level, dir: up ? 'down' : 'up',
          why: 'A stronger dollar pushes the rupee down, and the reverse.'),
    ],
  ];
}

/// How long to wait before the next check, for a ~1 s worst case right
/// after a release and almost no traffic otherwise.
///
/// * From 20 s before a red/orange event until its actual arrives (at most
///   5 minutes after): every second.
/// * Otherwise: once a minute, but wake up in time for the next event.
Duration nextPollDelay(DateTime now, List<ForexEvent> events, bool Function(ForexEvent) hasActual) {
  const lead = Duration(seconds: 20);
  const hotFor = Duration(minutes: 5);
  const fast = Duration(seconds: 1);
  const idle = Duration(minutes: 1);
  var wait = idle;
  for (final e in events) {
    if (!e.shown) continue;
    final start = e.date.subtract(lead);
    final end = e.date.add(hotFor);
    if (!now.isBefore(start) && now.isBefore(end) && !hasActual(e)) return fast;
    if (now.isBefore(start)) {
      final until = start.difference(now);
      if (until < wait) wait = until;
    }
  }
  return wait < fast ? fast : wait;
}

/// True while [nextPollDelay] is in its every-second mode.
bool isHot(DateTime now, List<ForexEvent> events, bool Function(ForexEvent) hasActual) =>
    nextPollDelay(now, events, hasActual) == const Duration(seconds: 1) &&
    events.any((e) =>
        e.shown &&
        !now.isBefore(e.date.subtract(const Duration(seconds: 20))) &&
        now.isBefore(e.date.add(const Duration(minutes: 5))) &&
        !hasActual(e));
