import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/forex.dart';
import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// Forex Factory's red (High) and orange (Medium) events, in IST.
class ForexScreen extends StatelessWidget {
  const ForexScreen({super.key, this.now});

  /// Fixed "now" for tests; the real time otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // Rebuild when the currencies are changed in Settings.
    return ListenableBuilder(
      listenable: context.app.settings,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final events = app.forexShown;
    final t = now ?? DateTime.now();
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
      rows.add(_EventRow(event: e, result: app.forexResult(e), now: t));
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
  const _EventRow({required this.event, required this.result, required this.now});
  final ForexEvent event;
  final ForexResult? result;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final past = !event.date.isAfter(now);
    final r = result;
    final actualColor = switch (r?.vsForecast) {
      'better' => look.up,
      'worse' => look.down,
      _ => look.ink,
    };
    return Opacity(
      // Past events without a result fade back; results stay readable.
      opacity: past && r == null ? 0.55 : 1,
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
                if (r != null)
                  Text('Actual ${r.actual}',
                      style: look.number(12.5, color: actualColor, weight: FontWeight.w700)),
                if (event.forecast.isNotEmpty)
                  Text('Forecast ${event.forecast}', style: look.number(12.5, color: look.muted)),
                if (event.previous.isNotEmpty)
                  Text('Previous ${event.previous}', style: look.number(12.5, color: look.muted)),
              ]),
              if (r != null) ...[
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: () => openLink(r.source.url),
                  child: Text('${r.why}  (${r.source.name})',
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
