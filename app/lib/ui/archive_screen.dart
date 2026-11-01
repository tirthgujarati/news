import 'package:flutter/material.dart';

import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// Every edition stored on the phone, newest first, grouped by day.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key, required this.onOpened});

  /// Called after an edition is opened, so the app can switch to Home.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final entries = app.store.entries;
    final rows = <Widget>[];
    String? lastDate;
    for (final e in entries) {
      if (e.date != lastDate) {
        lastDate = e.date;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Text(dayLabel(DateTime.parse(e.date)).toUpperCase(),
              style: look.label(11.5, color: look.ink)),
        ));
      }
      final showing = app.edition?.editionId == e.editionId;
      rows.add(ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        title: Text(e.title, style: look.headline(15.5)),
        subtitle: Text('${clock(e.generatedAt)} · ${e.storyCount} stories',
            style: look.body(12.5)),
        trailing: showing
            ? Icon(Icons.visibility, size: 18, color: look.muted)
            : Icon(Icons.chevron_right, color: look.muted),
        onTap: () async {
          await app.openEdition(e.editionId);
          onOpened();
        },
      ));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: entries.isEmpty
          ? Center(child: Text('No editions stored yet.', style: look.body(14)))
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
    );
  }
}
