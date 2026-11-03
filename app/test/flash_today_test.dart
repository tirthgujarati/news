import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/flash/flash.dart';
import 'package:newsapp/flash/rules.dart';
import 'package:newsapp/flash/today.dart';
import 'package:newsapp/models/edition.dart' show ImpactTag;

final now = DateTime(2026, 11, 4, 15, 0); // phone-local

FlashEvent ev(String text, int minutesAgo, {List<ImpactTag>? chips, Verdict? opus}) {
  final r = readHeadline(text);
  final e = FlashEvent(
    id: '$text$minutesAgo',
    headlines: [Headline(text: text, channel: 'marketfeed', at: now.subtract(Duration(minutes: minutesAgo)))],
    topic: r.topic,
    score: r.score,
    ruleChips: chips ?? r.chips,
  );
  if (opus != null) {
    e.desk = DeskResult(
      verdict: opus,
      confirmed: true,
      headline: text,
      why: '',
      india: '',
      watchNext: '',
      impact: chips ?? r.chips,
      sources: const [],
      checkedAt: now,
    );
  }
  return e;
}

ImpactTag tag(String on, String level, String dir, [String? detail]) =>
    ImpactTag(on: on, detail: detail, level: level, dir: dir, why: '');

void main() {
  test('running stories: two or more bursts today, one strong; names and momentum', () {
    final events = [
      ev('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ', 10),
      ev('HORMUZ: TANKERS DIVERTED AFTER ATTACK', 40),
      ev('HORMUZ: SHIPPING HALTED, SAYS UKMTO', 150),
      ev('RBI CUTS REPO RATE BY 25 BPS', 30),
      ev('BITCOIN SURGES', 20), // once only: not a story
      ev('FED HIKES RATES BY 25 BPS', 60 * 20), // yesterday
      ev('FED: RATE PATH UNCHANGED', 60 * 19),
    ];
    final s = runningStories(events, now);
    expect(s.map((x) => x.name), ['Oil · Hormuz']);
    expect(s.single.events.length, 3);
    expect(s.single.momentum(now), 'building');
    expect(s.single.momentum(now.add(const Duration(hours: 3))), 'fading');
  });

  test('heat map adds chips by level and direction, per source', () {
    final fed = ev('FED UNEXPECTEDLY CUTS RATES BY 50 BPS', 30,
        chips: [tag('currency', 'high', 'down', 'USD'), tag('gold', 'high', 'up')], opus: Verdict.hot);
    final oil1 = ev('IRAN SAYS IT WILL CLOSE THE STRAIT OF HORMUZ', 10);
    final oil2 = ev('HORMUZ: TANKERS DIVERTED AFTER ATTACK', 40);
    final events = [oil1, fed, oil2];
    final stories = runningStories(events, now);
    final items = [
      ...flashItems(events, stories, now),
      HeatItem(
          source: HeatSource.calendar,
          label: 'Forex 7:00 PM: USD Non-Farm Payrolls',
          at: now,
          chips: [tag('gold', 'medium', 'down'), tag('currency', 'medium', 'up', 'USD')]),
    ];
    Heat cell(List<Heat> m, String name) => m.firstWhere((h) => h.asset.name == name);

    final all = heatMap(items, HeatSource.all);
    expect(cell(all, 'Gold').net, 3 + 1 * 2 - 2); // Fed +3, Hormuz x2 low +1 each, NFP -2
    expect(cell(all, 'Oil').net, 6);
    expect(cell(all, 'Oil').strength, 'strong');
    expect(cell(all, 'USD').net, -3 + 2);
    expect(cell(all, 'USD').strength, 'low');
    expect(cell(all, 'Crypto').strength, 'quiet');
    expect(cell(all, 'Gold').reasons.first.$1.label, startsWith('FED'));

    final hot = heatMap(items, HeatSource.hot);
    expect(cell(hot, 'Oil').strength, 'quiet');
    expect(cell(hot, 'Gold').net, 3);
    expect(cell(heatMap(items, HeatSource.running), 'Oil').net, 6);
    expect(cell(heatMap(items, HeatSource.calendar), 'USD').net, 2);

    // Both ways equally: mixed, not quiet.
    final mixed = heatMap([
      HeatItem(source: HeatSource.hot, label: 'a', at: now, chips: [tag('silver', 'low', 'up')]),
      HeatItem(source: HeatSource.hot, label: 'b', at: now, chips: [tag('silver', 'low', 'down')]),
    ], HeatSource.all);
    expect(cell(mixed, 'Silver').strength, 'mixed');
  });
}
