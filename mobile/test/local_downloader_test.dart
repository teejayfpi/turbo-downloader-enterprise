import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/local_downloader.dart';
import 'package:turbo_downloader/services/retry_policy.dart';

/// Serves a byte blob over real HTTP, with configurable range support, so the
/// engine is exercised end to end rather than against a mock.
class _Origin {
  List<int> data;
  final bool supportRange;
  final bool advertiseAcceptRanges;
  final int? throttle;

  /// When true, any request whose User-Agent is missing or contains "dart"
  /// (the bare dart:io default) is answered 403, the way many CDNs reject it.
  final bool rejectDartAgent;

  /// Resource validator advertised as `ETag`. Mutable so a test can simulate
  /// the remote file changing between attempts.
  String? etag;

  /// The last `If-Range` header the server saw, for assertions.
  String? lastIfRange;

  /// Session headers the origin saw on the most recent request.
  String? lastCookie;
  String? lastReferer;

  /// When true, a request without a `Cookie` is answered 403, standing in for
  /// a site that gates the file behind a login.
  bool requireCookie;

  HttpServer? _server;

  _Origin(
    this.data, {
    this.supportRange = true,
    this.advertiseAcceptRanges = true,
    this.throttle,
    this.rejectDartAgent = false,
    this.etag,
    this.requireCookie = false,
  });

  /// Replaces the served bytes and their validator, as a redeployed file would.
  void mutate(List<int> newData, {String? newEtag}) {
    data = newData;
    etag = newEtag;
  }

  String get url =>
      'http://127.0.0.1:${_server!.port}/payload.bin';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  void _setValidator(HttpHeaders headers) {
    if (etag != null) headers.set('etag', etag!);
  }

  Future<void> _handle(HttpRequest req) async {
    final total = data.length;
    final ifRange = req.headers.value(HttpHeaders.ifRangeHeader);
    if (ifRange != null) lastIfRange = ifRange;
    lastCookie = req.headers.value('cookie');
    lastReferer = req.headers.value('referer');
    if (requireCookie && (lastCookie == null || lastCookie!.isEmpty)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    if (rejectDartAgent) {
      final agent = req.headers.value(HttpHeaders.userAgentHeader) ?? '';
      if (agent.isEmpty || agent.toLowerCase().contains('dart')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
    }

    if (req.method == 'HEAD') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = total;
      _setValidator(req.response.headers);
      if (advertiseAcceptRanges && supportRange) {
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }
      await req.response.close();
      return;
    }

    final range = req.headers.value(HttpHeaders.rangeHeader);
    // A ranged request carrying a stale `If-Range` must be answered with the
    // full body (200), exactly as a real origin does.
    final staleIfRange = ifRange != null && ifRange != etag;
    if (range != null && supportRange && !staleIfRange) {
      final match =
          RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final end = match.group(2)!.isEmpty
            ? total - 1
            : min(int.parse(match.group(2)!), total - 1);
        final slice = data.sublist(start, end + 1);
        req.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
              HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total')
          ..headers.contentLength = slice.length;
        _setValidator(req.response.headers);
        await _writeThrottled(req.response, slice);
        await req.response.close();
        return;
      }
    }

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = total;
    _setValidator(req.response.headers);
    await _writeThrottled(req.response, data);
    await req.response.close();
  }

  /// Writes [body], paced by [throttle] when set. Ranged and full responses
  /// both use this so a test can hold a transfer open long enough to watch
  /// the engine adapt.
  Future<void> _writeThrottled(
      HttpResponse response, List<int> body) async {
    if (throttle == null) {
      response.add(body);
      return;
    }
    const chunk = 16 * 1024;
    for (var i = 0; i < body.length; i += chunk) {
      final end = min(i + chunk, body.length);
      response.add(body.sublist(i, end));
      await response.flush();
      await Future.delayed(Duration(milliseconds: throttle!));
    }
  }
}

List<int> _blob(int size) {
  final r = Random(7);
  return List<int>.generate(size, (_) => r.nextInt(256));
}

