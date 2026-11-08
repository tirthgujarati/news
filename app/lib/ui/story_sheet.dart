import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/edition.dart';
import '../theme/look.dart';
import 'format.dart';
import 'widgets.dart';

/// Opens the story detail as a bottom sheet.
Future<void> showStory(BuildContext context, Story story, Edition edition) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) =>
            StorySheet(story: story, edition: edition, scroll: scroll),
      ),
    );

class StorySheet extends StatelessWidget {
  const StorySheet({
    super.key,
    required this.story,
    required this.edition,
    required this.scroll,
  });

  final Story story;
  final Edition edition;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final saved = app.isSaved(story);
    final sec = look.section(story.sectionId);
    final img = story.image;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        // Save and Share sit at the top so they're reachable on long stories.
        Row(children: [
          Expanded(
            child: Text(sectionTitle(story.sectionId).toUpperCase(),
                style: look.label(11, color: sec)),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 18),
            label: Text(saved ? 'Saved' : 'Save'),
            onPressed: () async {
              final now = await app.toggleSaved(story, edition);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(now ? 'Saved' : 'Removed from Saved'),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Share',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () => SharePlus.instance.share(ShareParams(
              text: '${story.headline}\n${story.sources.first.url}',
            )),
          ),
        ]),
        const SizedBox(height: 6),
        SourceLabel(story: story, editionDate: edition.date),
        const SizedBox(height: 8),
        Text(story.headline, style: look.headline(24, height: 1.18)),
        if (img != null) ...[
          const SizedBox(height: 14),
          StoryPhoto(image: img, height: 210, radius: 12),
          const SizedBox(height: 4),
          PhotoCredit(img),
        ],
        const SizedBox(height: 14),
        Text(story.summary, style: look.body(15.5, color: look.ink, height: 1.5)),
        if (story.whyItMatters != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sec.withValues(alpha: look.dark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: sec, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('WHY IT MATTERS', style: look.label(10.5, color: sec)),
              const SizedBox(height: 5),
              Text(story.whyItMatters!,
                  style: look.body(14.5, color: look.ink, height: 1.45)),
            ]),
          ),
        ],
        if (story.impact.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImpactBox(impact: story.impact),
        ],
        if (story.mondayEffect != null)
          _Callout(label: 'MONDAY EFFECT', text: story.mondayEffect!, color: look.section('markets')),
        if (story.watchNext != null)
          _Callout(label: 'WHAT TO WATCH', text: story.watchNext!, color: look.muted),
        if (story.note != null) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: look.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(story.note!, style: look.body(13))),
          ]),
        ],
        const SizedBox(height: 18),
        Text('SOURCES', style: look.label(10.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in story.sources)
            ActionChip(
              avatar: Icon(Icons.open_in_new, size: 16, color: look.ink),
              label: Text(s.name, style: look.body(13, color: look.ink, weight: FontWeight.w600)),
              backgroundColor: look.surface,
              side: BorderSide(color: look.line),
              onPressed: () => openLink(s.url),
            ),
        ]),
      ],
    );
  }
}

/// A labelled note under the story (Monday effect, what to watch).
class _Callout extends StatelessWidget {
  const _Callout({required this.label, required this.text, required this.color});
  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: look.dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: look.label(10.5, color: color)),
        const SizedBox(height: 5),
        Text(text, style: look.body(14.5, color: look.ink, height: 1.45)),
      ]),
    );
  }
}
