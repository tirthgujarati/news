import 'dart:convert';

import 'package:flutter/services.dart';

/// A company in the Nifty 100 (the companies "Most affected" lists can name).
class ListedCompany {
  const ListedCompany({required this.symbol, required this.name, required this.sector});
  final String symbol;
  final String name;
  final String sector;
}

List<ListedCompany> parseNifty100(String raw) => [
      for (final c in (jsonDecode(raw) as Map<String, dynamic>)['companies'] as List)
        ListedCompany(
          symbol: (c as Map<String, dynamic>)['symbol'] as String,
          name: c['name'] as String,
          sector: c['sector'] as String,
        )
    ];

/// The list bundled with the app (a copy of data/nifty100.json, refreshed
/// at build time).
Future<List<ListedCompany>> loadNifty100() async =>
    parseNifty100(await rootBundle.loadString('assets/nifty100.json'));
