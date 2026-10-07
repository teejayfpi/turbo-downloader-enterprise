import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'file_store.dart';
import 'media_extractor.dart';
import 'services/diagnostics.dart';
import 'services/download_error.dart';
import 'services/ffmpeg.dart';
import 'services/history_store.dart';
import 'services/retry_policy.dart';
import 'services/url_validator.dart';
import 'ytdlp.dart';

// `ResolvedMedia`/`MediaResolveException` appear in the manager's public API
// (the resolver hook and its errors), so re-export them for callers.
export 'media_extractor.dart'
    show MediaExtractor, MediaFormat, MediaInfo, MediaResolveException, ResolvedMedia;

// The yt-dlp engine types cross the manager boundary for the UI and resolver.
export 'ytdlp.dart' show YtdlpEngine, YtdlpException, YtdlpFormat, YtdlpProbe;

// The muxer and its failure type are part of the manager's public surface.
export 'services/ffmpeg.dart' show FfmpegMuxer, MediaMuxException;

/// Moves a finished file into its final location. The default hands it to
/// Android's MediaStore; tests substitute a plain move.
typedef PublishFn = Future<File> Function(File tempFile, String filename);

/// Starts or stops Android's foreground service so the process keeps running
/// while transfers are in flight. Counts downloads, not calls.
typedef BackgroundFn = Future<void> Function(int active);

/// Resolves a media page to a direct stream. The default uses the on-device
/// extractor; tests substitute a fake so they never call YouTube.
typedef ResolveMediaFn = Future<ResolvedMedia> Function(
  String pageUrl, {
  String? formatId,
});

/// Runs the yt-dlp engine. Tests substitute a fake so they never spawn a
/// process; the default delegates to [YtdlpEngine].
typedef YtdlpDownloadFn = Future<File?> Function({
  required String url,
  required String selector,
  required Directory dir,
  required String stem,
  void Function(int downloaded, int total, int speed)? onProgress,
  bool Function()? isCancelled,
});

/// Merges a downloaded video-only stream with its audio track. Tests
/// substitute a fake so they never reach the bundled FFmpeg.
typedef MediaMuxFn = Future<void> Function({
  required String videoPath,
  required String audioPath,
  required String outPath,
  required String container,
});

/// Sent with every engine request. Hosts commonly answer the bare dart:io
/// default (`Dart/<sdk> (dart:io)`) with a 403, so present a conventional
/// browser agent the way the legacy server engine does.
const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36';

Future<void> _deviceBackground(int active) async {
  try {
    await const MethodChannel('turbo_downloader/files')
        .invokeMethod<bool>('background', {'active': active});
  } catch (_) {
    // Desktop and tests have no service; a missing bridge is not an error.
  }
}

/// A download that runs on the phone itself: the device opens the connections,
/// writes the bytes to its own storage, and keeps them there. This is the
/// opposite of a server task, where the phone is only a remote control.
///
/// State is small and serialisable so the queue survives a restart.
class LocalTask {
  final String id;
  String url;
  String filename;
  int connections;
  int total;
  int downloaded;
  int speed;
  String status; // queued | preparing | active | paused | completed | failed
  String? error;

  /// Actionable classification of [error], for the UI and diagnostics.
  String? errorKind;
  String? errorDetail;

  /// Automatic attempts made so far, and when the next one is due. A task that
  /// exhausts its retries stays failed until the user retries by hand.
  int attempts;
  DateTime? nextRetryAt;

  String? filePath;

  /// "http" for a direct file link, "media" for a page resolved on-device.
  /// A media task is resolved to a stream URL just before it is fetched, so
  /// the bytes still land on this device rather than a server.
  String kind;

  /// Which engine fetches this task: "http" (the built-in multi-connection
  /// engine) or "ytdlp" (the external program, used for non-YouTube sites and
  /// high-resolution merged downloads). Chosen when the task is created.
  String engine;

  /// The yt-dlp `-f` selector, when [engine] is "ytdlp".
  String? formatSelector;

  /// Chosen rendition id from the extractor (e.g. `muxed:720p:mp4`) when the
  /// built-in extractor resolves the stream.
  String? formatId;

  /// Best-effort output extension, used for the filename when the engine
  /// chooses the container (yt-dlp).
  String? extensionHint;

  /// Media metadata captured when the link was inspected, kept for the UI and
  /// for naming the saved file. Null for plain files.
  String? mediaTitle;
  String? mediaAuthor;
  int? mediaDuration;
  String? thumbnailUrl;

  /// The direct stream a media [url] resolved to. Not persisted: it is
  /// re-resolved on every start because signed stream URLs expire, and
  /// resuming against a stale one would fail. Null for direct links.
  String? streamUrl;

  /// The URL the worker actually fetches.
  String get fetchUrl => streamUrl ?? url;

  /// True when this task runs through the external yt-dlp engine.
  bool get usesYtdlp => engine == 'ytdlp';

  /// True when extraction was requested but yt-dlp turned out to be missing,
  /// so the task was served by the built-in extractor instead.
  bool fellBackToBuiltin = false;

  /// Whether the server confirmed support for HTTP range requests. False means
  /// an interrupted transfer must restart from the beginning.
  bool rangeSupported = true;

  /// Resource validator captured when the transfer first started (`ETag` or
  /// `Last-Modified`). Replayed as `If-Range` so a resumed transfer restarts
  /// when the remote file changed instead of stitching two versions together.
  String? etag;

  /// Per-download retry budget, overridable from Settings.
  int maxAttempts;

  List<int> segmentStart;
  List<int> segmentEnd;
  List<int> segmentDone;
  final DateTime createdAt;
  DateTime? completedAt;
  DateTime? startedAt;

