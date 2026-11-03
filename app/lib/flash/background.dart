/// Starts the Flash engine inside the background Flutter engine that
/// Android runs for the Telegram listener and the market watcher.
library;

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'desk.dart';
import 'engine.dart';
import 'prices.dart';
import 'store.dart';
import 'watcher.dart';

const native = MethodChannel('apex/native');

/// [FlashPlatform] through the "apex/native" channel (see ApexNative.kt).
class ChannelPlatform implements FlashPlatform {
  @override
  Future<String?> secret(String name) => native.invokeMethod<String>('secret', {'name': name});

  @override
  Future<void> alert(FlashAlert a) => native.invokeMethod('alert', {
        'id': a.id,
        'loud': a.loud,
        'title': a.title,
        'text': a.text,
        'eventId': a.eventId,
      });

  @override
  Future<void> cancelAlert(int id) => native.invokeMethod('cancelAlert', {'id': id});

  @override
  Future<void> dismissSource(String key) => native.invokeMethod('dismissSource', {'key': key});

  @override
  void changed() => unawaited(native.invokeMethod('changed'));
}

Future<void> runFlashEngine() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final prices = Prices();
  final engine = FlashEngine(
    store: FlashStore(docs),
    platform: ChannelPlatform(),
    config: FlashConfig.read,
    deskFor: (token) => FlashDesk(token: token),
    prices: prices,
  );
  await engine.start();

  final watcher = ChannelWatcher();
  Timer? pages, spikes;
  Future<void> applySettings() async {
    final cfg = await FlashConfig.read();
    pages?.cancel();
    spikes?.cancel();
    if (!cfg.enabled || !cfg.watchMode) return;
    pages = Timer.periodic(const Duration(seconds: 15), (_) async {
      for (final c in cfg.channels) {
        try {
          for (final h in await watcher.poll(c, DateTime.now())) {
            await engine.ingest(h);
          }
        } catch (_) {
          // The page will be read again in 15 seconds.
        }
      }
    });
    spikes = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        await engine.checkSpikes(await prices.all());
      } catch (_) {}
    });
  }

  const flash = MethodChannel('apex/flash');
  flash.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'telegram':
        final m = (call.arguments as Map).cast<String, Object?>();
        await engine.onTelegram(
          title: m['title'] as String,
          text: m['text'] as String,
          at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
          key: m['key'] as String?,
        );
      case 'settings':
        await applySettings();
      case 'desk':
        await engine.deskReady((call.arguments as Map)['issue'] as int);
    }
    return null;
  });
  await applySettings();
  await flash.invokeMethod('ready');
}
