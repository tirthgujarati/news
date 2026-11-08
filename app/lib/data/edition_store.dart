import 'dart:convert';
import 'dart:io';

import '../models/edition.dart';
import '../models/forex.dart';

/// One edition in the local archive list (kept small so the list loads fast).
class EditionEntry {
  final String editionId;
  final String title;
  final String date;
  final String slot;
  final DateTime generatedAt;
  final int storyCount;

  const EditionEntry({
    required this.editionId,
    required this.title,
    required this.date,
    required this.slot,
    required this.generatedAt,
    required this.storyCount,
  });

  factory EditionEntry.of(Edition e) => EditionEntry(
        editionId: e.editionId,
        title: e.title,
        date: e.date,
        slot: e.slot,
        generatedAt: e.generatedAt,
        storyCount: e.storyCount,
      );

  factory EditionEntry.fromJson(Map<String, dynamic> j) => EditionEntry(
        editionId: j['edition_id'] as String,
        title: j['title'] as String,
        date: j['date'] as String,
        slot: j['slot'] as String,
        generatedAt: DateTime.parse(j['generated_at'] as String),
        storyCount: j['story_count'] as int,
      );

  Map<String, dynamic> toJson() => {
        'edition_id': editionId,
        'title': title,
        'date': date,
        'slot': slot,
        'generated_at': generatedAt.toIso8601String(),
        'story_count': storyCount,
      };
}

/// A search result: enough to show a row and open the story.
class SearchHit {
  final String editionId;
  final String storyId;
  final String sectionId;
  final String headline;
  final String summary;
  final String sourceName;
  final DateTime publishedAt;

  const SearchHit({
    required this.editionId,
    required this.storyId,
    required this.sectionId,
    required this.headline,
    required this.summary,
    required this.sourceName,
    required this.publishedAt,
  });

  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
        editionId: j['e'] as String,
        storyId: j['s'] as String,
        sectionId: j['sec'] as String,
        headline: j['h'] as String,
        summary: j['m'] as String,
        sourceName: j['src'] as String,
        publishedAt: DateTime.parse(j['t'] as String),
      );

  Map<String, dynamic> toJson() => {
        'e': editionId,
        's': storyId,
        'sec': sectionId,
        'h': headline,
        'm': summary,
        'src': sourceName,
        't': publishedAt.toIso8601String(),
      };
}

/// A story the user saved. Kept with its full JSON so it survives the edition
/// being deleted by the storage setting.
class SavedStory {
  final Story story;
  final String editionId;
  final String editionTitle;
  final DateTime savedAt;

  const SavedStory({
    required this.story,
    required this.editionId,
    required this.editionTitle,
    required this.savedAt,
  });

