import 'package:flutter/material.dart';

import '../flash/engine.dart' show FlashConfig;
import '../flash/flash_view.dart';
import '../theme/look.dart';
import 'widgets.dart';

/// Flash setup and settings: the one-time steps, keys, limits and modes.
class FlashSettingsScreen extends StatefulWidget {
  const FlashSettingsScreen({super.key, required this.flash});
  final FlashView flash;

  @override
  State<FlashSettingsScreen> createState() => _FlashSettingsScreenState();
}

class _FlashSettingsScreenState extends State<FlashSettingsScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.flash.refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings: show the new state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.flash.refreshStatus();
  }

  Future<void> _editSecret(String name, String title, String hint) async {
    final ctl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (value == null) return;
    await widget.flash.setSecret(name, value);
  }

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final f = widget.flash;

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
          child: Text(t.toUpperCase(), style: look.label(11)),
        );

    Widget step(bool done, String title, String detail, {String? action, VoidCallback? onTap}) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? look.up : look.impact('medium')),
          title: Text(title, style: look.body(14.5, color: look.ink, weight: FontWeight.w600)),
          subtitle: Text(detail, style: look.body(12.5)),
          trailing: action == null ? null : TextButton(onPressed: onTap, child: Text(action)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Flash setup')),
      body: ListenableBuilder(
        listenable: f,
        builder: (context, _) {
          final s = f.status;
          final c = f.config;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              heading('One-time steps'),
              step(s.telegram, 'Telegram with the squawk channels',
                  'Install Telegram and join @marketfeed and @financialjuice, with notifications on (sound can be off).',
                  action: 'Open', onTap: () => openLink('https://t.me/marketfeed')),
              step(s.listener, 'Let apex read Telegram notifications',
                  'This is how apex sees each post the second it arrives. It only uses the channels below.',
                  action: s.listener ? null : 'Allow', onTap: () => f.native('openListenerSettings')),
              step(s.notifications, 'Allow apex notifications', 'For HOT (sound) and WATCH (silent) alerts.',
                  action: s.notifications ? null : 'Allow', onTap: () => f.native('requestNotifications')),
              step(s.battery, 'Battery: Unrestricted',
                  'So Android doesn\'t pause apex while the phone sleeps.',
                  action: s.battery ? null : 'Set', onTap: () => f.native('openBatterySettings')),
              step(s.apiKey, 'Claude API key (quick judge)',
                  'Your own key from console.anthropic.com. Stored encrypted on this phone only.',
                  action: s.apiKey ? 'Change' : 'Add',
                  onTap: () => _editSecret('anthropic_key', 'Claude API key', 'sk-ant-...')),
              step(s.githubToken, 'GitHub token (Opus flash desk)',
                  'Fine-grained token for tirthgujarati/news with Issues: read and write and Contents: read.',
                  action: s.githubToken ? 'Change' : 'Add',
                  onTap: () => _editSecret('github_token', 'GitHub token', 'github_pat_...')),
              heading('Flash'),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Flash on', style: look.body(14.5, color: look.ink)),
                value: c.enabled,
                onChanged: (v) => f.setConfig((p) => p.setBool(FlashConfig.kEnabled, v)),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Channels', style: look.body(14.5, color: look.ink)),
                subtitle: Text(c.channels.join(', '), style: look.body(12.5)),
                trailing: TextButton(
                  child: const Text('Edit'),
                  onPressed: () async {
                    final ctl = TextEditingController(text: c.channels.join(', '));
                    final v = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Telegram channels'),
                        content: TextField(
                          controller: ctl,
                          decoration: const InputDecoration(helperText: 'Names as Telegram shows them, comma separated'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (v == null) return;
                    final list = [for (final x in v.split(',')) if (x.trim().isNotEmpty) x.trim()];
                    await f.setConfig((p) => p.setStringList(FlashConfig.kChannels, list));
                  },
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Replace Telegram\'s alerts', style: look.body(14.5, color: look.ink)),
                subtitle: Text('Clear Telegram\'s own notifications for these channels; apex alerts instead.',
                    style: look.body(12.5)),
                value: c.hideTelegram,
                onChanged: (v) => f.setConfig((p) => p.setBool(FlashConfig.kHide, v)),
              ),
              heading('Claude'),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Monthly limit for the quick judge', style: look.body(14.5, color: look.ink)),
                subtitle: Text('Sonnet 5.5, about ₹0.25 a call. At the limit, apex uses rules only.',
                    style: look.body(12.5)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 100, label: Text('₹100')),
                    ButtonSegment(value: 200, label: Text('₹200')),
                    ButtonSegment(value: 500, label: Text('₹500')),
                  ],
                  selected: {c.monthlyInr},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => f.setConfig((p) => p.setDouble(FlashConfig.kMonthly, v.first)),
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Opus flash desk on HOT', style: look.body(14.5, color: look.ink)),
                subtitle: Text(
                    'Your plan\'s Opus checks HOT news with real sources in ~3 minutes. Up to ${c.deskDaily} a day.',
                    style: look.body(12.5)),
                value: c.deskAuto,
                onChanged: (v) => f.setConfig((p) => p.setBool(FlashConfig.kDeskAuto, v)),
              ),
              heading('Faster when closed'),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text('Market watcher', style: look.body(14.5, color: look.ink)),
                subtitle: Text(
                    'Keeps apex running with a small notification: also reads the channels\' public pages every '
                    '15 s and flags sudden price moves. Uses more battery and data (about 50 MB a day).',
                    style: look.body(12.5)),
                value: c.watchMode,
                onChanged: f.setWatchMode,
              ),
            ],
          );
        },
      ),
    );
  }
}
