import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../flash/flash.dart';
import '../flash/flash_view.dart';
import '../flash/prices.dart';
import '../theme/look.dart';
import 'flash_settings_screen.dart';
import 'widgets.dart';

String _clock(DateTime t) => DateFormat('h:mm:ss a').format(t.toLocal());

String _pct(double v, {int digits = 2}) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}%';

Color verdictColor(Look look, Verdict v) => switch (v) {
      Verdict.hot => look.impact('high'),
      Verdict.watch => look.impact('medium'),
      Verdict.noise => look.muted,
    };

/// Hot news in seconds: squawk headlines judged by rules, Claude Sonnet and
/// the Opus flash desk, with the market's own reaction.
class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key, required this.flash, this.visible = true});
  final FlashView flash;

  /// True while this tab is on screen (runs the momentum meter).
  final bool visible;

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  bool _tape = false;
  bool _showNoise = false;

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
        final events = [
          for (final e in f.events)
            if (_showNoise || e.verdict != Verdict.noise) e
        ];
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
                _SpendLine(flash: f),
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
                    if (!_tape)
                      FilterChip(
                        label: const Text('Noise'),
                        selected: _showNoise,
                        onSelected: (v) => setState(() => _showNoise = v),
                      ),
                  ]),
                ),
                if (_tape)
                  ..._tapeRows(look, f)
                else if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      f.status.listener || f.config.watchMode
                          ? 'Nothing hot yet. Market-moving squawk headlines show up here within seconds.'
                          : 'Finish the setup above to start catching hot news.',
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

/// "Sonnet 2.1 s · Opus ✓ confirmed" / "Opus checking…" / "Rules (No key)".
String calledByLine(FlashEvent e) {
  final parts = <String>[];
  final j = e.judgement;
  if (j != null) {
    parts.add('Sonnet ${(j.ms / 1000).toStringAsFixed(1)} s${j.isNew ? '' : ' · already known'}');
  } else {
    parts.add(e.judgeError == null ? 'Rules' : 'Rules · ${e.judgeError}');
  }
  if (e.desk != null) {
    final mins = e.desk!.checkedAt.difference(e.at).inMinutes;
    parts.add('Opus ${e.desk!.confirmed ? '✓ confirmed' : 'not confirmed'}${mins > 0 ? ' in $mins min' : ''}');
  } else if (e.issue != null) {
    parts.add('Opus checking…');
  }
  return parts.join(' · ');
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
    final why = e.desk?.why ?? e.judgement?.why;
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
        ] else if (e.issue != null) ...[
          heading('Opus flash desk'),
          Text('Checking with independent sources… usually 2–4 minutes.', style: look.body(14)),
        ],
        if (e.judgement != null) ...[
          heading('Sonnet quick judge'),
          Text(
            '${e.judgement!.verdict.label}${e.judgement!.isNew ? '' : ' · already known'} · '
            '${(e.judgement!.ms / 1000).toStringAsFixed(1)} s',
            style: look.body(13),
          ),
          if (d != null && e.judgement!.why.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e.judgement!.why, style: look.body(13.5, color: look.ink)),
            ),
        ] else if (e.judgeError != null) ...[
          heading('Quick judge'),
          Text('Rules only: ${e.judgeError}', style: look.body(13)),
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

class _SpendLine extends StatelessWidget {
  const _SpendLine({required this.flash});
  final FlashView flash;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final s = flash.spend;
    final c = flash.config;
    final used = s == null || s.month != DateTime.now().toIso8601String().substring(0, 7) ? 0.0 : s.usd * c.inrPerUsd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: Text(
        'Claude Sonnet: ₹${used.toStringAsFixed(0)} of ₹${c.monthlyInr.toStringAsFixed(0)} this month'
        '${s == null ? '' : ' · ${s.calls} calls'} · Opus desk ${flash.deskToday}/${c.deskDaily} today',
        style: look.body(12),
      ),
    );
  }
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
