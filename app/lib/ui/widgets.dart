import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../data/settings.dart';
import '../models/edition.dart';
import '../theme/look.dart';
import 'format.dart';
import 'scope.dart';

Future<void> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// "CNBC · OCT 31  [single source]" above every headline. Tapping the source
/// name opens the article.
class SourceLabel extends StatelessWidget {
  const SourceLabel({
    super.key,
    required this.story,
    required this.editionDate,
    this.color,
    this.dot = true,
  });

  final Story story;
  final String editionDate;
  final Color? color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final sec = look.section(story.sectionId);
    final textColor =
        color ?? (look.style == AppStyle.bold ? sec : look.muted);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        GestureDetector(
          onTap: () => openLink(story.sources.first.url),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: sec,
                  borderRadius: BorderRadius.circular(
                      look.style == AppStyle.night ? 2 : 4),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              '${story.sources.first.name.toUpperCase()} · ${storyTime(story, editionDate)}',
              style: look.label(10.5, color: textColor),
            ),
          ]),
        ),
        if (story.singleSource) const SingleSourceTag(),
      ],
    );
  }
}

class SingleSourceTag extends StatelessWidget {
  const SingleSourceTag({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: look.tagBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('SINGLE SOURCE', style: look.label(9, color: look.tagInk)),
    );
  }
}

/// A story photo from the phone's storage, downloading it when allowed.
/// Shows nothing (not a broken image) if the photo isn't available.
class StoryPhoto extends StatelessWidget {
  const StoryPhoto({
    super.key,
    required this.image,
    this.height,
    this.radius = 0,
    this.expand = false,
  });

  final StoryImage image;
  final double? height;
  final double radius;

  /// Fill the parent instead of using [height].
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cached = app.photos.cached(image.url);
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: expand
              ? child
              : SizedBox(height: height, width: double.infinity, child: child),
        );
    if (cached != null) return frame(_image(cached));
    return FutureBuilder<File?>(
      future: app.photos.get(image.url, allowDownload: app.photosAllowed),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) {
          if (snap.connectionState == ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return frame(ColoredBox(color: Look.of(context).line));
        }
        return frame(_image(f));
      },
    );
  }

  Widget _image(File f) => Image.file(
        f,
        fit: BoxFit.cover,
        semanticLabel: image.alt,
        gaplessPlayback: true,
        cacheWidth: 1080,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
}

class PhotoCredit extends StatelessWidget {
  const PhotoCredit(this.image, {super.key, this.color});
  final StoryImage image;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        'Photo: ${image.credit}',
        style: Look.of(context).body(10, color: color),
      );
}

/// The horizontally scrolling market ticker.
class Ticker extends StatelessWidget {
  const Ticker({super.key, required this.items});
  final List<SnapshotItem> items;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    String arrow(String dir) => dir == 'up' ? '▲ ' : dir == 'down' ? '▼ ' : '';
    // Grow with the text-size setting so tiles never clip.
    final k = MediaQuery.textScalerOf(context).scale(10) / 10;

    switch (look.tickerShape) {
      case TickerShape.tiles:
        return SizedBox(
          height: 16 + 60 * k,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final t = items[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: look.surface,
                  border: Border.all(color: look.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.label, style: look.body(10.5, height: 1.2)),
                    Text(t.value,
                        style: look.number(14,
                            weight: FontWeight.w700, color: look.ink)),
                    Text(t.change == null ? '—' : '${arrow(t.dir)}${t.change}',
                        style: look.body(10.5,
                            color: look.forDir(t.dir),
                            weight: FontWeight.w600,
                            height: 1.2)),
                  ],
                ),
              );
            },
          ),
        );
      case TickerShape.strip:
        return Container(
          height: 62 * k,
          decoration: BoxDecoration(
            color: look.tickerBg,
            border: Border.symmetric(horizontal: BorderSide(color: look.line)),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: look.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.label.toUpperCase(),
                        style: look.body(9.5, height: 1.2)
                            .copyWith(letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(t.value, style: look.number(13.5, color: look.tickerInk)),
                    Text(t.change == null ? '—' : '${arrow(t.dir)}${t.change}',
                        style: look.number(10.5, color: look.forDir(t.dir))),
                  ],
                ),
              );
            },
          ),
        );
      case TickerShape.inline:
        return Container(
          height: 38 * k,
          color: look.tickerBg,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final t = items[i];
              return Row(children: [
                Text(t.label,
                    style: look.body(12,
                        color: look.tickerInk.withValues(alpha: 0.65),
                        weight: FontWeight.w500)),
                const SizedBox(width: 6),
                Text(t.value,
                    style: look.number(13,
                        color: look.tickerInk, weight: FontWeight.w800)),
                if (t.change != null) ...[
                  const SizedBox(width: 5),
                  Text('${arrow(t.dir)}${t.change}',
                      style: look.body(11,
                          color: look.forDir(t.dir), weight: FontWeight.w600)),
                ],
              ]);
            },
          ),
        );
    }
  }
}

