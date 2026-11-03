import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../flash/flash.dart';
import '../flash/flash_view.dart';
import '../flash/prices.dart';
import '../flash/today.dart';
import '../models/combined.dart';
import '../models/forex.dart';
import '../theme/look.dart';
import 'flash_settings_screen.dart';
import 'forex_screen.dart' show Readout;
import 'widgets.dart';

String _clock(DateTime t) => DateFormat('h:mm:ss a').format(t.toLocal());

String _pct(double v, {int digits = 2}) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}%';

Color verdictColor(Look look, Verdict v) => switch (v) {
      Verdict.hot => look.impact('high'),
      Verdict.watch => look.impact('medium'),
      Verdict.noise => look.muted,
    };

/// Hot news in seconds: squawk headlines scored by rules at once and judged
/// by the Opus flash desk in minutes, with the market's own reaction.
class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key, required this.flash, this.visible = true, this.now});
  final FlashView flash;

  /// Fixed "now" for tests; the real time otherwise.
  final DateTime? now;

  /// True while this tab is on screen (runs the momentum meter).
  final bool visible;

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  bool _tape = false;
  bool _showWatch = false;
  bool _showNoise = false;
  HeatSource _source = HeatSource.all;

  @override
  void initState() {
    super.initState();
    widget.flash.meter(widget.visible);
    widget.flash.openRequest.addListener(_openRequested);
  }

  @override
  void didUpdateWidget(FlashScreen old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      widget.flash.meter(widget.visible);
      if (widget.visible) {
        widget.flash.refreshStatus();
        widget.flash.markSeen(widget.flash.events.take(20));
      }
    }
  }

  @override
  void dispose() {
    widget.flash.openRequest.removeListener(_openRequested);
    widget.flash.meter(false);
    super.dispose();
  }

  void _openRequested() {
    final id = widget.flash.openRequest.value;
    if (id == null) return;
    widget.flash.openRequest.value = null;
    final e = widget.flash.events.where((x) => x.id == id).firstOrNull;
    if (e != null && mounted) showFlashEvent(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final f = widget.flash;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final now = widget.now ?? DateTime.now();
        // High impact only by default; WATCH and NOISE on request.
        final events = [
          for (final e in f.events)
            if (switch (e.verdict) {
              Verdict.hot => true,
              Verdict.watch => _showWatch,
              Verdict.noise => _showNoise,
            })
              e
        ];
        final stories = runningStories(f.events, now);
        final heat = heatMap(
          [...flashItems(f.events, stories, now), ...calendarItems(context.app, now)],
          _source,
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('Flash'),
            actions: [
              IconButton(
                tooltip: 'Flash settings',
                icon: const Icon(Icons.tune),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => FlashSettingsScreen(flash: f))),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await f.reload();
              await f.refreshStatus();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!f.status.ready) _SetupCard(flash: f),
                _Meter(flash: f),
                _DeskLine(flash: f),
                _HeatMap(
                  cells: heat,
                  source: _source,
                  prices: f.prices,
                  onSource: (s) => setState(() => _source = s),
                ),
                if (stories.isNotEmpty) _Stories(stories: stories, now: now, flash: f),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Row(children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Events')),
                        ButtonSegment(value: true, label: Text('Tape')),
                      ],
                      selected: {_tape},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _tape = s.first),
                    ),
                    const Spacer(),
                    if (!_tape) ...[
                      FilterChip(
                        label: const Text('WATCH'),
                        selected: _showWatch,
                        onSelected: (v) => setState(() => _showWatch = v),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Noise'),
                        selected: _showNoise,
                        onSelected: (v) => setState(() => _showNoise = v),
                      ),
                    ],
                  ]),
                ),
                if (_tape)
                  ..._tapeRows(look, f)
                else if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      !(f.status.listener || f.config.watchMode)
                          ? 'Finish the setup above to start catching hot news.'
                          : _showWatch
                              ? 'Nothing yet. Market-moving squawk headlines show up here within seconds.'
                              : 'No HOT news yet. Tap WATCH to see the smaller ones.',
                      style: look.body(14),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final e in events) FlashCard(event: e, seen: f.isSeen(e)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _tapeRows(Look look, FlashView f) => [
        for (final t in f.tape)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 64,
                child: Text(DateFormat('h:mm a').format(t.headline.at.toLocal()),
                    style: look.number(11.5, color: look.muted)),
              ),
              Expanded(
                child: Text(t.headline.text,
                    style: look.body(13,
                        color: t.score >= candidateScore ? look.ink : look.muted,
                        weight: t.eventId != null ? FontWeight.w600 : FontWeight.w400)),
              ),
            ]),
          ),
      ];
}

