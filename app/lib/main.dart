import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';
import 'background/background.dart';
import 'data/edition_store.dart';
import 'data/photo_cache.dart';
import 'data/remote.dart';
import 'data/settings.dart';
import 'flash/background.dart';
import 'theme/look.dart';
import 'ui/flash_screen.dart';
import 'ui/forex_screen.dart';
import 'ui/home_screen.dart';
import 'ui/saved_screen.dart';
import 'ui/scope.dart';
import 'ui/settings_screen.dart';
import 'ui/week_ahead_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Both are disk lookups: run them side by side.
  final (settings, docs) =
      await (Settings.load(), getApplicationDocumentsDirectory()).wait;
  final app = AppController(
    settings: settings,
    store: EditionStore(docs),
    photos: PhotoCache(docs),
    remote: Remote(),
  );
  runApp(ApexApp(app: app));
  // The stored edition shows first; the network check follows inside start().
  unawaited(app.start());
  unawaited(scheduleBackgroundChecks());
}

/// Entry point of the background Flash engine (started by Android for the
/// Telegram listener and the market watcher; see FlashHub.kt).
@pragma('vm:entry-point')
Future<void> flashMain() => runFlashEngine();

class ApexApp extends StatelessWidget {
  const ApexApp({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final settings = app.settings;
    // AppScope sits above MaterialApp so story sheets and pushed screens
    // (which live in the Navigator's overlay) can reach the controller too.
    return AppScope(
      app: app,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'apex',
          debugShowCheckedModeBanner: false,
          theme: themeFor(settings.style, Brightness.light),
          darkTheme: themeFor(settings.style, Brightness.dark),
          themeMode: settings.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(settings.textScale)),
            child: child!,
          ),
          home: const Shell(),
        ),
      ),
    );
  }
}

/// Bottom navigation between the main screens.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  AppController? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!identical(app, _app)) {
      _app?.newEditionSignal.removeListener(_onNewEdition);
      _app?.tabRequest.removeListener(_onTabRequest);
      _app?.flash.openRequest.removeListener(_onFlashOpen);
      _app = app
        ..newEditionSignal.addListener(_onNewEdition)
        ..tabRequest.addListener(_onTabRequest)
        ..flash.openRequest.addListener(_onFlashOpen);
    }
  }

  @override
  void dispose() {
    _app?.newEditionSignal.removeListener(_onNewEdition);
    _app?.tabRequest.removeListener(_onTabRequest);
    _app?.flash.openRequest.removeListener(_onFlashOpen);
    super.dispose();
  }

  void _onTabRequest() {
    final t = _app?.tabRequest.value;
    if (t == null) return;
    _app!.tabRequest.value = null;
    setState(() => _tab = t);
  }

  // A Flash notification was tapped: show the Flash tab (it opens the event).
  void _onFlashOpen() {
    if (_app?.flash.openRequest.value != null && _tab != 1) setState(() => _tab = 1);
  }

  void _onNewEdition() {
    final title = _app?.edition?.title ?? 'New edition';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('New edition: $title'),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final screens = [
      const HomeScreen(),
      FlashScreen(flash: _app!.flash, visible: _tab == 1),
      const ForexScreen(),
      const WeekAheadScreen(),
      const SavedScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: look.bg,
        indicatorColor: look.section('markets').withValues(alpha: 0.22),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), selectedIcon: Icon(Icons.newspaper), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Flash'),
          NavigationDestination(icon: Icon(Icons.currency_exchange), label: 'Forex'),
          NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Week'),
          NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
