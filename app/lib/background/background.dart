import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../data/edition_store.dart';
import '../data/photo_cache.dart';
import '../data/remote.dart';
import '../data/settings.dart';
import '../data/sync.dart';
import 'schedule.dart';

const _taskName = 'apex.editionCheck';
const _uniqueName = 'edition-check';

/// Runs in a background isolate when Android wakes the app.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final attempt = (input?['attempt'] as int?) ?? 0;
    var gotNew = false;
    try {
      gotNew = await _checkForEditions();
    } catch (e) {
      debugPrint('Background check failed: $e');
    }
    if (!gotNew && attempt < maxRetries) {
      // The edition may be a few minutes late: try again shortly.
      await _schedule(retryEvery, attempt + 1);
    } else {
      final now = DateTime.now();
      await _schedule(nextCheckUtc(now).difference(now.toUtc()), 0);
    }
    return true;
  });
}

/// Called on every app start: books the next fixed check (8 AM, 2 PM or
/// 9 PM IST). Android may run it a few minutes late to save battery.
Future<void> scheduleBackgroundChecks() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    final now = DateTime.now();
    await _schedule(nextCheckUtc(now).difference(now.toUtc()), 0);
  } catch (e) {
    debugPrint('Could not schedule background checks: $e');
  }
}

Future<void> _schedule(Duration delay, int attempt) =>
    Workmanager().registerOneOffTask(
      _uniqueName,
      _taskName,
      initialDelay: delay,
      inputData: {'attempt': attempt},
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

/// Downloads new editions and their photos. Returns true if anything new
/// arrived.
Future<bool> _checkForEditions() async {
  final settings = await Settings.load();
  final docs = await getApplicationDocumentsDirectory();
  final store = EditionStore(docs);
  await store.init();
  final remote = Remote();
  final photos = PhotoCache(docs);
  try {
    final result = await syncEditions(remote, store);
    try {
      await store.saveForexFeeds(await remote.fetchForexFeeds());
    } catch (_) {
      // The Forex tab keeps its last copy.
    }
    await store.prune(settings.keepTextDays, DateTime.now());

    var photosAllowed = true;
    if (settings.photosWifiOnly) {
      final kinds = await Connectivity().checkConnectivity();
      photosAllowed = kinds.contains(ConnectivityResult.wifi) ||
          kinds.contains(ConnectivityResult.ethernet);
    }
    if (photosAllowed && store.entries.isNotEmpty) {
      final raw = await store.readRaw(store.entries.first.editionId);
      if (raw != null) await photos.prefetch(parseEdition(raw));
    }
    await photos.prune(settings.keepPhotoDays, store.pinnedPhotoUrls);
    return result.changed;
  } finally {
    remote.close();
  }
}