/// Verdict badge: HOT red, WATCH orange, NOISE grey.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge(this.verdict, {super.key});
  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final c = verdictColor(look, verdict);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        border: Border.all(color: c.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(verdict.label, style: look.label(9.5, color: look.ink)),
      ]),
    );
  }
}

/// "Opus ✓ confirmed in 3 min" / "Rules · Opus checking…" / "Rules · No GitHub token".
String calledByLine(FlashEvent e) {
  final d = e.desk;
  if (d != null) {
    final mins = d.checkedAt.difference(e.at).inMinutes;
    return 'Opus ${d.confirmed ? '✓ confirmed' : 'not confirmed'}${mins > 0 ? ' in $mins min' : ''}';
  }
  if (e.deskChecking) return 'Rules · Opus checking…';
  return e.deskError == null ? 'Rules' : 'Rules · ${e.deskError}';
}

/// "Market agrees ✓ · USD/INR +0.21%" from the latest check.
String? marketLine(FlashEvent e) {
  if (e.moves.isEmpty) return null;
  final latest = e.moves.map((m) => m.after).reduce((a, b) => a > b ? a : b);
  final moves = e.moves.where((m) => m.after == latest).toList();
  final v = marketVerdict(e.chips, moves);
  final head = switch (v) {
    'agrees' => 'Market agrees ✓',
    'disagrees' => 'Market disagrees ✗',
    _ => 'Market quiet',
  };
  return '$head · ${moves.map((m) => '${m.name} ${_pct(m.pct)}').join(' · ')} ($latest min)';
}

class FlashCard extends StatelessWidget {
  const FlashCard({super.key, required this.event, this.seen = true});
  final FlashEvent event;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final e = event;
    final c = verdictColor(look, e.verdict);
    final why = e.desk?.why;
    final market = marketLine(e);
    return InkWell(
      onTap: () => showFlashEvent(context, e),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: look.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: e.verdict == Verdict.hot ? c.withValues(alpha: 0.6) : look.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            VerdictBadge(e.verdict),
            const SizedBox(width: 8),
            Text(_clock(e.at), style: look.number(12, color: look.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.headlines.first.channel,
                  overflow: TextOverflow.ellipsis, style: look.body(12, color: look.muted)),
            ),
            if (!seen) Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 8),
          Text(e.title, style: look.headline(16.5, height: 1.25)),
          if (e.chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            ImpactChips(impact: e.chips),
          ],
          if (why != null && why.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(why, style: look.body(13, color: look.ink, height: 1.4)),
          ],
          const SizedBox(height: 7),
          Text(calledByLine(e), style: look.body(11.5)),
          if (market != null) ...[
            const SizedBox(height: 3),
            Text(market, style: look.body(11.5, color: look.ink)),
          ],
        ]),
      ),
    );
  }
}

Future<void> showFlashEvent(BuildContext context, FlashEvent e) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => _EventDetail(event: e, scroll: scroll),
      ),
    );

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event, required this.scroll});
  final FlashEvent event;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final e = event;
    final d = e.desk;
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t.toUpperCase(), style: look.label(11)),
        );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(children: [
          VerdictBadge(e.verdict),
          const SizedBox(width: 8),
          Text('${_clock(e.at)} · called by ${e.calledBy}', style: look.body(12.5)),
        ]),
        const SizedBox(height: 10),
        Text(e.title, style: look.headline(21, height: 1.2)),
        if (e.chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImpactBox(impact: e.chips),
        ],
        if (d != null) ...[
          heading(d.confirmed ? 'Opus flash desk · confirmed' : 'Opus flash desk · not confirmed'),
          Text(d.why, style: look.body(14, color: look.ink)),
          if (d.india.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('India: ${d.india}', style: look.body(14, color: look.ink)),
          ],
          if (d.watchNext.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Watch next: ${d.watchNext}', style: look.body(14, color: look.ink)),
          ],
          const SizedBox(height: 8),
          for (final s in d.sources)
            InkWell(
              onTap: () => openLink(s.url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('↗ ${s.name}', style: look.body(13.5, color: look.section('markets'))),
              ),
            ),
        ] else if (e.deskChecking) ...[
          heading('Opus flash desk'),
          Text('Judging and checking with independent sources… usually about 3 minutes.', style: look.body(14)),
        ] else ...[
          heading('Rules only'),
          Text(
            e.deskError ?? 'Not strong enough to send to Opus (rule score ${e.score}).',
            style: look.body(13),
          ),
        ],
        if (e.moves.isNotEmpty) ...[
          heading('Market reaction'),
          for (final m in e.moves)
            Text('${m.after} min: ${m.name} ${_pct(m.pct)}', style: look.number(13)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(marketLine(e)!, style: look.body(13, color: look.ink)),
          ),
        ],
        heading('Squawk headlines (unverified)'),
        for (final h in e.headlines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${_clock(h.at)} · ${h.channel}\n${h.text}', style: look.body(13.5, color: look.ink)),
          ),
      ],
    );
  }
}

