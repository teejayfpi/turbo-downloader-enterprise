import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/local_downloader.dart';

/// A task can be queued before the manager's storage root is ready (for
/// example, while `init()` is still recovering the queue, or if it failed).
/// The worker must fail such a task with a clear, actionable storage error
/// rather than tripping the `_taskDir(...)!` null-check and reporting the
/// opaque "The download stopped unexpectedly."
void main() {
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

