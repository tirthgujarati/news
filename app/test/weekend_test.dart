import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/data/sync.dart';
import 'package:newsapp/main.dart';

import 'ui_helpers.dart';

/// The fixture (Monday 2026-11-02, 7:30 AM) turned into that Monday's
/// 5:30 AM Weekend Special edition.
String mondayWeekend() {
  final e = jsonDecode(File('test/fixtures/edition.json').readAsStringSync()) as Map<String, dynamic>;
  final oil = Map<String, dynamic>.of(e['sections'][3]['stories'][0] as Map<String, dynamic>);
  e
    ..['edition_id'] = '2026-11-02-weekend'
    ..['slot'] = 'weekend'
    ..['title'] = 'Monday Weekend Edition'
    ..['generated_at'] = '2026-11-02T05:34:00+05:30'
    ..['weekend_special'] = {
      'title': 'Weekend: Fri to Sun',
      'stories': [
        {
          ...oil,
          'rank': 1,
          'lead': false,
          'image': null,
          'impact': [
            {'on': 'us_stocks', 'level': 'high', 'dir': 'down', 'why': 'Tech selloff on AI spending.'},
          ],
          'monday_effect': 'IT stocks like Infosys and TCS could open weaker; Nifty likely flat to lower.',
          'watch_next': 'Nasdaq futures on Sunday night; Apple results on Thursday.',
        },
      ],
    };
  return jsonEncode(e);
}

void main() {
  late Directory dir;

  setUpAll(loadAppFonts);
  setUp(() async => dir = await Directory.systemTemp.createTemp('weekend_test'));
  tearDown(() => dir.delete(recursive: true));

  test('reads the Monday effect and what to watch', () {
    final ws = parseEdition(mondayWeekend()).weekendSpecial!;
    expect(ws.monday, isTrue);
    expect(ws.stories.single.mondayEffect, contains('Infosys'));
    expect(ws.stories.single.watchNext, contains('Nasdaq'));
    expect(ws.stories.single.impact.single.dir, 'down');
  });

  testWidgets('the 7:30 edition leads, and the 5:30 Weekend Special stays a tap away', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
        () => makeTestApp(dir, style: AppStyle.night, extraEditions: [mondayWeekend()])))!;
    expect(app.edition!.editionId, '2026-11-02-morning');
    expect(app.weekend!.editionId, '2026-11-02-weekend');

    await tester.pumpWidget(ApexApp(app: app));
    await tester.pumpAndSettle();
    expect(find.text('WEEKEND SPECIAL'), findsOneWidget);
    expect(find.textContaining('stories most likely to move Monday'), findsOneWidget);

    await tester.tap(find.text('WEEKEND SPECIAL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Friday afternoon to Sunday night'), findsOneWidget);

    await tester.tap(find.textContaining('Wall Street ends October').first);
    await tester.pumpAndSettle();
    expect(find.text('MONDAY EFFECT'), findsOneWidget);
    expect(find.text('WHAT TO WATCH'), findsOneWidget);
    expect(find.textContaining('Infosys and TCS'), findsOneWidget);
  });
}
