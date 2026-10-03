import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_downloader.dart';
import 'media_url.dart';

/// How aggressively the built-in engine splits a download.
enum SpeedMode {
  /// Fewer connections; polite to the host.
  balanced,

  /// More connections for the fastest transfer the host allows.
  turbo;

  int connections(int base) => switch (this) {
        SpeedMode.balanced => base.clamp(1, 8),
        SpeedMode.turbo => 16,
      };

  String get label => switch (this) {
        SpeedMode.balanced => 'Balanced',
        SpeedMode.turbo => 'Turbo',
      };
}

/// The result of inspecting a media page with whichever engine can read it.
class ProbeResult {
  final String title;
  final String? author;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final List<MediaFormat> formats;

  /// True when yt-dlp produced this (its format ids are `-f` selectors).
  final bool usedYtdlp;

  /// True when the engine can merge separate high-resolution tracks.
  final bool canMux;

  const ProbeResult({
    required this.title,
    required this.formats,
    required this.usedYtdlp,
    this.author,
    this.durationSeconds,
    this.thumbnailUrl,
    this.canMux = false,
  });
}

/// Application state for the on-device download manager.
///
/// Everything runs on the device: the phone or computer opens the connections,
/// writes the bytes to its own storage, and needs no server, account, or key.
class TurboState extends ChangeNotifier {
  static const _kAccent = 'turbo.accent';
  static const _kConnections = 'turbo.connections';
  static const _kPlaySound = 'turbo.playSound';
  static const _kSpeedMode = 'turbo.speedMode';
  static const _kPreferredEngine = 'turbo.preferredEngine';
  static const _kYtdlpPath = 'turbo.ytdlpPath';

  String accentKey = 'cyan';

  /// Base segment count applied to new downloads.
  int defaultConnections = 4;

  /// Speed profile; Turbo raises the segment ceiling for range-capable hosts.
  SpeedMode speedMode = SpeedMode.turbo;

  /// When true, non-YouTube sites and every format are routed through yt-dlp
  /// whenever it is installed. When false, YouTube uses the built-in extractor.
  bool preferEngine = true;

  /// Play the system completion sound when a download finishes.
  bool playSound = true;

  bool loading = true;

  /// Last engine detection result, for Settings.
  bool ytdlpAvailable = false;
  bool ytdlpHasFfmpeg = false;

  final local = LocalDownloadManager();

  bool _disposed = false;

  /// Overridable resolver so tests can describe a page without the network.
  @visibleForTesting
  Future<MediaInfo> Function(String pageUrl)? describeOverride;

  TurboState() {
    local.addListener(_safeNotify);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    accentKey = prefs.getString(_kAccent) ?? 'cyan';
    defaultConnections = prefs.getInt(_kConnections) ?? 4;
    speedMode = prefs.getString(_kSpeedMode) == 'balanced'
        ? SpeedMode.balanced
        : SpeedMode.turbo;
    preferEngine = prefs.getBool(_kPreferredEngine) ?? true;
    playSound = prefs.getBool(_kPlaySound) ?? true;
    local.ytdlp.overridePath = prefs.getString(_kYtdlpPath);
    local.maxConnections = speedMode.connections(defaultConnections);
    await local.init();
    loading = false;
    _safeNotify();
    unawaited(refreshEngine());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Re-detects yt-dlp and ffmpeg; called at startup and from Settings.
  Future<void> refreshEngine() async {
    final bin = await local.ytdlp.refresh();
    ytdlpAvailable = bin != null;
    ytdlpHasFfmpeg = ytdlpAvailable && await local.ytdlp.hasFfmpeg();
    _safeNotify();
  }

  Future<void> setYtdlpPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    local.ytdlp.overridePath = path;
    if (path == null || path.isEmpty) {
      await prefs.remove(_kYtdlpPath);
    } else {
      await prefs.setString(_kYtdlpPath, path);
    }
    await refreshEngine();
  }

