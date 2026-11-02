import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/data/sync.dart';
import 'package:newsapp/models/edition.dart';

String fixture() => File('test/fixtures/edition.json').readAsStringSync();

void main() {
  test('parses the real edition', () {
    final e = parseEdition(fixture());
    expect(e.editionId, '2026-11-02-morning');
    expect(e.slot, 'morning');
    expect(e.sections.map((s) => s.id), sectionOrder);
    expect(e.storyCount, 12);
    expect(e.snapshot, isNotEmpty);
    expect(e.weekendSpecial, isNull);
    expect(e.weekAhead.first.events, isNotEmpty);
  });

  test('finds exactly one lead story, with its photo', () {
    final e = parseEdition(fixture());
    final lead = e.leadStory!;
    expect(lead.sectionId, 'world');
    expect(lead.image, isNotNull);
    expect(lead.image!.credit, isNotEmpty);
    expect(e.allStories.where((s) => s.lead), hasLength(1));
  });

  test('marks single-source stories and date-only times', () {
    final e = parseEdition(fixture());
    final cyclone = e.section('india')!.stories.first;
    expect(cyclone.singleSource, isTrue);
    expect(cyclone.publishedDateOnly, isFalse);
    final gst = e.section('india')!.stories[1];
    expect(gst.singleSource, isFalse);
    expect(gst.publishedDateOnly, isTrue);
  });

  test('reads impact tags, biggest first, and tolerates older editions', () {
    final e = parseEdition(fixture());
    final wallSt = e.section('markets')!.stories.first;
    expect(wallSt.impact.map((t) => t.level), ['high', 'medium']);
    expect(wallSt.impact.last.label, 'IT stocks');
    expect(wallSt.impact.first.arrow, '▼');
    expect(e.leadStory!.impact.first.on, 'oil');

    // Editions written before impact tags existed have no "impact" key.
    final old = jsonDecode(fixture()) as Map<String, dynamic>;
    for (final s in old['sections'] as List) {
      for (final st in (s as Map)['stories'] as List) {
        (st as Map).remove('impact');
      }
    }
    expect(Edition.fromJson(old).allStories.every((s) => s.impact.isEmpty), isTrue);
  });

  test('keeps the raw story JSON for Saved', () {
    final e = parseEdition(fixture());
    final st = e.allStories.first;
    expect(st.raw['id'], st.id);
    expect(Story.fromJson(st.raw).headline, st.headline);
  });

  test('rejects an unknown schema version', () {
    final j = jsonDecode(fixture()) as Map<String, dynamic>;
    j['schema_version'] = 2;
    expect(() => Edition.fromJson(j), throwsFormatException);
  });

  test('rejects an edition with the wrong shape', () {
    final j = jsonDecode(fixture()) as Map<String, dynamic>;
    j['sections'] = 'oops';
    expect(() => Edition.fromJson(j), throwsFormatException);
  });
}
