import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/edition.dart';
import 'remote.dart' show userAgent;

/// Keeps story photos on the phone so they show offline.
///
/// Files live in `<root>/photos/<hash>`; the original link is never needed to
/// show a stored photo. Photos are only links in the data: nothing is shared.
class PhotoCache {
  PhotoCache(this.root, [http.Client? client])
      : _client = client ?? http.Client();

  final Directory root;
  final http.Client _client;
  final _inFlight = <String, Future<File?>>{};

  Directory get _dir => Directory('${root.path}/photos');

  File fileFor(String url) => File('${_dir.path}/${_fnv1a64(url)}');

  /// The stored photo, if it is already on the phone.
  File? cached(String url) {
    final f = fileFor(url);
    return f.existsSync() ? f : null;
  }

  /// Returns the stored photo, downloading it first if [allowDownload].
  Future<File?> get(String url, {required bool allowDownload}) {
    final have = cached(url);
    if (have != null) return Future.value(have);
    if (!allowDownload) return Future.value(null);
    return _inFlight.putIfAbsent(url, () async {
      try {
        return await _download(url);
      } finally {
        _inFlight.remove(url);
      }
    });
  }

  /// Downloads the photos of one edition (lead + top of each section).
  Future<void> prefetch(Edition edition) async {
    for (final st in edition.allStories) {
      final img = st.image;
      if (img != null) await get(img.url, allowDownload: true);
    }
  }

  /// Deletes photos older than [keepDays] (null = keep forever), except
  /// [pinned] ones (photos of saved stories).
  Future<int> prune(int? keepDays, Set<String> pinned) async {
    if (keepDays == null || !await _dir.exists()) return 0;
    final keep = {for (final u in pinned) fileFor(u).path};
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    var removed = 0;
    await for (final f in _dir.list()) {
      if (f is! File || keep.contains(f.path)) continue;
      if ((await f.lastModified()).isBefore(cutoff)) {
        await f.delete();
        removed++;
      }
    }
    return removed;
  }

  Future<int> sizeOnDisk() async {
    if (!await _dir.exists()) return 0;
    var total = 0;
    await for (final f in _dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<File?> _download(String url) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 30));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/')) return null;
      await _dir.create(recursive: true);
      final f = fileFor(url);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(f.path);
      return f;
    } catch (_) {
      return null; // No photo is fine; the story still shows.
    }
  }

  /// Stable 64-bit FNV-1a hash of the link, as hex (Dart's hashCode can
  /// change between app versions).
  static String _fnv1a64(String s) {
    // Dart ints are 64-bit and wrap on overflow, which is what FNV needs.
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash *= prime;
    }
    String hex32(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return hex32(hash >> 32) + hex32(hash);
  }
}