Future<bool> _waitFor(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return true;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

Future<LocalDownloadManager> _manager(Directory root) async {
  final manager = LocalDownloadManager();
  manager.rootOverride = root;
  // Mirrors what MediaStore does: move the finished file out of the scratch
  // area so the part-directory cleanup cannot remove it.
  manager.publishOverride = (file, name) async {
    final dir = Directory('${root.path}/published');
    if (!await dir.exists()) await dir.create(recursive: true);
    return file.rename('${dir.path}/$name');
  };
  await manager.init();
  return manager;
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('turbo_local_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('downloads a ranged file with several segments and stores exact bytes',
      () async {
    final data = _blob(3 * 1024 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'big.bin', connections: 4);
    final done = await _waitFor(() => task.isCompleted || task.isFailed);

    expect(done, isTrue, reason: 'task did not settle: ${task.status}');
    expect(task.error, isNull);
    expect(task.isCompleted, isTrue);
    expect(task.segmentStart.length, greaterThan(1),
        reason: 'a 3 MiB file should have been segmented');
    expect(task.filePath, isNotNull);

    final saved = File(task.filePath!);
    expect(await saved.readAsBytes(), equals(data));
  });

  test('adaptive ramp-up widens the plan when the host is fast', () async {
    // A host that delivers quickly should be pushed toward the requested
    // width. The transfer must still assemble the exact bytes while the plan
    // grows underneath it.
    final data = _blob(8 * 1024 * 1024);
    final origin = _Origin(data, throttle: 2)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.adaptiveConnections = true;
    manager.initialSegments = 2;
    manager.rampWindow = const Duration(milliseconds: 80);
    manager.rampMinBytesPerSecond = 32 * 1024;

    final task = manager.add(origin.url, filename: 'fast.bin', connections: 6);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(task.segmentStart.length, greaterThan(2),
        reason: 'a fast host should have earned more connections');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('adaptive ramp-up holds the initial width on a slow host', () async {
    // Raising the throughput bar above what the host delivers must leave the
    // plan at its starting width: no extra connections, no byte mistakes.
    final data = _blob(2 * 1024 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.adaptiveConnections = true;
    manager.initialSegments = 2;
    manager.rampWindow = const Duration(milliseconds: 60);
    manager.rampMinBytesPerSecond = 500 * 1024 * 1024;

    final task = manager.add(origin.url, filename: 'slow.bin', connections: 6);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(task.segmentStart.length, 2,
        reason: 'a slow host should not be handed more connections');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('resumes a partially ramped download without duplicating bytes',
      () async {
    // Ramp-up appends split segments out of array order; a pause and resume in
    // the middle must keep that partition intact instead of re-planning.
    final data = _blob(4 * 1024 * 1024);
    final origin = _Origin(data, throttle: 3)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.adaptiveConnections = true;
    manager.initialSegments = 2;
    manager.rampWindow = const Duration(milliseconds: 80);
    manager.rampMinBytesPerSecond = 32 * 1024;

    final task = manager.add(origin.url, filename: 'ramped.bin', connections: 5);
    await _waitFor(() => task.downloaded > 0 && task.segmentStart.length > 2);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);

    final width = task.segmentStart.length;
    manager.resume(task.id);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    // Resume must keep the ramped partition (it may legitimately widen
    // further), never fall back to the two-segment starting plan.
    expect(task.segmentStart.length, greaterThanOrEqualTo(width));
    expect(task.segmentStart.length, greaterThan(2));
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('remembers a fast host and starts the next download wide', () async {
    final data = _blob(8 * 1024 * 1024);
    final origin = _Origin(data, throttle: 2)..start();
    addTearDown(origin.stop);
    final root = await Directory.systemTemp.createTemp('turbo_host_test');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final manager = await _manager(root);
    manager.adaptiveConnections = true;
    manager.rememberHostSpeed = true;
    manager.initialSegments = 2;
    manager.rampWindow = const Duration(milliseconds: 80);
    manager.rampMinBytesPerSecond = 32 * 1024;

    final first =
        manager.add(origin.url, filename: 'one.bin', connections: 6);
    await _waitFor(() => first.isCompleted || first.isFailed);
    expect(first.isCompleted, isTrue, reason: first.error ?? '');
    final learned = first.segmentStart.length;
    expect(learned, greaterThan(2), reason: 'host should have earned width');

    // Simulate a restart: a fresh manager reading the persisted memory.
    manager.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final restarted = await _manager(root);
    addTearDown(restarted.dispose);
    restarted.adaptiveConnections = true;
    restarted.rememberHostSpeed = true;
    restarted.initialSegments = 2;

    final second =
        restarted.add(origin.url, filename: 'two.bin', connections: 6);
    await _waitFor(() => second.isCompleted || second.isFailed);
    expect(second.isCompleted, isTrue, reason: second.error ?? '');
    expect(second.segmentStart.length, greaterThan(2),
        reason: 'a remembered host should start wider than the default');
    expect(await File(second.filePath!).readAsBytes(), equals(data));
  });

  test('does not remember a slow host', () async {
    final data = _blob(2 * 1024 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.adaptiveConnections = true;
    manager.rememberHostSpeed = true;
    manager.initialSegments = 2;
    manager.rampWindow = const Duration(milliseconds: 60);
    manager.rampMinBytesPerSecond = 500 * 1024 * 1024;

    final task = manager.add(origin.url, filename: 'slow.bin', connections: 6);
    await _waitFor(() => task.isCompleted || task.isFailed);
    expect(task.isCompleted, isTrue, reason: task.error ?? '');

    final memory = File('${root.path}/host_speed.json');
    expect(await memory.exists() && (await memory.readAsString()).isNotEmpty,
        isFalse,
        reason: 'a host that never ramped should not be written down');
  });

  test('off-peak window logic handles normal, wrap, and empty windows', () {
    // Normal window 01:00–07:00.
    expect(LocalDownloadManager.withinWindow(60, 60, 420), isTrue);
    expect(LocalDownloadManager.withinWindow(419, 60, 420), isTrue);
    expect(LocalDownloadManager.withinWindow(420, 60, 420), isFalse);
    expect(LocalDownloadManager.withinWindow(59, 60, 420), isFalse);
    expect(LocalDownloadManager.withinWindow(0, 60, 420), isFalse);

    // Wrapping window 22:00–06:00.
    expect(LocalDownloadManager.withinWindow(1320, 1320, 360), isTrue);
    expect(LocalDownloadManager.withinWindow(1380, 1320, 360), isTrue);
    expect(LocalDownloadManager.withinWindow(30, 1320, 360), isTrue);
    expect(LocalDownloadManager.withinWindow(360, 1320, 360), isFalse);
    expect(LocalDownloadManager.withinWindow(720, 1320, 360), isFalse);

    // A zero-length window is always open, so a stray value cannot wedge the
    // queue.
    expect(LocalDownloadManager.withinWindow(0, 300, 300), isTrue);
    expect(LocalDownloadManager.withinWindow(1439, 300, 300), isTrue);
  });

  test('off-peak scheduling holds a queued download until the window opens',
      () async {
    final data = _blob(1024 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.maxConcurrent = 1;

    final now = DateTime.now();
    final minuteOfDay = now.hour * 60 + now.minute;
    // A window that opens well after now, so the task is held.
    manager.setOffPeakSchedule(
      enabled: true,
      startMinute: (minuteOfDay + 30) % 1440,
      endMinute: (minuteOfDay + 90) % 1440,
    );
    expect(manager.scheduleHold, isTrue);
    expect(manager.holdingNewTransfers, isTrue);

    final task = manager.add(origin.url, filename: 'later.bin', connections: 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(task.isQueued, isTrue, reason: 'the schedule should hold it');
    expect(task.downloaded, 0);

    // Open the window around now; the worker should pick the task up. The
    // bounds are widened so a clock tick mid-test cannot fall outside the
    // (end-exclusive) window.
    final openMinute = DateTime.now().hour * 60 + DateTime.now().minute;
    manager.setOffPeakSchedule(
      enabled: true,
      startMinute: (openMinute - 5 + 1440) % 1440,
      endMinute: (openMinute + 5) % 1440,
    );
    expect(manager.scheduleHold, isFalse);

    await _waitFor(() => task.isCompleted || task.isFailed);
    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('disabling the schedule releases a held download immediately',
      () async {
    final data = _blob(1024 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final now = DateTime.now();
    final minuteOfDay = now.hour * 60 + now.minute;
    manager.setOffPeakSchedule(
      enabled: true,
      startMinute: (minuteOfDay + 30) % 1440,
      endMinute: (minuteOfDay + 90) % 1440,
    );
    final task = manager.add(origin.url, filename: 'off.bin', connections: 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(task.isQueued, isTrue);

    manager.setOffPeakSchedule(enabled: false, startMinute: 0, endMinute: 1);
    expect(manager.scheduleHold, isFalse);

    await _waitFor(() => task.isCompleted || task.isFailed);
    expect(task.isCompleted, isTrue, reason: task.error ?? '');
  });

  test('falls back to one connection when the server ignores ranges', () async {
    final data = _blob(2 * 1024 * 1024);
    final origin = _Origin(data, supportRange: false, advertiseAcceptRanges: false)
      ..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'flat.bin', connections: 8);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue);
    expect(task.segmentStart.length, 1);
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('sends a browser User-Agent so a picky host does not 403', () async {
    // The bare dart:io default agent is rejected by many CDNs. The engine must
    // present a conventional one on every request (probe, segments and the
    // muxed track path), or the download fails as "server refused access".
    final data = _blob(2 * 1024 * 1024);
    final origin = _Origin(data, rejectDartAgent: true)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'agent.bin', connections: 4);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue,
        reason: 'a browser-like agent should be accepted: ${task.error}');
    expect(task.error, isNull);
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('handles a server that ignores Range but advertises support', () async {
    final data = _blob(2 * 1024 * 1024);
    // Lying server: says it accepts ranges upfront, then returns full bodies.
    final origin = _Origin(data, supportRange: false)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'liar.bin', connections: 4);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue,
        reason: 'a misbehaving server should not corrupt or hang the download');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('downloads a file whose length is unknown up front', () async {
    final data = _blob(300 * 1024);
    final origin = _Origin(data, supportRange: false, advertiseAcceptRanges: false)
      ..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'unknown.bin');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue);
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('resumes from stored progress without duplicating bytes', () async {
    final data = _blob(600 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'resume.bin', connections: 2);

    // Let it get going, then pause and record the layout.
    await _waitFor(() => task.downloaded > 0);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);

    final marks = List<int>.from(task.segmentDone);
    expect(marks.any((m) => m > 0), isTrue,
        reason: 'expected some progress before pausing');

    manager.resume(task.id);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    // Resume must continue the same part file. If progress were reset, the
    // second pass would append a full copy and the saved bytes would be wrong.
    expect(task.segmentStart.length, 1);
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('persists the queue and reloads it paused', () async {
    final data = _blob(1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final first = await _manager(root);
    final task = first.add(origin.url, filename: 'kept.bin', connections: 2);
    await _waitFor(() => task.isCompleted || task.isFailed);
    expect(task.isCompleted, isTrue);
    final id = task.id;
    first.dispose();

    final second = await _manager(root);
    addTearDown(second.dispose);
    final restored = second.task(id);
    expect(restored, isNotNull);
    expect(restored!.filename, 'kept.bin');
    expect(restored.isCompleted, isTrue);
  });

  test('starts the foreground service while downloading and stops after',
      () async {
    final data = _blob(600 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final calls = <int>[];
    manager.backgroundOverride = (active) async => calls.add(active);

    final task = manager.add(origin.url, filename: 'svc.bin', connections: 2);
    await _waitFor(() => calls.contains(1));
    expect(calls, contains(1), reason: 'service should start with a transfer');

    await _waitFor(() => task.isCompleted || task.isFailed);
    await _waitFor(() => calls.isNotEmpty && calls.last == 0);
    expect(calls.last, 0, reason: 'service should stop once idle');
  });

  test('records a friendly error when the host is unreachable', () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add('http://127.0.0.1:1/nope.bin', filename: 'x.bin');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    expect(task.error, isNotNull);
  });

  test('removing a task deletes its partial data', () async {
    final data = _blob(600 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'gone.bin', connections: 2);
    await _waitFor(() => task.downloaded > 0);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);

    final parts = Directory('${root.path}/parts/${task.id}');
    await manager.remove(task.id);

    expect(manager.task(task.id), isNull);
    expect(await parts.exists(), isFalse);

    final raw = File('${root.path}/local_tasks.json').readAsStringSync();
    expect(jsonDecode(raw), isEmpty);
  });

  test('resolves a media page on-device then downloads and saves it', () async {
    final data = _blob(2 * 1024 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    var resolved = 0;
    manager.resolveMediaOverride = (page, {String? formatId}) async {
      resolved++;
      // The page URL is a YouTube link; the phone must never fetch it directly.
      expect(page, contains('youtube.com'));
      return ResolvedMedia(
        url: origin.url,
        title: 'Launch / Recap',
        extension: 'mp4',
        size: data.length,
        qualityLabel: '360p',
        kind: 'video',
      );
    };

    final task = manager.add('https://youtube.com/watch?v=abc123',
        filename: 'download', connections: 4, kind: 'media');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(resolved, 1);
    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    // The page URL is kept (so resume can re-resolve), the stream URL is only
    // held in memory, and the file is named from the media title with
    // filesystem-unsafe characters replaced.
    expect(task.url, 'https://youtube.com/watch?v=abc123');
    expect(task.streamUrl, origin.url);
    expect(task.filename, 'Launch _ Recap.mp4');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('resuming a media task re-resolves instead of reusing a stale stream',
      () async {
    final data = _blob(600 * 1024);
    final origin = _Origin(data, throttle: 20)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    var resolved = 0;
    manager.resolveMediaOverride = (page, {String? formatId}) async {
      resolved++;
      return ResolvedMedia(
        url: origin.url,
        title: 'Clip',
        extension: 'mp4',
        size: data.length,
        qualityLabel: '360p',
        kind: 'video',
      );
    };

    final task = manager.add('https://youtube.com/watch?v=clip', kind: 'media');
    await _waitFor(() => task.downloaded > 0);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);

    manager.resume(task.id);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(resolved, greaterThanOrEqualTo(2),
        reason: 'each start should resolve the page again');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('media resolution failure is surfaced as a friendly task error',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);

    manager.resolveMediaOverride = (page, {String? formatId}) async =>
        throw const MediaResolveException('Video unavailable');

    final task = manager.add('https://youtube.com/watch?v=gone',
        kind: 'media');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    expect(task.error, 'Video unavailable');
  });

  test('a yt-dlp task streams progress, saves the file, and skips resolution',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);

    // The built-in resolver must not be touched for a yt-dlp task.
    manager.resolveMediaOverride =
        (page, {String? formatId}) async => throw StateError('should not resolve');

    String? seenUrl;
    String? seenSelector;
    final bytes = _blob(512 * 1024);
    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async {
      seenUrl = url;
      seenSelector = selector;
      onProgress?.call(bytes.length ~/ 2, bytes.length, 4096);
      final f = File('${dir.path}/$stem.mkv');
      await f.writeAsBytes(bytes);
      return f;
    };

    final task = manager.add(
      'https://vimeo.com/12345',
      filename: 'My Clip',
      kind: 'media',
      engine: 'ytdlp',
      formatSelector: 'bestvideo+bestaudio',
    );
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(seenUrl, 'https://vimeo.com/12345');
    expect(seenSelector, 'bestvideo+bestaudio');
    expect(task.filename, 'My Clip.mkv');
    expect(await File(task.filePath!).readAsBytes(), equals(bytes));
  });

  test('progress-only yt-dlp failures surface as a friendly task error',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);

    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async =>
        throw const YtdlpException('Video unavailable');

    final task = manager.add('https://vimeo.com/gone',
        kind: 'media', engine: 'ytdlp', formatSelector: 'best');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    expect(task.error, 'Video unavailable');
  });

  test('a transient yt-dlp 403 is retried, then gives actionable advice',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);
    // Keep the backoff tiny so the test does not wait on real seconds.
    manager.retryPolicy = const RetryPolicy(
      maxAttempts: 2,
      baseDelay: Duration(milliseconds: 10),
      maxDelay: Duration(milliseconds: 20),
    );

    var calls = 0;
    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async {
      calls += 1;
      throw const YtdlpException(
        'The site refused to serve this download (HTTP 403).',
        detail: 'ERROR: unable to download video data: HTTP Error 403: '
            'Forbidden',
      );
    };

    final task = manager.add('https://youtube.com/watch?v=blocked',
        kind: 'media', engine: 'ytdlp', formatSelector: 'best');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    expect(task.errorKind, 'engine');
    // A 403 from the media host is often temporary, so it is retried up to the
    // policy limit before giving up — not stopped after a single attempt.
    expect(calls, 2);
    expect(task.attempts, 2);
    expect(task.errorAdvice, contains('Retry'));
    expect(task.errorDetail, contains('HTTP Error 403'));
  });

  test('a yt-dlp failure falls back to the built-in engine for a media page',
      () async {
    final data = _blob(300 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);
    // Pretend yt-dlp is installed so the fallback is allowed to trigger.
    manager.ytdlp.setBinaryForTest('/bin/true');

    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async =>
        throw const YtdlpException('HTTP Error 403: Forbidden');

    manager.resolveMediaOverride = (page, {String? formatId}) async =>
        ResolvedMedia(
          url: origin.url,
          title: 'Fallback Clip',
          extension: 'mp4',
          size: data.length,
          qualityLabel: '360p',
          kind: 'video',
        );

    final task = manager.add('https://youtube.com/watch?v=fb',
        kind: 'media', engine: 'ytdlp', formatSelector: 'best');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(task.fellBackToBuiltin, isTrue);
    expect(task.engine, 'http');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('a missing-format failure does not silently fall back to 360p',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.ytdlp.setBinaryForTest('/bin/true');

    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async =>
        throw const YtdlpException(
          'Requested format is not available. Use --list-formats for a list '
          'of available formats',
        );

    var resolved = false;
    manager.resolveMediaOverride = (page, {String? formatId}) async {
      resolved = true;
      throw const MediaResolveException('should not run');
    };

    final task = manager.add('https://youtube.com/watch?v=fmt',
        kind: 'media', engine: 'ytdlp', formatSelector: 'bestvideo+bestaudio');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    // The user asked for a specific rendition; a format that does not exist
    // must surface, not be swapped for a different one behind their back.
    expect(resolved, isFalse);
    expect(task.fellBackToBuiltin, isFalse);
    expect(task.engine, 'ytdlp');
  });

  test('a built-in resolve failure falls back to yt-dlp for a media page',
      () async {
    final manager = await _manager(root);
    addTearDown(manager.dispose);
    manager.ytdlp.setBinaryForTest('/bin/true');

    manager.resolveMediaOverride = (page, {String? formatId}) async =>
        throw const MediaResolveException('Video unavailable');

    final bytes = _blob(256 * 1024);
    manager.ytdlpOverride = ({
      required String url,
      required String selector,
      required Directory dir,
      required String stem,
      void Function(int, int, int)? onProgress,
      bool Function()? isCancelled,
    }) async {
      final f = File('${dir.path}/$stem.mp4');
      await f.writeAsBytes(bytes);
      return f;
    };

    final task = manager.add('https://youtube.com/watch?v=fb2',
        kind: 'media');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(task.engine, 'ytdlp');
    expect(await File(task.filePath!).readAsBytes(), equals(bytes));
  });

  test('a direct link is never sent through the extractor', () async {
    final data = _blob(256 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    var resolved = 0;
    manager.resolveMediaOverride = (page, {String? formatId}) async {
      resolved++;
      throw StateError('should not be called for a direct link');
    };

    final task = manager.add(origin.url, filename: 'file.bin');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(resolved, 0);
    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('a video-only rendition downloads both tracks and merges them',
      () async {
    final video = _blob(700 * 1024);
    final audio = _blob(120 * 1024);
    final videoOrigin = _Origin(video)..start();
    final audioOrigin = _Origin(audio)..start();
    addTearDown(videoOrigin.stop);
    addTearDown(audioOrigin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    // A 1080p video-only pick resolves to the video stream plus an audio track.
    manager.resolveMediaOverride = (page, {String? formatId}) async {
      expect(formatId, 'video:1080p:mp4');
      return ResolvedMedia(
        url: videoOrigin.url,
        title: 'Keynote',
        extension: 'mp4',
        size: video.length + audio.length,
        qualityLabel: '1080p',
        kind: 'video',
        audioUrl: audioOrigin.url,
        audioExtension: 'm4a',
        audioSize: audio.length,
      );
    };

    String? seenVideo;
    String? seenAudio;
    String? seenContainer;
    manager.muxOverride = ({
      required String videoPath,
      required String audioPath,
      required String outPath,
      required String container,
    }) async {
      seenVideo = videoPath;
      seenAudio = audioPath;
      seenContainer = container;
      // Stand in for FFmpeg: prove both tracks were fetched to disk, then
      // concatenate them into the merged output.
      final v = await File(videoPath).readAsBytes();
      final a = await File(audioPath).readAsBytes();
      await File(outPath).writeAsBytes([...v, ...a]);
    };

    final task = manager.add(
      'https://youtube.com/watch?v=hd',
      filename: 'Keynote',
      kind: 'media',
      formatId: 'video:1080p:mp4',
      extensionHint: 'mp4',
    );
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(seenVideo, isNotNull);
    expect(seenAudio, isNotNull);
    expect(seenContainer, 'mp4');
    expect(task.filename, 'Keynote.mp4');
    // Progress covered both transfers.
    expect(task.total, video.length + audio.length);
    expect(task.downloaded, video.length + audio.length);
    expect(await File(task.filePath!).readAsBytes(),
        equals([...video, ...audio]));
  });

  test('a merge failure is reported as an actionable mux error', () async {
    final video = _blob(200 * 1024);
    final audio = _blob(60 * 1024);
    final videoOrigin = _Origin(video)..start();
    final audioOrigin = _Origin(audio)..start();
    addTearDown(videoOrigin.stop);
    addTearDown(audioOrigin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    manager.resolveMediaOverride = (page, {String? formatId}) async =>
        ResolvedMedia(
          url: videoOrigin.url,
          title: 'Clip',
          extension: 'mp4',
          size: video.length + audio.length,
          qualityLabel: '720p',
          kind: 'video',
          audioUrl: audioOrigin.url,
          audioExtension: 'm4a',
          audioSize: audio.length,
        );
    manager.muxOverride = ({
      required String videoPath,
      required String audioPath,
      required String outPath,
      required String container,
    }) async =>
        throw const MediaMuxException('Could not merge the tracks.');

    final task = manager.add('https://youtube.com/watch?v=hd',
        kind: 'media', formatId: 'video:720p:mp4');
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isFailed, isTrue);
    expect(task.error, 'Could not merge the tracks.');
    expect(task.errorKind, 'mux');
  });

  test('sends If-Range with the stored validator when resuming', () async {
    final data = _blob(600 * 1024);
    final origin = _Origin(data, throttle: 20, etag: '"v1"')..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'cond.bin', connections: 1);
    await _waitFor(() => task.downloaded > 0);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);
    expect(task.etag, '"v1"');

    manager.resume(task.id);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(origin.lastIfRange, '"v1"',
        reason: 'a resumed transfer must pin the range to the validator');
    expect(await File(task.filePath!).readAsBytes(), equals(data));
  });

  test('restarts cleanly when the remote file changed between attempts',
      () async {
    final first = _blob(400 * 1024);
    final origin = _Origin(first, throttle: 20, etag: '"v1"')..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(origin.url, filename: 'swap.bin', connections: 1);
    await _waitFor(() => task.downloaded > 0);
    manager.pause(task.id);
    await _waitFor(() => !task.isActive);
    expect(task.segmentDone.any((d) => d > 0), isTrue);

    // The origin redeploys a different file under the same URL.
    final second = _blob(512 * 1024);
    origin.mutate(second, newEtag: '"v2"');

    manager.resume(task.id);
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    // The stale bytes must have been discarded: the saved file is wholly the
    // new version, not a splice of the two.
    expect(await File(task.filePath!).readAsBytes(), equals(second));
  });

  test('sends session headers on every request and persists them', () async {
    final data = _blob(80 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(
      origin.url,
      filename: 'gated.bin',
      connections: 1,
      headers: {'Cookie': 'sid=abc123', 'Referer': 'https://site.example/x'},
    );
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(origin.lastCookie, 'sid=abc123',
        reason: 'the session cookie must reach the origin');
    expect(origin.lastReferer, 'https://site.example/x',
        reason: 'the referer must reach the origin');

    // The session survives a restart so a resumed transfer stays authenticated.
    final reloaded = LocalDownloadManager();
    reloaded.rootOverride = root;
    await reloaded.init();
    addTearDown(reloaded.dispose);
    expect(reloaded.task(task.id)?.headers['Cookie'], 'sid=abc123');
  });

  test('drops headers the engine owns, and CR/LF injection', () async {
    final data = _blob(40 * 1024);
    final origin = _Origin(data)..start();
    addTearDown(origin.stop);

    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final task = manager.add(
      origin.url,
      filename: 'sanitized.bin',
      connections: 1,
      headers: {
        'Cookie': 'sid=ok',
        'User-Agent': 'evil',
        'Range': 'bytes=0-1',
        'Accept-Encoding': 'gzip',
        'X-Trace': 'a\r\nInjected: 1',
        'Bad Name': 'x',
      },
    );
    await _waitFor(() => task.isCompleted || task.isFailed);

    expect(task.isCompleted, isTrue, reason: task.error ?? '');
    expect(task.headers.keys, contains('Cookie'));
    expect(task.headers.keys, isNot(contains('User-Agent')));
    expect(task.headers.keys, isNot(contains('Range')));
    expect(task.headers.keys, isNot(contains('Accept-Encoding')));
    expect(task.headers.keys, isNot(contains('X-Trace')),
        reason: 'a CR/LF value must be dropped, not forwarded');
    expect(task.headers.keys, isNot(contains('Bad Name')));
    expect(origin.lastCookie, 'sid=ok');
  });

  test('a gated origin fails without the session and succeeds with it',
      () async {
    final data = _blob(50 * 1024);

    final locked = _Origin(data, requireCookie: true)..start();
    addTearDown(locked.stop);
    final manager = await _manager(root);
    addTearDown(manager.dispose);

    final unauth = manager.add(locked.url, filename: 'no-cookie.bin', connections: 1);
    await _waitFor(() => unauth.isCompleted || unauth.isFailed);
    expect(unauth.isFailed, isTrue,
        reason: 'a 403 must surface as a failure, not a silent success');

    final authed = manager.add(
      locked.url,
      filename: 'cookie.bin',
      connections: 1,
      headers: {'Cookie': 'sid=abc123'},
    );
    await _waitFor(() => authed.isCompleted || authed.isFailed);
    expect(authed.isCompleted, isTrue, reason: authed.error ?? '');
    expect(await File(authed.filePath!).readAsBytes(), equals(data));
  });
}
