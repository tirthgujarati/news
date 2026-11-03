/// The instant, on-phone part of Flash: which squawk headlines matter, which
/// are repeats, and the rule chips shown before Claude has answered.
library;

import '../models/combined.dart' show effectChips;
import '../models/edition.dart' show ImpactTag;

/// What the rules make of one headline.
class RuleRead {
  /// "rates", "oil", "war", "trade", "india", "data", "crypto", "stress",
  /// "metals" or "other".
  final String topic;
  final int score;
  final List<ImpactTag> chips;

  /// The thing it's about, for grouping bursts ("RBA", "HORMUZ", ...).
  final String? subject;

  const RuleRead(this.topic, this.score, this.chips, this.subject);

  bool get candidate => score >= 3;
}

RegExp _re(String p) => RegExp(p, caseSensitive: false);

final _banks = <RegExp, String>{
  _re(r'\b(FED|FOMC|POWELL|FEDERAL RESERVE)\b'): 'USD',
  _re(r'\b(RBI|MALHOTRA|RESERVE BANK OF INDIA)\b'): 'INR',
  _re(r'\b(ECB|LAGARDE)\b'): 'EUR',
  _re(r'\b(BOE|BANK OF ENGLAND|BAILEY)\b'): 'GBP',
  _re(r'\b(BOJ|BANK OF JAPAN|UEDA)\b'): 'JPY',
  _re(r'\b(RBA|RESERVE BANK OF AUSTRALIA|BULLOCK)\b'): 'AUD',
  _re(r'\b(BOC|BANK OF CANADA|MACKLEM)\b'): 'CAD',
  _re(r'\b(SNB|SWISS NATIONAL BANK)\b'): 'CHF',
  _re(r'\b(RBNZ|RESERVE BANK OF NEW ZEALAND)\b'): 'NZD',
  _re(r'\b(PBOC|PEOPLE.S BANK OF CHINA)\b'): 'CNY',
};
final _rateWords = _re(r'\b(RATES?|BPS|BASIS POINTS?|POLICY)\b');
final _hike = _re(r'\b(RAISES?|RAISED|HIKES?|HIKED|INCREASES?|INCREASED|TIGHTEN\w*|HAWKISH)\b');
final _cut = _re(r'\b(CUTS?|LOWERS?|LOWERED|REDUCES?|REDUCED|EASES?|EASED|DOVISH)\b');
final _hold = _re(r'\b(HOLDS?|HELD|UNCHANGED|KEEPS?|LEAVES?|PAUSES?)\b');
final _expected = _re(r'\bAS (EXPECTED|FORECAST)\b');

final _oil = _re(r'\b(HORMUZ|OPEC\+?|CRUDE|BRENT|WTI|OIL|REFINER(Y|IES)|TANKERS?|ARAMCO|PIPELINE|LNG)\b');
final _supplyHit = _re(r'\b(CUTS?|HALT\w*|CLOS(E|ED|ES|URE)|ATTACK\w*|STRIKES?|SEIZ\w*|BLOCK\w*|SHUT\w*|DISRUPT\w*|SANCTION\w*|EMBARGO)\b');
final _supplyEase = _re(r'\b(BOOST\w*|REOPEN\w*|RESUM\w*|CEASEFIRE|TRUCE|DEAL|RAISES? OUTPUT|INCREASES? (OUTPUT|PRODUCTION))\b');

final _war = _re(r'\b(WAR|MISSILES?|AIR ?STRIKES?|STRIKES ON|ATTACK\w*|INVADE\w*|INVASION|NUCLEAR|MILITARY|TROOPS|DRONES?|BOMB\w*|ESCALAT\w*)\b');
final _peace = _re(r'\b(CEASEFIRE|TRUCE|PEACE|DE-?ESCALAT\w*|AGREEMENT|DEAL REACHED)\b');
final _hotspot = _re(r'\b(IRAN\w*|TEHRAN|ISRAEL\w*|RUSSIA\w*|UKRAIN\w*|TAIWAN|PAKISTAN\w*|SAUDI|YEMEN|HOUTHI\w*|HEZBOLLAH|GAZA|CHINA|NORTH KOREA)\b');
final _middleEast = _re(r'\b(IRAN\w*|TEHRAN|ISRAEL\w*|SAUDI|YEMEN|HOUTHI\w*|HEZBOLLAH|GAZA|GULF|RED SEA|HORMUZ)\b');

final _trade = _re(r'\b(TARIFFS?|TRADE (WAR|DEAL|TALKS|AGREEMENT)|EXPORT (BAN|CURBS?|CONTROLS?)|IMPORT DUT(Y|IES)|SANCTIONS?)\b');
final _tradeEase = _re(r'\b(DEAL|AGREEMENT|PAUS\w*|EXEMPT\w*|LIFT\w*|REMOV\w*|CUTS?|DELAY\w*|TRUCE)\b');
final _india = _re(r'\b(INDIA\w*|NIFTY|SENSEX|SEBI|RUPEE|INR|NSE|BSE|MODI|SITHARAMAN|GST|DELHI)\b');

