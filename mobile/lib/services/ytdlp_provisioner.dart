import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_dirs.dart';
import 'update_checker.dart';

/// Installs the standalone `yt-dlp` binary for the current desktop platform.
///
/// Desktop does not bundle yt-dlp (Android does), and the built-in pure-Dart
/// extractor is bot-walled by YouTube far more often than yt-dlp, so a computer
/// with no yt-dlp installed can hit a 403 on a video yt-dlp would download
/// fine. This fetches the official release asset — the same program a user
/// would install by hand — verifies it against the release's published
/// SHA-256 manifest (fail-closed), and puts it where [YtdlpEngine] looks.
///
/// Nothing is proxied: the binary comes straight from the yt-dlp GitHub
/// release, exactly like the in-app updater fetches Turbo's own updates.
class YtdlpProvisioner {
  YtdlpProvisioner({
    Directory? dirOverride,
    Abi? abiOverride,
    UpdateInstaller? installer,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
    String? latestTagOverride,
  })  : _dirOverride = dirOverride,
        _abiOverride = abiOverride,
        _installer = installer ?? UpdateInstaller(),
        _isWindows = isWindows ?? Platform.isWindows,
        _isMacOS = isMacOS ?? Platform.isMacOS,
        _isLinux = isLinux ?? Platform.isLinux,
        _latestTagOverride = latestTagOverride;

  final Directory? _dirOverride;
  final Abi? _abiOverride;
  final UpdateInstaller _installer;
  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;

  /// Test seam: pins the release tag so no network call is made.
  final String? _latestTagOverride;

  static const String _releaseBase = 'https://github.com/yt-dlp/yt-dlp/releases';
  static const String _apiLatest =
      'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';

  Abi get _abi => _abiOverride ?? Abi.current();

  /// The release asset for the running platform and architecture, or null when
  /// no standalone build is published for it (e.g. 32-bit ARM Linux, which
  /// ships only as a `.zip`).
  String? get assetName {
    if (_isWindows) {
      return switch (_abi) {
        Abi.windowsArm64 => 'yt-dlp_arm64.exe',
        _ => 'yt-dlp.exe',
      };
    }
    if (_isMacOS) return 'yt-dlp_macos';
    if (_isLinux) {
      return switch (_abi) {
        Abi.linuxArm64 => 'yt-dlp_linux_aarch64',
        Abi.linuxX64 => 'yt-dlp_linux',
        _ => null,
      };
    }
    return null;
  }

  /// True when this platform can be provisioned automatically.
  bool get isSupported => assetName != null;

  /// The directory the binary is installed into.
  Future<Directory> _binDir() async {
    final base = _dirOverride ?? await AppDirs.data();
    return Directory('${base.path}${Platform.pathSeparator}bin');
  }

  /// Where the installed binary lives, whether or not it exists yet.
  Future<String> binaryPath() async {
    final dir = await _binDir();
    final exe = _isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    return '${dir.path}${Platform.pathSeparator}$exe';
  }

  /// The installed binary, when it is present and executable, else null.
  Future<String?> installedBinary() async {
    final path = await binaryPath();
    if (await File(path).exists()) return path;
    return null;
  }

  /// Downloads, verifies, and installs the binary. Returns its path.
  ///
  /// Throws with a user-safe message when the platform has no asset, the
  /// release cannot be read, or the checksum does not match.
  Future<String> install({void Function(double? progress)? onProgress}) async {
    final asset = assetName;
    if (asset == null) {
      throw const YtdlpInstallException(
        'No prebuilt yt-dlp is published for this platform. Install it with '
        'your package manager, then tap Re-check.',
      );
    }

    // Resolve the tag first, then pin both the asset and its manifest to that
    // tag, so a release published between the two requests cannot make the
    // checksum describe a different build than the one downloaded.
    final tag = await _latestTag();
    final assetUrl = '$_releaseBase/download/$tag/$asset';
    final sumsUrl = '$_releaseBase/download/$tag/SHA2-256SUMS';

    final File downloaded;
    try {
      downloaded = await _installer.download(
        assetUrl,
        checksumUrls: [sumsUrl],
        onProgress: onProgress,
      );
    } on HttpException catch (e) {
      throw YtdlpInstallException(_friendly(e.message));
    }

    final dir = await _binDir();
    await dir.create(recursive: true);
    final target = await binaryPath();
    final out = File(target);
    if (await out.exists()) await out.delete();
    // The temp file and the target can be on different filesystems, so copy
    // rather than rename; the copy is what the user will run.
    await downloaded.copy(target);
    if (!_isWindows) {
      try {
        await Process.run('chmod', ['+x', target]);
      } catch (_) {
        // The binary is still written; execution may still work if the mode
        // inherited from the temp file was already executable.
      }
    }
    if (onProgress != null) onProgress(1);
    return target;
  }

  Future<String> _latestTag() async {
    final override = _latestTagOverride;
    if (override != null && override.isNotEmpty) return override;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_apiLatest));
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const YtdlpInstallException(
          'Could not reach the yt-dlp release page. Check your connection and '
          'try again.',
        );
      }
      final json =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      final tag = json['tag_name']?.toString() ?? '';
      if (tag.isEmpty) {
        throw const YtdlpInstallException(
          'The yt-dlp release did not report a version. Try again later.',
        );
      }
      return tag;
    } on YtdlpInstallException {
      rethrow;
    } catch (_) {
      throw const YtdlpInstallException(
        'Could not reach the yt-dlp release page. Check your connection and '
        'try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Turns the updater's generic download failure into engine-specific advice.
  static String _friendly(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('no checksum')) {
      return 'The yt-dlp release publishes no checksum for this file, so Turbo '
          'refused to install it. Install yt-dlp with your package manager '
          'instead.';
    }
    if (lower.contains('verification')) {
      return 'The downloaded yt-dlp did not match its published checksum, so '
          'it was discarded. Try again; if it keeps failing, install yt-dlp '
          'with your package manager.';
    }
    return 'The download engine could not be installed: $message';
  }
}

/// A provisioning failure with a message safe to show the user.
class YtdlpInstallException implements Exception {
  final String message;
  const YtdlpInstallException(this.message);

  @override
  String toString() => message;
}

/// True when the running platform can have yt-dlp installed in-app.
bool get canProvisionYtdlp {
  if (kIsWeb) return false;
  if (Platform.isWindows || Platform.isMacOS) return true;
  if (Platform.isLinux) {
    return Abi.current() == Abi.linuxX64 || Abi.current() == Abi.linuxArm64;
  }
  return false;
}
