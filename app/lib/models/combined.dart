/// The approximate combined effect of several red/orange events released at
/// the same moment (e.g. a rate decision with its statements).
library;

import 'edition.dart' show ImpactTag;
import 'forex.dart';

/// Central bank rate decisions: "Cash Rate", "Federal Funds Rate",
/// "Official Bank Rate", "BOJ Policy Rate", "Main Refinancing Rate", ...
bool isRateDecision(String title) =>
    RegExp(r'\b(cash|funds|bank|policy|overnight|refinancing|prime) rate\b', caseSensitive: false)
        .hasMatch(title);

class CombinedEffect {
  /// True once at least one event has a reading; [chips] is then the effect
  /// so far. Before that, [ifStronger] and [ifWeaker] are the two scenarios.
  final bool released;
  final List<ImpactTag> chips;
  final List<ImpactTag> ifStronger;
  final List<ImpactTag> ifWeaker;

  /// True when a rate decision is in the group (scenarios read
  /// "Hawkish"/"Dovish" and the decision outweighs the rest).
  final bool rateDecision;

  /// Results so far pull the currency both ways or are all in line.
  final bool flat;

  /// Events still without a reading (e.g. a statement the editor hasn't
  /// read yet).
  final List<ForexEvent> waiting;

  const CombinedEffect({
    required this.released,
    required this.chips,
    required this.ifStronger,
    required this.ifWeaker,
    required this.rateDecision,
    required this.flat,
    required this.waiting,
  });
}

const _rank = {'low': 0, 'medium': 1, 'high': 2};

String _lower(String level) => level == 'high' ? 'medium' : 'low';

int _weight(ForexEvent e) => isRateDecision(e.title) ? 100 : (e.impact == 'High' ? 2 : 1);

/// [verdictOf] gives each event's reading for its currency: better, worse,
/// in_line, no_forecast, or null while it's not out yet.
///
/// Rules: a rate decision outweighs everything else; otherwise red counts 2
/// and orange 1. Statements count once the editor has read their tone.
CombinedEffect combine(List<ForexEvent> group, String? Function(ForexEvent) verdictOf) {
  final rate = group.any((e) => isRateDecision(e.title));
  final score = <String, int>{};
  final level = <String, String>{};
  final rateLed = <String>{};
  final waiting = <ForexEvent>[];
  var counted = 0;

  for (final e in group) {
    final v = verdictOf(e);
    if (v == null) {
      waiting.add(e);
      continue;
    }
    if (v != 'better' && v != 'worse') {
      if (v == 'in_line') counted++;
      continue;
    }
    counted++;
    final w = _weight(e);
    score[e.country] = (score[e.country] ?? 0) + (v == 'better' ? w : -w);
    final l = e.impact == 'High' ? 'high' : 'medium';
    if (_rank[l]! > _rank[level[e.country] ?? 'low']!) level[e.country] = l;
    if (w == 100) rateLed.add(e.country);
  }

  List<ImpactTag> scenario(bool stronger) {
    final s = <String, int>{}, l = <String, String>{};
    for (final e in group) {
      s[e.country] = (s[e.country] ?? 0) + (stronger ? 1 : -1) * _weight(e);
      final lv = e.impact == 'High' ? 'high' : 'medium';
      if (_rank[lv]! > _rank[l[e.country] ?? 'low']!) l[e.country] = lv;
    }
    return _chips(s, l, {for (final e in group) if (isRateDecision(e.title)) e.country});
  }

  final chips = _chips(score, level, rateLed);
  return CombinedEffect(
    released: counted > 0,
    chips: chips,
    ifStronger: scenario(true),
    ifWeaker: scenario(false),
    rateDecision: rate,
    flat: counted > 0 && !chips.any((c) => c.on == 'currency' && c.dir != 'mixed'),
    waiting: waiting,
  );
}

/// Turns net scores per currency into chips: the currency itself, then what
/// usually follows it. The dollar moves gold, silver, the rupee, Indian
/// stocks, oil and crypto the other way; other currencies move gold and
/// silver a little (through the dollar).
List<ImpactTag> _chips(Map<String, int> score, Map<String, String> level, Set<String> rateLed) {
  final out = <ImpactTag>[];
  final seen = <String>{};
  void add(String on, String lv, String dir, String why, {String? detail}) {
    if (!seen.add(detail ?? on)) return;
    out.add(ImpactTag(on: on, detail: detail, level: lv, dir: dir, why: why));
  }

  // USD first, then the biggest moves.
  final ccys = score.keys.toList()
    ..sort((a, b) {
      if (a == 'USD') return -1;
      if (b == 'USD') return 1;
      return score[b]!.abs().compareTo(score[a]!.abs());
    });
  for (final c in ccys) {
    final s = score[c]!;
    final lv = level[c] ?? 'medium';
    if (s == 0) {
      add('currency', lv, 'mixed', 'Results pull both ways.', detail: c);
      continue;
    }
    final up = s > 0;
    final dir = up ? 'up' : 'down';
    final other = up ? 'down' : 'up';
    add('currency', lv, dir, up ? 'Better than expected for $c.' : 'Worse than expected for $c.',
        detail: c);
    if (c == 'USD') {
      add('gold', lv, other, 'Gold usually moves against the dollar.');
      add('silver', lv, other, 'Silver usually moves against the dollar.');
      add('rupee', lv, other, 'A stronger dollar pushes the rupee down, and the reverse.');
      add('indian_stocks', _lower(lv), other,
          'A strong dollar tends to pull foreign money out of India.');
      add('oil', _lower(lv), other, 'Oil is priced in dollars.');
      add('crypto', _lower(lv), other, 'Crypto tends to fall when the dollar and yields rise.');
      add('us_stocks', _lower(lv), rateLed.contains(c) ? other : 'mixed',
          rateLed.contains(c)
              ? 'Higher US rates weigh on stocks; lower rates lift them.'
              : 'Strong data helps earnings but can mean higher rates.');
    } else {
      add('gold', 'low', dir, 'A stronger $c means a slightly weaker dollar, which helps gold.');
      add('silver', 'low', dir, 'Moves with gold through the dollar.');
      if (c == 'CNY') add('oil', 'low', dir, "China's demand drives oil.");
    }
  }
  return out;
}
