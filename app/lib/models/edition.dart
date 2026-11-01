/// Data model for one news edition, matching schema/edition.schema.json.
library;

const supportedSchemaVersion = 1;

const sectionOrder = ['india', 'world', 'currency', 'markets', 'built'];

class Source {
  final String name;
  final String url;
  const Source({required this.name, required this.url});

  factory Source.fromJson(Map<String, dynamic> j) =>
      Source(name: j['name'] as String, url: j['url'] as String);
}

class StoryImage {
  final String url;
  final String credit;
  final String sourceUrl;
  final String alt;
  const StoryImage({
    required this.url,
    required this.credit,
    required this.sourceUrl,
    required this.alt,
  });

  factory StoryImage.fromJson(Map<String, dynamic> j) => StoryImage(
        url: j['url'] as String,
        credit: j['credit'] as String,
        sourceUrl: j['source_url'] as String,
        alt: j['alt'] as String,
      );
}

class Story {
  final String id;
  final String headline;
  final String summary;
  final String? whyItMatters;
  final int importance;
  final bool lead;
  final bool verified;
  final String? note;
  final DateTime publishedAt;

  /// True when the source gave only a date (published_at ends in T00:00:00).
  final bool publishedDateOnly;
  final List<String> tags;
  final List<Source> sources;
  final StoryImage? image;

  /// Only set for Weekend Special stories (1 = biggest).
  final int? rank;

  /// The story exactly as it appeared in the edition file (kept for Saved).
  final Map<String, dynamic> raw;

  const Story({
    required this.id,
    required this.headline,
    required this.summary,
    required this.whyItMatters,
    required this.importance,
    required this.lead,
    required this.verified,
    required this.note,
    required this.publishedAt,
    required this.publishedDateOnly,
    required this.tags,
    required this.sources,
    required this.image,
    required this.raw,
    this.rank,
  });

  /// Section id is the first part of the story id, e.g. "markets-...".
  String get sectionId => id.split('-').first;

  bool get singleSource => !verified;

  factory Story.fromJson(Map<String, dynamic> j) {
    final published = j['published_at'] as String;
    return Story(
      id: j['id'] as String,
      headline: j['headline'] as String,
      summary: j['summary'] as String,
      whyItMatters: j['why_it_matters'] as String?,
      importance: j['importance'] as int,
      lead: j['lead'] as bool,
      verified: j['verified'] as bool,
      note: j['note'] as String?,
      publishedAt: DateTime.parse(published),
      publishedDateOnly: published.contains('T00:00:00'),
      tags: (j['tags'] as List).cast<String>(),
      sources: (j['sources'] as List)
          .map((s) => Source.fromJson(s as Map<String, dynamic>))
          .toList(),
      image: j['image'] == null
          ? null
          : StoryImage.fromJson(j['image'] as Map<String, dynamic>),
      rank: j['rank'] as int?,
      raw: j,
    );
  }
}

class Section {
  final String id;
  final String title;
  final List<Story> stories;
  const Section({required this.id, required this.title, required this.stories});

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        id: j['id'] as String,
        title: j['title'] as String,
        stories: (j['stories'] as List)
            .map((s) => Story.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class SnapshotItem {
  final String id;
  final String label;
  final String value;
  final String? change;

  /// "up", "down" or "flat".
  final String dir;
  final DateTime asOf;
  final Source source;

  const SnapshotItem({
    required this.id,
    required this.label,
    required this.value,
    required this.change,
    required this.dir,
    required this.asOf,
    required this.source,
  });

  factory SnapshotItem.fromJson(Map<String, dynamic> j) => SnapshotItem(
        id: j['id'] as String,
        label: j['label'] as String,
        value: j['value'] as String,
        change: j['change'] as String?,
        dir: j['dir'] as String,
        asOf: DateTime.parse(j['as_of'] as String),
        source: Source.fromJson(j['source'] as Map<String, dynamic>),
      );
}

class WeekEvent {
  final String text;
  final String section;
  const WeekEvent({required this.text, required this.section});
}

class WeekDay {
  final DateTime date;
  final List<WeekEvent> events;
  const WeekDay({required this.date, required this.events});

  factory WeekDay.fromJson(Map<String, dynamic> j) => WeekDay(
        date: DateTime.parse(j['date'] as String),
        events: (j['events'] as List)
            .map((e) => WeekEvent(
                  text: (e as Map<String, dynamic>)['text'] as String,
                  section: e['section'] as String,
                ))
            .toList(),
      );
}

class WeekendSpecial {
  final String title;
  final List<Story> stories;
  const WeekendSpecial({required this.title, required this.stories});
}

class Edition {
  final int schemaVersion;
  final String editionId;
  final String date;
  final String slot;
  final String title;
  final DateTime generatedAt;
  final List<SnapshotItem> snapshot;
  final List<Section> sections;
  final WeekendSpecial? weekendSpecial;
  final List<WeekDay> weekAhead;

  const Edition({
    required this.schemaVersion,
    required this.editionId,
    required this.date,
    required this.slot,
    required this.title,
    required this.generatedAt,
    required this.snapshot,
    required this.sections,
    required this.weekendSpecial,
    required this.weekAhead,
  });

  /// Throws [FormatException] for an unknown schema version or bad shape.
  factory Edition.fromJson(Map<String, dynamic> j) {
    final version = j['schema_version'];
    if (version != supportedSchemaVersion) {
      throw FormatException('Unsupported schema_version: $version');
    }
    try {
      final ws = j['weekend_special'] as Map<String, dynamic>?;
      return Edition(
        schemaVersion: version as int,
        editionId: j['edition_id'] as String,
        date: j['date'] as String,
        slot: j['slot'] as String,
        title: j['title'] as String,
        generatedAt: DateTime.parse(j['generated_at'] as String),
        snapshot: (j['snapshot'] as List)
            .map((s) => SnapshotItem.fromJson(s as Map<String, dynamic>))
            .toList(),
        sections: (j['sections'] as List)
            .map((s) => Section.fromJson(s as Map<String, dynamic>))
            .toList(),
        weekendSpecial: ws == null
            ? null
            : WeekendSpecial(
                title: ws['title'] as String,
                stories: (ws['stories'] as List)
                    .map((s) => Story.fromJson(s as Map<String, dynamic>))
                    .toList(),
              ),
        weekAhead: (j['week_ahead'] as List)
            .map((d) => WeekDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
    } on TypeError catch (e) {
      throw FormatException('Edition has the wrong shape: $e');
    }
  }

  Iterable<Story> get allStories => sections.expand((s) => s.stories);

  Story? get leadStory {
    for (final s in allStories) {
      if (s.lead) return s;
    }
    return null;
  }

  int get storyCount => allStories.length;

  Section? section(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }
}
