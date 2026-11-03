/// The Flash engine: every squawk headline goes through
///   rules (instant) -> alert (loud when HOT by the rules)
///   -> Opus flash desk on the plan (strong events, ~3 min) -> market check.
/// It runs in the background (started by the Telegram listener or the watch
/// service), so it works with the app closed.
library;

import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/edition.dart' show ImpactTag;
import 'desk.dart';
import 'flash.dart';
import 'prices.dart';
import 'rules.dart';
import 'store.dart';

/// Flash settings (written by the Settings screen, read on every event).
class FlashConfig {
  final bool enabled;

  /// Telegram channel names to listen to (matched case-insensitively).
  final List<String> channels;
  final bool deskAuto;
  final int deskDaily;

  /// Also read the channels' public pages and watch prices (backup).
  final bool watchMode;

  /// Clear Telegram's own notifications for these channels (apex alerts
  /// instead).
  final bool hideTelegram;

  const FlashConfig({
    this.enabled = true,
    this.channels = defaultChannels,
    this.deskAuto = true,
    this.deskDaily = deskDailyLimit,
    this.watchMode = false,
    this.hideTelegram = false,
  });

  static const defaultChannels = ['marketfeed', 'FinancialJuice'];

  static const kEnabled = 'flash_enabled',
      kChannels = 'flash_channels',
      kDeskAuto = 'flash_desk_auto',
      kWatch = 'flash_watch_mode',
      kHide = 'flash_hide_telegram';

  static Future<FlashConfig> read() async {
    final p = await SharedPreferences.getInstance();
    // Another part of the app may have changed them.
    await p.reload();
    return FlashConfig(
      enabled: p.getBool(kEnabled) ?? true,
      channels: p.getStringList(kChannels) ?? defaultChannels,
      deskAuto: p.getBool(kDeskAuto) ?? true,
      watchMode: p.getBool(kWatch) ?? false,
      hideTelegram: p.getBool(kHide) ?? false,
    );
  }

  /// True when a Telegram notification title belongs to one of the channels.
  bool matches(String title) {
    final t = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return channels.any((c) {
      final n = c.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return n.isNotEmpty && t.contains(n);
    });
  }
}

/// A phone notification about an event.
class FlashAlert {
  final int id;

  /// Sound and vibration (HOT) or silent (WATCH).
  final bool loud;
  final String title;
  final String text;
  final String eventId;

  const FlashAlert({
    required this.id,
    required this.loud,
    required this.title,
    required this.text,
    required this.eventId,
  });
}

/// What the engine needs from Android.
abstract class FlashPlatform {
  /// "github_token"; null when not set.
  Future<String?> secret(String name);
  Future<void> alert(FlashAlert a);
  Future<void> cancelAlert(int id);

  /// Clears a Telegram notification apex has taken over.
  Future<void> dismissSource(String key);

  /// Tells the open app that flash.json changed.
  void changed();
}

int alertId(String eventId) => eventId.hashCode & 0x7fffffff;

String chipLine(FlashEvent e) => [for (final c in e.chips.take(4)) '${c.label} ${c.arrow}'].join(' · ');

class FlashEngine {
  FlashEngine({
    required this.store,
    required this.platform,
    required this.config,
    this.deskFor,
    Prices? prices,
    DateTime Function()? clock,
    this.gather = const Duration(seconds: 8),
    this.deskPoll = const Duration(seconds: 20),
    this.deskTimeout = const Duration(minutes: 12),
    this.checkAfter = const [2, 5, 10],
  })  : prices = prices ?? Prices(),
        _clock = clock ?? DateTime.now;

  final FlashStore store;
  final FlashPlatform platform;

  /// Reads the settings (fresh for each event).
  final Future<FlashConfig> Function() config;

  final FlashDesk Function(String token)? deskFor;
  final Prices prices;
  final DateTime Function() _clock;

  /// How long to collect a burst before sending it to the desk.
  final Duration gather;
  final Duration deskPoll;
  final Duration deskTimeout;

  /// Minutes after the news to check the market.
  final List<int> checkAfter;

  final _rand = Random();
  final _deskQueued = <String>{};
  final _loud = <String>{};
  Future<void> _queue = Future.value();

  DateTime get now => _clock();

  Future<void> start() => store.load();

