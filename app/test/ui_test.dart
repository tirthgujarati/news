import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/main.dart';

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
        await tester.tap(find.text(style == AppStyle.bold ? 'MONEY & MARKETS' : 'Money & Markets'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Wall Street ends October'));
        await tester.pumpAndSettle();
        expect(find.text('WHY IT MATTERS'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('every bottom tab opens without errors', (tester) async {
    await pumpApp(tester, AppStyle.night, ThemeMode.dark);
    for (final tab in ['Week', 'Saved', 'Archive', 'Settings', 'Home']) {
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
    expect(find.text('MONEY & MARKETS'), findsOneWidget);
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
}
