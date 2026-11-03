import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'data/edition_store.dart';
import 'data/forex_live.dart';
import 'data/photo_cache.dart';
import 'data/remote.dart';
import 'data/settings.dart';
import 'data/sync.dart';
import 'flash/flash_view.dart';
import 'models/edition.dart';
import 'models/forex.dart';
import 'startup_timer.dart';

/// App state: which edition is showing, online/offline, saved stories.
///
/// On launch the newest stored edition shows at once; the network check runs
/// after, and a new edition swaps in with a "New edition" notice.
class AppController extends ChangeNotifier {
  AppController({
    required this.settings,
    required this.store,
    required this.photos,
    required this.remote,
    this.liveUpdates = true,
  }) {
    live = ForexLive(remote: remote, events: () => forexEvents);
  }

  /// Live actual results for the Forex tab (Myfxbook, checked every second
  /// around releases while the app is open).
  late final ForexLive live;

  /// Off in tests, so nothing polls the network.
  final bool liveUpdates;

  /// Hot news caught from squawk channels (written by the background engine).
  late final FlashView flash = FlashView(store.root, live: liveUpdates);

  /// Completes when Flash has read its file (tests wait for it).
  Future<void>? flashStarted;

  /// Asks the tab bar to switch tab (e.g. Archive opened an edition: Home).
  final tabRequest = ValueNotifier<int?>(null);

  final Settings settings;
  final EditionStore store;
  final PhotoCache photos;
  final Remote remote;

  /// The edition on screen (newest, or one opened from Archive).
  Edition? edition;

  /// True while showing an older edition opened from Archive.
  bool viewingArchive = false;

  bool refreshing = false;

  /// True when the last check for new editions failed.
  bool offline = false;

  /// Whether photos may be downloaded right now (Wi-Fi-only setting).
  bool photosAllowed = true;

  /// Goes up by one each time a newer edition replaces the one on screen.
  final newEditionSignal = ValueNotifier<int>(0);

  bool get ready => edition != null;

  /// Forex Factory's calendar (all impacts), oldest first.
  List<ForexEvent> forexEvents = const [];

  /// True when the last Forex Factory download failed (showing the copy
  /// stored on the phone).
  bool forexOffline = false;

  /// Red and orange events for the currencies chosen in Settings.
  List<ForexEvent> get forexShown {
    final ccy = settings.forexShown;
    return [for (final e in forexEvents) if (e.shown && ccy.contains(e.country)) e];
  }

  ForexResult? forexResult(ForexEvent e) => store.forexResults[e.key];

  /// Time from tapping the icon to readable news on this launch (cold
  /// starts only), shown in Settings.
  int? openedInMs;

  Future<void> start() async {
    await store.init();
    forexEvents = parseForexFeeds(await store.readForexFeeds());
    if (liveUpdates) live.start();
    if (store.entries.isNotEmpty) {
      await _show(store.entries.first.editionId);
    }
    notifyListeners();
    if (edition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        openedInMs = await msSinceProcessStart();
        notifyListeners();
      });
    }
    unawaited(store.loadSearchIndex());
    unawaited(flashStarted = flash.start());
    unawaited(refresh());
  }

  /// Checks GitHub for new editions. Safe to call any time.
  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    // The Forex calendar is fetched alongside; its failure doesn't affect news.
    final forex = _refreshForex();
    try {
      await _updatePhotoPermission();
      final result = await syncEditions(remote, store);
      offline = false;
      await store.prune(settings.keepTextDays, DateTime.now());

      final newest = store.entries.isEmpty ? null : store.entries.first;
      if (newest != null && !viewingArchive) {
        final current = edition;
        final isNewer = current == null ||
            newest.editionId != current.editionId ||
            result.stored.contains(newest.editionId);
        if (isNewer) {
          await _show(newest.editionId);
          if (current != null) newEditionSignal.value++;
        }
      }
      unawaited(_photoHousekeeping());
    } catch (e) {
      debugPrint('Refresh failed: $e');
      offline = true;
    } finally {
      await forex;
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshForex() async {
    try {
      final raws = await remote.fetchForexFeeds();
      final events = parseForexFeeds(raws);
      if (events.isNotEmpty) {
        forexEvents = events;
        await store.saveForexFeeds(raws);
        live.checkNow();
      }
      forexOffline = false;
    } catch (e) {
      debugPrint('Forex calendar refresh failed: $e');
      forexOffline = true;
    }
  }

  /// Opens an older edition from the phone's archive.
  Future<void> openEdition(String editionId) async {
    final newestId = store.entries.isEmpty ? null : store.entries.first.editionId;
    await _show(editionId);
    viewingArchive = editionId != newestId;
    notifyListeners();
  }

  Future<void> backToLatest() async {
    viewingArchive = false;
    if (store.entries.isNotEmpty) await _show(store.entries.first.editionId);
    notifyListeners();
  }

  /// Loads any stored edition (for search results and saved stories).
  Future<Edition?> loadEdition(String editionId) async {
    final raw = await store.readRaw(editionId);
    if (raw == null) return null;
    try {
      // A 25 KB edition decodes in a few ms; a helper isolate costs more.
      return parseEdition(raw);
    } on FormatException {
      return null;
    }
  }

  bool isSaved(Story s) => store.isSaved(s.id);

  Future<bool> toggleSaved(Story story, Edition inEdition) async {
    final now = await store.toggleSaved(story, inEdition);
    if (now && story.image != null) {
      // Saved stories keep their photo forever, so fetch it now.
      unawaited(photos.get(story.image!.url, allowDownload: photosAllowed));
    }
    notifyListeners();
    return now;
  }

  /// Re-applies storage settings right away (called from Settings).
  Future<void> applyStorageSettings() async {
    await store.prune(settings.keepTextDays, DateTime.now());
    await photos.prune(settings.keepPhotoDays, store.pinnedPhotoUrls);
    notifyListeners();
  }

  Future<void> _show(String editionId) async {
    final e = await loadEdition(editionId);
    if (e != null) edition = e;
  }

  Future<void> _updatePhotoPermission() async {
    if (!settings.photosWifiOnly) {
      photosAllowed = true;
      return;
    }
    final kinds = await Connectivity().checkConnectivity();
    photosAllowed = kinds.contains(ConnectivityResult.wifi) ||
        kinds.contains(ConnectivityResult.ethernet);
  }

  Future<void> _photoHousekeeping() async {
    final e = edition;
    if (e != null && photosAllowed) await photos.prefetch(e);
    await photos.prune(settings.keepPhotoDays, store.pinnedPhotoUrls);
  }

  @override
  void dispose() {
    live.dispose();
    flash.dispose();
    tabRequest.dispose();
    newEditionSignal.dispose();
    remote.close();
    super.dispose();
  }
}
