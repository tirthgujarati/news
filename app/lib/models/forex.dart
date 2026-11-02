import 'dart:convert';

import 'edition.dart' show Source;

/// The currencies Forex Factory covers.
const forexCurrencies = ['USD', 'EUR', 'GBP', 'JPY', 'AUD', 'CAD', 'CHF', 'NZD', 'CNY'];

/// Matches an event to its result: same currency, title and moment.
String forexKey(String country, String title, DateTime date) =>
    '$country|$title|${date.toUtc().millisecondsSinceEpoch}';

/// One event from Forex Factory's calendar feed.
class ForexEvent {
  final String country;
  final String title;
  final DateTime date;

  /// "High" (red), "Medium" (orange), "Low" or "Holiday".
  final String impact;
  final String forecast;
  final String previous;

  const ForexEvent({
    required this.country,
    required this.title,
    required this.date,
    required this.impact,
    required this.forecast,
    required this.previous,
  });

  String get key => forexKey(country, title, date);

  /// Red and orange events only.
  bool get shown => impact == 'High' || impact == 'Medium';

  factory ForexEvent.fromJson(Map<String, dynamic> j) => ForexEvent(
        country: j['country'] as String,
        title: j['title'] as String,
        date: DateTime.parse(j['date'] as String),
        impact: j['impact'] as String,
        forecast: (j['forecast'] as String?) ?? '',
        previous: (j['previous'] as String?) ?? '',
      );
}

/// An actual result the news editor added for a released event.
class ForexResult {
  final String country;
  final String title;
  final DateTime date;
  final String actual;

  /// better, worse, in_line or no_forecast (for the currency).
  final String vsForecast;
  final String why;
  final Source source;

  const ForexResult({
    required this.country,
    required this.title,
    required this.date,
    required this.actual,
    required this.vsForecast,
    required this.why,
    required this.source,
  });

  String get key => forexKey(country, title, date);

  /// The JSON as it appeared in the edition (kept on the phone).
  Map<String, dynamic> toJson() => {
        'country': country,
        'title': title,
        'date': date.toUtc().toIso8601String(),
        'actual': actual,
        'vs_forecast': vsForecast,
        'why': why,
        'source': {'name': source.name, 'url': source.url},
      };

  factory ForexResult.fromJson(Map<String, dynamic> j) => ForexResult(
        country: j['country'] as String,
        title: j['title'] as String,
        date: DateTime.parse(j['date'] as String),
        actual: j['actual'] as String,
        vsForecast: j['vs_forecast'] as String,
        why: j['why'] as String,
        source: Source.fromJson(j['source'] as Map<String, dynamic>),
      );
}

/// Parses one or more Forex Factory weekly feeds (JSON arrays), oldest first,
/// without duplicates. Broken entries are skipped.
List<ForexEvent> parseForexFeeds(Iterable<String> raws) {
  final byKey = <String, ForexEvent>{};
  for (final raw in raws) {
    final Object? list;
    try {
      list = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    if (list is! List) continue;
    for (final e in list) {
      try {
        final ev = ForexEvent.fromJson(e as Map<String, dynamic>);
        byKey[ev.key] = ev;
      } catch (_) {
        // Skip an entry with a missing or odd field.
      }
    }
  }
  return byKey.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}