  LocalTask({
    required this.id,
    required this.url,
    required this.filename,
    required this.connections,
    this.total = 0,
    this.downloaded = 0,
    this.speed = 0,
    this.status = 'queued',
    this.error,
    this.errorKind,
    this.errorDetail,
    this.attempts = 0,
    this.nextRetryAt,
    this.filePath,
    this.kind = 'http',
    this.engine = 'http',
    this.formatSelector,
    this.formatId,
    this.extensionHint,
    this.mediaTitle,
    this.mediaAuthor,
    this.mediaDuration,
    this.thumbnailUrl,
    this.maxAttempts = 3,
    this.rangeSupported = true,
    this.etag,
    List<int>? segmentStart,
    List<int>? segmentEnd,
    List<int>? segmentDone,
    required this.createdAt,
    this.completedAt,
    this.startedAt,
  })  : segmentStart = segmentStart ?? const [],
        segmentEnd = segmentEnd ?? const [],
        segmentDone = segmentDone ?? const [];

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isQueued => status == 'queued';
  bool get isPreparing => status == 'preparing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isRunning => isActive || isPreparing;
  bool get canOpen => isCompleted && (filePath?.isNotEmpty ?? false);

  /// True while the task is waiting for its next automatic retry.
  bool get awaitingRetry => isQueued && nextRetryAt != null;

  /// Wall-clock seconds from start to completion, when both are known.
  int? get durationSeconds {
    final start = startedAt;
    final end = completedAt;
    if (start == null || end == null) return null;
    return end.difference(start).inSeconds;
  }

  /// Mean throughput over the whole transfer, in bytes per second.
  int? get averageSpeed {
    final seconds = durationSeconds;
    if (seconds == null || seconds <= 0 || total <= 0) return null;
    return (total / seconds).round();
  }