final _data = _re(r'\b(CPI|INFLATION|GDP|PAYROLLS?|NFP|NON-?FARM|JOBS REPORT|UNEMPLOYMENT|JOBLESS|PMI|RETAIL SALES|PCE)\b');
final _vs = _re(r'\b(VS\.?|VERSUS|EST\.?|ESTIMATE|EXPECTED|FORECAST|PRIOR)\b');

final _crypto = _re(r'\b(BITCOIN|BTC|CRYPTO\w*|ETHEREUM|ETHER|STABLECOINS?|BINANCE|COINBASE)\b');
final _cryptoUp = _re(r'\b(APPROV\w*|INFLOWS?|RESERVE|BUYS?|ADOPT\w*|RECORD HIGH|SOARS?|SURGES?)\b');
final _cryptoDown = _re(r'\b(HACK\w*|BAN\w*|CRACKDOWN|LAWSUIT|SUES|OUTFLOWS?|LIQUIDAT\w*|PLUNGES?|CRASH\w*|COLLAPS\w*)\b');

final _stress = _re(r'\b(CRASH\w*|PLUNG\w*|PLUMMET\w*|HALTED|CIRCUIT BREAKER|SELL-?OFF|ROUT|DEFAULTS?|BANKRUPT\w*|BAILOUT|DOWNGRADE\w*|SOARS?|SURGES?|RECORD HIGH|RECORD LOW)\b');
final _metals = _re(r'\b(GOLD|SILVER|BULLION)\b');

final _urgent = _re(r'\b(BREAKING|URGENT|EMERGENCY|UNEXPECTED\w*|SURPRISE\w*|UNSCHEDULED|SHOCK\w*|FLASH)\b');
final _noise = _re(r'\b(PREVIEW|WEEK AHEAD|FOLLOW US|SUBSCRIBE|OPINION|COLUMN|PODCAST|WATCH LIVE|RECAP|DAILY WRAP|HOROSCOPE|SPONSORED)\b');
final _earnings = _re(r'\b(EARNINGS|Q[1-4] \d{2}|EPS|REVENUE|REV:)');
final _indianCompanies = _re(r'\b(TCS|INFOSYS|RELIANCE|HDFC|ICICI|SBI|ADANI\w*|TATA|WIPRO|HCL|AIRTEL|BHARTI|LARSEN|L&T|ITC|MARUTI|KOTAK|BAJAJ|ONGC|NTPC|COAL INDIA|SUN PHARMA|ZOMATO|ETERNAL|PAYTM)\b');

ImpactTag _t(String on, String level, String dir, String why, [String? detail]) =>
    ImpactTag(on: on, detail: detail, level: level, dir: dir, why: why);

