/// Flash events, the squawk tape and the API spend, kept in one file on the
/// phone (flash.json). Only the background Flash engine writes it; the app's
/// screens read it.
library;

import 'dart:convert';
import 'dart:io';

import 'flash.dart';
import 'judge.dart' show Spend;

/// One line of the tape: every squawk headline, scored.
class TapeItem {
  final Headline headline;
  final int score;
  final String topic;

  /// The event it became part of, if any.
  final String? eventId;

  const TapeItem(this.headline, this.score, this.topic, this.eventId);

  Map<String, dynamic> toJson() =>
      {...headline.toJson(), 'score': score, 'topic': topic, if (eventId != null) 'event': eventId};

  factory TapeItem.fromJson(Map<String, dynamic> j) =>
      TapeItem(Headline.fromJson(j), j['score'] as int, j['topic'] as String, j['event'] as String?);
}

class FlashStore {
  FlashStore(Directory root) : file = File('${root.path}/flash.json');

  final File file;

  /// Newest first.
  List<FlashEvent> events = [];

  /// Newest first.
  List<TapeItem> tape = [];
  Spend? spend;

  /// Flash desk runs today: ("2026-11-03", 2).
  String deskDay = '';
  int deskCount = 0;

  static const keepDays = 3, keepTape = 300, keepEvents = 150;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      events = [
        for (final e in (j['events'] as List? ?? const [])) FlashEvent.fromJson(e as Map<String, dynamic>)
      ];
      tape = [for (final t in (j['tape'] as List? ?? const [])) TapeItem.fromJson(t as Map<String, dynamic>)];
      spend = j['spend'] == null ? null : Spend.fromJson(j['spend'] as Map<String, dynamic>);
      deskDay = j['desk_day'] as String? ?? '';
      deskCount = j['desk_count'] as int? ?? 0;
    } catch (_) {
      // A damaged file starts over rather than stopping Flash.
      events = [];
      tape = [];
    }
  }

  Future<void> save(DateTime now) async {
    final cutoff = now.subtract(const Duration(days: keepDays));
    events.removeWhere((e) => e.at.isBefore(cutoff));
    if (events.length > keepEvents) events = events.sublist(0, keepEvents);
    if (tape.length > keepTape) tape = tape.sublist(0, keepTape);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'events': [for (final e in events) e.toJson()],
      'tape': [for (final t in tape) t.toJson()],
      if (spend != null) 'spend': spend!.toJson(),
      'desk_day': deskDay,
      'desk_count': deskCount,
    }));
    // Replace in one step so a reader never sees half a file.
    await tmp.rename(file.path);
  }

  FlashEvent? byId(String id) => events.where((e) => e.id == id).firstOrNull;
}
