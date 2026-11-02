// Renders Home in every style for a visual check. Not part of `flutter test`
// (rendering differs between machines). Run:
//   flutter test test_goldens --update-goldens
// and look at test_goldens/goldens/*.png.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/main.dart';

import '../test/ui_helpers.dart';

const _photos = {
  'https://www.aljazeera.com/wp-content/uploads/2026/11/14405199-1793530960.jpg?resize=1920%2C1440':
      '../design/_cache/iran.jpg',
  'https://image.cnbcfm.com/api/v1/image/108432673-1792420157696-gettyimages-2300478114-AFP_D3QN9WE.jpeg?v=1792420206&w=1920&h=1080':
      '../design/_cache/markets.jpg',
};

void main() {
  setUpAll(() async {
    await loadAppFonts();
    // Material icons, so screenshots show icons instead of empty boxes.
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? '';
    final icons = File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  });

  for (final style in AppStyle.values) {
    for (final theme in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('home ${style.name} ${theme.name}', timeout: const Timeout(Duration(minutes: 2)), (tester) async {
        final dir = Directory.systemTemp.createTempSync('golden');
        addTearDown(() => dir.deleteSync(recursive: true));
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        final app = (await tester.runAsync(() => makeTestApp(dir,
            style: style, theme: theme, photos: _photos)))!;
        await tester.pumpWidget(ApexApp(app: app));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(style == AppStyle.bold ? 'MONEY & MARKETS' : 'Money & Markets'));
        await tester.pumpAndSettle();
        // Decode photos (real file IO), then draw again.
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/home_${style.name}_${theme.name}.png'));

        // The lead story's sheet.
        await tester.tap(find.textContaining('Iran cuts its Hormuz').first);
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400)); // let photo fade-ins finish
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/sheet_${style.name}_${theme.name}.png'));
      });
    }
  }
}
