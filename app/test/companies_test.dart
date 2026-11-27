import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/nifty100.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/data/sync.dart';
import 'package:newsapp/main.dart';
import 'package:newsapp/ui/watchlist_screen.dart';
import 'package:newsapp/ui/widgets.dart';

import 'ui_helpers.dart';

/// The fixture edition with "Most affected" companies on the Hormuz oil chip
/// and a symbol on a company chip.
String withCompanies() {
  final e = jsonDecode(File('test/fixtures/edition.json').readAsStringSync()) as Map<String, dynamic>;
  final hormuz = (e['sections'][1]['stories'] as List).first as Map<String, dynamic>;
  final oil = (hormuz['impact'] as List).firstWhere((i) => i['on'] == 'oil') as Map<String, dynamic>;
  oil['companies'] = [
    {'symbol': 'BPCL', 'name': 'BPCL', 'level': 'high', 'dir': 'up', 'why': 'Buys crude, so fuel margins widen.', 'basis': 'exposure'},
    {'symbol': 'IOC', 'name': 'Indian Oil', 'level': 'high', 'dir': 'up', 'why': 'Same: refiner and fuel retailer.', 'basis': 'exposure'},
    {'symbol': 'ONGC', 'name': 'ONGC', 'level': 'medium', 'dir': 'down', 'why': 'Sells crude, so it earns less per barrel.', 'basis': 'exposure'},
  ];
  final tech = (e['sections'][3]['stories'] as List).first as Map<String, dynamic>;
  (tech['impact'] as List).add(
      {'on': 'company', 'detail': 'Infosys', 'symbol': 'INFY', 'level': 'low', 'dir': 'down', 'why': 'US tech mood.'});
  return jsonEncode(e);
}

void main() {
  late Directory dir;

  setUpAll(loadAppFonts);
  setUp(() async => dir = await Directory.systemTemp.createTemp('companies_test'));
  tearDown(() => dir.delete(recursive: true));

  test('reads most affected companies and company symbols', () {
    final e = parseEdition(withCompanies());
    final hormuz = e.section('world')!.stories.first;
    final oil = hormuz.impact.firstWhere((t) => t.on == 'oil');
    expect(oil.companies.map((c) => c.symbol), ['BPCL', 'IOC', 'ONGC']);
    expect(oil.companies.last.dir, 'down');
    expect(oil.companies.first.direct, isFalse);
    expect(hormuz.symbols, {'BPCL', 'IOC', 'ONGC'});
    expect(e.section('markets')!.stories.first.symbols, {'INFY'});
    // Saved stories keep them.
    expect(oil.toJson()['companies'], hasLength(3));
  });

  test('the bundled Nifty 100 list matches the repo copy', () {
    final app = parseNifty100(File('assets/nifty100.json').readAsStringSync());
    expect(app, hasLength(100));
    expect(app.map((c) => c.symbol), containsAll(['BPCL', 'IOC', 'ONGC', 'HDFCBANK', 'INFY']));
  });

  testWidgets('story sheet lists the most affected; starring adds a Watchlist tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
        () => makeTestApp(dir, style: AppStyle.night, extraEditions: [withCompanies()])))!;
    await tester.pumpWidget(ApexApp(app: app));
    await tester.pumpAndSettle();
    final watchTab = find.byWidgetPredicate((w) => w is Text && (w.data?.toLowerCase().startsWith('watchlist') ?? false));
    expect(watchTab, findsNothing);

    await tester.tap(find.textContaining('Hormuz reopening').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('MOST AFFECTED'), 300,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('MOST AFFECTED'), findsOneWidget);
    expect(find.text('Indian Oil'), findsOneWidget);
    expect(find.text('Exposure'), findsNWidgets(3));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    Navigator.of(tester.element(find.text('MOST AFFECTED'))).pop();
    await tester.pumpAndSettle();

    app.setWatched('ONGC', true);
    await tester.pumpAndSettle();
    expect(app.watchlist, {'ONGC'});
    await tester.scrollUntilVisible(watchTab, 150,
        scrollable: find.descendant(of: find.byType(SectionTabs), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    await tester.tap(watchTab);
    await tester.pumpAndSettle();
    expect(find.textContaining('Hormuz reopening'), findsWidgets);
    expect(find.textContaining('Wall Street ends October'), findsNothing);
  });

  testWidgets('Watchlist screen: search and star', (tester) async {
    final app = (await tester.runAsync(() => makeTestApp(dir, style: AppStyle.night)))!;
    const list = [
      ListedCompany(symbol: 'HDFCBANK', name: 'HDFC Bank', sector: 'Financial Services'),
      ListedCompany(symbol: 'INFY', name: 'Infosys', sector: 'Information Technology'),
      ListedCompany(symbol: 'SBIN', name: 'State Bank of India', sector: 'Financial Services'),
    ];
    await tester.pumpWidget(ApexApp(app: app));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(builder: (_) => const WatchlistScreen(companies: list)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Star the companies'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bank');
    await tester.pumpAndSettle();
    expect(find.text('Infosys'), findsNothing);
    expect(find.text('HDFC Bank'), findsOneWidget);

    await tester.tap(find.text('State Bank of India'));
    await tester.pumpAndSettle();
    expect(app.watchlist, {'SBIN'});
    expect(find.text('1 starred · stays on this phone'), findsOneWidget);
  });
}