/// Section tabs: underline (Paper), pills (Night desk) or colour blocks (Bold).
class SectionTabs extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<Section> sections;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      color: look.bg,
      height: look.tabShape == TabShape.pill ? 52 : 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
            horizontal: look.tabShape == TabShape.block ? 0 : 14),
        children: [
          for (final s in sections) _tab(context, look, s),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, Look look, Section s) {
    final on = s.id == selected;
    final color = look.section(s.id);
    final title = look.uppercaseTabs ? s.title.toUpperCase() : s.title;
    return Semantics(
      selected: on,
      button: true,
      child: InkWell(
        onTap: () => onSelect(s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: look.tabShape == TabShape.pill
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 9)
              : EdgeInsets.zero,
          padding: EdgeInsets.symmetric(
              horizontal: look.tabShape == TabShape.underline ? 8 : 12),
          alignment: Alignment.center,
          decoration: switch (look.tabShape) {
            TabShape.underline => BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: on ? color : Colors.transparent, width: 3),
                ),
              ),
            TabShape.pill => BoxDecoration(
                color: on ? color : Colors.transparent,
                border: Border.all(color: on ? color : look.line),
                borderRadius: BorderRadius.circular(20),
              ),
            TabShape.block => BoxDecoration(color: on ? color : Colors.transparent),
          },
          child: Text(
            title,
            style: TextStyle(
              fontFamily: look.headlineFont,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
              letterSpacing: look.uppercaseTabs ? 0.5 : 0,
              color: switch (look.tabShape) {
                TabShape.underline => on ? look.ink : look.muted,
                TabShape.pill => on ? look.bg : look.muted,
                TabShape.block => on ? Colors.white : look.muted,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The edition's biggest story, drawn per style.
class LeadStory extends StatelessWidget {
  const LeadStory({super.key, required this.story, required this.edition, required this.onTap});
  final Story story;
  final Edition edition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final img = story.image;
    final why = story.whyItMatters ?? firstSentence(story.summary);

    switch (look.leadShape) {
      case LeadShape.card:
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Material(
            color: look.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: look.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (img != null) StoryPhoto(image: img, height: 200),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SourceLabel(story: story, editionDate: edition.date),
                    const SizedBox(height: 6),
                    Text(story.headline, style: look.headline(21, height: 1.18)),
                    const SizedBox(height: 7),
                    Text(why, style: look.body(13.5)),
                    if (img != null) ...[const SizedBox(height: 6), PhotoCredit(img)],
                  ]),
                ),
              ]),
            ),
          ),
        );
      case LeadShape.overlay:
        if (img == null) return _plain(context, look, why);
        const onPhoto = Color(0xFFE9EDF2);
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Material(
            // Dark base so the light text stays readable before (or without)
            // the photo, in light theme too.
            color: const Color(0xFF12151B),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 320,
                child: Stack(fit: StackFit.expand, children: [
                  StoryPhoto(image: img, expand: true),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.25, 0.85],
                        colors: [Color(0x00000000), Color(0xEB05070A)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SourceLabel(
                          story: story,
                          editionDate: edition.date,
                          color: const Color(0xFFC3CAD4)),
                      const SizedBox(height: 6),
                      Text(story.headline,
                          style: look.headline(22, color: onPhoto, height: 1.15)),
                      const SizedBox(height: 6),
                      Text(why,
                          style: look.body(12.5, color: const Color(0xFFC3CAD4))),
                      const SizedBox(height: 4),
                      PhotoCredit(img, color: const Color(0xFF9AA4B2)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      case LeadShape.fullBleed:
        return InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (img != null) StoryPhoto(image: img, height: 240),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: look.ink, width: 6)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LEAD · ${sectionTitle(story.sectionId).toUpperCase()}',
                    style: TextStyle(
                      fontFamily: look.headlineFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.3,
                      color: look.section(story.sectionId),
                    )),
                const SizedBox(height: 8),
                SourceLabel(story: story, editionDate: edition.date, dot: false),
                const SizedBox(height: 6),
                Text(story.headline, style: look.headline(26, height: 1.06)),
                const SizedBox(height: 8),
                Text(why, style: look.body(13.5, color: look.ink.withValues(alpha: 0.8))),
                if (img != null) ...[const SizedBox(height: 6), PhotoCredit(img)],
              ]),
            ),
          ]),
        );
    }
  }

  Widget _plain(BuildContext context, Look look, String why) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SourceLabel(story: story, editionDate: edition.date),
            const SizedBox(height: 6),
            Text(story.headline, style: look.headline(24, height: 1.15)),
            const SizedBox(height: 6),
            Text(why, style: look.body(13.5)),
          ]),
        ),
      );
}

/// One story row in a section list. The first row shows its photo.
class StoryTile extends StatelessWidget {
  const StoryTile({
    super.key,
    required this.story,
    required this.editionDate,
    required this.onTap,
    this.showPhoto = false,
    this.rank,
  });

  final Story story;
  final String editionDate;
  final VoidCallback onTap;
  final bool showPhoto;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final img = showPhoto ? story.image : null;
    final fullWidth = look.style == AppStyle.bold;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img != null && fullWidth) StoryPhoto(image: img, height: 180),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rank != null) ...[
                SizedBox(
                  width: 34,
                  child: Text('$rank',
                      style: look.headline(26,
                          color: look.section(story.sectionId), height: 1)),
                ),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (img != null && !fullWidth) ...[
                    StoryPhoto(image: img, height: 160, radius: 12),
                    const SizedBox(height: 10),
                  ],
                  SourceLabel(story: story, editionDate: editionDate, dot: !fullWidth),
                  const SizedBox(height: 5),
                  Text(story.headline, style: look.headline(16.5, height: 1.25)),
                  const SizedBox(height: 5),
                  Text(firstSentence(story.summary), style: look.body(13)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Shown when a section has no stories this edition.
class EmptySection extends StatelessWidget {
  const EmptySection({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Text('No real news in this section this edition.',
          style: look.body(14), textAlign: TextAlign.center),
    );
  }
}

/// Small helper for screens that only need the controller.
extension AppOf on BuildContext {
  AppController get app => AppScope.of(this);
}
