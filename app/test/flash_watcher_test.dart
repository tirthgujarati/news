import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newsapp/flash/watcher.dart';

void main() {
  test('reads posts from a public channel page', () {
    final posts = parseChannelPage(File('test/fixtures/tg_page.html').readAsStringSync());
    expect(posts.length, 3);
    expect(posts.first.id, lessThan(posts.last.id));
    for (final p in posts) {
      expect(p.text, isNot(contains('<')));
      expect(p.text, isNotEmpty);
      expect(p.at.isUtc || p.at.timeZoneOffset == Duration.zero, isTrue);
    }
  });

  test('channel page names', () {
    expect(pageName('FinancialJuice'), 'financialjuice');
    expect(pageName('marketfeed'), 'marketfeed');
  });
}