/// Live moves: last 5 minutes (big = spike) and today.
class _Meter extends StatelessWidget {
  const _Meter({required this.flash});
  final FlashView flash;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    if (flash.prices.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: look.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: look.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MOMENTUM · 5 MIN / TODAY', style: look.label(10.5, color: look.section('markets'))),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final m in markets)
            if (flash.prices[m.name] != null) _meterItem(look, m, flash.prices[m.name]!),
        ]),
      ]),
    );
  }

  Widget _meterItem(Look look, Market m, Bars b) {
    final five = b.changeOver(const Duration(minutes: 5));
    final day = b.dayChange;
    final spike = five != null && five.abs() >= m.spike;
    Color tone(double? v) => v == null || v.abs() < 0.01 ? look.muted : (v > 0 ? look.up : look.down);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${m.name}${m.delayed ? '*' : ''}', style: look.body(11.5)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(five == null ? '–' : _pct(five), style: look.number(13, color: tone(five), weight: spike ? FontWeight.w800 : null)),
        if (spike) Text(' ⚡', style: look.number(13)),
        Text(day == null ? '' : '  ${_pct(day, digits: 1)}', style: look.number(11.5, color: tone(day))),
      ]),
    ]);
  }
}

class _DeskLine extends StatelessWidget {
  const _DeskLine({required this.flash});
  final FlashView flash;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: Text(
        'Opus flash desk: ${flash.deskToday} of ${flash.config.deskDaily} checks today · on your plan',
        style: look.body(12),
      ),
    );
  }
}

/// Today's released Forex events with a reading, as heat items: a time with
/// several events counts once, as their combined effect.
List<HeatItem> calendarItems(AppController app, DateTime now) {
  final slots = <DateTime, List<ForexEvent>>{};
  for (final e in app.forexShown) {
    if (sameDay(e.date, now) && !e.date.isAfter(now)) slots.putIfAbsent(e.date, () => []).add(e);
  }
  final out = <HeatItem>[];
  for (final MapEntry(key: at, value: group) in slots.entries) {
    final time = DateFormat('h:mm a').format(at.toLocal());
    final first = group.first;
    if (group.length >= 2) {
      final c = combine(group, (x) => Readout.of(app, x).verdict);
      if (!c.released || c.chips.isEmpty) continue;
      out.add(HeatItem(
        source: HeatSource.calendar,
        label: 'Forex $time: ${first.country} ${first.title} + ${group.length - 1} more',
        at: at,
        chips: c.chips,
      ));
    } else {
      final r = Readout.of(app, first);
      if (r.verdict == null || r.chips.isEmpty) continue;
      out.add(HeatItem(
          source: HeatSource.calendar, label: 'Forex $time: ${first.country} ${first.title}', at: at, chips: r.chips));
    }
  }
  return out;
}

String _ago(DateTime t, DateTime now) {
  final m = now.difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  return '${m ~/ 60} h ${m % 60} min ago';
}