  factory SavedStory.fromJson(Map<String, dynamic> j) => SavedStory(
        story: Story.fromJson(j['story'] as Map<String, dynamic>),
        editionId: j['edition_id'] as String,
        editionTitle: j['edition_title'] as String,
        savedAt: DateTime.parse(j['saved_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'story': story.raw,
        'edition_id': editionId,
        'edition_title': editionTitle,
        'saved_at': savedAt.toIso8601String(),
      };
}

/// Stores editions on the phone, in the app's documents folder (not the cache
/// folder, which Android may clear).
///
/// Layout under [root]:
///   `editions/<edition_id>.json`  the edition exactly as downloaded
///   editions_index.json          [EditionEntry] list, newest first
///   search_index.json            [SearchHit] list for every stored story
///   saved.json                   [SavedStory] list, newest first
class EditionStore {
  EditionStore(this.root);

  final Directory root;

  List<EditionEntry> _entries = [];
  List<SearchHit> _hits = [];
  Future<void>? _hitsLoading;
  bool _hitsLoaded = false;
  List<SavedStory> _saved = [];
  Map<String, ForexResult> _fxResults = {};

  Directory get _editionsDir => Directory('${root.path}/editions');
  File get _indexFile => File('${root.path}/editions_index.json');
  File get _searchFile => File('${root.path}/search_index.json');
  File get _savedFile => File('${root.path}/saved.json');
  File get _fxResultsFile => File('${root.path}/forex_results.json');
  File get _fxFeedFile => File('${root.path}/forex_feed.json');
  File _editionFile(String id) => File('${_editionsDir.path}/$id.json');

  /// Newest first.
  List<EditionEntry> get entries => List.unmodifiable(_entries);
  List<SavedStory> get saved => List.unmodifiable(_saved);

  Future<void> init() async {
    await _editionsDir.create(recursive: true);
    _entries = await _readList(_indexFile, EditionEntry.fromJson);
    _saved = await _readList(_savedFile, SavedStory.fromJson);
    _fxResults = {
      for (final r in await _readList(_fxResultsFile, ForexResult.fromJson)) r.key: r
    };
  }

  /// The search index can grow past 1 MB, so it is read after the first
  /// screen is up instead of at launch. Safe to call many times.
  Future<void> loadSearchIndex() => _hitsLoading ??= () async {
        _hits = await _readList(_searchFile, SearchHit.fromJson);
        _hitsLoaded = true;
      }();

  bool get searchReady => _hitsLoaded;

  bool has(String editionId) => _entries.any((e) => e.editionId == editionId);

  EditionEntry? entry(String editionId) {
    for (final e in _entries) {
      if (e.editionId == editionId) return e;
    }
    return null;
  }

  /// The edition's JSON text as stored, or null if missing.
  Future<String?> readRaw(String editionId) async {
    final f = _editionFile(editionId);
    return await f.exists() ? f.readAsString() : null;
  }

  /// Saves (or replaces) an edition. [raw] must be the text [edition] was
  /// parsed from, so a half-parsed or broken file is never stored.
  Future<void> save(String raw, Edition edition) async {
    await _writeAtomic(_editionFile(edition.editionId), raw);

    _entries.removeWhere((e) => e.editionId == edition.editionId);
    _entries.add(EditionEntry.of(edition));
    _sortEntries();
    await _writeList(_indexFile, _entries.map((e) => e.toJson()));

    await loadSearchIndex();
    _hits.removeWhere((h) => h.editionId == edition.editionId);
    for (final st in edition.allStories) {
      _hits.add(SearchHit(
        editionId: edition.editionId,
        storyId: st.id,
        sectionId: st.sectionId,
        headline: st.headline,
        summary: st.summary,
        sourceName: st.sources.first.name,
        publishedAt: st.publishedAt,
      ));
    }
    await _writeList(_searchFile, _hits.map((h) => h.toJson()));

    if (edition.forexResults.isNotEmpty) {
      for (final r in edition.forexResults) {
        _fxResults[r.key] = r;
      }
      // Results older than ~2 weeks are no longer on the calendar.
      final cutoff = DateTime.now().subtract(const Duration(days: 16));
      _fxResults.removeWhere((_, r) => r.date.isBefore(cutoff));
      await _writeList(_fxResultsFile, _fxResults.values.map((r) => r.toJson()));
    }
  }

  /// Actual results for Forex Factory events, by [ForexEvent.key].
  Map<String, ForexResult> get forexResults => Map.unmodifiable(_fxResults);

  /// The last Forex Factory feeds downloaded (JSON arrays), for offline use.
  Future<List<String>> readForexFeeds() async {
    if (!await _fxFeedFile.exists()) return const [];
    try {
      return (jsonDecode(await _fxFeedFile.readAsString()) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveForexFeeds(List<String> raws) =>
      _writeAtomic(_fxFeedFile, jsonEncode(raws));

  /// Deletes editions whose date is more than [keepDays] before [today].
  /// `null` keeps everything. The newest edition is always kept.
  Future<List<String>> prune(int? keepDays, DateTime today) async {
    if (keepDays == null || _entries.length <= 1) return const [];
    final cutoff = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: keepDays));
    final removed = <String>[];
    for (final e in _entries.skip(1).toList()) {
      if (DateTime.parse(e.date).isBefore(cutoff)) {
        removed.add(e.editionId);
        final f = _editionFile(e.editionId);
        if (await f.exists()) await f.delete();
      }
    }
    if (removed.isEmpty) return removed;
    _entries.removeWhere((e) => removed.contains(e.editionId));
    await loadSearchIndex();
    _hits.removeWhere((h) => removed.contains(h.editionId));
    await _writeList(_indexFile, _entries.map((e) => e.toJson()));
    await _writeList(_searchFile, _hits.map((h) => h.toJson()));
    return removed;
  }

  /// Case-insensitive search of headlines and summaries in every stored
  /// edition, newest first. The same story repeated in later editions shows
  /// once, from the newest edition.
  List<SearchHit> search(String query, {int limit = 100}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final order = {
      for (var i = 0; i < _entries.length; i++) _entries[i].editionId: i
    };
    final matches = _hits.where((h) {
      final text = '${h.headline} ${h.summary}'.toLowerCase();
      return words.every(text.contains);
    }).toList()
      ..sort((a, b) =>
          (order[a.editionId] ?? 1 << 30).compareTo(order[b.editionId] ?? 1 << 30));
    final seen = <String>{};
    return matches.where((h) => seen.add(h.storyId)).take(limit).toList();
  }

  bool isSaved(String storyId) => _saved.any((s) => s.story.id == storyId);

  /// Saves or un-saves a story. Returns true if it is now saved.
  Future<bool> toggleSaved(Story story, Edition edition) async {
    final wasSaved = isSaved(story.id);
    if (wasSaved) {
      _saved.removeWhere((s) => s.story.id == story.id);
    } else {
      _saved.insert(
        0,
        SavedStory(
          story: story,
          editionId: edition.editionId,
          editionTitle: edition.title,
          savedAt: DateTime.now(),
        ),
      );
    }
    await _writeList(_savedFile, _saved.map((s) => s.toJson()));
    return !wasSaved;
  }

  /// Photo links that must never be deleted (photos of saved stories).
  Set<String> get pinnedPhotoUrls => {
        for (final s in _saved)
          if (s.story.image != null) s.story.image!.url
      };

  /// Total bytes of stored edition files.
  Future<int> sizeOnDisk() async {
    var total = 0;
    if (!await _editionsDir.exists()) return 0;
    await for (final f in _editionsDir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  void _sortEntries() {
    const slotOrder = {'weekend': 0, 'morning': 1, 'midday': 2, 'evening': 3};
    _entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (slotOrder[b.slot] ?? 0).compareTo(slotOrder[a.slot] ?? 0);
    });
  }

  static Future<List<T>> _readList<T>(
      File f, T Function(Map<String, dynamic>) parse) async {
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => parse(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // A damaged index is rebuilt as editions are downloaded again.
      return [];
    }
  }

  static Future<void> _writeList(File f, Iterable<Map<String, dynamic>> items) =>
      _writeAtomic(f, jsonEncode(items.toList()));

  /// Writes to a temp file, then renames, so a crash never leaves a
  /// half-written file behind.
  static Future<void> _writeAtomic(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(f.path);
    } on FileSystemException {
      // Windows (tests) can't rename over an existing file.
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    }
  }
}
