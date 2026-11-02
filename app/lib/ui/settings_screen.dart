import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../models/forex.dart' show forexCurrencies;
import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// Shown in Settings. CI passes the real version with --dart-define.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final s = app.settings;

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
          child: Text(t.toUpperCase(), style: look.label(11)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            heading('Style'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SegmentedButton<AppStyle>(
                segments: [
                  for (final st in AppStyle.values)
                    ButtonSegment(value: st, label: Text(st.label)),
                ],
                selected: {s.style},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.style = v.first,
              ),
            ),
            heading('Theme'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => s.themeMode = v.first,
              ),
            ),
            heading('Text size'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const SizedBox(width: 10),
                Text('A', style: look.body(13, color: look.ink)),
                Expanded(
                  child: Slider(
                    value: s.textScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    label: '${(s.textScale * 100).round()}%',
                    onChanged: (v) => s.textScale = v,
                  ),
                ),
                Text('A', style: look.body(22, color: look.ink)),
                const SizedBox(width: 10),
              ]),
            ),
            heading('Storage on this phone'),
            _RetentionTile(
              title: 'Keep editions',
              choices: textRetentionChoices,
              value: s.keepTextDays,
              onChanged: (v) {
                s.keepTextDays = v;
                app.applyStorageSettings();
              },
            ),
            _RetentionTile(
              title: 'Keep photos',
              subtitle: 'Saved stories always keep their photo',
              choices: photoRetentionChoices,
              value: s.keepPhotoDays,
              onChanged: (v) {
                s.keepPhotoDays = v;
                app.applyStorageSettings();
              },
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Text('Photos on Wi-Fi only', style: look.body(15, color: look.ink)),
              subtitle: Text('On mobile data you get text; photos fill in on Wi-Fi',
                  style: look.body(12.5)),
              value: s.photosWifiOnly,
              onChanged: (v) => s.photosWifiOnly = v,
            ),
            const _StorageUsed(),
            heading('Forex calendar currencies'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in forexCurrencies)
                  FilterChip(
                    label: Text(c),
                    selected: s.forexShown.contains(c),
                    onSelected: (on) {
                      final next = {...s.forexShown};
                      on ? next.add(c) : next.remove(c);
                      s.forexShown = next;
                    },
                  ),
              ]),
            ),
            heading('Updates'),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Text('Check for updates now', style: look.body(15, color: look.ink)),
              subtitle: Text(
                app.refreshing
                    ? 'Checking…'
                    : app.offline
                        ? 'Last check failed: offline'
                        : 'New editions also download at 8 AM, 2 PM and 9 PM',
                style: look.body(12.5),
              ),
              trailing: app.refreshing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onTap: app.refresh,
            ),
            heading('About'),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Text('Opened in', style: look.body(15, color: look.ink)),
              subtitle: Text('Tap on the icon to readable news, this launch. Target: under 1 s',
                  style: look.body(12.5)),
              trailing: Text(
                app.openedInMs == null
                    ? '—'
                    : '${(app.openedInMs! / 1000).toStringAsFixed(2)} s',
                style: look.number(13,
                    color: app.openedInMs == null
                        ? look.muted
                        : app.openedInMs! < 1000
                            ? look.up
                            : look.down),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              title: Text('App version', style: look.body(15, color: look.ink)),
              trailing: Text(appVersion, style: look.number(13, color: look.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetentionTile extends StatelessWidget {
  const _RetentionTile({
    required this.title,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Retention> choices;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final current = choices.firstWhere((c) => c.days == value,
        orElse: () => Retention('$value days', value));
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      title: Text(title, style: look.body(15, color: look.ink)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: look.body(12.5)),
      trailing: DropdownButton<int?>(
        value: current.days,
        underline: const SizedBox.shrink(),
        items: [
          for (final c in choices)
            DropdownMenuItem(value: c.days, child: Text(c.label)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _StorageUsed extends StatelessWidget {
  const _StorageUsed();

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    Future<(int, int)> sizes() async =>
        (await app.store.sizeOnDisk(), await app.photos.sizeOnDisk());
    return FutureBuilder<(int, int)>(
      future: sizes(),
      builder: (context, snap) {
        final d = snap.data;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          title: Text('Storage used', style: look.body(15, color: look.ink)),
          subtitle: Text(
            d == null
                ? '…'
                : '${bytes(d.$1)} editions (${app.store.entries.length}) · ${bytes(d.$2)} photos',
            style: look.body(12.5),
          ),
        );
      },
    );
  }
}
