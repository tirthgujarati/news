import 'package:intl/intl.dart';

import '../models/edition.dart';

final _time = DateFormat('h:mm a');
final _day = DateFormat('MMM d');

/// "4:22 PM" for stories from the edition's own day, else "OCT 31".
String storyTime(Story s, String editionDate) {
  final local = s.publishedAt.toLocal();
  final sameDay = DateFormat('yyyy-MM-dd').format(local) == editionDate;
  if (sameDay && !s.publishedDateOnly) return _time.format(local);
  // A date-only time is midnight at the source: show the source's own date,
  // not that midnight converted to India time.
  final d = s.publishedDateOnly
      ? DateTime.parse((s.raw['published_at'] as String).substring(0, 10))
      : local;
  return _day.format(d).toUpperCase();
}

String clock(DateTime t) => _time.format(t.toLocal());

/// "just now", "25 min ago", "3h ago", "2d ago".
String ago(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// "FRI" when a market price is from an earlier day than the edition.
String? staleDay(DateTime asOf, String editionDate) {
  final local = asOf.toLocal();
  if (DateFormat('yyyy-MM-dd').format(local) == editionDate) return null;
  return DateFormat('EEE').format(local).toUpperCase();
}

/// "Mon 2 Nov"
String dayLabel(DateTime d) => DateFormat('EEE d MMM').format(d);

/// "Mon 2 Nov, 7:34 AM"
String editionStamp(Edition e) =>
    '${DateFormat('EEE d MMM').format(e.generatedAt.toLocal())}, ${clock(e.generatedAt)}';

/// First sentence of a summary, for list rows.
String firstSentence(String text) {
  final i = text.indexOf('. ');
  return i < 0 ? text : text.substring(0, i + 1);
}

String bytes(int n) {
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String sectionTitle(String id) => switch (id) {
      'india' => 'India',
      'world' => 'World',
      'currency' => 'Currency Desk',
      'markets' => 'Money & Markets',
      'built' => 'Built This Week',
      _ => id,
    };
