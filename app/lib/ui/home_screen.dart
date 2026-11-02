import 'package:flutter/material.dart';

import '../models/edition.dart';
import '../theme/look.dart';
import 'format.dart';
import 'search_screen.dart';
import 'story_sheet.dart';
import 'weekend_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _section = sectionOrder.first;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final look = Look.of(context);
    final edition = app.edition;

    if (edition == null) {
      return Center(
        child: app.refreshing
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('No edition yet', style: look.headline(20)),
                  const SizedBox(height: 8),
                  Text(
                    app.offline
                        ? 'Connect to the internet to download the first edition.'
                        : 'Pull down or tap below to check for news.',
                    style: look.body(14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: app.refresh, child: const Text('Check now')),
                ]),
              ),
      );
    }

    final section = edition.section(_section) ?? edition.sections.first;
    final lead = edition.leadStory;

    return RefreshIndicator(
      onRefresh: app.refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(edition: edition)),
          SliverToBoxAdapter(child: Ticker(items: edition.snapshot, editionDate: edition.date)),
          if (app.viewingArchive)
            SliverToBoxAdapter(child: _ArchiveBanner(edition: edition)),
          if (app.offline && !app.viewingArchive)
            SliverToBoxAdapter(
              child: _Notice(
                icon: Icons.cloud_off,
                text: 'Offline, showing ${editionStamp(edition)}',
              ),
            ),
          if (edition.weekendSpecial != null)
            SliverToBoxAdapter(child: _WeekendBanner(edition: edition)),
          if (lead != null)
            SliverToBoxAdapter(
              child: LeadStory(
                story: lead,
                edition: edition,
                onTap: () => showStory(context, lead, edition),
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              look: look,
              child: SectionTabs(
                sections: edition.sections,
                selected: section.id,
                onSelect: (id) => setState(() => _section = id),
              ),
            ),
          ),
          if (section.stories.isEmpty)
            const SliverToBoxAdapter(child: EmptySection())
          else
            SliverList.builder(
              itemCount: section.stories.length,
              itemBuilder: (context, i) {
                final st = section.stories[i];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: StoryTile(
                    key: ValueKey('${edition.editionId}/${st.id}'),
                    story: st,
                    editionDate: edition.date,
                    showPhoto: i == 0 && !st.lead,
                    onTap: () => showStory(context, st, edition),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.edition});
  final Edition edition;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    final brand = Text.rich(
      TextSpan(children: [
        TextSpan(text: 'apex'),
        if (look.brandAccent != null)
          TextSpan(text: '.', style: TextStyle(color: look.brandAccent)),
      ]),
      style: look.headline(look.style.name == 'bold' ? 38 : 26, height: 1),
    );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 6, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          brand,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(edition.title,
                  style: look.body(12, color: look.ink, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              Text(
                app.refreshing
                    ? 'Checking…'
                    : 'Updated ${clock(edition.generatedAt)} · ${ago(edition.generatedAt)}',
                style: look.body(11.5),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Row(children: [
        Icon(icon, size: 16, color: look.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: look.body(12.5))),
      ]),
    );
  }
}

class _ArchiveBanner extends StatelessWidget {
  const _ArchiveBanner({required this.edition});
  final Edition edition;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: look.surface,
        border: Border.all(color: look.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.history, size: 18, color: look.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text('From the archive: ${editionStamp(edition)}',
              style: look.body(12.5, color: look.ink)),
        ),
        TextButton(onPressed: context.app.backToLatest, child: const Text('Latest')),
      ]),
    );
  }
}

class _WeekendBanner extends StatelessWidget {
  const _WeekendBanner({required this.edition});
  final Edition edition;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final ws = edition.weekendSpecial!;
    final accent = look.section('built');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Material(
        color: accent.withValues(alpha: look.dark ? 0.18 : 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => WeekendScreen(edition: edition),
          )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.auto_awesome, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('WEEKEND SPECIAL', style: look.label(10.5, color: accent)),
                  const SizedBox(height: 3),
                  Text(ws.title, style: look.headline(16)),
                  Text('The ${ws.stories.length} biggest stories of the week, ranked',
                      style: look.body(12.5)),
                ]),
              ),
              Icon(Icons.chevron_right, color: look.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.look, required this.child});
  final Look look;
  final Widget child;

  double get _h => look.tabShape == TabShape.pill ? 52 : 46;

  @override
  double get minExtent => _h + 1;
  @override
  double get maxExtent => _h + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        decoration: BoxDecoration(
          color: look.bg,
          border: Border(bottom: BorderSide(color: look.line)),
        ),
        child: child,
      );

  @override
  bool shouldRebuild(covariant _TabsHeader old) => true;
}