  double get progress {
    if (total <= 0) return 0;
    return (downloaded / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'connections': connections,
        'total': total,
        'downloaded': downloaded,
        'status': status,
        'error': error,
        'errorKind': errorKind,
        'errorDetail': errorDetail,
        'attempts': attempts,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
        'filePath': filePath,
        'kind': kind,
        'engine': engine,
        'formatSelector': formatSelector,
        'formatId': formatId,
        'extensionHint': extensionHint,
        'mediaTitle': mediaTitle,
        'mediaAuthor': mediaAuthor,
        'mediaDuration': mediaDuration,
        'thumbnailUrl': thumbnailUrl,
        'fellBackToBuiltin': fellBackToBuiltin,
        'rangeSupported': rangeSupported,
        'etag': etag,
        'maxAttempts': maxAttempts,
        'segmentStart': segmentStart,
        'segmentEnd': segmentEnd,
        'segmentDone': segmentDone,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory LocalTask.fromJson(Map<String, dynamic> json) {
    List<int> ints(dynamic v) => ((v as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    return LocalTask(
      id: json['id'].toString(),
      url: json['url'].toString(),
      filename: json['filename']?.toString() ?? 'download',
      connections: (json['connections'] as num?)?.toInt() ?? 4,
      total: (json['total'] as num?)?.toInt() ?? 0,
      downloaded: (json['downloaded'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'queued',
      error: json['error']?.toString(),
      errorKind: json['errorKind']?.toString(),
      errorDetail: json['errorDetail']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: json['nextRetryAt'] == null
          ? null
          : DateTime.tryParse(json['nextRetryAt'].toString()),
      filePath: json['filePath']?.toString(),
      kind: json['kind']?.toString() ?? 'http',
      engine: json['engine']?.toString() ?? 'http',
      formatSelector: json['formatSelector']?.toString(),
      formatId: json['formatId']?.toString(),
      extensionHint: json['extensionHint']?.toString(),
      mediaTitle: json['mediaTitle']?.toString(),
      mediaAuthor: json['mediaAuthor']?.toString(),
      mediaDuration: (json['mediaDuration'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      rangeSupported: json['rangeSupported'] as bool? ?? true,
      etag: json['etag']?.toString(),
      maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
      segmentStart: ints(json['segmentStart']),
      segmentEnd: ints(json['segmentEnd']),
      segmentDone: ints(json['segmentDone']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.tryParse(json['startedAt'].toString()),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
    );
  }
}

/// Owns the on-device queue, its worker slots, and persistence.
class LocalDownloadManager extends ChangeNotifier {
  static const _kTolerance = 1 << 20; // below 1 MiB, segmenting is not worth it

  final Map<String, LocalTask> _byId = {};
  final List<String> _order = [];
  final Map<String, _Run> _runs = {};

  Directory? _root;
  bool _loaded = false;
  bool _disposed = false;
  Timer? _ticker;
  Timer? _retryTimer;
  int _lastActiveForService = 0;

  /// How many downloads may run at once. Surplus tasks wait in the queue.
  int maxConcurrent = 1;

  /// Automatic retry budget applied to new tasks.
  RetryPolicy retryPolicy = const RetryPolicy();

  /// Set while the network or power state forbids starting new transfers.
  bool _networkBlocked = false;

  /// Partial-data root, exposed so the storage panel can size and clean it.
  Directory? get partsRoot =>
      _root == null ? null : Directory('${_root!.path}/parts');

  /// Records finished and failed transfers. Set by the app; null in unit tests
  /// that do not care about history.
  HistoryStore? history;

  /// Local diagnostics sink. Set by the app; null in unit tests.
  Diagnostics? diagnostics;

  /// Called when a download finishes or fails, so the app can notify the user.
  void Function(LocalTask task)? onFinished;

  /// Called when the retry budget is exhausted, for a one-off notification.
  void Function(LocalTask task)? onGaveUp;

  /// Overridden in tests to control where the queue and parts live.
  @visibleForTesting
  set rootOverride(Directory? dir) => _root = dir;

  /// Overridden in tests to avoid the Android MediaStore channel.
  @visibleForTesting
  PublishFn publishOverride = FileStore.publish;

  /// Overridden in tests to avoid the Android foreground-service channel.
  @visibleForTesting
  BackgroundFn backgroundOverride = _deviceBackground;

  /// Overridden in tests so media resolution never reaches YouTube.
  @visibleForTesting
  ResolveMediaFn resolveMediaOverride = _defaultResolve;

  /// Overridden in tests so yt-dlp is never spawned. When null the shared
  /// [ytdlp] engine is used.
  @visibleForTesting
  YtdlpDownloadFn? ytdlpOverride;

  /// Overridden in tests so muxing never reaches the bundled FFmpeg.
  @visibleForTesting
  MediaMuxFn? muxOverride;

  /// The yt-dlp engine, shared with Settings for detection and install help.
  final YtdlpEngine ytdlp = YtdlpEngine();

  /// Merges separate video and audio tracks with the bundled FFmpeg.
  final FfmpegMuxer muxer = FfmpegMuxer();

  /// Segment ceiling for range-capable hosts. Raised by Turbo speed mode.
  int maxConnections = 16;

  static Future<ResolvedMedia> _defaultResolve(
    String pageUrl, {
    String? formatId,
  }) =>
      const MediaExtractor().resolve(pageUrl, formatId: formatId);

  /// Runs [YtdlpEngine.download] with the shared engine (honouring the path
  /// the user configured in Settings).
  Future<File?> _runYtdlp({
    required String url,
    required String selector,
    required Directory dir,
    required String stem,
    void Function(int downloaded, int total, int speed)? onProgress,
    bool Function()? isCancelled,
  }) =>
      ytdlp.download(
        url: url,
        selector: selector,
        dir: dir,
        stem: stem,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

  List<LocalTask> get tasks =>
      _order.map((id) => _byId[id]).whereType<LocalTask>().toList();

  int get activeCount => _byId.values.where((t) => t.isRunning).length;
  int get queuedCount => _byId.values.where((t) => t.isQueued).length;

  /// True while new transfers are held back by the network or power policy.
  bool get networkBlocked => _networkBlocked;

  /// Applies the Wi-Fi-only / battery-aware policy. When [blocked], no new
  /// transfer starts and running ones are paused.
  void setNetworkBlocked(bool blocked) {
    if (_networkBlocked == blocked) return;
    _networkBlocked = blocked;
    if (blocked) {
      pauseAll();
    } else {
      resumeAll();
    }
    _safeNotify();
  }

  /// Total bytes still to fetch across the whole queue.
  int get remainingBytes => _byId.values
      .where((t) => !t.isCompleted)
      .fold(0, (sum, t) => sum + (t.total > 0 ? t.total - t.downloaded : 0));

  Future<void> init() async {
    if (_loaded) return;
    _root ??= await getApplicationSupportDirectory();
    final file = File('${_root!.path}/local_tasks.json');
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        for (final entry in (raw as List).whereType<Map>()) {
          final task = LocalTask.fromJson(Map<String, dynamic>.from(entry));
          // A download cannot have been running while the app was closed, so
          // requeue whatever was in flight and let the worker resume it from
          // the byte offset already recorded.
          if (task.isActive || task.isPreparing) task.status = 'queued';
          task.speed = 0;
          task.nextRetryAt = null;
          _byId[task.id] = task;
          _order.add(task.id);
        }
      } catch (_) {
        // A corrupt queue file should not stop the app from starting.
      }
    }
    _loaded = true;
    await _recoverPartialData();
    _safeNotify();
    _pump();
  }

  /// After a crash, a `.part` file can be longer than the byte count the queue
  /// recorded (a write that landed before the state was persisted), which would
  /// append duplicate bytes on resume. Truncating each part to its recorded
  /// length keeps the merge byte-exact.
  Future<void> _recoverPartialData() async {
    for (final task in _byId.values) {
      if (task.isCompleted) continue;
      final dir = _taskDir(task.id);
      if (dir == null || !await dir.exists()) continue;
      for (var i = 0; i < task.segmentDone.length; i++) {
        final part = File('${dir.path}/part_$i.part');
        if (!await part.exists()) continue;
        try {
          final expected = task.segmentDone[i];
          final actual = await part.length();
          if (actual > expected) {
            final handle = await part.open(mode: FileMode.append);
            await handle.truncate(expected);
            await handle.close();
          }
        } catch (_) {}
      }
    }
  }

  // ------------------------------------------------------------------ public

  LocalTask? task(String id) => _byId[id];

  /// The URL of every task still in the queue (not completed or failed), for
  /// duplicate detection before a new one is added.
  Iterable<String> get pendingUrls => _byId.values
      .where((t) => !t.isCompleted && !t.isFailed)
      .map((t) => t.url);

  /// True when [url] is already queued or running.
  bool isDuplicate(String url) =>
      isDuplicateDownload(url, pendingUrls);

  /// Queues a download and returns its task. The worker starts it if a slot is
  /// free. Direct file links are fetched as-is; media pages are resolved on the
  /// device first (or handed to yt-dlp), then stored here too.
  LocalTask add(
    String url, {
    String? filename,
    int connections = 4,
    String kind = 'http',
    String engine = 'http',
    String? formatSelector,
    String? formatId,
    String? extensionHint,
    String? mediaTitle,
    String? mediaAuthor,
    int? mediaDuration,
    String? thumbnailUrl,
  }) {
    final trimmed = url.trim();
    final id = _newId();
    final task = LocalTask(
      id: id,
      url: trimmed,
      filename: filename?.trim().isNotEmpty == true
          ? filename!.trim()
          : _fallbackName(url),
      connections: connections.clamp(1, 16),
      kind: kind,
      engine: engine,
      formatSelector: formatSelector,
      formatId: formatId,
      extensionHint: extensionHint,
      mediaTitle: mediaTitle,
      mediaAuthor: mediaAuthor,
      mediaDuration: mediaDuration,
      thumbnailUrl: thumbnailUrl,
      maxAttempts: retryPolicy.maxAttempts,
      createdAt: DateTime.now(),
    );
    _byId[id] = task;
    _order.insert(0, id);
    _persist();
    _safeNotify();
    _pump();
    return task;
  }

  /// Queues [url] only when it is not already pending, returning null when it
  /// is a duplicate. This is what the Add screen uses so a link pasted twice is
  /// not downloaded twice.
  LocalTask? addIfNew(
    String url, {
    String? filename,
    int connections = 4,
    String kind = 'http',
    String engine = 'http',
    String? formatSelector,
    String? formatId,
    String? extensionHint,
    String? mediaTitle,
    String? mediaAuthor,
    int? mediaDuration,
    String? thumbnailUrl,
  }) {
    if (isDuplicate(url)) return null;
    return add(
      url,
      filename: filename,
      connections: connections,
      kind: kind,
      engine: engine,
      formatSelector: formatSelector,
      formatId: formatId,
      extensionHint: extensionHint,
      mediaTitle: mediaTitle,
      mediaAuthor: mediaAuthor,
      mediaDuration: mediaDuration,
      thumbnailUrl: thumbnailUrl,
    );
  }

  void pause(String id) {
    final task = _byId[id];
    if (task == null) return;
    _runs[id]?.cancel();
    if (task.isActive || task.isPreparing || task.isQueued) {
      task.status = 'paused';
      task.speed = 0;
      task.nextRetryAt = null;
    }
    _persist();
    _safeNotify();
  }

  void resume(String id) {
    final task = _byId[id];
    if (task == null || task.isCompleted) return;
    task.status = 'queued';
    task.error = null;
    task.errorKind = null;
    task.errorDetail = null;
    task.nextRetryAt = null;
    _persist();
    _safeNotify();
    _pump();
  }

  /// Retries a task by hand, resetting its attempt counter so the automatic
  /// backoff budget is available again.
  void retry(String id) {
    final task = _byId[id];
    if (task == null) return;
    task.attempts = 0;
    resume(id);
  }

  /// Stops the download and forgets it, deleting any partial data.
  Future<void> remove(String id) async {
    final run = _runs[id];
    run?.cancel();
    // Wait for the download loop to stop writing before deleting its folder,
    // otherwise a late chunk can recreate it and leave orphaned partial data.
    if (run != null) await run.done.future;
    final task = _byId[id];
    _byId.remove(id);
    _order.remove(id);
    final dir = _taskDir(id);
    if (dir != null && await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    if (task != null) await _recordHistory(task);
    _persist();
    _safeNotify();
  }

  void pauseAll() {
    for (final id in List.of(_order)) {
      final task = _byId[id];
      if (task != null && (task.isRunning || task.isQueued)) pause(id);
    }
  }

  void resumeAll() {
    for (final id in List.of(_order)) {
      final task = _byId[id];
      if (task != null && (task.isPaused || task.isFailed)) resume(id);
    }
  }

  /// Cancels every queued and running task, keeping them in the list so the
  /// user can restart one later.
  void cancelAll() {
    for (final id in List.of(_order)) {
      final task = _byId[id];
      if (task == null || task.isCompleted || task.isFailed) continue;
      _runs[id]?.cancel();
      task.status = 'paused';
      task.speed = 0;
      task.nextRetryAt = null;
    }
    _persist();
    _safeNotify();
  }

  void clearCompleted() {
    for (final id in List.of(_order)) {
      if (_byId[id]?.isCompleted ?? false) {
        _byId.remove(id);
        _order.remove(id);
      }
    }
    _persist();
    _safeNotify();
  }

  /// Deletes the partial-data folder for a failed or cancelled task, keeping
  /// the task itself so it can be retried. Returns the bytes reclaimed.
  Future<int> clearPartialData(String id) async {
    final dir = _taskDir(id);
    var reclaimed = 0;
    if (dir != null && await dir.exists()) {
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            try {
              reclaimed += await entity.length();
            } catch (_) {}
          }
        }
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    final task = _byId[id];
    if (task != null && task.isFailed) {
      task.segmentStart = const [];
      task.segmentEnd = const [];
      task.segmentDone = const [];
      task.downloaded = 0;
    }
    _persist();
    return reclaimed;
  }

  /// Where a completed file was saved, if it is still present.
  String? filePathOf(String id) => _byId[id]?.filePath;

  // ------------------------------------------------------------------ worker

  /// Starts queued tasks until the concurrency limit is reached. A task waiting
  /// for its backoff window is skipped until its timer fires.
  void _pump() {
    if (_networkBlocked) return;
    final now = DateTime.now();
    for (final id in List.of(_order)) {
      if (_runs.length >= maxConcurrent) break;
      final task = _byId[id];
      if (task == null || !task.isQueued) continue;
      if (task.nextRetryAt != null && task.nextRetryAt!.isAfter(now)) continue;
      _start(task);
    }
    if (_runs.isEmpty) _stopTicker();
  }

  void _start(LocalTask task) {
    final run = _Run();
    _runs[task.id] = run;
    task.status = 'preparing';
    task.error = null;
    task.errorKind = null;
    task.errorDetail = null;
    task.nextRetryAt = null;
    task.startedAt ??= DateTime.now();
    _syncBackground();
    _safeNotify();
    _startTicker();

    _execute(task, run).whenComplete(() {
      if (!run.done.isCompleted) run.done.complete();
      _runs.remove(task.id);
      task.speed = 0;
      _persist();
      _syncBackground();
      _safeNotify();
      _pump();
    });
  }

  /// Tells Android whether a foreground service is needed right now.
  void _syncBackground() {
    final active = _runs.length;
    if (active == _lastActiveForService) return;
    _lastActiveForService = active;
    unawaited(backgroundOverride(active));
  }

  Future<void> _execute(LocalTask task, _Run run) async {
    try {
      await _runTask(task, run);
      if (run.cancelled) return;
      task.status = 'completed';
      task.completedAt = DateTime.now();
      task.attempts = 0;
      unawaited(_recordHistory(task));
      unawaited(diagnostics?.info('download.completed', 'task completed'));
      onFinished?.call(task);
    } catch (e) {
      if (run.cancelled) return;
      await _handleFailure(task, e);
    } finally {
      _persist();
      _safeNotify();
    }
  }

  /// Runs the task on its engine, transparently switching to the other one if
  /// the chosen engine cannot handle the page. yt-dlp and the built-in
  /// extractor fail on different videos, so a YouTube link that one rejects
  /// usually still downloads through the other. The switch happens before the
  /// error reaches [_handleFailure], so the user sees a result, not a failure.
  Future<void> _runTask(LocalTask task, _Run run) async {
    // The external engine manages its own connections and writes into the
    // task's folder; the built-in engine (ranges, resume, multi-connection)
    // handles everything else.
    if (task.usesYtdlp) {
      try {
        await _executeYtdlp(task, run);
      } on YtdlpException {
        if (run.cancelled || task.kind != 'media' || !ytdlp.isAvailable) {
          rethrow;
        }
        // Fall back to the built-in extractor at whatever quality it can
        // produce (its muxed streams cap at 360p).
        task.engine = 'http';
        task.fellBackToBuiltin = true;
        unawaited(diagnostics?.warn(
            'engine.fallback', 'yt-dlp failed; using the built-in engine'));
        await _executeBuiltin(task, run);
      }
      return;
    }

    try {
      await _executeBuiltin(task, run);
    } on MediaResolveException {
      if (run.cancelled || task.kind != 'media' || !ytdlp.isAvailable) rethrow;
      // The built-in extractor could not read the page; yt-dlp covers more
      // cases and can also merge HD renditions.
      task.engine = 'ytdlp';
      task.formatSelector = null;
      unawaited(diagnostics?.warn(
          'engine.fallback', 'built-in extractor failed; using yt-dlp'));
      await _executeYtdlp(task, run);
    }
  }

  /// Turns a thrown error into an actionable state, and schedules an automatic
  /// retry with exponential backoff when the failure is transient and attempts
  /// remain.
  Future<void> _handleFailure(LocalTask task, Object error) async {
    final failure = _classify(error);
    task.error = failure.message;
    task.errorKind = failure.kind.name;
    task.errorDetail = failure.technicalDetails;
    task.attempts += 1;

    unawaited(diagnostics?.error('download.failed', failure.kind.name));

    if (failure.retryable && retryPolicy.shouldRetry(task.attempts)) {
      final delay = retryPolicy.delayFor(task.attempts);
      task.status = 'queued';
      task.nextRetryAt = DateTime.now().add(delay);
      _scheduleRetry(delay);
      return;
    }

    task.status = 'failed';
    task.nextRetryAt = null;
    unawaited(_recordHistory(task));
    onFinished?.call(task);
    if (failure.retryable) onGaveUp?.call(task);
  }

  static DownloadError _classify(Object error) {
    if (error is MediaResolveException) {
      return DownloadError(DownloadErrorKind.media, error.message);
    }
    if (error is MediaMuxException) {
      return DownloadError(
        DownloadErrorKind.mux,
        error.message,
        retryable: true,
      );
    }
    if (error is YtdlpException) {
      return DownloadError(
        DownloadErrorKind.engine,
        error.message,
        retryable: true,
      );
    }
    return DownloadError.from(error);
  }

  void _scheduleRetry(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay + const Duration(milliseconds: 50), _pump);
  }

  /// Appends a finished or failed task to the history store, if one is wired.
  Future<void> _recordHistory(LocalTask task) async {
    final store = history;
    if (store == null) return;
    if (!task.isCompleted && !task.isFailed) return;
    await store.add(HistoryEntry(
      id: task.id,
      url: task.url,
      filename: task.filename,
      status: task.status,
      filePath: task.filePath,
      destination: task.filePath == null ? null : FileStore.subfolderFor(task.filename),
      size: task.total > 0 ? task.total : task.downloaded,
      durationMs: task.durationSeconds == null ? null : task.durationSeconds! * 1000,
      averageSpeed: task.averageSpeed,
      errorKind: task.errorKind,
      errorMessage: task.error,
      finishedAt: task.completedAt ?? DateTime.now(),
    ));
  }

  Future<void> _executeBuiltin(LocalTask task, _Run run) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    // Content-encoding would change byte offsets and break ranged/resumed
    // downloads, so take the raw bytes.
    client.autoUncompress = false;
    try {
      // A media page points at HTML, not a file. Resolve it to the real stream
      // on this device first, then download that URL directly. Only the
      // resolved URL is fetched here; nothing is proxied through a server.
      if (task.kind == 'media') {
        final media =
            await resolveMediaOverride(task.url, formatId: task.formatId);
        task.streamUrl = media.url;
        if (task.filename.isEmpty || task.filename == 'download') {
          task.filename = _mediaName(media);
        } else if (task.extensionHint == null &&
            !task.filename.contains('.')) {
          task.filename = '${task.filename}.${media.extension}';
        }
        if (media.size > 0) task.total = media.size;

        // A video-only rendition above 360p: fetch the video and a separate
        // audio track, then merge them with the bundled FFmpeg. Nothing is
        // re-encoded, and everything still lands on this device.
        if (media.audioUrl != null) {
          await _downloadMuxed(client, task, run, media);
          return;
        }
      }

      final probe = await _probe(client, task.fetchUrl);
      task.rangeSupported = probe.range;
      // Drop bytes from a previous run when the remote resource changed. The
      // `If-Range` header only protects mid-transfer resumes; across sessions
      // the part files on disk may belong to an older version of the file, so
      // compare validators and start over instead of stitching two files.
      final previous = task.etag;
      final changed =
          previous != null && probe.etag != null && previous != probe.etag;
      if (changed && task.segmentDone.any((d) => d > 0)) {
        task.segmentStart = [];
        task.segmentEnd = [];
        task.segmentDone = [];
        task.downloaded = 0;
      }
      task.etag = probe.etag;
      task.filename = _chooseName(task.filename, probe.filename);
      if (probe.total > 0) task.total = probe.total;

      _planSegments(task, probe);
      task.status = 'active';
      await _fetch(client, task, run);
      if (run.cancelled) return;

      final merged = await _merge(task, run);
      if (run.cancelled) return;
      task.downloaded = task.total > 0 ? task.total : task.downloaded;

      final saved = await publishOverride(merged, task.filename);
      task.filePath = saved.path;
      await _cleanupParts(task);
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads a video-only stream and its audio track, then muxes them into
  /// the final container. Progress covers both transfers; the merge itself is
  /// a fast container remux.
  Future<void> _downloadMuxed(
    HttpClient client,
    LocalTask task,
    _Run run,
    ResolvedMedia media,
  ) async {
    final dir = _requireTaskDir(task.id);
    if (!await dir.exists()) await dir.create(recursive: true);

    final videoPath = '${dir.path}/video';
    final audioPath = '${dir.path}/audio';
    final total = media.size > 0 ? media.size : 0;
    if (total > 0) task.total = total;
    task.status = 'active';

    // Fetch the video first, so the audio download reports a rising total
    // rather than double-counting bytes already on disk.
    final videoDone = await _downloadToFile(
      client,
      media.url,
      videoPath,
      run,
      onBytes: (n) {
        task.downloaded = n;
        _safeNotify();
      },
    );
    if (run.cancelled) return;

    await _downloadToFile(
      client,
      media.audioUrl!,
      audioPath,
      run,
      onBytes: (n) {
        task.downloaded = videoDone + n;
        _safeNotify();
      },
    );
    if (run.cancelled) return;

    if (total > 0) task.downloaded = total;

    final container = media.extension.isEmpty ? 'mp4' : media.extension;
    task.filename = _withExtension(task.filename, container, 'out.$container');
    final out = '${dir.path}/.merged';
    final mux = muxOverride ??
        ({
          required String videoPath,
          required String audioPath,
          required String outPath,
          required String container,
        }) =>
            muxer.mux(
              videoPath: videoPath,
              audioPath: audioPath,
              outPath: outPath,
              container: container,
            );
    await mux(
      videoPath: videoPath,
      audioPath: audioPath,
      outPath: out,
      container: container,
    );
    if (run.cancelled) return;

    final merged = File(out);
    final saved = await publishOverride(merged, task.filename);
    task.filePath = saved.path;
    await _cleanupParts(task);
  }

  /// Streams [url] into [path], reporting the running byte count. Uses a
  /// single connection because the caller is already fetching in parallel and
  /// these signed URLs expire quickly.
  Future<int> _downloadToFile(
    HttpClient client,
    String url,
    String path,
    _Run run, {
    required void Function(int bytes) onBytes,
  }) async {
    final file = File(path);
    final req = await _open(client, Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok &&
        res.statusCode != HttpStatus.partialContent) {
      await res.drain<void>();
      throw DownloadErrors.httpStatus(res.statusCode);
    }
    final sink = file.openWrite();
    var done = 0;
    try {
      await for (final chunk in res) {
        if (run.cancelled) break;
        sink.add(chunk);
        done += chunk.length;
        run.addBytes(chunk.length);
        onBytes(done);
      }
    } finally {
      await sink.close();
    }
    return done;
  }

  /// Runs the task through yt-dlp, reporting progress into the same fields the
  /// UI already renders.
  Future<void> _executeYtdlp(LocalTask task, _Run run) async {
    final dir = _requireTaskDir(task.id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final stem = _safeStem(task.filename);
    final selector = task.formatSelector ?? 'best';
    final run_ = ytdlpOverride ?? _runYtdlp;
    task.status = 'active';

    final file = await run_(
      url: task.url,
      selector: selector,
      dir: dir,
      stem: stem,
      isCancelled: () => run.cancelled,
      onProgress: (downloaded, total, speed) {
        task.downloaded = downloaded;
        if (total > 0) task.total = total;
        task.speed = speed;
        _safeNotify();
      },
    );
    if (run.cancelled) return;
    if (file == null) {
      throw const YtdlpException('The engine produced no file.');
    }

    task.filename = _withExtension(task.filename, task.extensionHint, file.path);
    task.downloaded = task.total > 0 ? task.total : await file.length();
    final saved = await publishOverride(file, task.filename);
    task.filePath = saved.path;
    await _cleanupParts(task);
  }

  /// Opens a request with the shared browser-like headers. Every engine
  /// request (probe, segment, muxed track) goes through here so a host that
  /// rejects the default dart:io agent does not 403 one path but not another.
  Future<HttpClientRequest> _open(HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    // `autoUncompress` is off, so ask for an identity body explicitly: a
    // transparently gzipped reply would shift byte offsets and break ranged
    // and resumed downloads.
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    return req;
  }

  Future<_Probe> _probe(HttpClient client, String url) async {
    final uri = Uri.parse(url);

    // HEAD is free and tells us length, range support, and often the filename.
    try {
      final head = await client.headUrl(uri);
      head.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      head.headers.set(HttpHeaders.acceptHeader, '*/*');
      head.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await head.close();
      final name =
          _nameFromDisposition(res.headers.value('content-disposition'));
      final range = res.headers
              .value(HttpHeaders.acceptRangesHeader)
              ?.toLowerCase() ==
          'bytes';
      // dart:io reports an unknown length as -1, never null.
      final len = res.contentLength;
      final known = len >= 0;
      await res.drain<void>();
      if (res.statusCode == HttpStatus.ok && (known || range)) {
        return _Probe(
          total: known ? len : 0,
          range: range,
          filename: name,
          etag: _validatorFrom(res.headers),
        );
      }
    } catch (_) {
      // Some servers reject HEAD; fall through to a ranged GET.
    }

    final req = await _open(client, uri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final res = await req.close();
    final status = res.statusCode;
    final name = _nameFromDisposition(res.headers.value('content-disposition'));

    if (status == HttpStatus.partialContent) {
      final total = _totalFromContentRange(
          res.headers.value(HttpHeaders.contentRangeHeader));
      final etag = _validatorFrom(res.headers);
      await res.drain<void>();
      return _Probe(total: total, range: true, filename: name, etag: etag);
    }

    if (status == HttpStatus.ok) {
      final len = res.contentLength;
      final etag = _validatorFrom(res.headers);
      await res.drain<void>();
      return _Probe(
        total: len >= 0 ? len : 0,
        range: false,
        filename: name,
        etag: etag,
      );
    }

    await res.drain<void>();
    throw HttpException('Server responded ${res.statusCode}');
  }

  void _planSegments(LocalTask task, _Probe probe) {
    final known = probe.total > 0;
    final wantSegments = probe.range && known && probe.total > _kTolerance;

    if (wantSegments) {
      final n = min(task.connections, _maxSegments(probe.total));

      // Keep the existing plan when it still matches so a resumed task asks
      // only for the bytes it is missing. Re-planning from zero would append
      // duplicates into the part files.
      final resumable = task.segmentDone.length == n &&
          task.segmentStart.length == n &&
          task.total == probe.total &&
          task.segmentStart.first == 0 &&
          task.segmentEnd.last == probe.total - 1;
      if (resumable) return;

      final size = (probe.total / n).floor();
      task.segmentStart = [];
      task.segmentEnd = [];
      task.segmentDone = [];
      for (var i = 0; i < n; i++) {
        final start = i * size;
        final end = i == n - 1 ? probe.total - 1 : (start + size - 1);
        task.segmentStart.add(start);
        task.segmentEnd.add(end);
        task.segmentDone.add(0);
      }
      return;
    }

    // Single connection. A fresh task starts with an unknown length, which
    // becomes concrete once the response arrives.
    if (task.segmentDone.length != 1) {
      task.segmentStart = [0];
      task.segmentEnd = [-1];
      task.segmentDone = [0];
    } else if (known && task.total != probe.total) {
      task.segmentEnd = [probe.total - 1];
      task.segmentDone = [0];
    } else if (known) {
      task.segmentEnd = [probe.total - 1];
    }
  }

  Future<void> _fetch(HttpClient client, LocalTask task, _Run run) async {
    final dir = _requireTaskDir(task.id);
    if (!await dir.exists()) await dir.create(recursive: true);

    Future<void> fetchOne(int index) async {
      if (run.cancelled) return;
      final start = task.segmentStart[index];
      final end = task.segmentEnd[index];
      var done = index < task.segmentDone.length ? task.segmentDone[index] : 0;

      final req = await _open(client, Uri.parse(task.fetchUrl));
      // Ask only for the bytes still missing. `end < 0` means the length is
      // unknown, so an open-ended range from the resume point is used.
      if (done > 0 || end >= 0) {
        final to = end >= 0 ? '$end' : '';
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=${start + done}-$to');
      }
      // Resuming mid-file: bind the range to the validator seen at probe time.
      // If the file changed, the server ignores the range and replies 200,
      // which the `restarted` branch below turns into a clean restart.
      final etag = task.etag;
      if (done > 0 && etag != null) {
        req.headers.set(HttpHeaders.ifRangeHeader, etag);
      }
      final res = await req.close();

      // A server can ignore our Range and reply 200 with the whole body. That
      // is only usable from offset zero, so restart the part rather than
      // appending a full copy onto bytes we already have.
      final restarted = res.statusCode == HttpStatus.ok && done > 0;
      if (restarted && etag != null) {
        // We sent `If-Range` and still got the full body, so the resource
        // changed underneath this transfer. Restarting one segment would
        // splice two versions together, so fail and let the next attempt
        // detect the new validator and reset cleanly from zero.
        await res.drain<void>();
        throw DownloadErrors.fileChanged;
      }
      if (res.statusCode == HttpStatus.ok &&
          end >= 0 &&
          res.contentLength == end + 1 &&
          index != 0) {
        await res.drain<void>();
        throw DownloadErrors.rangeIgnored(index);
      } else if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await res.drain<void>();
        throw DownloadErrors.fileChanged;
      } else if (res.statusCode != HttpStatus.ok &&
          res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        throw DownloadErrors.httpStatus(res.statusCode);
      }
      if (restarted) done = 0;

      final part = File('${dir.path}/part_$index.part');
      final sink = part.openWrite(
          mode: restarted || done == 0 ? FileMode.write : FileMode.append);
      try {
        await for (final chunk in res) {
          if (run.cancelled) break;
          sink.add(chunk);
          done += chunk.length;
          task.segmentDone[index] = done;
          task.downloaded = task.segmentDone.fold<int>(0, (a, b) => a + b);
          run.addBytes(chunk.length);
        }
      } finally {
        await sink.close();
      }

      if (!run.cancelled && end >= 0 && done != end - start + 1) {
        throw DownloadErrors.endedEarly(end - start + 1, done);
      }
    }

    final futures = <Future<void>>[];
    for (var i = 0; i < task.segmentStart.length; i++) {
      futures.add(fetchOne(i));
    }
    await Future.wait(futures);
    run.flush(task);
  }

  Future<File> _merge(LocalTask task, _Run run) async {
    final dir = _requireTaskDir(task.id);
    final out = File('${dir.path}/.merged');
    if (await out.exists()) await out.delete();
    final sink = out.openWrite();
    try {
      for (var i = 0; i < task.segmentStart.length; i++) {
        final part = File('${dir.path}/part_$i.part');
        if (!await part.exists()) continue;
        final reader = part.openRead();
        await for (final chunk in reader) {
          if (run.cancelled) break;
          sink.add(chunk);
        }
      }
    } finally {
      await sink.close();
    }
    return out;
  }

  Future<void> _cleanupParts(LocalTask task) async {
    final dir = _taskDir(task.id);
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ helpers

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 600), (_) {
      for (final run in _runs.values) {
        for (final t in run.tasks) {
          t.speed = run.speed();
        }
      }
      _safeNotify();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Directory? _taskDir(String id) =>
      _root == null ? null : Directory('${_root!.path}/parts/$id');

  /// The task's scratch folder, or a clear storage error when the root is not
  /// ready. The worker can run before [init] finishes (a queued task started
  /// from a restored queue, for instance), so this must never assume the root
  /// exists — that previously tripped a null-check and reported the opaque
  /// "The download stopped unexpectedly."
  Directory _requireTaskDir(String id) {
    final dir = _taskDir(id);
    if (dir == null) throw DownloadErrors.storageUnavailable;
    return dir;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _persist() {
    final root = _root;
    if (root == null) return;
    try {
      final file = File('${root.path}/local_tasks.json');
      final encoded = _order
          .map((id) => _byId[id])
          .whereType<LocalTask>()
          .map((t) => t.toJson())
          .toList();
      file.writeAsStringSync(jsonEncode(encoded));
    } catch (_) {}
  }

  int _maxSegments(int total) => max(1, min(maxConnections, total ~/ (1 << 19)));

  static int _totalFromContentRange(String? header) {
    // "bytes 0-0/12345"
    if (header == null) return 0;
    final slash = header.indexOf('/');
    if (slash < 0) return 0;
    return int.tryParse(header.substring(slash + 1).trim()) ?? 0;
  }

  static String? _nameFromDisposition(String? header) {
    if (header == null) return null;
    final match = RegExp('filename\\*?=(?:UTF-8\'\')?"?([^";]+)"?',
            caseSensitive: false)
        .firstMatch(header);
    return match?.group(1);
  }

  static String _chooseName(String current, String? fromHeaders) {
    if (current.isNotEmpty && current != 'download') return current;
    if (fromHeaders != null && fromHeaders.isNotEmpty) return fromHeaders;
    return current;
  }

  static String _fallbackName(String url) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isNotEmpty && path.last.isNotEmpty) return path.last;
    } catch (_) {}
    return 'download';
  }

  /// A filesystem-safe stem (no extension) for a yt-dlp output template.
  static String _safeStem(String filename) {
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    final cleaned = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  /// Ensures [filename] carries the container the file actually has.
  static String _withExtension(String filename, String? hint, String filePath) {
    var base = filename;
    final dot = base.lastIndexOf('.');
    final fileExt = _extensionOf(filePath);
    if (dot <= 0) {
      final ext = fileExt.isNotEmpty
          ? fileExt
          : (hint != null && hint.isNotEmpty ? hint : 'bin');
      return '$base.$ext';
    }
    // Replace a generic/incorrect hint with the real container.
    if (fileExt.isNotEmpty && base.substring(dot + 1).toLowerCase() != fileExt) {
      base = '${base.substring(0, dot)}.$fileExt';
    }
    return base;
  }

  static String _extensionOf(String path) {
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Builds a safe filename from a resolved media title and container.
  static String _mediaName(ResolvedMedia media) {
    final base = media.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stem = base.isEmpty ? 'media' : base;
    final ext = media.extension.isEmpty ? 'mp4' : media.extension;
    return '$stem.$ext';
  }

  String _newId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${r.nextInt(1 << 20).toRadixString(36)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    _retryTimer?.cancel();
    for (final run in _runs.values) {
      run.cancel();
    }
    _lastActiveForService = 0;
    unawaited(backgroundOverride(0));
    super.dispose();
  }
}

class _Probe {
  final int total;
  final bool range;
  final String? filename;

  /// Validator for [total]: the strong `ETag` if the server sent one, else
  /// `Last-Modified`. Sent back as `If-Range` on a resumed request so the
  /// server refuses the range (416) instead of splicing a changed file.
  final String? etag;
  const _Probe({
    required this.total,
    required this.range,
    this.filename,
    this.etag,
  });
}

/// Picks a resource validator for `If-Range`. A weak `ETag` (`W/"…"`) is not a
/// valid `If-Range` value, so fall back to `Last-Modified` in that case.
String? _validatorFrom(HttpHeaders headers) {
  final etag = headers.value('etag');
  if (etag != null && !etag.trimLeft().startsWith('W/')) return etag.trim();
  return headers.value(HttpHeaders.lastModifiedHeader)?.trim();
}

/// Cancellation flag plus a rolling speed window for one active download.
class _Run {
  bool cancelled = false;
  final List<LocalTask> tasks = [];
  int _totalBytes = 0;
  int _lastSampleBytes = 0;
  DateTime _lastSampleAt = DateTime.now();

  void cancel() => cancelled = true;

  /// Completed once the download loop for this run has fully unwound, so
  /// callers can delete the task folder without a writer recreating it.
  final Completer<void> done = Completer<void>();

  void addBytes(int n) => _totalBytes += n;

  /// Bytes per second, sampled over the window since the previous call.
  int speed() {
    final now = DateTime.now();
    final ms = now.difference(_lastSampleAt).inMilliseconds;
    if (ms < 250) return 0;
    final delta = _totalBytes - _lastSampleBytes;
    _lastSampleBytes = _totalBytes;
    _lastSampleAt = now;
    return (delta * 1000 / ms).round();
  }

  void flush(LocalTask task) {
    if (task.total > 0) task.downloaded = task.total;
    task.speed = 0;
  }
}
