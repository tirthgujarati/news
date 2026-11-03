/// Live prices for the market check and the momentum meter (Yahoo Finance's
/// public chart data, minute bars). Nifty, USD/INR, EUR/USD and Bitcoin are
/// live within seconds; gold and oil futures are about 10 minutes behind.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/edition.dart' show ImpactTag;
import 'flash.dart' show Move;

class Market {
  final String name;
  final String symbol;

  /// True when the feed runs about 10 minutes late.
  final bool delayed;

  /// A move this big (percent) within 5 minutes counts as a spike.
  final double spike;

  const Market(this.name, this.symbol, this.spike, {this.delayed = false});
}

const markets = [
  Market('Nifty', '^NSEI', 0.3),
  Market('USD/INR', 'INR=X', 0.15),
  Market('EUR/USD', 'EURUSD=X', 0.15),
  Market('Bitcoin', 'BTC-USD', 1.0),
  Market('Gold', 'GC=F', 0.4, delayed: true),
  Market('Oil', 'CL=F', 0.8, delayed: true),
];

/// Minute bars for one market.
class Bars {
  final List<DateTime> times;
  final List<double> closes;
  final double? previousClose;

  const Bars(this.times, this.closes, this.previousClose);

  double? get last => closes.isEmpty ? null : closes.last;

  /// The close at or just before [t], or null if the bars start later.
  double? at(DateTime t) {
    double? v;
    for (var i = 0; i < times.length; i++) {
      if (times[i].isAfter(t)) break;
      v = closes[i];
    }
    return v;
  }

  /// Percent change over the last [d] (null if not enough data).
  double? changeOver(Duration d) {
    final l = last;
    if (l == null || times.isEmpty) return null;
    final from = at(times.last.subtract(d));
    return from == null || from == 0 ? null : (l - from) / from * 100;
  }

  /// Percent change since the previous session's close.
  double? get dayChange {
    final l = last, p = previousClose;
    return l == null || p == null || p == 0 ? null : (l - p) / p * 100;
  }
}

/// Parses Yahoo's chart JSON. Minutes without a trade are skipped.
Bars parseBars(String body) {
  final r = (((jsonDecode(body) as Map)['chart'] as Map)['result'] as List).first as Map;
  final ts = (r['timestamp'] as List?) ?? const [];
  final closes = ((((r['indicators'] as Map)['quote'] as List).first as Map)['close'] as List?) ?? const [];
  final times = <DateTime>[], values = <double>[];
  for (var i = 0; i < ts.length && i < closes.length; i++) {
    final c = closes[i];
    if (c == null) continue;
    times.add(DateTime.fromMillisecondsSinceEpoch((ts[i] as int) * 1000, isUtc: true));
    values.add((c as num).toDouble());
  }
  final meta = r['meta'] as Map;
  final prev = (meta['previousClose'] ?? meta['chartPreviousClose']) as num?;
  return Bars(times, values, prev?.toDouble());
}

class Prices {
  Prices([http.Client? client]) : _client = client ?? http.Client();
  final http.Client _client;

  Future<Bars> bars(Market m) async {
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(m.symbol)}'
        '?interval=1m&range=1d';
    final res = await _client
        .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0 (Android) apex'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
    return parseBars(res.body);
  }

  /// All markets at once; a market that fails is left out.
  Future<Map<String, Bars>> all() async {
    final out = <String, Bars>{};
    await Future.wait(markets.map((m) async {
      try {
        out[m.name] = await bars(m);
      } catch (_) {}
    }));
    return out;
  }

  void close() => _client.close();
}

/// The market that shows a chip's move, and +1 when the chip's "up" means
/// that price goes up (-1 when it goes down: a stronger rupee is a lower
/// USD/INR). Null when no live price shows it.
(String, int)? marketFor(ImpactTag t) => switch (t.on) {
      'indian_stocks' when t.detail == null => ('Nifty', 1),
      'rupee' => ('USD/INR', -1),
      'gold' => ('Gold', 1),
      'oil' => ('Oil', 1),
      'crypto' => ('Bitcoin', 1),
      'currency' when t.detail == 'USD' => ('EUR/USD', -1),
      'currency' when t.detail == 'EUR' => ('EUR/USD', 1),
      _ => null,
    };

/// How each chip's market moved [after] minutes since the news.
List<Move> movesSince(DateTime news, int after, Map<String, Bars> bars, List<ImpactTag> chips) {
  final out = <Move>[];
  final names = {for (final c in chips) ?marketFor(c)?.$1};
  for (final name in names) {
    final b = bars[name];
    final before = b?.at(news), now = b?.last;
    if (before == null || now == null || before == 0) continue;
    out.add(Move(name: name, pct: (now - before) / before * 100, after: after));
  }
  return out;
}

/// "agrees", "disagrees" or "quiet": does the market move the way the chips
/// said? Moves under 0.05% don't count.
String marketVerdict(List<ImpactTag> chips, List<Move> moves) {
  var agree = 0, disagree = 0;
  for (final c in chips) {
    final m = marketFor(c);
    if (m == null || c.dir == 'mixed') continue;
    final move = moves.where((x) => x.name == m.$1).lastOrNull;
    if (move == null || move.pct.abs() < 0.05) continue;
    final expected = (c.dir == 'up' ? 1 : -1) * m.$2;
    if ((move.pct > 0 ? 1 : -1) == expected) {
      agree++;
    } else {
      disagree++;
    }
  }
  if (agree == 0 && disagree == 0) return 'quiet';
  return agree >= disagree ? 'agrees' : 'disagrees';
}
