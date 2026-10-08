import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_downloader.dart';
import 'media_url.dart';
import 'services/device_policy.dart';
import 'services/diagnostics.dart';
import 'services/history_store.dart';
import 'services/notifications.dart';
import 'services/retry_policy.dart';
import 'services/secure_store.dart';
import 'services/session_store.dart';
import 'services/settings_store.dart';
import 'services/storage_stats.dart';
import 'services/update_checker.dart';
import 'services/url_validator.dart';
import 'services/youtube_browser.dart';

/// How aggressively the built-in engine splits a download.
enum SpeedMode {
  /// Fewer connections; polite to the host.
  balanced,

  /// More connections for the fastest transfer the host allows.
  turbo;

  int connections(int base) => switch (this) {
        SpeedMode.balanced => base.clamp(1, 16),
        SpeedMode.turbo => 32,
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

/// Outcome of queueing a batch (a channel, a playlist, or a multi-selection).
class BatchResult {
  final int queued;
  final int duplicates;
  final int failed;
  final int total;

  const BatchResult({
    required this.queued,
    required this.duplicates,
    required this.failed,
    required this.total,
  });

  /// A short, user-facing summary of what happened.
  String get summary {
    final parts = <String>['$queued queued'];
    if (duplicates > 0) parts.add('$duplicates already queued');
    if (failed > 0) parts.add('$failed failed');
    return parts.join(' · ');
  }
}

/// Application state for the on-device download manager.
///
/// Everything runs on the device: the phone or computer opens the connections,
/// writes the bytes to its own storage, and needs no server, account, or key.
class TurboState extends ChangeNotifier {
  TurboState({
    SettingsStore? settings,
    HistoryStore? history,
    Diagnostics? diagnostics,
    StorageInspector? storage,
    UpdateChecker? updater,
    DevicePolicy? device,
    Notifications? notifications,
    SecureStore? secure,
    SessionStore? session,
    UpdateInstaller? installer,
  })  : settings = settings ?? SettingsStore(),
        history = history ?? HistoryStore(),
        diagnostics = diagnostics ?? Diagnostics(),
        storage = storage ?? const StorageInspector(),
        updater = updater ?? UpdateChecker(),
        device = device ?? DevicePolicy(),
        notifications = notifications ?? const Notifications(),
        secure = secure ?? SecureStore(),
        session = session ?? SessionStore(),
        installer = installer ?? UpdateInstaller() {
    local.addListener(_safeNotify);
    local.history = this.history;
    local.diagnostics = this.diagnostics;
    local.onFinished = _onTaskFinished;
    local.onGaveUp = _onTaskGaveUp;
  }

  final SettingsStore settings;
  final HistoryStore history;
  final Diagnostics diagnostics;
  final StorageInspector storage;
  final UpdateChecker updater;
  final DevicePolicy device;
  final Notifications notifications;
  final SecureStore secure;
  final SessionStore session;
  final UpdateInstaller installer;

  // --------------------------------------------------------------- appearance

  String accentKey = 'cyan';

  /// System, light, or dark. The brand palette has a light counterpart.
  ThemeMode themeMode = ThemeMode.dark;

  /// Active UI language code ('en', 'fr', 'yo'). Null follows the system.
  String? localeCode;

  /// A high-contrast palette for accessibility.
  bool highContrast = false;

  /// Suppresses non-essential animation for reduced-motion preferences.
  bool reducedMotion = false;

  /// Extra text scaling applied on top of the system setting.
  double textScale = 1.0;

  // ------------------------------------------------------------------ engine

  /// Base segment count applied to new downloads.
  int defaultConnections = 4;

  /// Speed profile; Turbo raises the segment ceiling for range-capable hosts.
  SpeedMode speedMode = SpeedMode.turbo;

  /// When true, non-YouTube sites and every format are routed through yt-dlp
  /// whenever it is installed. When false, YouTube uses the built-in extractor.
  bool preferEngine = true;

  /// Play the system completion sound when a download finishes.
  bool playSound = true;

  /// Retry transient failures automatically with exponential backoff.
  bool autoRetry = true;

  // --------------------------------------------------------------- behaviour

  /// How many downloads may run at once.
  int maxConcurrent = 1;

  /// Pause new transfers unless the device is on Wi-Fi.
  bool wifiOnly = false;

  /// Pause new transfers on a low, unplugged battery.
  bool batteryAware = false;

  /// Start ranged downloads with a small number of segments and add more as
  /// the host proves able to feed them (adaptive acceleration). When off, the
  /// full connection width is opened immediately.
  bool adaptiveConnections = true;

  /// Remember how wide a host let the ramp grow last time, so a repeat
  /// download from that host starts near its proven width instead of ramping
  /// from scratch. Only hosts that benefited are remembered; slow ones are not
  /// penalised. Requires adaptive acceleration.
  bool rememberHostSpeed = true;

  /// Notify when the whole queue finishes, every download, or never.
  NotificationStyle notifyStyle = NotificationStyle.onQueueComplete;

  /// Show the running-download progress notification.
  bool notifyProgress = false;

  /// Whether to look for a newer release at startup.
  bool checkUpdates = true;

  /// Which release channel this build follows.
  UpdateChannel updateChannel = UpdateChannel.stable;

  /// Watch the clipboard for copied links and offer them in the Add tab.
  bool clipboardMonitor = false;

  // ------------------------------------------------------------------- status

  bool loading = true;

  /// A newer release, when one was found. Null when up to date or unchecked.
  UpdateInfo? updateAvailable;

  /// The latest storage snapshot, refreshed on demand and after transfers.
  StorageStats storageStats = const StorageStats();

  /// Live device conditions (Wi-Fi, battery).
  DeviceState deviceState = DeviceState.unknown;

  /// True when onboarding has been completed or skipped.
  bool onboardingDone = false;

  /// A link handed to the app from outside (deep link, share sheet, drop).
  /// The shell watches this, jumps to Add, and the Add screen consumes it.
  String? pendingUrl;

  /// Receives a link that arrived from anywhere on the device.
  void receiveLink(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    pendingUrl = trimmed;
    _safeNotify();
  }

  /// Returns the pending incoming link once, then clears it.
  String? takePendingLink() {
    final url = pendingUrl;
    pendingUrl = null;
    return url;
  }

  /// Last engine detection result, for Settings.
  bool ytdlpAvailable = false;
  bool ytdlpHasFfmpeg = false;

  /// True when a signed-in session (cookie jar or browser profile) is set, and
  /// how many cookies it holds. Shown in Settings; the values stay in the vault.
  bool sessionConfigured = false;
  int sessionCookieCount = 0;

  /// The browser profile yt-dlp should read, when the user chose that route.
  String? sessionBrowser;

  /// True when the bundled FFmpeg can merge separate video and audio tracks,
  /// which is what unlocks HD quality through the built-in extractor.
  bool ffmpegAvailable = false;

  final local = LocalDownloadManager();

  bool _disposed = false;
  Timer? _deviceTimer;
  Timer? _progressTimer;

  static const _startupTimeout = Duration(seconds: 12);

  /// Overridable resolver so tests can describe a page without the network.
  @visibleForTesting
  Future<MediaInfo> Function(String pageUrl)? describeOverride;

  Future<void> init() async {
    var stage = 'preferences';
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(_startupTimeout);
      accentKey = prefs.getString('turbo.accent') ?? 'cyan';
      defaultConnections = prefs.getInt('turbo.connections') ?? 4;
      speedMode = prefs.getString('turbo.speedMode') == 'balanced'
          ? SpeedMode.balanced
          : SpeedMode.turbo;
      preferEngine = prefs.getBool('turbo.preferredEngine') ?? true;
      playSound = prefs.getBool('turbo.playSound') ?? true;
      local.ytdlp.overridePath = prefs.getString('turbo.ytdlpPath');

      themeMode = _themeModeFrom(prefs.getString(SettingsStore.kThemeMode));
      localeCode = prefs.getString(SettingsStore.kLocale);
      highContrast = prefs.getBool(SettingsStore.kHighContrast) ?? false;
      reducedMotion = prefs.getBool(SettingsStore.kReducedMotion) ?? false;
      textScale = prefs.getDouble(SettingsStore.kTextScale) ?? 1.0;
      maxConcurrent = prefs.getInt(SettingsStore.kMaxConcurrent) ?? 1;
      wifiOnly = prefs.getBool(SettingsStore.kWifiOnly) ?? false;
      batteryAware = prefs.getBool(SettingsStore.kBatteryAware) ?? false;
      autoRetry = prefs.getBool(SettingsStore.kAutoRetry) ?? true;
      adaptiveConnections =
          prefs.getBool(SettingsStore.kAdaptiveConnections) ?? true;
      rememberHostSpeed =
          prefs.getBool(SettingsStore.kRememberHostSpeed) ?? true;
      notifyProgress = prefs.getBool(SettingsStore.kNotifyProgress) ?? false;
      checkUpdates = prefs.getBool(SettingsStore.kCheckUpdates) ?? true;
      onboardingDone = prefs.getBool(SettingsStore.kOnboardingDone) ?? false;
      updateChannel = _channelFrom(prefs.getString(SettingsStore.kUpdateChannel));
      notifyStyle =
          _notifyStyleFrom(prefs.getString(SettingsStore.kNotifyComplete));
      clipboardMonitor = prefs.getBool(SettingsStore.kClipboardMonitor) ?? false;

      local.maxConnections = speedMode.connections(defaultConnections);
      local.adaptiveConnections = adaptiveConnections;
      local.rememberHostSpeed = rememberHostSpeed;
      local.maxConcurrent = maxConcurrent;
      if (!autoRetry) local.retryPolicy = RetryPolicy.none;

      stage = 'history';
      await history.init().timeout(_startupTimeout);
      stage = 'diagnostics';
      await diagnostics.init().timeout(_startupTimeout);
      stage = 'notifications';
      await notifications.ensureChannel().timeout(_startupTimeout);
      stage = 'download queue recovery';
      await local.init().timeout(_startupTimeout);

      unawaited(refreshEngine());
      unawaited(refreshStorage());
      unawaited(refreshDevice());
      _deviceTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(refreshDevice());
      });
      _progressTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
        _pushProgressNotification();
      });
      if (checkUpdates) unawaited(checkForUpdates());
    } catch (error) {
      // A startup failure must never strand the user on the splash. Keep the
      // diagnostic intentionally generic: paths, URLs, and personal data do
      // not belong in the local diagnostic bundle.
      try {
        await diagnostics.error(
          'startup_failed',
          '$stage: ${error.runtimeType}',
        );
      } catch (_) {}
    } finally {
      // This is the critical handoff. Previously, any exception or hung plugin
      // call before this point left loading=true forever.
      loading = false;
      _safeNotify();
    }
  }

  /// Mirrors the queue into Android's ongoing progress notification, when the
  /// user has asked for progress and a transfer is running.
  void _pushProgressNotification() {
    final active = local.activeCount + local.queuedCount;
    if (!notifyProgress || active == 0) {
      unawaited(notifications.setProgress(active: 0, percent: 0));
      return;
    }
    final running = local.tasks
        .where((t) => t.isRunning || t.isQueued)
        .toList();
    final total = running.fold<int>(
        0, (sum, t) => sum + (t.total > 0 ? t.total : 0));
    final done = running.fold<int>(
        0, (sum, t) => sum + (t.total > 0 ? t.downloaded : 0));
    final percent = total > 0 ? ((done / total) * 100).round() : 0;
    unawaited(notifications.setProgress(active: active, percent: percent));
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Re-detects yt-dlp, ffmpeg, and the bundled muxer; called at startup and
  /// from Settings.
  Future<void> refreshEngine() async {
    final bin = await local.ytdlp.refresh();
    ytdlpAvailable = bin != null;
    ytdlpHasFfmpeg = ytdlpAvailable && await local.ytdlp.hasFfmpeg();
    ffmpegAvailable = await local.muxer.isAvailable();
    await refreshSession();
    _safeNotify();
  }

  /// Re-reads the signed-in session from the vault and points the engine at it.
  Future<void> refreshSession() async {
    final browser = await session.browser();
    final jar = await session.cookies();
    sessionBrowser = browser;
    sessionCookieCount = jar == null ? 0 : SessionStore.countCookies(jar);
    sessionConfigured = browser != null || sessionCookieCount > 0;
    await session.applyTo(local.ytdlp);
    _safeNotify();
  }

  /// Saves an imported cookie jar and switches the engine to it.
  Future<void> setSessionCookies(String text) async {
    await session.setCookies(text);
    await session.setBrowser(null);
    await refreshSession();
  }

  /// Uses a local browser profile instead of an imported file.
  Future<void> setSessionBrowser(String? name) async {
    await session.setBrowser(name);
    await refreshSession();
  }

  /// Forgets the session entirely.
  Future<void> clearSession() async {
    await session.clear();
    await refreshSession();
  }

  Future<void> setYtdlpPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    local.ytdlp.overridePath = path;
    if (path == null || path.isEmpty) {
      await prefs.remove('turbo.ytdlpPath');
    } else {
      await prefs.setString('turbo.ytdlpPath', path);
    }
    await refreshEngine();
  }

  // ------------------------------------------------------------- preferences

  Future<void> setAccent(String key) async {
    accentKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('turbo.accent', key);
    _safeNotify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await settings.setString(SettingsStore.kThemeMode, mode.name);
    _safeNotify();
  }

  Future<void> setLocale(String? code) async {
    localeCode = code;
    if (code == null) {
      await settings.remove(SettingsStore.kLocale);
    } else {
      await settings.setString(SettingsStore.kLocale, code);
    }
    _safeNotify();
  }

  Future<void> setHighContrast(bool value) async {
    highContrast = value;
    await settings.setBool(SettingsStore.kHighContrast, value);
    _safeNotify();
  }

  Future<void> setReducedMotion(bool value) async {
    reducedMotion = value;
    await settings.setBool(SettingsStore.kReducedMotion, value);
    _safeNotify();
  }

  Future<void> setTextScale(double value) async {
    textScale = value.clamp(0.8, 1.6);
    await settings.setDouble(SettingsStore.kTextScale, textScale);
    _safeNotify();
  }

  Future<void> setDefaultConnections(int value) async {
    defaultConnections = value.clamp(1, 32);
    local.maxConnections = speedMode.connections(defaultConnections);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('turbo.connections', defaultConnections);
    _safeNotify();
  }

  Future<void> setSpeedMode(SpeedMode mode) async {
    speedMode = mode;
    local.maxConnections = mode.connections(defaultConnections);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'turbo.speedMode', mode == SpeedMode.turbo ? 'turbo' : 'balanced');
    _safeNotify();
  }

  Future<void> setPreferEngine(bool value) async {
    preferEngine = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('turbo.preferredEngine', value);
    _safeNotify();
  }

  Future<void> setPlaySound(bool value) async {
    playSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('turbo.playSound', value);
    _safeNotify();
  }

  Future<void> setMaxConcurrent(int value) async {
    maxConcurrent = value.clamp(1, 6);
    local.maxConcurrent = maxConcurrent;
    await settings.setInt(SettingsStore.kMaxConcurrent, maxConcurrent);
    local.resumeAll();
    _safeNotify();
  }

  Future<void> setAutoRetry(bool value) async {
    autoRetry = value;
    local.retryPolicy = value ? const RetryPolicy() : RetryPolicy.none;
    await settings.setBool(SettingsStore.kAutoRetry, value);
    _safeNotify();
  }

  Future<void> setAdaptiveConnections(bool value) async {
    adaptiveConnections = value;
    local.adaptiveConnections = value;
    await settings.setBool(SettingsStore.kAdaptiveConnections, value);
    _safeNotify();
  }

  Future<void> setRememberHostSpeed(bool value) async {
    rememberHostSpeed = value;
    local.rememberHostSpeed = value;
    await settings.setBool(SettingsStore.kRememberHostSpeed, value);
    _safeNotify();
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    await settings.setBool(SettingsStore.kWifiOnly, value);
    await refreshDevice();
    _safeNotify();
  }

  Future<void> setBatteryAware(bool value) async {
    batteryAware = value;
    await settings.setBool(SettingsStore.kBatteryAware, value);
    await refreshDevice();
    _safeNotify();
  }

  Future<void> setNotifyStyle(NotificationStyle style) async {
    notifyStyle = style;
    await settings.setString(SettingsStore.kNotifyComplete, style.name);
    _safeNotify();
  }

  Future<void> setNotifyProgress(bool value) async {
    notifyProgress = value;
    await settings.setBool(SettingsStore.kNotifyProgress, value);
    _safeNotify();
  }

  Future<void> setCheckUpdates(bool value) async {
    checkUpdates = value;
    await settings.setBool(SettingsStore.kCheckUpdates, value);
    _safeNotify();
  }

  Future<void> setUpdateChannel(UpdateChannel channel) async {
    updateChannel = channel;
    await settings.setString(SettingsStore.kUpdateChannel, channel.name);
    _safeNotify();
  }

  Future<void> setClipboardMonitor(bool value) async {
    clipboardMonitor = value;
    await settings.setBool(SettingsStore.kClipboardMonitor, value);
    _safeNotify();
  }

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    await settings.setBool(SettingsStore.kOnboardingDone, true);
    _safeNotify();
  }

  // -------------------------------------------------------- device and storage

  /// Re-reads Wi-Fi and battery, and applies the pause policy.
  Future<void> refreshDevice() async {
    deviceState = await device.read();
    final blocked = device.blocksDownloads(
      deviceState,
      wifiOnly: wifiOnly,
      batteryAware: batteryAware,
    );
    local.setNetworkBlocked(blocked);
    _safeNotify();
  }

  /// Recomputes the storage snapshot shown in the storage panel.
  Future<void> refreshStorage() async {
    storageStats = await storage.inspect(
      partsRoot: local.partsRoot,
      downloadedBytes: history.totalBytes,
    );
    _safeNotify();
  }

  /// Deletes all partial data. Returns the bytes reclaimed.
  Future<int> cleanUpPartials() async {
    final reclaimed = await storage.clearTemporary(local.partsRoot);
    await refreshStorage();
    _safeNotify();
    return reclaimed;
  }

  /// Looks for a newer release on the selected channel.
  Future<void> checkForUpdates() async {
    updateAvailable = await updater.check();
    _safeNotify();
  }

  /// Progress of an in-app update download, 0..1. Null when idle or the total
  /// size is unknown. [updateInstalling] is true while it runs.
  double? updateProgress;
  bool updateInstalling = false;

  /// Downloads the available update and hands it to the platform installer.
  /// Returns a short status for the UI to show.
  Future<String> installUpdate() async {
    final update = updateAvailable;
    final url = update?.downloadUrl;
    if (update == null || url == null) {
      return 'This build cannot be installed automatically. Open the release '
          'page to update.';
    }
    updateInstalling = true;
    updateProgress = null;
    _safeNotify();
    try {
      final file = await installer.download(
        url,
        checksumUrls: update.checksumUrls,
        // Android verifies the APK by its signing key at install time, and a
        // release may publish no Android checksum manifest, so the manifest is
        // a best-effort extra there. Every other platform fails closed when no
        // checksum covers the asset.
        allowUnverified: defaultTargetPlatform == TargetPlatform.android,
        onProgress: (p) {
          updateProgress = p;
          _safeNotify();
        },
      );
      final result = await installer.install(file);
      if (result.needsPermission) {
        return 'Allow "Install unknown apps" for Turbo, then tap Download & '
            'install again.';
      }
      return result.started
          ? 'Installer opened. Follow the prompts to finish updating to '
              'v${update.version}.'
          : 'Downloaded to ${file.path}. Open it to finish updating.';
    } catch (error) {
      return 'Update download failed: $error';
    } finally {
      updateInstalling = false;
      updateProgress = null;
      _safeNotify();
    }
  }

  // ----------------------------------------------------------------- history

  /// History entries matching [filter], newest first.
  List<HistoryEntry> historyEntries(HistoryFilter filter) =>
      history.query(filter);

  Future<void> deleteHistoryEntry(String id) async {
    await history.remove(id);
    // Keep the live queue consistent: if the same transfer is still present,
    // remove it too so a deleted record cannot linger as a card.
    local.remove(id);
    await refreshStorage();
    _safeNotify();
  }

  /// Removes a task from the live queue by its URL, used when a history entry
  /// is deleted while its card is still on screen.
  void removeTaskForUrl(String url) {
    for (final t in local.tasks) {
      if (t.url == url) local.remove(t.id);
    }
  }

  /// Clears the local diagnostic log and refreshes the UI.
  Future<void> clearDiagnostics() async {
    await diagnostics.clear();
    _safeNotify();
  }

  Future<void> clearHistory() async {
    await history.clear();
    _safeNotify();
  }

  // --------------------------------------------------------------- completion

  /// Raises a notification when a transfer settles, and refreshes storage.
  void _onTaskFinished(LocalTask task) {
    if (task.isCompleted && notifyStyle == NotificationStyle.everyDownload) {
      unawaited(notifications.show(
        title: 'Download complete',
        body: task.filename,
      ));
    }
    if (local.activeCount == 0 &&
        local.queuedCount == 0 &&
        notifyStyle != NotificationStyle.off) {
      final completed = local.tasks.where((t) => t.isCompleted).length;
      if (completed > 0) {
        unawaited(notifications.show(
          title: 'Downloads finished',
          body: '$completed file${completed == 1 ? '' : 's'} saved to your '
              'Downloads folder.',
        ));
      }
    }
    unawaited(refreshStorage());
  }

  void _onTaskGaveUp(LocalTask task) {
    unawaited(notifications.show(
      title: 'Download failed',
      body: '${task.filename}: ${task.error ?? 'unknown error'}',
    ));
  }

  /// Builds the copyable diagnostic bundle, including live app state.
  String diagnosticsBundle() => diagnostics.buildBundle(extra: {
        'downloads_active': '${local.activeCount}',
        'downloads_queued': '${local.queuedCount}',
        'engine_ytdlp': '$ytdlpAvailable',
        'theme': themeMode.name,
        'locale': localeCode ?? 'system',
      });

  // ------------------------------------------------------------------- adding

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
        canMux: ffmpegAvailable,
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
      canMux: ffmpegAvailable,
    );
  }

  /// Decides how a pasted link should be fetched and queues it on this device.
  ///
  /// A known media platform is always treated as a page. An unlisted link is
  /// only treated as a page when yt-dlp is installed — otherwise a direct file
  /// URL with a query string would be misrouted to an extractor that cannot
  /// read it. YouTube uses the built-in extractor unless yt-dlp (with its HD
  /// options) is available and preferred.
  ///
  /// Returns null when [url] is already pending; use [LocalDownloadManager.add]
  /// directly to force a duplicate.
  LocalTask? addLink(
    String url, {
    String? filename,
    int? connections,
    String? engine,
    String? formatSelector,
    String? formatId,
    String? extensionHint,
    ProbeResult? mediaInfo,
    Map<String, String>? headers,
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
    return local.addIfNew(
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
      headers: headers,
    );
  }

  /// Queues a whole channel, playlist, or hand-picked set of videos as one
  /// batch.
  ///
  /// The first [probeLimit] links are inspected and queued at the best
  /// available quality immediately; the remainder are queued as media pages
  /// and resolved on-device just before each transfer starts. Probing a large
  /// listing in full would keep the user waiting, so the queue fills fast and
  /// stays responsive.
  Future<BatchResult> addBatch(
    List<BrowseVideo> videos, {
    int probeLimit = 5,
  }) async {
    var queued = 0;
    var duplicates = 0;
    var failed = 0;

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      ProbeResult? probe;
      MediaFormat? format;
      if (i < probeLimit) {
        try {
          probe = await probeMedia(video.watchUrl);
          format = probe.formats.isEmpty ? null : probe.formats.first;
        } catch (_) {
          // Leave it to the per-task resolver; a probe failure here should not
          // drop the video from the batch.
          probe = null;
          format = null;
        }
      }
      final task = addLink(
        video.watchUrl,
        filename: probe?.title ?? video.title,
        engine: probe != null && probe.usedYtdlp ? 'ytdlp' : null,
        mediaInfo: probe,
        formatSelector:
            probe != null && probe.usedYtdlp ? format?.id : null,
        formatId: probe != null && !probe.usedYtdlp ? format?.id : null,
        extensionHint: format?.extension,
      );
      if (task == null) {
        duplicates++;
      } else {
        queued++;
      }
    }

    return BatchResult(
      queued: queued,
      duplicates: duplicates,
      failed: failed,
      total: videos.length,
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

  /// Validates a URL and reports whether it is already queued.
  UrlValidation validateUrl(String? input) => UrlValidation.check(input);

  // ------------------------------------------------------------------ helpers

  static ThemeMode _themeModeFrom(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  static UpdateChannel _channelFrom(String? value) => switch (value) {
        'beta' => UpdateChannel.beta,
        'nightly' => UpdateChannel.nightly,
        _ => UpdateChannel.stable,
      };

  static NotificationStyle _notifyStyleFrom(String? value) => switch (value) {
        'off' => NotificationStyle.off,
        'everyDownload' => NotificationStyle.everyDownload,
        _ => NotificationStyle.onQueueComplete,
      };

  @override
  void dispose() {
    _disposed = true;
    _deviceTimer?.cancel();
    _progressTimer?.cancel();
    unawaited(notifications.setProgress(active: 0, percent: 0));
    local.removeListener(_safeNotify);
    local.dispose();
    super.dispose();
  }
}
