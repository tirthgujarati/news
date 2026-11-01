import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/edition_store.dart';
import 'package:newsapp/data/sync.dart';

String fixture() => File('test/fixtures/edition.json').readAsStringSync();

/// The fixture re-dated, to make a second (or older) edition.
String editionOn(String date, String slot, {String? headlinePrefix}) {
  final j = jsonDecode(fixture()) as Map<String, dynamic>;
  j['date'] = date;
  j['slot'] = slot;
  j['edition_id'] = '$date-$slot';
  j['generated_at'] = '${date}T07:34:00+05:30';
  if (headlinePrefix != null) {
    for (final s in j['sections'] as List) {
      for (final st in (s as Map)['stories'] as List) {
        (st as Map)['headline'] = '$headlinePrefix ${st['headline']}';
      }
    }
  }
  return jsonEncode(j);
}

void main() {
  late Directory dir;
  late EditionStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('store_test');
    store = EditionStore(dir);
    await store.init();
  });

  tearDown(() => dir.delete(recursive: true));

  Future<void> add(String raw) => store.save(raw, parseEdition(raw));

  test('saves editions newest first and survives a restart', () async {
    await add(editionOn('2026-11-01', 'evening'));
    await add(editionOn('2026-11-02', 'morning'));
    await add(editionOn('2026-11-01', 'midday'));
    expect(store.entries.map((e) => e.editionId),
        ['2026-11-02-morning', '2026-11-01-evening', '2026-11-01-midday']);

    final again = EditionStore(dir);
    await again.init();
    expect(again.entries.first.editionId, '2026-11-02-morning');
    expect(await again.readRaw('2026-11-01-evening'), isNotNull);
  });

  test('replacing an edition keeps one copy', () async {
    await add(editionOn('2026-11-02', 'morning'));
    await add(editionOn('2026-11-02', 'morning', headlinePrefix: 'NEW'));
    expect(store.entries, hasLength(1));
    expect(store.search('NEW').length, 12);
  });

  test('search covers every stored edition, newest first, no repeats', () async {
    await add(editionOn('2026-10-30', 'evening', headlinePrefix: 'ARCHIVED'));
    await add(editionOn('2026-11-02', 'morning'));
    final hits = store.search('hormuz');
    expect(hits, hasLength(1)); // same story id in both: shown once
    expect(hits.first.editionId, '2026-11-02-morning');
    expect(store.search('archived iran').single.editionId, '2026-10-30-evening');
    expect(store.search('   '), isEmpty);
    expect(store.search('no such words anywhere'), isEmpty);
  });

  test('prune deletes old editions but never the newest', () async {
    await add(editionOn('2026-09-01', 'morning'));
    await add(editionOn('2026-10-25', 'morning'));
    await add(editionOn('2026-11-02', 'morning'));
    final removed = await store.prune(30, DateTime(2026, 11, 2));
    expect(removed, ['2026-09-01-morning']);
    expect(store.entries, hasLength(2));
    expect(await store.readRaw('2026-09-01-morning'), isNull);
    expect(await store.prune(null, DateTime(2026, 11, 2)), isEmpty);

    // Even with 0 days, the newest edition stays.
    await store.prune(0, DateTime(2030, 1, 1));
    expect(store.entries.single.editionId, '2026-11-02-morning');
  });

  test('saved stories persist after their edition is deleted', () async {
    await add(editionOn('2026-09-01', 'morning'));
    await add(editionOn('2026-11-02', 'morning'));
    final old = parseEdition((await store.readRaw('2026-09-01-morning'))!);
    final lead = old.leadStory!;
    expect(await store.toggleSaved(lead, old), isTrue);
    await store.prune(7, DateTime(2026, 11, 2));

    final again = EditionStore(dir);
    await again.init();
    expect(again.isSaved(lead.id), isTrue);
    expect(again.saved.single.story.headline, lead.headline);
    expect(again.pinnedPhotoUrls, {lead.image!.url});

    expect(await again.toggleSaved(lead, old), isFalse);
    expect(again.saved, isEmpty);
  });
}