  Future<void> setAccent(String key) async {
    accentKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, key);
    _safeNotify();
  }

  Future<void> setDefaultConnections(int value) async {
    defaultConnections = value.clamp(1, 16);
    local.maxConnections = speedMode.connections(defaultConnections);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConnections, defaultConnections);
    _safeNotify();
  }

  Future<void> setSpeedMode(SpeedMode mode) async {
    speedMode = mode;
    local.maxConnections = mode.connections(defaultConnections);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kSpeedMode, mode == SpeedMode.turbo ? 'turbo' : 'balanced');
    _safeNotify();
  }

  Future<void> setPreferEngine(bool value) async {
    preferEngine = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPreferredEngine, value);
    _safeNotify();
  }

  Future<void> setPlaySound(bool value) async {
    playSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlaySound, value);
    _safeNotify();
  }

  /// Inspects a pasted media page (title, duration, thumbnail, formats).
  ///
  /// YouTube is read by the built-in extractor; every other platform, and any
  /// YouTube video when yt-dlp is installed, is read by yt-dlp so formats
  /// include high-resolution merged options.
  Future<ProbeResult> probeMedia(String url) async {
    final override = describeOverride;
    if (override != null) {
      final info = await override(url);
      return ProbeResult(
        title: info.title,
        author: info.author,
        durationSeconds: info.durationSeconds,
        thumbnailUrl: info.thumbnailUrl,
        formats: info.formats,
        usedYtdlp: false,
        canMux: ytdlpHasFfmpeg,
      );
    }

    final youtube = isYouTubeUrl(url);
    // The built-in extractor only reads YouTube, so any other platform must go
    // through yt-dlp even when the user has turned the preference off.
    final useYtdlp = ytdlpAvailable && (preferEngine || !youtube);
    Object? ytdlpError;
    if (useYtdlp) {
      try {
        final probe = await local.ytdlp.probe(url);
        return ProbeResult(
          title: probe.title,
          author: probe.author,
          durationSeconds: probe.durationSeconds,
          thumbnailUrl: probe.thumbnailUrl,
          formats: probe.formats
              .map((f) => MediaFormat(
                    id: f.selector,
                    label: f.label,
                    kind: f.kind,
                    extension: f.extension,
                    size: f.size,
                    height: f.height,
                    requiresMux: f.requiresMux,
                  ))
              .toList(),
          usedYtdlp: true,
          canMux: probe.hasFfmpeg,
        );
      } catch (e) {
        ytdlpError = e;
      }
    }

    // The built-in extractor only reads YouTube. A different platform needs
    // yt-dlp, so report that directly instead of a confusing failure.
    if (!isYouTubeUrl(url)) {
      if (!ytdlpAvailable) {
        throw const MediaResolveException(
          'This platform needs the yt-dlp engine. Install yt-dlp, then tap '
          'Re-check in Settings.',
        );
      }
      throw MediaResolveException(
        ytdlpError is YtdlpException
            ? ytdlpError.message
            : 'Could not read this page: $ytdlpError',
      );
    }

    // If yt-dlp was tried for YouTube but failed, fall through to the built-in
    // extractor rather than giving up.

    final info = await const MediaExtractor().describe(url);
    return ProbeResult(
      title: info.title,
      author: info.author,
      durationSeconds: info.durationSeconds,
      thumbnailUrl: info.thumbnailUrl,
      formats: info.formats,
      usedYtdlp: false,
      canMux: false,
    );
  }

  /// Decides how a pasted link should be fetched and queues it on this device.
  ///
  /// A known media platform is always treated as a page. An unlisted link is
  /// only treated as a page when yt-dlp is installed — otherwise a direct file
  /// URL with a query string would be misrouted to an extractor that cannot
  /// read it. YouTube uses the built-in extractor unless yt-dlp (with its HD
  /// options) is available and preferred.
  LocalTask addLink(
    String url, {
    String? filename,
    int? connections,
    String? engine,
    String? formatSelector,
    String? formatId,
    String? extensionHint,
    ProbeResult? mediaInfo,
  }) {
    final trimmed = url.trim();
    final known = isMediaUrl(trimmed);
    final youtube = isYouTubeUrl(trimmed);
    final page = known || (looksLikePage(trimmed) && ytdlpAvailable);

    // Resolve which engine runs this link. An explicit caller choice wins;
    // otherwise yt-dlp is used when it is installed (it unlocks non-YouTube
    // platforms and HD), and YouTube falls back to the built-in extractor.
    String resolvedEngine = 'http';
    if (page) {
      final useYtdlp = engine == 'ytdlp' ||
          (engine == null && known && !youtube) ||
          (engine == null && preferEngine && ytdlpAvailable);
      resolvedEngine = useYtdlp ? 'ytdlp' : 'http';
    }

    final conns = speedMode.connections(connections ?? defaultConnections);
    return local.add(
      trimmed,
      filename: filename ?? mediaInfo?.title,
      connections: conns,
      kind: page ? 'media' : 'http',
      engine: resolvedEngine,
      formatSelector: formatSelector,
      formatId: formatId,
      extensionHint: extensionHint,
      mediaTitle: mediaInfo?.title,
      mediaAuthor: mediaInfo?.author,
      mediaDuration: mediaInfo?.durationSeconds,
      thumbnailUrl: mediaInfo?.thumbnailUrl,
    );
  }

  /// Queues a plain download without any inspection (used by tests and the
  /// direct-link flow).
  void addToDevice(
    String url, {
    String? filename,
    int connections = 4,
    String kind = 'http',
    String engine = 'http',
  }) {
    local.add(
      url,
      filename: filename,
      connections: speedMode.connections(connections),
      kind: kind,
      engine: engine,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    local.removeListener(_safeNotify);
    local.dispose();
    super.dispose();
  }
}
