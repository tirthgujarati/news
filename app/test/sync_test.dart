import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsapp/data/edition_store.dart';
import 'package:newsapp/data/remote.dart';
import 'package:newsapp/data/sync.dart';

import 'store_test.dart' show editionOn;

/// A fake GitHub serving the given editions (newest first).
Remote fakeRemote(Map<String, String> editionsById, {List<String>? requested}) {
  final ids = editionsById.keys.toList();
  return Remote(MockClient((req) async {
    requested?.add(req.url.path);
    expect(req.headers['User-Agent'], userAgent);
    final path = req.url.path.split('/data/').last;
    if (path == 'index.json') {
      return http.Response(
        jsonEncode({
          'updated_at': '2026-11-02T07:34:00+05:30',
          'editions': [
            for (final id in ids) {'edition_id': id, 'path': 'editions/$id.json'}
          ],
        }),
        200,
      );
    }
    final id = path.replaceFirst('editions/', '').replaceFirst('.json', '');
    final body = editionsById[id];
    return body == null ? http.Response('nope', 404) : http.Response.bytes(utf8.encode(body), 200);
  }));
}

void main() {
  late Directory dir;
  late EditionStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_test');
    store = EditionStore(dir);
    await store.init();
  });

  tearDown(() => dir.delete(recursive: true));

  test('downloads every edition the phone is missing', () async {
    final remote = fakeRemote({
      '2026-11-02-morning': editionOn('2026-11-02', 'morning'),
      '2026-11-01-evening': editionOn('2026-11-01', 'evening'),
    });
    final r = await syncEditions(remote, store);
    expect(r.stored, ['2026-11-01-evening', '2026-11-02-morning']);
    expect(store.entries.first.editionId, '2026-11-02-morning');
  });

  test('skips editions it already has, but re-checks the newest', () async {
    final eds = {
      '2026-11-02-morning': editionOn('2026-11-02', 'morning'),
      '2026-11-01-evening': editionOn('2026-11-01', 'evening'),
    };
    await syncEditions(fakeRemote(eds), store);

    final requested = <String>[];
    final r = await syncEditions(fakeRemote(eds, requested: requested), store);
    expect(r.changed, isFalse);
    expect(requested.where((p) => p.contains('2026-11-01-evening')), isEmpty);
    expect(requested.where((p) => p.contains('2026-11-02-morning')), hasLength(1));
  });

  test('a re-run that replaces the newest edition is picked up', () async {
    await syncEditions(
        fakeRemote({'2026-11-02-morning': editionOn('2026-11-02', 'morning')}), store);
    final rerun = jsonDecode(editionOn('2026-11-02', 'morning', headlinePrefix: 'UPDATED'))
        as Map<String, dynamic>;
    rerun['generated_at'] = '2026-11-02T07:52:00+05:30';
    final r = await syncEditions(
        fakeRemote({'2026-11-02-morning': jsonEncode(rerun)}), store);
    expect(r.stored, ['2026-11-02-morning']);
    expect(store.search('updated'), isNotEmpty);
  });

  test('never stores a broken edition', () async {
    final bad = jsonDecode(editionOn('2026-11-02', 'morning')) as Map<String, dynamic>;
    bad['schema_version'] = 99;
    final r = await syncEditions(
      fakeRemote({
        '2026-11-02-morning': jsonEncode(bad),
        '2026-11-01-evening': editionOn('2026-11-01', 'evening'),
      }),
      store,
    );
    expect(r.rejected, ['2026-11-02-morning']);
    expect(store.entries.single.editionId, '2026-11-01-evening');
  });

  test('a network failure throws so the app can show Offline', () async {
    final remote = Remote(MockClient((_) async => throw const SocketException('no net')));
    expect(syncEditions(remote, store), throwsA(isA<SocketException>()));
  });
}
