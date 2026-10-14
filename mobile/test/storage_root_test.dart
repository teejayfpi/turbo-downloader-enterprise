import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:turbo_downloader/local_downloader.dart';

/// A path_provider stand-in whose support and temp directories are
/// unavailable, standing in for a restricted install, a locked-down desktop,
/// or a build where the plugin channel is missing.
class _UnavailablePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw Exception('support directory unavailable');

  @override
  Future<String?> getTemporaryPath() async =>
      throw Exception('temp directory unavailable');
}

/// A provider whose support directory exists but cannot be written to, as on
/// a restricted install.
class _ReadOnlyPathProvider extends PathProviderPlatform {
  _ReadOnlyPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<bool> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

/// A reachable origin, so any failure is the storage layer and not the network.
Future<HttpServer> _origin() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = 4
      ..add([1, 2, 3, 4]);
    await req.response.close();
  });
  return server;
}

/// A task can be queued before the manager's storage root is ready (for
/// example, while `init()` is still recovering the queue, or if it failed).
/// The worker must fail such a task with a clear, actionable storage error
/// rather than tripping the `_taskDir(...)!` null-check and reporting the
/// opaque "The download stopped unexpectedly."
void main() {
  final originalProvider = PathProviderPlatform.instance;
  tearDown(() => PathProviderPlatform.instance = originalProvider);

  test('a task still downloads when the support directory is unavailable',
      () async {
    PathProviderPlatform.instance = _UnavailablePathProvider();

    final server = await _origin();
    addTearDown(() => server.close(force: true));

    // Keep the fallback inside this test's temp space, not the real HOME.
    final scratch = await Directory.systemTemp.createTemp('turbo_fallback');
    addTearDown(() => scratch.delete(recursive: true));

    final manager = LocalDownloadManager();
    manager.envRootPathOverride = () => '${scratch.path}/data';
    manager.tempDirOverride = () async => scratch;
    // Move the finished file out of the scratch area, the way publishing does.
    manager.publishOverride = (file, name) async {
      final dir = Directory('${scratch.path}/published');
      if (!await dir.exists()) await dir.create(recursive: true);
      return file.rename('${dir.path}/$name');
    };

    // init() must survive the unavailable support directory and settle on a
    // usable root, so a normal download then completes instead of failing.
    await manager.init();
    final task = manager.add('http://127.0.0.1:${server.port}/x.bin',
        filename: 'x.bin');

    final done = await _waitFor(() => task.isCompleted || task.isFailed);
    expect(done, isTrue, reason: 'task did not settle: ${task.status}');
    expect(task.isCompleted, isTrue,
        reason: 'expected completion, got ${task.error}');
    expect(task.error, isNull);
    expect(task.filePath, isNotNull);
    expect(await File(task.filePath!).exists(), isTrue);
    manager.dispose();
  });

  test('a read-only support directory falls back to a writable root',
      () async {
    final scratch = await Directory.systemTemp.createTemp('turbo_readonly');
    addTearDown(() => scratch.delete(recursive: true));

    final locked = Directory('${scratch.path}/support');
    await locked.create();
    // Best effort: as root this still writes, but the test still holds because
    // the download completes either way.
    await Process.run('chmod', ['555', locked.path]);
    PathProviderPlatform.instance = _ReadOnlyPathProvider(locked.path);

    final server = await _origin();
    addTearDown(() => server.close(force: true));

    final manager = LocalDownloadManager();
    manager.envRootPathOverride = () => '${scratch.path}/fallback';
    manager.tempDirOverride = () async => scratch;
    manager.publishOverride = (file, name) async {
      final dir = Directory('${scratch.path}/published');
      if (!await dir.exists()) await dir.create(recursive: true);
      return file.rename('${dir.path}/$name');
    };

    await manager.init();
    expect(manager.isInitialized, isTrue);
    expect(manager.partsRoot, isNotNull);

    final task = manager.add('http://127.0.0.1:${server.port}/x.bin',
        filename: 'x.bin');
    final done = await _waitFor(() => task.isCompleted || task.isFailed);
    expect(done, isTrue, reason: 'task did not settle: ${task.status}');
    expect(task.isCompleted, isTrue, reason: 'got ${task.error}');
    manager.dispose();
  });

  test('a task started with no storage root reports a storage error', () async {
    // A reachable origin, so the failure is the missing root and not the
    // network.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 4
        ..add([1, 2, 3, 4]);
      await req.response.close();
    });

    final manager = LocalDownloadManager();
    manager.publishOverride = (file, name) async => file;
    // Deliberately skip init(): the root is still null when the worker starts.
    final task = manager.add('http://127.0.0.1:${server.port}/x.bin',
        filename: 'x.bin');

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!task.isFailed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(task.isFailed, isTrue);
    expect(task.errorDetail ?? '', isNot(contains('Null check operator')));
    expect(task.error, isNotNull);
    expect(task.error!.toLowerCase(), contains('storage'));
    manager.dispose();
  });
}