/// Scores one squawk headline. Fast (regular expressions only): runs on
/// every message that arrives.
RuleRead readHeadline(String text) {
  var score = 0;
  String topic = 'other';
  String? subject;
  var chips = <ImpactTag>[];

  void take(String t, int s, List<ImpactTag> c, [String? subj]) {
    if (s > score) {
      topic = t;
      score = s;
      chips = c;
      subject = subj;
    }
  }

  // Central banks and rates.
  for (final MapEntry(key: re, value: ccy) in _banks.entries) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    var s = 3;
    if (_rateWords.hasMatch(text)) s += 3;
    final up = _hike.hasMatch(text), down = _cut.hasMatch(text);
    if (_expected.hasMatch(text)) s -= 2;
    var c = <ImpactTag>[];
    if (up != down && !_hold.hasMatch(text)) {
      if (ccy == 'INR') {
        c = up
            ? [
                _t('rates', 'high', 'up', 'RBI tightening raises borrowing costs.'),
                _t('rupee', 'medium', 'up', 'Higher rates support the rupee.'),
                _t('indian_stocks', 'medium', 'down', 'Dearer money weighs on stocks.'),
              ]
            : [
                _t('rates', 'high', 'down', 'RBI easing lowers borrowing costs.'),
                _t('indian_stocks', 'high', 'up', 'Cheaper money lifts banks, autos and real estate.'),
                _t('rupee', 'low', 'down', 'Lower rates soften the rupee.'),
              ];
      } else {
        c = effectChips({ccy: up ? 1 : -1}, {ccy: 'high'}, {ccy});
      }
    }
    // The bank's currency, so "FED ..." and "POWELL: ..." group together.
    take('rates', s, c, ccy);
  }

  // Oil supply.
  final oil = _oil.firstMatch(text);
  if (oil != null) {
    var s = 3;
    final hit = _supplyHit.hasMatch(text), ease = _supplyEase.hasMatch(text);
    if (hit || ease) s += 2;
    if (_middleEast.hasMatch(text)) s += 1;
    final up = hit && !ease;
    final c = hit == ease
        ? <ImpactTag>[]
        : [
            _t('oil', 'high', up ? 'up' : 'down', up ? 'Supply at risk.' : 'Supply easing.'),
            _t('rupee', 'medium', up ? 'down' : 'up', 'India imports most of its oil.'),
            _t('indian_stocks', 'medium', up ? 'down' : 'up', 'Oil costs hit Indian companies and inflation.'),
            _t('gold', 'low', up ? 'up' : 'down', 'Supply shocks drive safe-haven buying.'),
          ];
    take('oil', s, c, oil[0]!.toUpperCase());
  }

  // War and peace.
  final war = _war.hasMatch(text), peace = _peace.hasMatch(text);
  final spot = _hotspot.firstMatch(text);
  if ((war || peace) && spot != null) {
    final s = 4 + (_middleEast.hasMatch(text) ? 1 : 0);
    final up = war && !peace; // escalation
    final c = war == peace
        ? <ImpactTag>[]
        : [
            _t('gold', 'high', up ? 'up' : 'down', up ? 'Safe-haven buying.' : 'Less need for safety.'),
            if (_middleEast.hasMatch(text))
              _t('oil', 'high', up ? 'up' : 'down', 'Middle East supply risk.'),
            _t('rupee', 'medium', up ? 'down' : 'up', 'Risk moves money into the dollar.'),
            _t('indian_stocks', 'medium', up ? 'down' : 'up', 'Foreign investors pull back in a crisis.'),
          ];
    take('war', s, c, spot[0]!.toUpperCase());
  }

  // Trade and tariffs.
  final trade = _trade.firstMatch(text);
  if (trade != null) {
    final india = _india.hasMatch(text);
    final s = 3 + (india ? 2 : 0);
    final ease = _tradeEase.hasMatch(text);
    final c = [
      if (india) ...[
        _t('indian_stocks', 'high', ease ? 'up' : 'down',
            ease ? 'Easier trade helps exporters.' : 'Tariffs hit Indian exporters.'),
        _t('rupee', 'medium', ease ? 'up' : 'down', 'Trade flows move the rupee.'),
      ] else
        _t('us_stocks', 'medium', ease ? 'up' : 'down',
            ease ? 'Trade relief lifts stocks.' : 'Tariffs raise costs and risk.'),
      _t('gold', 'low', ease ? 'down' : 'up', 'Trade fights drive safe-haven buying.'),
    ];
    take('trade', s, c, trade[0]!.toUpperCase());
  }

  // India: markets, regulators, big companies.
  final india = _india.firstMatch(text) ?? _indianCompanies.firstMatch(text);
  if (india != null) take('india', 2 + (_indianCompanies.hasMatch(text) ? 1 : 0), [], india[0]!.toUpperCase());

  // Economic data with a number against the forecast.
  final data = _data.firstMatch(text);
  if (data != null) take('data', 2 + (_vs.hasMatch(text) ? 2 : 0), [], data[0]!.toUpperCase());

  // Crypto.
  final crypto = _crypto.firstMatch(text);
  if (crypto != null) {
    final up = _cryptoUp.hasMatch(text), down = _cryptoDown.hasMatch(text);
    take('crypto', 2 + (up != down ? 2 : 0),
        up == down ? [] : [_t('crypto', 'medium', up ? 'up' : 'down', 'Direct crypto news.')],
        crypto[0]!.toUpperCase());
  }

  // Market stress and big moves.
  final stress = _stress.firstMatch(text);
  if (stress != null) take('stress', 3, [], stress[0]!.toUpperCase());

  final metal = _metals.firstMatch(text);
  if (metal != null) take('metals', 2, [], metal[0]!.toUpperCase());

  // Modifiers on the best topic.
  if (_urgent.hasMatch(text)) score += 3;
  if (_noise.hasMatch(text)) score -= 5;
  if (_earnings.hasMatch(text) && !_indianCompanies.hasMatch(text)) score -= 2;
  return RuleRead(topic, score, chips, subject);
}

const _stop = {
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are', 'was', 'has', 'have',
  'will', 'its', 'says', 'said', 'say', 'not', 'but', 'than', 'into', 'over',
};

/// Lower-case words worth comparing, without the channel's tail ("| FJ",
/// "- FXS", "...").
Set<String> headlineWords(String text) {
  final t = text
      .toLowerCase()
      .replaceAll(RegExp(r'\|\s*\w+\s*$'), ' ')
      .replaceAll(RegExp(r'[-–—]\s*(fxs|wsj|ft|rtrs|reuters|bbg|bloomberg|cnbc)\s*\.*\s*$'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9%.\s]'), ' ')
      .replaceAll(RegExp(r'\.(?!\d)'), ' ');
  return t.split(RegExp(r'\s+')).where((w) => w.length > 1 && !_stop.contains(w)).toSet();
}

/// True when two headlines say the same thing (the channels echo each
/// other, often in different words and case).
bool sameNews(String a, String b) {
  final wa = headlineWords(a), wb = headlineWords(b);
  if (wa.isEmpty || wb.isEmpty) return false;
  final common = wa.intersection(wb).length;
  final smaller = wa.length < wb.length ? wa.length : wb.length;
  return common / smaller >= 0.7;
}
