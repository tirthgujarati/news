/// Flash: hot market headlines caught from squawk channels, judged in
/// seconds (rules, then Claude Sonnet) and checked in minutes (the Opus
/// flash desk on the plan, and the market itself).
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

/// Claude Sonnet's quick reading, seconds after the headline.
class Judgement {
  final Verdict verdict;

  /// False when the news was already known or fully expected.
  final bool isNew;

  /// Claude's own one-line version of what happened.
  final String headline;
  final String why;
  final List<ImpactTag> chips;
  final int ms;
  final DateTime at;

  const Judgement({
    required this.verdict,
    required this.isNew,
    required this.headline,
    required this.why,
    required this.chips,
    required this.ms,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'verdict': verdict.label,
        'is_new': isNew,
        'headline': headline,
        'why': why,
        'chips': [for (final c in chips) c.toJson()],
        'ms': ms,
        'at': at.toUtc().toIso8601String(),
      };

  factory Judgement.fromJson(Map<String, dynamic> j) => Judgement(
        verdict: Verdict.parse(j['verdict'] as String?) ?? Verdict.watch,
        isNew: j['is_new'] as bool? ?? true,
        headline: j['headline'] as String? ?? '',
        why: j['why'] as String? ?? '',
        chips: _tags(j['chips']),
        ms: j['ms'] as int? ?? 0,
        at: DateTime.parse(j['at'] as String),
      );
}

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
    this.judgement,
    this.judgeError,
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

  Judgement? judgement;

  /// Why there's no judgement ("No API key", "Monthly limit reached", ...).
  String? judgeError;

  /// The GitHub issue that asked the flash desk, once opened.
  int? issue;
  DeskResult? desk;
  final List<Move> moves;
  bool seen;

  DateTime get at => headlines.first.at;

  /// Best reading so far: the desk, then Claude, then the rules.
  Verdict get verdict =>
      desk?.verdict ?? judgement?.verdict ?? (score >= hotScore ? Verdict.hot : Verdict.watch);

  List<ImpactTag> get chips => desk?.impact ?? judgement?.chips ?? ruleChips;

  String get title => desk?.headline ?? judgement?.headline ?? headlines.first.text;

  /// Who made the current call: "Opus", "Sonnet" or "Rules".
  String get calledBy => desk != null ? 'Opus' : (judgement != null ? 'Sonnet' : 'Rules');

  Map<String, dynamic> toJson() => {
        'id': id,
        'headlines': [for (final h in headlines) h.toJson()],
        'topic': topic,
        'score': score,
        'rule_chips': [for (final c in ruleChips) c.toJson()],
        if (judgement != null) 'judgement': judgement!.toJson(),
        if (judgeError != null) 'judge_error': judgeError,
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
        judgement: j['judgement'] == null
            ? null
            : Judgement.fromJson(j['judgement'] as Map<String, dynamic>),
        judgeError: j['judge_error'] as String?,
        issue: j['issue'] as int?,
        desk: j['desk'] == null ? null : DeskResult.fromJson(j['desk'] as Map<String, dynamic>),
        moves: [for (final m in (j['moves'] as List?) ?? const []) Move.fromJson(m as Map<String, dynamic>)],
        seen: j['seen'] as bool? ?? false,
      );
}

/// Rule score from which an event counts as HOT when Claude can't judge it.
const hotScore = 8;

/// Rule score from which a headline is worth showing and judging.
const candidateScore = 3;
