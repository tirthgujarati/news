import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/edition.dart';
import 'edition_store.dart';
import 'remote.dart';

class SyncResult {
  /// Edition ids that were downloaded and stored (new or replaced).
  final List<String> stored;

  /// Editions that were skipped because they failed to parse.
  final List<String> rejected;

  const SyncResult({required this.stored, required this.rejected});

  bool get changed => stored.isNotEmpty;
}

/// Parses edition JSON. Top-level so it can run in a background isolate.
Edition parseEdition(String raw) =>
    Edition.fromJson(jsonDecode(raw) as Map<String, dynamic>);

/// Downloads every edition the phone doesn't have yet (the repo keeps the
/// last 7 days) and stores it. The newest edition is always re-checked, since
/// a later run may replace an edition with the same id.
Future<SyncResult> syncEditions(Remote remote, EditionStore store) async {
  final index = await remote.fetchIndex();
  final stored = <String>[];
  final rejected = <String>[];

  // Oldest first, so the archive fills in order.
  for (final (i, entry) in index.reversed.indexed) {
    final isNewest = i == index.length - 1;
    if (store.has(entry.editionId) && !isNewest) continue;

    final raw = await remote.fetchEdition(entry.path);
    final Edition edition;
    try {
      edition = await compute(parseEdition, raw);
    } on FormatException catch (e) {
      // Never store a file that doesn't parse; keep showing what we have.
      debugPrint('Skipping ${entry.editionId}: $e');
      rejected.add(entry.editionId);
      continue;
    }

    final existing = store.entry(edition.editionId);
    if (existing != null && existing.generatedAt == edition.generatedAt) {
      continue; // Same edition we already have.
    }
    await store.save(raw, edition);
    stored.add(edition.editionId);
  }
  return SyncResult(stored: stored, rejected: rejected);
}
