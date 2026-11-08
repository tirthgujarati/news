import 'package:flutter/material.dart';

import '../models/edition.dart';
import '../theme/look.dart';
import 'story_sheet.dart';
import 'widgets.dart';

/// Weekend Special: the week's biggest stories, ranked 1 to 7.
class WeekendScreen extends StatelessWidget {
  const WeekendScreen({super.key, required this.edition});
  final Edition edition;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final ws = edition.weekendSpecial!;
    final stories = [...ws.stories]..sort((a, b) => (a.rank ?? 99).compareTo(b.rank ?? 99));
    return Scaffold(
      appBar: AppBar(title: Text(ws.title)),
      body: ListView.builder(
        itemCount: stories.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Text(
                  ws.monday
                      ? 'Friday afternoon to Sunday night, ranked by how much each could move markets '
                          'on Monday. Tap a story for its Monday effect and what to watch.'
                      : 'The biggest stories of the past 7 days, with why each one matters.',
                  style: look.body(13.5)),
            );
          }
          final st = stories[i - 1];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StoryTile(
              story: st,
              editionDate: edition.date,
              rank: st.rank,
              onTap: () => showStory(context, st, edition),
            ),
          ]);
        },
      ),
    );
  }
}
