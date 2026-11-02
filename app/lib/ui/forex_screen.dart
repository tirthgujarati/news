import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../models/edition.dart' show ImpactTag, Source;
import '../models/forex.dart';
import '../models/live.dart' as rules;
import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// What we know about one event right now: the actual (live first, then the
/// editor's), the forecast, how it compares, and the instant chips.
class Readout {
  final String? actual;
  final String forecast;
  final String previous;

  /// better, worse, in_line or no_forecast; null before release.
  final String? verdict;
  final List<ImpactTag> chips;

  /// The editor's one-line meaning and source, once an edition has it.
  final String? why;
  final Source? source;

  const Readout({
    required this.actual,
    required this.forecast,
    required this.previous,
    required this.verdict,
    required this.chips,
    required this.why,
    required this.source,
  });

  factory Readout.of(AppController app, ForexEvent e) {
    final row = app.live.rowFor(e);
    final edited = app.forexResult(e);
    final forecast = (row != null && row.consensus.isNotEmpty) ? row.consensus : e.forecast;
    final previous = (row != null && row.previous.isNotEmpty) ? row.previous : e.previous;
    final actual = (row != null && row.released) ? row.actual : edited?.actual;
    String? v;
    if (actual != null) {
      v = rules.verdict(e.title, actual, forecast);
      // Speeches and statements: use the editor's reading if there is one.
      if (v == 'no_forecast' && edited != null) v = edited.vsForecast;
    }
    return Readout(
      actual: actual,
      forecast: forecast,
      previous: previous,
      verdict: v,
      chips: actual == null || v == null ? const [] : rules.instantChips(e, actual, forecast, v),
      why: edited?.why,
      source: edited?.source,
    );
  }
}

/// Forex Factory's red (High) and orange (Medium) events, in IST.
class ForexScreen extends StatelessWidget {
  const ForexScreen({super.key, this.now});

  /// Fixed "now" for tests; the real time otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // Rebuild on new live results and when currencies change in Settings.
    return ListenableBuilder(
      listenable: Listenable.merge([context.app.settings, context.app.live]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final events = app.forexShown;
    final t = now ?? app.live.now;
    final next = events.where((e) => e.date.isAfter(t)).firstOrNull;

    final rows = <Widget>[];
    String? day;
    for (final e in events) {
      final d = DateFormat('yyyy-MM-dd').format(e.date.toLocal());
      if (d != day) {
        day = d;
        final isToday = d == DateFormat('yyyy-MM-dd').format(t);
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Row(children: [
            Text(dayLabel(e.date.toLocal()).toUpperCase(),
                style: look.label(11.5, color: look.ink)),
            if (isToday) ...[
              const SizedBox(width: 8),
              Text('TODAY', style: look.label(10.5, color: look.section('markets'))),
            ],
          ]),
        ));
      }
      rows.add(_EventRow(event: e, readout: Readout.of(app, e), now: t));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Forex calendar')),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Text(
                app.forexOffline
                    ? 'Offline: showing the last saved calendar. Times in IST.'
                    : 'High and medium impact events from Forex Factory. Times in IST.',
                style: look.body(12.5),
              ),
            ),
            _LiveStatus(app: app),
            if (next != null) _NextCard(event: next, now: t),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  app.forexEvents.isEmpty
                      ? 'No calendar yet. Pull down to download it.'
                      : 'No red or orange events for your currencies this week.',
                  style: look.body(14),
                  textAlign: TextAlign.center,
                ),
              ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// "HIGH" in red or "MED" in orange, the same style as impact chips.
class ForexImpactChip extends StatelessWidget {
  const ForexImpactChip(this.impact, {super.key});
  final String impact;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final high = impact == 'High';
    final c = look.impact(high ? 'high' : 'medium');
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        border: Border.all(color: c.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(high ? 'HIGH' : 'MED', style: look.label(9.5, color: look.ink)),
      ]),
    );
  }
}

String _countdown(Duration d) {
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  if (d.inHours < 24) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
  return 'in ${d.inDays}d ${d.inHours % 24}h';
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.event, required this.now});
  final ForexEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final c = look.impact(event.impact == 'High' ? 'high' : 'medium');
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: look.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('NEXT', style: look.label(10.5, color: c)),
          const SizedBox(width: 8),
          ForexImpactChip(event.impact),
          const Spacer(),
          Text(_countdown(event.date.difference(now)),
              style: look.number(13, color: look.ink, weight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text('${event.country}  ${event.title}', style: look.headline(19, height: 1.2)),
        const SizedBox(height: 4),
        Text(
          '${dayLabel(event.date.toLocal())}, ${clock(event.date)}'
          '${event.forecast.isEmpty ? '' : ' · Forecast ${event.forecast}'}'
          '${event.previous.isEmpty ? '' : ' · Previous ${event.previous}'}',
          style: look.body(13),
        ),
      ]),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.readout, required this.now});
  final ForexEvent event;
  final Readout readout;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final r = readout;
    final past = !event.date.isAfter(now);
    final waiting = past && r.actual == null && now.difference(event.date).inMinutes < 5;
    final actualColor = switch (r.verdict) {
      'better' => look.up,
      'worse' => look.down,
      _ => look.ink,
    };
    return Opacity(
      // Past events without a result fade back; results stay readable.
      opacity: past && r.actual == null && !waiting ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            // Fits "10:00 AM" with room to spare.
            width: 78,
            child: Text(clock(event.date), style: look.number(12.5, color: look.muted)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ForexImpactChip(event.impact),
                const SizedBox(width: 8),
                Text(event.country,
                    style: look.number(12.5, color: look.ink, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 5),
              Text(event.title, style: look.headline(15, height: 1.25)),
              const SizedBox(height: 4),
              Wrap(spacing: 12, children: [
                if (r.actual != null)
                  Text('Actual ${r.actual}',
                      style: look.number(12.5, color: actualColor, weight: FontWeight.w700)),
                if (waiting)
                  Text('Actual …', style: look.number(12.5, color: look.ink, weight: FontWeight.w700)),
                if (r.forecast.isNotEmpty)
                  Text('Forecast ${r.forecast}', style: look.number(12.5, color: look.muted)),
                if (r.previous.isNotEmpty)
                  Text('Previous ${r.previous}', style: look.number(12.5, color: look.muted)),
              ]),
              if (r.chips.isNotEmpty) ...[
                const SizedBox(height: 7),
                ImpactChips(impact: r.chips),
              ],
              if (r.why != null && r.source != null) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => openLink(r.source!.url),
                  child: Text('${r.why}  (${r.source!.name})',
                      style: look.body(12.5, color: look.ink, height: 1.4)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "● LIVE · checking every second" around releases; otherwise when the
/// last check ran.
class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final live = app.live;
    final String text;
    final Color color;
    if (live.failing) {
      text = 'Live results paused: no connection';
      color = look.down;
    } else if (live.hot) {
      text = 'LIVE · checking every second for the actual';
      color = look.up;
    } else if (live.lastChecked != null) {
      text = 'Live results on · last checked ${DateFormat('h:mm:ss a').format(live.lastChecked!.toLocal())}';
      color = look.muted;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
      child: Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: look.body(12, color: color))),
      ]),
    );
  }
}
