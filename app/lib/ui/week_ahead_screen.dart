import 'package:flutter/material.dart';

import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// Day-by-day list of the week's scheduled events.
class WeekAheadScreen extends StatelessWidget {
  const WeekAheadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final days = context.app.edition?.weekAhead ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Week Ahead')),
      body: days.isEmpty
          ? Center(child: Text('Nothing scheduled yet.', style: look.body(14)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final d = days[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dayLabel(d.date).toUpperCase(), style: look.label(11.5, color: look.ink)),
                    const SizedBox(height: 8),
                    for (final ev in d.events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: look.section(ev.section),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(ev.text,
                                style: look.body(14.5, color: look.ink, height: 1.4)),
                          ),
                        ]),
                      ),
                    Divider(color: look.line, height: 12),
                  ]),
                );
              },
            ),
    );
  }
}
