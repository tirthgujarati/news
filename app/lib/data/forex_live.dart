import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/forex.dart';
import '../models/live.dart';
import 'remote.dart';

/// Keeps actual results fresh while the app is open.
///
/// Checks Myfxbook every second from 20 s before a red/orange event until its
/// actual arrives (one request at a time, on a kept-alive connection), and
/// once a minute otherwise. Stops when the app goes to the background and
/// checks at once when it comes back.
class ForexLive extends ChangeNotifier with WidgetsBindingObserver {
  ForexLive({required this.remote, required this.events});

  final Remote remote;

  /// The Forex Factory events to watch (red/orange are used).
  final List<ForexEvent> Function() events;

  final Map<String, LiveRow> _rows = {};
  Duration _clockOffset = Duration.zero;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _inFlight = false;

  /// When the last successful check finished (corrected time).
  DateTime? lastChecked;

  /// True when the last check failed (no internet, server error).
  bool failing = false;

  /// The current time by the server's clock, so a phone clock that's a few
  /// seconds off doesn't delay the every-second checks.
  DateTime get now => DateTime.now().toUtc().add(_clockOffset);

  LiveRow? rowFor(ForexEvent e) => _rows[e.key];

  bool hasActual(ForexEvent e) => _rows[e.key]?.released ?? false;

  /// True while checking every second around a release.
  bool get hot => isHot(now, events(), hasActual);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _tick();
  }

  /// Checks now (e.g. right after the calendar itself was refreshed).
  void checkNow() {
    if (!_started) return;
    _timer?.cancel();
    _tick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground) _tick();
  }

  Future<void> _tick() async {
    if (!_foreground || _inFlight) return;
    _inFlight = true;
    final began = DateTime.now();
    try {
      final (body, server) = await remote.fetchLiveCalendar();
      if (server != null) {
        // The server's Date header is whole seconds; only correct a phone
        // clock that is clearly off.
        final off = server.difference(DateTime.now().toUtc());
        _clockOffset = off.abs() > const Duration(seconds: 2) ? off : Duration.zero;
      }
      final rows = parseMyfxbookRss(body);
      for (final e in events()) {
        if (!e.shown) continue;
        final r = matchLive(e, rows);
        if (r != null) _rows[e.key] = r;
      }
      failing = false;
      lastChecked = now;
    } catch (e) {
      debugPrint('Live calendar check failed: $e');
      failing = true;
    } finally {
      _inFlight = false;
      notifyListeners();
      if (_foreground) {
        var wait = nextPollDelay(now, events(), hasActual);
        if (wait == const Duration(seconds: 1)) {
          // Keep the gap between checks at ~1 s including download time.
          final took = DateTime.now().difference(began);
          wait = took >= wait ? Duration.zero : wait - took;
        }
        _timer?.cancel();
        _timer = Timer(wait, _tick);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