  /// Runs [f] after everything queued before it: headlines are handled one
  /// at a time, in order, so the file is never written twice at once.
  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _queue.then((_) => f());
    _queue = r.then((_) {}, onError: (_) {});
    return r;
  }

  /// A Telegram notification arrived. [title] is the channel name.
  Future<void> onTelegram({required String title, required String text, required DateTime at, String? key}) async {
    final cfg = await config();
    if (!cfg.enabled || !cfg.matches(title)) return;
    if (cfg.hideTelegram && key != null) unawaited(platform.dismissSource(key));
    await ingest(Headline(text: text.trim(), channel: _channelName(title, cfg), at: at));
  }

  String _channelName(String title, FlashConfig cfg) =>
      cfg.channels.firstWhere((c) => FlashConfig(channels: [c]).matches(title), orElse: () => title);

  /// One headline in. Returns the event it joined or started, if any.
  Future<FlashEvent?> ingest(Headline h) => _serial(() => _ingest(h));

  Future<FlashEvent?> _ingest(Headline h) async {
    if (h.text.isEmpty) return null;
    final t = now;
    // The channels echo each other: skip a repeat from the last 15 minutes.
    final recent = store.tape.takeWhile((x) => t.difference(x.headline.at).inMinutes < 15);
    if (recent.any((x) => sameNews(x.headline.text, h.text))) return null;

    final read = readHeadline(h.text);
    FlashEvent? event;
    if (read.candidate) {
      event = _openEventFor(read, t);
      if (event != null) {
        event.headlines.add(h);
        if (read.score > event.score) {
          event.score = read.score;
          if (event.ruleChips.isEmpty) event.ruleChips = read.chips;
          // The story got bigger: it may now be HOT or worth the desk.
          if (event.desk == null && event.worthDesk) {
            await _alert(event);
            _scheduleDesk(event);
          }
        }
      } else {
        event = FlashEvent(
          id: _newId(h.at),
          headlines: [h],
          topic: read.topic,
          score: read.score,
          ruleChips: read.chips,
        );
        store.events.insert(0, event);
        // Strong: alert now (loud when HOT), and Opus checks it. Weaker
        // headlines only show in the app.
        if (event.worthDesk) {
          await _alert(event);
          _scheduleDesk(event);
          if (event.chips.isNotEmpty) _scheduleMarketChecks(event);
        }
      }
    }
    store.tape.insert(0, TapeItem(h, read.score, read.topic, event?.id));
    await _save();
    return event;
  }

  /// A recent unfinished event about the same thing.
  FlashEvent? _openEventFor(RuleRead r, DateTime t) {
    for (final e in store.events) {
      if (t.difference(e.at).inMinutes >= 3) break;
      final sameSubject = r.subject != null &&
          e.headlines.any((h) => readHeadline(h.text).subject == r.subject);
      if (sameSubject || (r.subject == null && e.topic == r.topic)) return e;
    }
    return null;
  }

  String _newId(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    final u = at.toUtc();
    return 'ev-${u.year}${two(u.month)}${two(u.day)}-${two(u.hour)}${two(u.minute)}${two(u.second)}'
        '-${_rand.nextInt(1 << 16).toRadixString(16)}';
  }

  /// Sends the event to the desk once the burst has had time to gather.
  void _scheduleDesk(FlashEvent e) {
    if (!_deskQueued.add(e.id)) return;
    Timer(gather, () => _serial(() => _askDesk(e)));
  }

  Future<void> _alert(FlashEvent e) async {
    final id = alertId(e.id);
    final v = e.verdict;
    if (v == Verdict.noise) {
      await platform.cancelAlert(id);
      return;
    }
    // Loud once per event (when it first becomes HOT); later updates are silent.
    final loud = v == Verdict.hot && _loud.add(e.id);
    final chips = chipLine(e);
    final why = e.desk?.why;
    final by = e.desk != null
        ? 'Opus checked${e.desk!.confirmed ? ' ✓ confirmed' : ' (not confirmed)'}'
        : e.deskChecking
            ? 'Rules · Opus checking (~3 min)'
            : (e.deskError == null ? 'Rules' : 'Rules (${e.deskError})');
    await platform.alert(FlashAlert(
      id: id,
      loud: loud,
      title: '${v.label} · ${e.title}',
      text: [if (chips.isNotEmpty) chips, if (why != null && why.isNotEmpty) why, '$by · ${e.headlines.first.channel}']
          .join('\n'),
      eventId: e.id,
    ));
  }

  Future<void> _askDesk(FlashEvent e) async {
    final cfg = await config();
    if (!cfg.deskAuto || deskFor == null || e.issue != null) return;
    final token = await platform.secret('github_token');
    String? skip;
    if (token == null || token.isEmpty) {
      skip = 'No GitHub token';
    } else {
      final today = deskDayOf(now);
      if (store.deskDay != today) {
        store.deskDay = today;
        store.deskCount = 0;
      }
      // A story that keeps running (a press conference, a war) goes to the
      // desk once in 20 minutes, unless something HOT comes up.
      final subject = readHeadline(e.headlines.first.text).subject;
      final checked = store.events.any((x) =>
          x != e &&
          x.issue != null &&
          x.topic == e.topic &&
          now.difference(x.at).inMinutes < 20 &&
          readHeadline(x.headlines.first.text).subject == subject);
      if (checked && e.score < hotScore) {
        skip = 'Opus checked this story already';
      } else if (store.deskCount >= cfg.deskDaily) {
        skip = 'Daily Opus limit (${cfg.deskDaily}) reached';
      }
    }
    if (skip != null) {
      e.deskError = skip;
      await _alert(e);
      await _save();
      return;
    }
    final desk = deskFor!(token!);
    try {
      e.issue = await desk.open(e);
      store.deskCount++;
      await _alert(e);
      await _save();
      _pollDesk(e, token, now.add(deskTimeout));
    } on Exception catch (err) {
      e.deskError = 'Flash desk: $err';
      await _alert(e);
      await _save();
    } finally {
      desk.dispose();
    }
  }

  void _pollDesk(FlashEvent e, String token, DateTime giveUp) {
    Timer(deskPoll, () => _serial(() async {
          if (e.desk != null || e.issue == null) return;
          final desk = deskFor!(token);
          try {
            final r = await desk.result(e.issue!);
            if (r != null) {
              e.desk = r;
              await _alert(e);
              await _save();
              await desk.close(e.issue!).catchError((_) {});
              if (e.chips.isNotEmpty) _scheduleMarketChecks(e);
              return;
            }
          } catch (_) {
            // Try again on the next round.
          } finally {
            desk.dispose();
          }
          if (now.isBefore(giveUp)) {
            _pollDesk(e, token, giveUp);
          } else {
            e.deskError = "Opus didn't answer in ${deskTimeout.inMinutes} min";
            await _alert(e);
            await _save();
          }
        }));
  }

  final _checking = <String>{};

  void _scheduleMarketChecks(FlashEvent e) {
    if (!_checking.add(e.id)) return;
    for (final m in checkAfter) {
      final due = e.at.add(Duration(minutes: m));
      final wait = due.difference(now);
      if (wait.isNegative && now.difference(due).inMinutes > 2) continue;
      Timer(wait.isNegative ? Duration.zero : wait, () => _serial(() => _checkMarket(e, m)));
    }
  }

  Future<void> _checkMarket(FlashEvent e, int after) async {
    try {
      final bars = await prices.all();
      e.moves
        ..removeWhere((m) => m.after == after)
        ..addAll(movesSince(e.at, after, bars, e.chips));
      await _save();
    } catch (_) {}
  }

  /// Watch mode: a sudden price move with or without a headline becomes a
  /// silent "move" event, linked to the latest news (no Claude call).
  Future<void> checkSpikes(Map<String, Bars> bars) => _serial(() async {
        for (final m in markets) {
          final b = bars[m.name];
          final ch = b?.changeOver(const Duration(minutes: 5));
          if (ch == null || ch.abs() < m.spike) continue;
          final already = store.events.any((e) =>
              e.topic == 'move' &&
              e.headlines.first.text.startsWith(m.name) &&
              now.difference(e.at).inMinutes < 15);
          if (already) continue;
          final up = ch > 0;
          final chip = switch (m.name) {
            'Nifty' => const ImpactTag(on: 'indian_stocks', detail: null, level: 'medium', dir: 'up', why: ''),
            'USD/INR' => const ImpactTag(on: 'rupee', detail: null, level: 'medium', dir: 'down', why: ''),
            'EUR/USD' => const ImpactTag(on: 'currency', detail: 'USD', level: 'medium', dir: 'down', why: ''),
            'Bitcoin' => const ImpactTag(on: 'crypto', detail: null, level: 'medium', dir: 'up', why: ''),
            'Gold' => const ImpactTag(on: 'gold', detail: null, level: 'medium', dir: 'up', why: ''),
            _ => const ImpactTag(on: 'oil', detail: null, level: 'medium', dir: 'up', why: ''),
          };
          // The chip templates above describe a rise; flip them for a fall.
          final dir = up == (chip.dir == 'up') ? 'up' : 'down';
          final e = FlashEvent(
            id: _newId(now),
            headlines: [
              Headline(
                  text: '${m.name} ${up ? '+' : ''}${ch.toStringAsFixed(2)}% in 5 min'
                      '${m.delayed ? ' (price ~10 min delayed)' : ''}',
                  channel: 'prices',
                  at: now)
            ],
            topic: 'move',
            score: candidateScore + 2,
            ruleChips: [ImpactTag(on: chip.on, detail: chip.detail, level: chip.level, dir: dir, why: 'Price move.')],
          );
          store.events.insert(0, e);
          await _alert(e);
        }
        await _save();
      });

  Future<void> _save() async {
    await store.save(now);
    platform.changed();
  }
}
