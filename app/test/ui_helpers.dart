import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:newsapp/app_controller.dart';
import 'package:newsapp/data/edition_store.dart';
import 'package:newsapp/data/photo_cache.dart';
import 'package:newsapp/data/remote.dart';
import 'package:newsapp/data/settings.dart';
import 'package:newsapp/data/sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the bundled fonts so text renders as it will on the phone.
Future<void> loadAppFonts() async {
  const families = {
    'SpaceGrotesk': ['500', '700'],
    'JetBrainsMono': ['500'],
    'Archivo': ['700', '800', '900'],
    'InterTight': ['600', '800', '900'],
    'Inter': ['400', '500', '600', '700'],
  };
  for (final MapEntry(key: family, value: weights) in families.entries) {
    final loader = FontLoader(family);
    for (final w in weights) {
      final bytes = File('assets/fonts/$family-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// An app with the real fixture edition stored, offline (no network).
/// [photos] maps image URLs to local files to place in the photo cache.
Future<AppController> makeTestApp(
  Directory dir, {
  AppStyle style = AppStyle.night,
  ThemeMode theme = ThemeMode.dark,
  Map<String, String> photos = const {},
}) async {
  SharedPreferences.setMockInitialValues({'style': style.name, 'theme': theme.name});
  final settings = await Settings.load();
  final store = EditionStore(dir);
  await store.init();
  final raw = File('test/fixtures/edition.json').readAsStringSync();
  await store.save(raw, parseEdition(raw));
  final cache = PhotoCache(dir, MockClient((_) async => throw const SocketException('offline')));
  for (final MapEntry(key: url, value: path) in photos.entries) {
    final f = cache.fileFor(url);
    await f.parent.create(recursive: true);
    await File(path).copy(f.path);
  }
  final app = AppController(
    settings: settings,
    store: store,
    photos: cache,
    remote: Remote(MockClient((_) async => throw const SocketException('offline'))),
  );
  await app.start();
  // Let the background refresh fail (offline) before the test continues.
  while (app.refreshing) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return app;
}
