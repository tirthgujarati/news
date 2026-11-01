import 'package:flutter/material.dart';

import '../data/edition_store.dart';
import '../theme/look.dart';
import 'format.dart';
import 'story_sheet.dart';
import 'widgets.dart';

/// Searches headlines and summaries in every edition stored on the phone.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final hits = app.store.search(_query);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: look.body(16, color: look.ink),
          decoration: InputDecoration(
            hintText: 'Search all stored editions',
            hintStyle: look.body(16),
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: _query.trim().isEmpty
          ? const SizedBox.shrink()
          : hits.isEmpty
              ? Center(child: Text('No stories match.', style: look.body(14)))
              : ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: look.line),
                  itemBuilder: (context, i) => _HitTile(hit: hits[i]),
                ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    return InkWell(
      onTap: () async {
        final ed = await app.loadEdition(hit.editionId);
        final story = ed?.allStories.where((s) => s.id == hit.storyId).firstOrNull;
        if (ed != null && story != null && context.mounted) {
          await showStory(context, story, ed);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: look.section(hit.sectionId), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${hit.sourceName.toUpperCase()} · ${dayLabel(hit.publishedAt.toLocal()).toUpperCase()}',
              style: look.label(10.5),
            ),
          ]),
          const SizedBox(height: 4),
          Text(hit.headline, style: look.headline(15.5, height: 1.25)),
          const SizedBox(height: 3),
          Text(firstSentence(hit.summary),
              style: look.body(12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
