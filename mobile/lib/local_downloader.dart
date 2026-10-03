import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'file_store.dart';
import 'media_extractor.dart';
import 'ytdlp.dart';

// `ResolvedMedia`/`MediaResolveException` appear in the manager's public API
// (the resolver hook and its errors), so re-export them for callers.
export 'media_extractor.dart'
    show MediaExtractor, MediaFormat, MediaInfo, MediaResolveException, ResolvedMedia;

// The yt-dlp engine types cross the manager boundary for the UI and resolver.
export 'ytdlp.dart' show YtdlpEngine, YtdlpException, YtdlpFormat, YtdlpProbe;

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
  String status; // queued | active | paused | completed | failed
  String? error;
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

  List<int> segmentStart;
  List<int> segmentEnd;
  List<int> segmentDone;
  final DateTime createdAt;
  DateTime? completedAt;

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
    List<int>? segmentStart,
    List<int>? segmentEnd,
    List<int>? segmentDone,
    required this.createdAt,
    this.completedAt,
  })  : segmentStart = segmentStart ?? const [],
        segmentEnd = segmentEnd ?? const [],
        segmentDone = segmentDone ?? const [];

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isQueued => status == 'queued';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get canOpen => isCompleted && (filePath?.isNotEmpty ?? false);

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
        'segmentStart': segmentStart,
        'segmentEnd': segmentEnd,
        'segmentDone': segmentDone,
        'createdAt': createdAt.toIso8601String(),
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
      segmentStart: ints(json['segmentStart']),
      segmentEnd: ints(json['segmentEnd']),
      segmentDone: ints(json['segmentDone']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
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
  int _lastActiveForService = 0;

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

  /// The yt-dlp engine, shared with Settings for detection and install help.
  final YtdlpEngine ytdlp = YtdlpEngine();

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

  int get activeCount => _byId.values.where((t) => t.isActive).length;
  int get queuedCount => _byId.values.where((t) => t.isQueued).length;

  Future<void> init() async {
    if (_loaded) return;
    _root ??= await getApplicationSupportDirectory();
    final file = File('${_root!.path}/local_tasks.json');
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        for (final entry in (raw as List).whereType<Map>()) {
          final task = LocalTask.fromJson(Map<String, dynamic>.from(entry));
          // A download cannot have been running while the app was closed.
          if (task.isActive) task.status = 'paused';
          task.speed = 0;
          _byId[task.id] = task;
          _order.add(task.id);
        }
      } catch (_) {
        // A corrupt queue file should not stop the app from starting.
      }
    }
    _loaded = true;
    _safeNotify();
    _pump();
  }

  // ------------------------------------------------------------------ public

  LocalTask? task(String id) => _byId[id];

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
    final id = _newId();
    final task = LocalTask(
      id: id,
      url: url.trim(),
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
      createdAt: DateTime.now(),
    );
    _byId[id] = task;
    _order.insert(0, id);
    _persist();
    _safeNotify();
    _pump();
    return task;
  }

  void pause(String id) {
    final task = _byId[id];
    if (task == null) return;
    _runs[id]?.cancel();
    if (task.isActive || task.isQueued) {
      task.status = 'paused';
      task.speed = 0;
    }
    _persist();
    _safeNotify();
  }

  void resume(String id) {
    final task = _byId[id];
    if (task == null || task.isCompleted) return;
    task.status = 'queued';
    task.error = null;
    _persist();
    _safeNotify();
    _pump();
  }

  void retry(String id) => resume(id);

  /// Stops the download and forgets it, deleting any partial data.
  Future<void> remove(String id) async {
    _runs[id]?.cancel();
    _byId.remove(id);
    _order.remove(id);
    final dir = _taskDir(id);
    if (dir != null && await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    _persist();
    _safeNotify();
  }

  void pauseAll() {
    for (final id in List.of(_order)) {
      if (_byId[id]!.isActive || _byId[id]!.isQueued) pause(id);
    }
  }

  void resumeAll() {
    for (final id in List.of(_order)) {
      if (_byId[id]!.isPaused || _byId[id]!.isFailed) resume(id);
    }
  }

  void clearCompleted() {
    for (final id in List.of(_order)) {
      if (_byId[id]!.isCompleted) {
        _byId.remove(id);
        _order.remove(id);
      }
    }
    _persist();
    _safeNotify();
  }

  /// Where a completed file was saved, if it is still present.
  String? filePathOf(String id) => _byId[id]?.filePath;

  // ------------------------------------------------------------------ worker

  void _pump() {
    if (_runs.isNotEmpty) return;
    final next = _order
        .map((id) => _byId[id]!)
        .where((t) => t.isQueued)
        .toList();
    if (next.isEmpty) return;
    final task = next.first;
    final run = _Run();
    _runs[task.id] = run;
    task.status = 'active';
    task.error = null;
    _syncBackground();
    _safeNotify();
    _startTicker();

    _execute(task, run).whenComplete(() {
      _runs.remove(task.id);
      task.speed = 0;
      _persist();
      _syncBackground();
      _safeNotify();
      if (_runs.isEmpty) _stopTicker();
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
      // The external engine is a separate program that manages its own
      // connections and writes into the task's folder; the built-in engine
      // (ranges, resume, multi-connection) handles everything else.
      if (task.usesYtdlp) {
        await _executeYtdlp(task, run);
        return;
      }
      await _executeBuiltin(task, run);
    } catch (e) {
      if (run.cancelled) return;
      task.status = 'failed';
      task.error = _friendly(e);
    } finally {
      _persist();
      _safeNotify();
    }
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
      }

      final probe = await _probe(client, task.fetchUrl);
      task.filename = _chooseName(task.filename, probe.filename);
      if (probe.total > 0) task.total = probe.total;

      _planSegments(task, probe);
      await _fetch(client, task, run);
      if (run.cancelled) return;

      final merged = await _merge(task, run);
      if (run.cancelled) return;
      task.downloaded = task.total > 0 ? task.total : task.downloaded;

      final saved = await publishOverride(merged, task.filename);
      task.filePath = saved.path;
      task.status = 'completed';
      task.completedAt = DateTime.now();
      await _cleanupParts(task);
    } finally {
      client.close(force: true);
    }
  }

  /// Runs the task through yt-dlp, reporting progress into the same fields the
  /// UI already renders.
  Future<void> _executeYtdlp(LocalTask task, _Run run) async {
    final dir = _taskDir(task.id)!;
    if (!await dir.exists()) await dir.create(recursive: true);
    final stem = _safeStem(task.filename);
    final selector = task.formatSelector ?? 'best';
    final run_ = ytdlpOverride ?? _runYtdlp;

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
    task.status = 'completed';
    task.completedAt = DateTime.now();
    await _cleanupParts(task);
  }

  Future<_Probe> _probe(HttpClient client, String url) async {
    final uri = Uri.parse(url);

    // HEAD is free and tells us length, range support, and often the filename.
    try {
      final head = await client.headUrl(uri);
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
        return _Probe(total: known ? len : 0, range: range, filename: name);
      }
    } catch (_) {
      // Some servers reject HEAD; fall through to a ranged GET.
    }

    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final res = await req.close();
    final status = res.statusCode;
    final name = _nameFromDisposition(res.headers.value('content-disposition'));

    if (status == HttpStatus.partialContent) {
      final total = _totalFromContentRange(
          res.headers.value(HttpHeaders.contentRangeHeader));
      await res.drain<void>();
      return _Probe(total: total, range: true, filename: name);
    }

    if (status == HttpStatus.ok) {
      final len = res.contentLength;
      await res.drain<void>();
      return _Probe(total: len >= 0 ? len : 0, range: false, filename: name);
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
    final dir = _taskDir(task.id)!;
    if (!await dir.exists()) await dir.create(recursive: true);

    Future<void> fetchOne(int index) async {
      if (run.cancelled) return;
      final start = task.segmentStart[index];
      final end = task.segmentEnd[index];
      var done = index < task.segmentDone.length ? task.segmentDone[index] : 0;

      final req = await client.getUrl(Uri.parse(task.fetchUrl));
      // Ask only for the bytes still missing. `end < 0` means the length is
      // unknown, so an open-ended range from the resume point is used.
      if (done > 0 || end >= 0) {
        final to = end >= 0 ? '$end' : '';
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=${start + done}-$to');
      }
      final res = await req.close();

      // A server can ignore our Range and reply 200 with the whole body. That
      // is only usable from offset zero, so restart the part rather than
      // appending a full copy onto bytes we already have.
      final restarted = res.statusCode == HttpStatus.ok && done > 0;
      if (res.statusCode == HttpStatus.ok &&
          end >= 0 &&
          res.contentLength == end + 1 &&
          index != 0) {
        await res.drain<void>();
        throw HttpException(
            'Server ignored range requests for segment ${index + 1}');
      } else if (res.statusCode != HttpStatus.ok &&
          res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        throw HttpException('Server responded ${res.statusCode}');
      }
      if (restarted) done = 0;

      final part = File('${dir.path}/part_$index');
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
        throw const HttpException('Connection ended early');
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
    final dir = _taskDir(task.id)!;
    final out = File('${dir.path}/.merged');
    if (await out.exists()) await out.delete();
    final sink = out.openWrite();
    try {
      for (var i = 0; i < task.segmentStart.length; i++) {
        final part = File('${dir.path}/part_$i');
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

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _persist() {
    final root = _root;
    if (root == null) return;
    try {
      final file = File('${root.path}/local_tasks.json');
      file.writeAsStringSync(
          jsonEncode(_order.map((id) => _byId[id]!.toJson()).toList()));
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

  static String _friendly(Object e) {
    if (e is MediaResolveException) return e.message;
    if (e is YtdlpException) return e.message;
    if (e is SocketException) {
      return 'Network error. Check your connection.';
    }
    if (e is HttpException) return e.message;
    if (e is HandshakeException) return 'Secure connection failed.';
    return e.toString();
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
  const _Probe({required this.total, required this.range, this.filename});
}

/// Cancellation flag plus a rolling speed window for one active download.
class _Run {
  bool cancelled = false;
  final List<LocalTask> tasks = [];
  int _totalBytes = 0;
  int _lastSampleBytes = 0;
  DateTime _lastSampleAt = DateTime.now();

  void cancel() => cancelled = true;

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
