import 'package:flutter/material.dart';

import '../data/nifty100.dart';
import '../theme/look.dart';
import 'widgets.dart';

/// Settings -> Watchlist: star Nifty 100 companies. The list stays on the
/// phone; starred companies get a star wherever they're named, and Home gets
/// a Watchlist tab.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, this.companies});

  /// For tests; the bundled Nifty 100 list otherwise.
  final List<ListedCompany>? companies;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late final Future<List<ListedCompany>> _list =
      widget.companies != null ? Future.value(widget.companies) : loadNifty100();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('Watchlist')),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final q = _query.trim().toLowerCase();
          final shown = [
            for (final c in all)
              if (q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  c.symbol.toLowerCase().contains(q) ||
                  c.sector.toLowerCase().contains(q))
                c
          ]..sort((a, b) {
              final byStar = (app.watches(b.symbol) ? 1 : 0) - (app.watches(a.symbol) ? 1 : 0);
              return byStar != 0 ? byStar : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Text(
                app.watchlist.isEmpty
                    ? 'Star the companies you follow. They get a star wherever the news names them, '
                        'and Home gets a Watchlist tab. Stays on this phone.'
                    : '${app.watchlist.length} starred · stays on this phone',
                style: look.body(13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search Nifty 100: name, symbol or sector',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final c = shown[i];
                  final on = app.watches(c.symbol);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                    title: Text(c.name, style: look.body(15, color: look.ink)),
                    subtitle: Text('${c.symbol} · ${c.sector}', style: look.body(12.5)),
                    trailing: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: on ? watchStar : look.muted),
                    onTap: () => app.setWatched(c.symbol, !on),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