/// Today's push on each commodity and market, from the news so far.
class _HeatMap extends StatelessWidget {
  const _HeatMap({required this.cells, required this.source, required this.prices, required this.onSource});
  final List<Heat> cells;
  final HeatSource source;
  final Map<String, Bars> prices;
  final ValueChanged<HeatSource> onSource;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final quiet = cells.every((c) => c.strength == 'quiet');
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: look.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: look.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("TODAY'S PUSH", style: look.label(10.5, color: look.section('markets'))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in HeatSource.values)
            ChoiceChip(
              label: Text(s.label),
              selected: s == source,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSource(s),
            ),
        ]),
        const SizedBox(height: 6),
        if (quiet)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              switch (source) {
                HeatSource.all => 'Quiet so far today: no strong news has pushed these yet.',
                HeatSource.hot => 'No HOT news today yet.',
                HeatSource.running => 'No running stories today yet.',
                HeatSource.calendar => 'No Forex results with a push today yet.',
              },
              style: look.body(13),
            ),
          )
        else
          for (final c in cells) _row(context, look, c),
      ]),
    );
  }

  Widget _row(BuildContext context, Look look, Heat c) {
    final up = c.net > 0;
    final color = switch (c.strength) {
      'quiet' => look.muted,
      'mixed' => look.impact('medium'),
      _ => up ? look.up : look.down,
    };
    final arrow = switch (c.strength) { 'quiet' => '–', 'mixed' => '↕', _ => up ? '▲' : '▼' };
    final bars = c.asset.market == null ? null : prices[c.asset.market];
    final day = bars?.dayChange == null ? null : (c.asset.inverted ? -bars!.dayChange! : bars!.dayChange!);
    return InkWell(
      onTap: c.reasons.isEmpty ? null : () => _showReasons(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 74, child: Text(c.asset.name, style: look.body(13, color: look.ink))),
          for (var i = 0; i < 3; i++)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: i < c.blocks || (i == 0 && c.strength == 'mixed')
                    ? color.withValues(alpha: 0.35 + 0.2 * c.blocks)
                    : look.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 6),
          SizedBox(
            width: 82,
            child: Text('$arrow ${c.strength}', style: look.body(12.5, color: color, weight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              c.reasons.isEmpty ? '' : c.reasons.first.$1.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: look.body(11.5),
            ),
          ),
          if (day != null) ...[
            const SizedBox(width: 6),
            Text(_pct(day, digits: 1),
                style: look.number(11.5, color: day.abs() < 0.01 ? look.muted : (day > 0 ? look.up : look.down))),
          ],
        ]),
      ),
    );
  }

  void _showReasons(BuildContext context, Heat c) {
    final look = Look.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text('${c.asset.name}: ${c.strength} ${c.net > 0 ? 'up' : c.net < 0 ? 'down' : ''}'.trim(),
              style: look.headline(19)),
          const SizedBox(height: 4),
          Text('${source.label} news today, biggest push first.', style: look.body(12.5)),
          const SizedBox(height: 10),
          for (final (item, w) in c.reasons)
            InkWell(
              onTap: item.event == null ? null : () => showFlashEvent(context, item.event!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 44,
                    child: Text(w > 0 ? '▲ $w' : (w < 0 ? '▼ ${-w}' : '↕'),
                        style: look.number(13, color: w > 0 ? look.up : (w < 0 ? look.down : look.muted))),
                  ),
                  Expanded(
                    child: Text('${DateFormat('h:mm a').format(item.at.toLocal())} · ${item.label}',
                        style: look.body(13.5, color: look.ink)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// News that keeps coming today, one line per story.
class _Stories extends StatelessWidget {
  const _Stories({required this.stories, required this.now, required this.flash});
  final List<Story> stories;
  final DateTime now;
  final FlashView flash;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text('RUNNING STORIES', style: look.label(10.5, color: look.section('markets'))),
      ),
      for (final s in stories)
        InkWell(
          onTap: () => _open(context, s),
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: look.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: s.hot ? look.impact('high').withValues(alpha: 0.6) : look.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (s.hot) ...[const VerdictBadge(Verdict.hot), const SizedBox(width: 8)],
                Expanded(child: Text(s.name, style: look.headline(15))),
                Text(
                  switch (s.momentum(now)) { 'building' => '↗ building', 'fading' => '↘ fading', _ => '→ steady' },
                  style: look.body(12, color: s.momentum(now) == 'building' ? look.impact('high') : look.muted),
                ),
              ]),
              const SizedBox(height: 4),
              Text('${s.updates} updates · last ${_ago(s.last, now)}',
                  style: look.body(11.5)),
              const SizedBox(height: 4),
              Text(s.events.first.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: look.body(13, color: look.ink)),
            ]),
          ),
        ),
    ]);
  }

  void _open(BuildContext context, Story s) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(s.name, style: Look.of(context).headline(20)),
              ),
              for (final e in s.events) FlashCard(event: e, seen: flash.isSeen(e)),
            ],
          ),
        ),
      );
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.flash});
  final FlashView flash;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: look.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: look.impact('medium').withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Finish setting up Flash', style: look.headline(16)),
        const SizedBox(height: 6),
        Text('A few one-time steps. Tap the gear for all of them.', style: look.body(13)),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => FlashSettingsScreen(flash: flash))),
          child: const Text('Open setup'),
        ),
      ]),
    );
  }
}
