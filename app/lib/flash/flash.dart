/// Flash: hot market headlines caught from squawk channels, scored in an
/// instant by rules and judged in minutes by Claude Opus on the plan (the
/// flash desk) and by the market itself.
library;

import '../models/edition.dart' show ImpactTag, Source;

/// One headline as it arrived on the phone.
class Headline {
  final String text;

  /// Where it came from ("marketfeed", "FinancialJuice").
  final String channel;
  final DateTime at;

  const Headline({required this.text, required this.channel, required this.at});

  Map<String, dynamic> toJson() =>
      {'text': text, 'channel': channel, 'at': at.toUtc().toIso8601String()};

  factory Headline.fromJson(Map<String, dynamic> j) => Headline(
        text: j['text'] as String,
        channel: j['channel'] as String,
        at: DateTime.parse(j['at'] as String),
      );
}

/// HOT, WATCH or NOISE.
enum Verdict {
  hot('HOT'),
  watch('WATCH'),
  noise('NOISE');

  const Verdict(this.label);
  final String label;

  static Verdict? parse(String? s) =>
      Verdict.values.where((v) => v.label == s).firstOrNull;
}

List<ImpactTag> _tags(Object? list) => [
      for (final t in (list as List?) ?? const [])
        ImpactTag.fromJson(t as Map<String, dynamic>)
    ];

/// The Opus flash desk's checked result (`data/flash/<issue>.json`).
class DeskResult {
  final Verdict verdict;
  final bool confirmed;
  final String headline;
  final String why;
  final String india;
  final String watchNext;
  final List<ImpactTag> impact;
  final List<Source> sources;
  final DateTime checkedAt;

  const DeskResult({
    required this.verdict,
    required this.confirmed,
    required this.headline,
    required this.why,
    required this.india,
    required this.watchNext,
    required this.impact,
    required this.sources,
    required this.checkedAt,
  });

  Map<String, dynamic> toJson() => {
        'verdict': verdict.label,
        'confirmed': confirmed,
        'headline': headline,
        'why': why,
        'india': india,
        'watch_next': watchNext,
        'impact': [for (final c in impact) c.toJson()],
        'sources': [for (final s in sources) {'name': s.name, 'url': s.url}],
        'checked_at': checkedAt.toIso8601String(),
      };

  factory DeskResult.fromJson(Map<String, dynamic> j) => DeskResult(
        verdict: Verdict.parse(j['verdict'] as String?) ?? Verdict.watch,
        confirmed: j['confirmed'] as bool? ?? false,
        headline: j['headline'] as String? ?? '',
        why: j['why'] as String? ?? '',
        india: j['india'] as String? ?? '',
        watchNext: j['watch_next'] as String? ?? '',
        impact: _tags(j['impact']),
        sources: [
          for (final s in (j['sources'] as List?) ?? const [])
            Source.fromJson(s as Map<String, dynamic>)
        ],
        checkedAt: DateTime.parse(j['checked_at'] as String),
      );
}

/// A price move measured after the news, for the market check.
class Move {
  /// "Nifty", "USD/INR", "EUR/USD", "Bitcoin", "Gold", "Oil".
  final String name;

  /// Percent change from just before the news.
  final double pct;

  /// Minutes after the news.
  final int after;

  const Move({required this.name, required this.pct, required this.after});

  Map<String, dynamic> toJson() => {'name': name, 'pct': pct, 'after': after};

  factory Move.fromJson(Map<String, dynamic> j) => Move(
        name: j['name'] as String,
        pct: (j['pct'] as num).toDouble(),
        after: j['after'] as int,
      );
}

/// One piece of hot news: the headlines that make it up, and every reading.
class FlashEvent {
  FlashEvent({
    required this.id,
    required this.headlines,
    required this.topic,
    required this.score,
    required this.ruleChips,
    this.deskError,
    this.issue,
    this.desk,
    List<Move>? moves,
    this.seen = false,
  }) : moves = moves ?? [];

  final String id;
  final List<Headline> headlines;

  /// The rule topic that caught it ("rates", "oil", "war", ...).
  String topic;
  int score;
  List<ImpactTag> ruleChips;

  /// Why Opus didn't (or couldn't) check it ("No GitHub token", ...).
  String? deskError;

  /// The GitHub issue that asked the flash desk, once opened.
  int? issue;
  DeskResult? desk;
  final List<Move> moves;
  bool seen;

  DateTime get at => headlines.first.at;

  /// Best reading so far: the desk, then the rules.
  Verdict get verdict => desk?.verdict ?? (score >= hotScore ? Verdict.hot : Verdict.watch);

  List<ImpactTag> get chips => desk?.impact ?? ruleChips;

  String get title => desk?.headline ?? headlines.first.text;

  /// Who made the current call: "Opus" or "Rules".
  String get calledBy => desk != null ? 'Opus' : 'Rules';

  /// Sent to the flash desk and waiting for its answer.
  bool get deskChecking => issue != null && desk == null && deskError == null;

  /// Strong enough to spend a flash desk run on: HOT by the rules, or a
  /// strong central bank, war, oil, trade or India headline.
  bool get worthDesk => score >= hotScore || (score >= deskScore && deskTopics.contains(topic));

  Map<String, dynamic> toJson() => {
        'id': id,
        'headlines': [for (final h in headlines) h.toJson()],
        'topic': topic,
        'score': score,
        'rule_chips': [for (final c in ruleChips) c.toJson()],
        if (deskError != null) 'desk_error': deskError,
        if (issue != null) 'issue': issue,
        if (desk != null) 'desk': desk!.toJson(),
        'moves': [for (final m in moves) m.toJson()],
        'seen': seen,
      };

  factory FlashEvent.fromJson(Map<String, dynamic> j) => FlashEvent(
        id: j['id'] as String,
        headlines: [
          for (final h in j['headlines'] as List) Headline.fromJson(h as Map<String, dynamic>)
        ],
        topic: j['topic'] as String,
        score: j['score'] as int,
        ruleChips: _tags(j['rule_chips']),
        deskError: j['desk_error'] as String?,
        issue: j['issue'] as int?,
        desk: j['desk'] == null ? null : DeskResult.fromJson(j['desk'] as Map<String, dynamic>),
        moves: [for (final m in (j['moves'] as List?) ?? const []) Move.fromJson(m as Map<String, dynamic>)],
        seen: j['seen'] as bool? ?? false,
      );
}

/// Rule score from which an event counts as HOT before Opus has checked it.
const hotScore = 8;

/// Rule score from which a headline is worth showing.
const candidateScore = 3;

/// Rule score from which an event on one of [deskTopics] goes to Opus.
const deskScore = 5;
const deskTopics = {'rates', 'war', 'oil', 'trade', 'india'};
