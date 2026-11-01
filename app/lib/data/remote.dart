import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the scheduled news task publishes editions.
const dataBaseUrl =
    'https://raw.githubusercontent.com/tirthgujarati/news/main/data/';

/// Some photo and data servers refuse requests that don't say who they are.
const userAgent = 'apex-news/1.0 (Android; personal news reader)';

const _timeout = Duration(seconds: 20);

class RemoteIndexEntry {
  final String editionId;
  final String path;
  const RemoteIndexEntry({required this.editionId, required this.path});
}

/// Reads the public data files from GitHub. No login or keys are needed.
class Remote {
  Remote([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  /// Editions still in the repo (last 7 days), newest first.
  Future<List<RemoteIndexEntry>> fetchIndex() async {
    // A changing query string skips GitHub's few-minute cache.
    final bust = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final body = await _get('${dataBaseUrl}index.json?t=$bust');
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['editions'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteIndexEntry(
        editionId: m['edition_id'] as String,
        path: m['path'] as String,
      );
    }).toList();
  }

  /// The edition's JSON text. [path] is relative to data/.
  Future<String> fetchEdition(String path) => _get('$dataBaseUrl$path');

  Future<String> _get(String url) async {
    final res = await _client
        .get(Uri.parse(url), headers: {'User-Agent': userAgent})
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
    }
    return utf8.decode(res.bodyBytes);
  }

  void close() => _client.close();
}
