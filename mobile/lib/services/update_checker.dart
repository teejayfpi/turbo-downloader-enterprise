import 'dart:convert';
import 'dart:io';

import '../credits.dart';

/// A published release the app can offer to the user.
class UpdateInfo {
  final String tag;
  final String version;
  final String notesUrl;
  final String? downloadUrl;
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.notesUrl,
    this.downloadUrl,
    this.publishedAt,
  });
}

/// Checks the project's GitHub releases for a newer version.
///
/// Read-only and anonymous: it fetches the public releases API. It never sends
/// anything about the user or the device.
class UpdateChecker {
  UpdateChecker({
    this.repo = 'teejayfpi/turbo-downloader-enterprise',
    HttpClient? client,
  }) : _client = client;

  final String repo;
  final HttpClient? _client;

  /// Returns the newest release when it is newer than [currentVersion],
  /// otherwise null. Network failures are swallowed so a check never blocks or
  /// breaks the app.
  Future<UpdateInfo?> check({String currentVersion = appVersion}) async {
    final client = _client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name']?.toString() ?? '';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (version.isEmpty || !isNewer(version, currentVersion)) return null;

      String? download;
      for (final asset in (json['assets'] as List?) ?? const []) {
        final name = (asset as Map)['name']?.toString() ?? '';
        if (name.endsWith('.exe') || name.endsWith('.apk') || name.endsWith('.zip')) {
          download = asset['browser_download_url']?.toString();
          break;
        }
      }
      return UpdateInfo(
        tag: tag,
        version: version,
        notesUrl: json['html_url']?.toString() ??
            'https://github.com/$repo/releases',
        downloadUrl: download,
        publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  /// True when [candidate] is a higher semantic version than [current].
  static bool isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String version) {
    final core = version.split('-').first.split('+').first;
    return core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}

/// The update channels a build can follow.
enum UpdateChannel {
  stable,
  beta,
  nightly;

  String get label => switch (this) {
        UpdateChannel.stable => 'Stable',
        UpdateChannel.beta => 'Beta',
        UpdateChannel.nightly => 'Nightly',
      };
}
