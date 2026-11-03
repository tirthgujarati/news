/// What the Flash screen shows. Reads flash.json (written by the background
/// engine), asks Android for the setup status, and keeps the momentum meter.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desk.dart' show deskDayOf;
import 'engine.dart' show FlashConfig;
import 'flash.dart';
import 'prices.dart';
import 'store.dart';

const _native = MethodChannel('apex/native');
const _ui = MethodChannel('apex/flashui');

/// The phone-side setup: what's done and what's missing.
class FlashStatus {
  final bool listener;
  final bool notifications;
  final bool battery;
  final bool telegram;
  final bool githubToken;

  /// The app was built with Firebase (push notifications work).
  final bool push;

  const FlashStatus({
    this.listener = false,
    this.notifications = false,
    this.battery = false,
    this.telegram = false,
    this.githubToken = false,
    this.push = false,
  });

  bool get ready => listener && notifications && githubToken;
}

class FlashView extends ChangeNotifier {
  FlashView(Directory root, {this.live = true}) : _store = FlashStore(root);

  final FlashStore _store;

  /// Off in tests: no Android channels, no network.
  final bool live;

  List<FlashEvent> get events => _store.events;
  List<TapeItem> get tape => _store.tape;
  int get deskToday => _store.deskDay == deskDayOf(DateTime.now()) ? _store.deskCount : 0;

  FlashStatus status = const FlashStatus();
  FlashConfig config = const FlashConfig();
  Map<String, Bars> prices = {};
  DateTime? pricesAt;
  Set<String> _seen = {};

  /// An event to open (from a tapped notification).
  final openRequest = ValueNotifier<String?>(null);

  final _prices = Prices();
  Timer? _meter;

  bool isSeen(FlashEvent e) => e.seen || _seen.contains(e.id);

  int get unseenHot => events
      .where((e) => e.verdict == Verdict.hot && !isSeen(e) && DateTime.now().difference(e.at).inHours < 12)
      .length;

  Future<void> start() async {
    await reload();
    if (!live) return;
    _ui.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          await reload();
        case 'open':
          openRequest.value = call.arguments as String?;
      }
      return null;
    });
    try {
      final launch = await _native.invokeMethod<String>('takeLaunchEvent');
      if (launch != null) openRequest.value = launch;
      // Make sure the background engine runs (it also starts with Telegram access).
      await _native.invokeMethod('startEngine');
      await _native.invokeMethod('setPush', {'editions': config.pushEditions});
    } on MissingPluginException {
      // Not on Android.
    }
    await refreshStatus();
  }

  Future<void> reload() async {
    await _store.load();
    final p = await SharedPreferences.getInstance();
    _seen = (p.getStringList('flash_seen') ?? const []).toSet();
    config = await FlashConfig.read();
    notifyListeners();
  }

  Future<void> markSeen(Iterable<FlashEvent> list) async {
    final add = list.map((e) => e.id).where((id) => !_seen.contains(id)).toList();
    if (add.isEmpty) return;
    _seen.addAll(add);
    final keep = events.map((e) => e.id).toSet();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('flash_seen', _seen.where(keep.contains).toList());
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    if (!live) return;
    try {
      final s = (await _native.invokeMethod<Map>('status'))!.cast<String, Object?>();
      final gh = await _native.invokeMethod<String>('secret', {'name': 'github_token'});
      status = FlashStatus(
        listener: s['listener'] == true,
        notifications: s['notifications'] == true,
        battery: s['battery'] == true,
        telegram: s['telegram'] == true,
        githubToken: gh != null && gh.isNotEmpty,
        push: s['push'] == true,
      );
      notifyListeners();
    } on MissingPluginException {
      // Not on Android.
    }
  }

  Future<void> native(String method, [Map<String, Object?>? args]) async {
    try {
      await _native.invokeMethod(method, args);
    } on MissingPluginException {
      // Not on Android.
    }
  }

  Future<void> setSecret(String name, String value) async {
    await native('setSecret', {'name': name, 'value': value.trim()});
    await refreshStatus();
  }

  Future<void> setConfig(void Function(SharedPreferences p) write) async {
    final p = await SharedPreferences.getInstance();
    write(p);
    config = await FlashConfig.read();
    await native('settingsChanged');
    notifyListeners();
  }

  Future<void> setPushEditions(bool on) async {
    await setConfig((p) => p.setBool(FlashConfig.kPushEditions, on));
    await native('setPush', {'editions': on});
  }

  Future<void> setWatchMode(bool on) async {
    await setConfig((p) => p.setBool(FlashConfig.kWatch, on));
    await native('setWatch', {'on': on});
  }

  /// The momentum meter: refreshed every 30 seconds while Flash is on screen.
  void meter(bool visible) {
    _meter?.cancel();
    if (!visible || !live) return;
    Future<void> tick() async {
      try {
        prices = await _prices.all();
        pricesAt = DateTime.now();
        notifyListeners();
      } catch (_) {}
    }

    unawaited(tick());
    _meter = Timer.periodic(const Duration(seconds: 30), (_) => tick());
  }

  @override
  void dispose() {
    _meter?.cancel();
    _prices.close();
    openRequest.dispose();
    super.dispose();
  }
}
