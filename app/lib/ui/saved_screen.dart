import 'package:flutter/material.dart';

import '../models/edition.dart';
import '../theme/look.dart';
import 'archive_screen.dart';
import 'story_sheet.dart';
import 'widgets.dart';

/// Stories saved on the phone. They stay after the edition changes or is
/// deleted by the storage setting.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final saved = app.store.saved;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved'),
        actions: [
          // Archive lives here so the tab bar has room for Flash.
          TextButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('Archive'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (route) => ArchiveScreen(onOpened: () {
                Navigator.of(route).pop();
                app.tabRequest.value = 0;
              }),
            )),
          ),
        ],
      ),
      body: saved.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Tap Save on any story to keep it here.',
                    style: look.body(14), textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              itemCount: saved.length,
              itemBuilder: (context, i) {
                final s = saved[i];
                return StoryTile(
                  story: s.story,
                  editionDate: s.editionId.substring(0, 10),
                  showPhoto: s.story.image != null,
                  onTap: () async {
                    // Open in its edition if still stored, else on its own.
                    final ed = await app.loadEdition(s.editionId) ??
                        _standalone(s.editionId, s.editionTitle, s.story);
                    if (context.mounted) await showStory(context, s.story, ed);
                  },
                );
              },
            ),
    );
  }

  /// A minimal edition wrapper so the story sheet works after the edition
  /// itself has been deleted from the phone.
  Edition _standalone(String id, String title, Story story) => Edition(
        schemaVersion: supportedSchemaVersion,
        editionId: id,
        date: id.substring(0, 10),
        slot: id.substring(11),
        title: title,
        generatedAt: story.publishedAt,
        snapshot: const [],
        sections: [Section(id: story.sectionId, title: '', stories: [story])],
        weekendSpecial: null,
        weekAhead: const [],
      );
}
