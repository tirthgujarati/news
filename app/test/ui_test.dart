import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/main.dart';
import 'package:newsapp/theme/look.dart';
import 'package:newsapp/ui/forex_screen.dart';
import 'package:newsapp/ui/scope.dart';

import 'ui_helpers.dart';

void main() {
  late Directory dir;

  setUpAll(loadAppFonts);
  setUp(() async => dir = await Directory.systemTemp.createTemp('ui_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<void> pumpApp(WidgetTester tester, AppStyle style, ThemeMode theme) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
        () => makeTestApp(dir, style: style, theme: theme)))!;
    await tester.pumpWidget(ApexApp(app: app));
    await tester.pumpAndSettle();
  }

  for (final style in AppStyle.values) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Home builds: ${style.label}, ${theme.name}', (tester) async {
        await pumpApp(tester, style, theme);
        expect(tester.takeException(), isNull);
        expect(find.text('Monday Morning Edition'), findsOneWidget);
        expect(find.textContaining('Iran cuts its Hormuz'), findsOneWidget);
        expect(find.textContaining('Offline, showing'), findsOneWidget);
        expect(find.text('SINGLE SOURCE'), findsWidgets);

        // Switch to Money & Markets and open the first story.
        await tester.tap(find.textContaining(style == AppStyle.bold ? 'MONEY & MARKETS' : 'Money & Markets'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Wall Street ends October'));
        await tester.pumpAndSettle();
        expect(find.text('WHY IT MATTERS'), findsOneWidget);
        expect(find.text('IMPACT'), findsOneWidget);
        expect(find.text('US STOCKS ▼'), findsWidgets);
        expect(find.text('Save'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('every bottom tab opens without errors', (tester) async {
    await pumpApp(tester, AppStyle.night, ThemeMode.dark);
    for (final tab in ['Forex', 'Week', 'Saved', 'Archive', 'Settings', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();
    expect(find.text('US midterm elections'), findsOneWidget);
  });

  testWidgets('saving a story shows it in Saved', (tester) async {
    await pumpApp(tester, AppStyle.paper, ThemeMode.light);
    await tester.tap(find.textContaining('Iran cuts its Hormuz'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsWidgets);
    await tester.tapAt(const Offset(200, 40)); // close the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Iran cuts its Hormuz'), findsOneWidget);
  });

  testWidgets('changing style in Settings restyles the app', (tester) async {
    await pumpApp(tester, AppStyle.night, ThemeMode.dark);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('MONEY & MARKETS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds stories across stored editions', (tester) async {
    await pumpApp(tester, AppStyle.night, ThemeMode.dark);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'binance');
    await tester.pumpAndSettle();
    expect(find.textContaining('Binance hack'), findsOneWidget);
  });

  testWidgets('Forex tab: next event, IST times, actual result', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(() => makeTestApp(dir)))!;
    // 2 Nov 2026, 6:00 PM IST; ISM is at 8:30 PM IST (10:00 AM New York).
    final now = DateTime.utc(2026, 11, 2, 12, 30);
    await tester.pumpWidget(AppScope(
      app: app,
      child: MaterialApp(
        theme: themeFor(AppStyle.night, Brightness.dark),
        home: ForexScreen(now: now),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('USD  ISM Manufacturing PMI'), findsOneWidget);
    expect(find.text('in 2h 30m'), findsOneWidget);
    expect(find.text('Actual 55.1'), findsOneWidget);
    expect(find.text('HIGH'), findsWidgets);
    expect(find.text('MED'), findsWidgets);
    expect(find.textContaining('MI Inflation Gauge'), findsNothing); // Low impact
    expect(tester.takeException(), isNull);

    // Hide USD in Settings: US events disappear.
    app.settings.forexShown = {'AUD', 'CHF'};
    await tester.pumpAndSettle();
    expect(find.textContaining('ISM Manufacturing'), findsNothing);
    expect(find.textContaining('Cash Rate'), findsWidgets);
  });
}
