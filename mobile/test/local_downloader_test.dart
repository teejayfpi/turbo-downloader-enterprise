import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/local_downloader.dart';

/// Serves a byte blob over real HTTP, with configurable range support, so the
/// engine is exercised end to end rather than against a mock.
class _Origin {
  final List<int> data;
  final bool supportRange;
  final bool advertiseAcceptRanges;
  final int? throttle;
  HttpServer? _server;

  _Origin(
    this.data, {
    this.supportRange = true,
    this.advertiseAcceptRanges = true,
    this.throttle,
  });

  String get url =>
      'http://127.0.0.1:${_server!.port}/payload.bin';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final total = data.length;

    if (req.method == 'HEAD') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = total;
      if (advertiseAcceptRanges && supportRange) {
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }
      await req.response.close();
      return;
    }

    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && supportRange) {
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
          ..headers.contentLength = slice.length
          ..add(slice);
        await req.response.close();
        return;
      }
    }

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = total;
    if (throttle != null) {
      const chunk = 16 * 1024;
      for (var i = 0; i < data.length; i += chunk) {
        final end = min(i + chunk, data.length);
        req.response.add(data.sublist(i, end));
        await req.response.flush();
        await Future.delayed(Duration(milliseconds: throttle!));
      }
    } else {
      req.response.add(data);
    }
    await req.response.close();
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
}
