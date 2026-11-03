/// The day so far: running stories (news that keeps coming) and the heat
/// map of what today's news pushes up or down.
library;

import '../models/edition.dart' show ImpactTag;
import 'flash.dart';
import 'rules.dart';

/// True when [t] is on the same (phone-local) day as [now].
bool sameDay(DateTime t, DateTime now) {
  final a = t.toLocal(), b = now.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

const _topicNames = {
  'rates': 'Rates',
  'oil': 'Oil',
  'war': 'War',
  'trade': 'Trade',
  'india': 'India',
  'data': 'Data',
  'crypto': 'Crypto',
  'stress': 'Markets',
  'metals': 'Metals',
};

/// One story that keeps coming through the day (a war, a central bank, an
/// oil supply scare): two or more separate bursts, at least one strong.
class Story {
  Story(this.key, this.name, this.events);

  /// "oil:HORMUZ".
  final String key;

  /// "Oil · Hormuz".
  final String name;

  /// Newest first.
  final List<FlashEvent> events;

  int get updates => events.fold(0, (n, e) => n + e.headlines.length);
  DateTime get last => events.first.headlines.map((h) => h.at).reduce((a, b) => a.isAfter(b) ? a : b);
  bool get hot => events.any((e) => e.verdict == Verdict.hot);

  /// "building" (more in the last hour than the hour before), "fading"
  /// (nothing in the last hour) or "steady".
  String momentum(DateTime now) {
    var recent = 0, before = 0;
    for (final e in events) {
      for (final h in e.headlines) {
        final m = now.difference(h.at).inMinutes;
        if (m < 60) {
          recent++;
        } else if (m < 120) {
          before++;
        }
      }
    }
    if (recent == 0) return 'fading';
    return recent > before ? 'building' : 'steady';
  }
}

const _banks = {
  'USD': 'Fed', 'INR': 'RBI', 'EUR': 'ECB', 'GBP': 'BoE', 'JPY': 'BoJ',
  'AUD': 'RBA', 'CAD': 'BoC', 'CHF': 'SNB', 'NZD': 'RBNZ', 'CNY': 'PBoC',
};

const _acronyms = {
  'OPEC', 'OPEC+', 'LNG', 'WTI', 'GST', 'SEBI', 'NSE', 'BSE', 'CPI', 'GDP', 'PMI', 'NFP', 'PCE',
  'BTC', 'INR', 'TCS', 'HDFC', 'ICICI', 'SBI', 'ITC', 'ONGC', 'NTPC', 'L&T', 'HCL',
};

/// "HORMUZ" -> "Hormuz", "OPEC+" stays, a rates subject -> its bank.
String _subjectName(String topic, String subject) {
  if (topic == 'rates') return _banks[subject] ?? subject;
  if (_acronyms.contains(subject)) return subject;
  return subject[0] + subject.substring(1).toLowerCase();
}

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Today's running stories, the most recent first.
List<Story> runningStories(List<FlashEvent> events, DateTime now) {
  final groups = <String, List<FlashEvent>>{};
  final names = <String, String>{};
  for (final e in events) {
    if (e.topic == 'move' || e.verdict == Verdict.noise || !sameDay(e.at, now)) continue;
    final subject = readHeadline(e.headlines.first.text).subject;
    final key = '${e.topic}:${subject ?? ''}';
    groups.putIfAbsent(key, () => []).add(e);
    final topic = _topicNames[e.topic] ?? _title(e.topic);
    names[key] = subject == null || subject.toLowerCase() == e.topic
        ? topic
        : '$topic · ${_subjectName(e.topic, subject)}';
  }
  final out = [
    for (final MapEntry(:key, :value) in groups.entries)
      if (value.length >= 2 && value.any((e) => e.worthDesk || e.desk != null))
        Story(key, names[key]!, value..sort((a, b) => b.at.compareTo(a.at)))
  ];
  out.sort((a, b) => b.last.compareTo(a.last));
  return out;
}

/// What the heat map adds up.
enum HeatSource {
  all('All'),
  hot('HOT'),
  running('Running'),
  calendar('Calendar');

  const HeatSource(this.label);
  final String label;
}

/// One piece of news with its chips: a Flash event or a Forex release.
class HeatItem {
  final HeatSource source;
  final String label;
  final DateTime at;
  final List<ImpactTag> chips;

  /// The Flash event behind it, if any.
  final FlashEvent? event;

  const HeatItem({required this.source, required this.label, required this.at, required this.chips, this.event});
}

/// A row of the heat map.
class Asset {
  final String name;
  final bool Function(ImpactTag) matches;

  /// The momentum-meter market showing its price, and whether a rise there
  /// means this asset fell (USD/INR up = rupee down).
  final String? market;
  final bool inverted;

  const Asset(this.name, this.matches, {this.market, this.inverted = false});
}

bool _isUsd(ImpactTag t) =>
    t.on == 'currency' && const {'USD', 'DOLLAR', 'US DOLLAR'}.contains((t.detail ?? '').toUpperCase());

final assets = [
  Asset('Gold', (t) => t.on == 'gold', market: 'Gold'),
  Asset('Silver', (t) => t.on == 'silver'),
  Asset('Oil', (t) => t.on == 'oil', market: 'Oil'),
  Asset('Rupee', (t) => t.on == 'rupee', market: 'USD/INR', inverted: true),
  Asset('Nifty', (t) => t.on == 'indian_stocks', market: 'Nifty'),
  Asset('USD', _isUsd, market: 'EUR/USD', inverted: true),
  Asset('Crypto', (t) => t.on == 'crypto', market: 'Bitcoin'),
  Asset('US stocks', (t) => t.on == 'us_stocks'),
];

const _levelWeight = {'high': 3, 'medium': 2, 'low': 1};

/// One cell: the net push on an asset and the news behind it.
class Heat {
  Heat(this.asset);
  final Asset asset;

  /// Positive = pushed up.
  int net = 0;

  /// All push, both ways.
  int total = 0;

  /// (item, signed weight), biggest first once built.
  final reasons = <(HeatItem, int)>[];

  /// "strong", "medium", "low", "mixed" or "quiet".
  String get strength {
    final n = net.abs();
    if (n >= 6) return 'strong';
    if (n >= 3) return 'medium';
    if (n >= 1) return 'low';
    return total > 0 ? 'mixed' : 'quiet';
  }

  /// 0 to 3 blocks.
  int get blocks => switch (strength) { 'strong' => 3, 'medium' => 2, 'low' => 1, _ => 0 };
}

/// Today's Flash events as heat items: HOT ones, and those in running
/// stories (an event can be both; [HeatSource.all] counts it once).
List<HeatItem> flashItems(List<FlashEvent> events, List<Story> stories, DateTime now) {
  final inStory = {for (final s in stories) for (final e in s.events) e.id};
  final out = <HeatItem>[];
  for (final e in events) {
    if (e.topic == 'move' || e.verdict == Verdict.noise || !sameDay(e.at, now)) continue;
    if (e.verdict == Verdict.hot) {
      out.add(HeatItem(source: HeatSource.hot, label: e.title, at: e.at, chips: e.chips, event: e));
    }
    if (inStory.contains(e.id)) {
      out.add(HeatItem(source: HeatSource.running, label: e.title, at: e.at, chips: e.chips, event: e));
    }
  }
  return out;
}

/// Adds up [items] (only those from [source], or all) into one cell per
/// asset.
List<Heat> heatMap(List<HeatItem> items, HeatSource source) {
  final cells = [for (final a in assets) Heat(a)];
  final counted = <String>{};
  for (final item in items) {
    if (source != HeatSource.all && item.source != source) continue;
    // In "All", an event that is both HOT and running counts once.
    final id = item.event?.id;
    if (source == HeatSource.all && id != null && !counted.add(id)) continue;
    for (final cell in cells) {
      var w = 0;
      for (final c in item.chips.where(cell.asset.matches)) {
        final lw = _levelWeight[c.level] ?? 1;
        cell.total += lw;
        w += switch (c.dir) { 'up' => lw, 'down' => -lw, _ => 0 };
      }
      if (w == 0 && !item.chips.any(cell.asset.matches)) continue;
      cell.net += w;
      cell.reasons.add((item, w));
    }
  }
  for (final c in cells) {
    c.reasons.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
  }
  return cells;
}
