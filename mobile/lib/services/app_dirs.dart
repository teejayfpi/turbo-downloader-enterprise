import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves the directory that holds the app's small state files — the signed
/// in session, history, and desktop credentials.
///
/// The old approach built the path as `HOME ?? '.'` + `/.turbo`. When `HOME` and
/// `USERPROFILE` are both unset — an Android launch, a sandbox, a service, or
/// any process started with a clean environment — that resolves to a
/// *working-directory-relative* `./.turbo`. A read-only working directory then
/// fails the whole session read with `OS Error: Read-only file system`, which
/// looks like a sign-in failure and blocks the user exactly when they are trying
/// to get past a YouTube login wall.
///
/// Candidates are tried in order of preference, and a candidate is only used
/// once it is confirmed writable, so this never returns a path that will fail on
/// write. The temp directory is the guaranteed-writable last resort.
class AppDirs {
  AppDirs._();

  static Future<Directory>? _cached;

  /// Test seam: forces [data] to a known directory without touching the real
  /// environment or platform channel.
  static Directory? _testOverride;

  @visibleForTesting
  static set testOverride(Directory? dir) {
    _testOverride = dir;
    _cached = null;
  }

  /// The per-user directory for app state. Prefers the historical `~/.turbo`
  /// (so existing desktop installs keep their data), then the platform's own
  /// app-support directory (the only sensible location on Android), then the
  /// temp directory. Resolved once and cached: callers read it on every state
  /// file access.
  static Future<Directory> data() {
    final override = _testOverride;
    if (override != null) return Future.value(override);
    return _cached ??= resolve(
          home: Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'],
          platform: _platformSupportDir,
          temp: Directory.systemTemp,
        );
  }

  /// Drops the cached answer, e.g. after the environment changes in a test.
  @visibleForTesting
  static void resetCache() => _cached = null;

  static Future<Directory?> _platformSupportDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      // No platform channel (tests, headless) — let the caller fall through.
      return null;
    }
  }

  /// The candidate resolution, with the environment injected so it is testable
  /// without spawning a process. Never throws and never returns a directory it
  /// could not create.
  @visibleForTesting
  static Future<Directory> resolve({
    Directory? override,
    String? home,
    Future<Directory?> Function()? platform,
    Directory? temp,
  }) async {
    final fallback = temp ?? Directory.systemTemp;
    final candidates = <Directory>[];
    if (override != null) candidates.add(override);
    if (home != null && home.trim().isNotEmpty) {
      candidates.add(Directory('$home${Platform.pathSeparator}.turbo'));
    }
    if (platform != null) {
      final p = await platform();
      if (p != null) candidates.add(p);
    }
    candidates.add(fallback);

    for (final candidate in candidates) {
      if (await _ensure(candidate)) return candidate;
    }
    return fallback;
  }

  static Future<bool> _ensure(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
