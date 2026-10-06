import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../credits.dart';

/// A downloadable release asset, as published on GitHub.
@visibleForTesting
class ReleaseAsset {
  final String name;
  final String url;
  const ReleaseAsset(this.name, this.url);
}

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

      final assets = ((json['assets'] as List?) ?? const [])
          .whereType<Map>()
          .map((a) => ReleaseAsset(
                a['name']?.toString() ?? '',
                a['browser_download_url']?.toString() ?? '',
              ))
          .toList();
      return UpdateInfo(
        tag: tag,
        version: version,
        notesUrl: json['html_url']?.toString() ??
            'https://github.com/$repo/releases',
        downloadUrl: pickAsset(assets),
        publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  /// The release asset to offer on this platform, or null when the release
  /// carries nothing installable here. Pure, so it is easy to test.
  static String? pickAsset(List<ReleaseAsset> assets,
      {TargetPlatform? platform}) {
    final p = platform ?? defaultTargetPlatform;
    final preferred = switch (p) {
      TargetPlatform.android => const ['.apk'],
      TargetPlatform.windows => const ['.exe'],
      TargetPlatform.macOS => const ['.dmg', '.pkg', '.zip'],
      TargetPlatform.linux => const ['.appimage', '.deb', '.rpm', '.tar.gz'],
      _ => const <String>[],
    };
    for (final suffix in preferred) {
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith(suffix) &&
            asset.url.isNotEmpty) {
          return asset.url;
        }
      }
    }
    return null;
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

/// The outcome of handing an update file to the platform installer.
class InstallResult {
  /// The installer was launched (or the folder was revealed on desktop).
  final bool started;

  /// Android only: the user must allow installing apps from Turbo first. The
  /// system settings screen was opened; a second attempt should succeed.
  final bool needsPermission;

  const InstallResult({this.started = false, this.needsPermission = false});
}

/// Downloads a release asset to a temporary file and opens the platform
/// installer. The download happens on this device straight from GitHub; the app
/// does not proxy it through any server.
class UpdateInstaller {
  UpdateInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('turbo_downloader/install');

  final MethodChannel _channel;

  /// Fetches [url] into a temp file, reporting 0..1 progress (null when the
  /// total size is unknown), and returns the file.
  Future<File> download(
    String url, {
    void Function(double? progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Update download failed (${response.statusCode})');
      }
      final total = response.contentLength;
      final dir = await getTemporaryDirectory();
      final segments = Uri.parse(url).pathSegments;
      final name = segments.isNotEmpty ? segments.last : 'turbo-update.bin';
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        if (isCancelled?.call() ?? false) {
          await sink.close();
          try {
            await file.delete();
          } catch (_) {}
          throw const HttpException('Update download cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : null);
      }
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }

  /// Hands [file] to the platform's installer.
  ///
  /// On Android this opens the system package installer for the APK; on desktop
  /// it launches the downloaded installer so the OS takes over. A [started]
  /// false result means the caller should fall back to opening the release page.
  Future<InstallResult> install(File file) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        try {
          final reply = await _channel.invokeMapMethod<String, dynamic>(
            'installApk',
            {'path': file.path},
          );
          return InstallResult(
            started: reply?['started'] == true,
            needsPermission: reply?['needsPermission'] == true,
          );
        } on MissingPluginException {
          return const InstallResult();
        } catch (_) {
          return const InstallResult();
        }
      case TargetPlatform.windows:
        return InstallResult(started: await _launch(file.path));
      case TargetPlatform.macOS:
        // A .dmg or .pkg is handed to the OS opener; a .zip is revealed so the
        // user can drag the app across themselves.
        if (file.path.toLowerCase().endsWith('.zip')) {
          return InstallResult(started: await _launch(file.parent.path));
        }
        return InstallResult(started: await _launch(file.path));
      case TargetPlatform.linux:
        if (!file.path.toLowerCase().endsWith('.appimage')) {
          return InstallResult(started: await _launch(file.parent.path));
        }
        try {
          await Process.run('chmod', ['+x', file.path]);
        } catch (_) {}
        return InstallResult(started: await _launch(file.path));
      default:
        return const InstallResult();
    }
  }

  Future<bool> _launch(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path],
            runInShell: true, mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {}
    return false;
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
