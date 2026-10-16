@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/ytdlp.dart';

/// End-to-end checks against the real YouTube endpoints through the yt-dlp
/// engine (the desktop path). Opt in with:
///   TURBO_LIVE=1 flutter test test/live_ytdlp_test.dart
/// Skipped by default so the normal suite (and CI) never depends on a network
/// call to YouTube or on yt-dlp being installed.
void main() {
  const url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  final live = Platform.environment['TURBO_LIVE'] == '1';
  // Some videos are bot-checked for an anonymous datacenter IP; allow a
  // different one to be supplied when probing by hand.
  final target = Platform.environment['TURBO_LIVE_URL'] ?? url;

  bool blocked(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('refused to serve') ||
        message.contains('sign in to confirm') ||
        message.contains('is unavailable') ||
        message.contains('not a bot');
  }

  test('the engine probes real formats and downloads bytes', () async {
    final engine = YtdlpEngine();
    if (await engine.locate() == null) {
      markTestSkipped('yt-dlp is not installed on this machine');
      return;
    }

    final YtdlpProbe probe;
    try {
      probe = await engine.probe(target);
    } catch (error) {
      if (blocked(error)) {
        markTestSkipped('YouTube blocked this network: $error');
        return;
      }
      rethrow;
    }
    // ignore: avoid_print
    print('TITLE: ${probe.title}');
    // ignore: avoid_print
    print('FORMATS: ${probe.formats.length}, '
        'kinds=${probe.formats.map((f) => f.kind).toSet()}');
    expect(probe.title, isNotEmpty);
    expect(probe.formats, isNotEmpty);

    // Prefer a small, single-file rendition so the test stays quick; fall back
    // to the engine default.
    final pick = probe.formats
        .where((f) => f.kind == 'audio')
        .cast<YtdlpFormat?>()
        .firstWhere((_) => true, orElse: () => null);
    final selector = pick?.selector ?? YtdlpEngine.defaultSelector;

    final dir = Directory.systemTemp.createTempSync('turbo_live_ytdlp');
    try {
      final started = DateTime.now();
      final file = await engine.download(
        url: target,
        selector: selector,
        dir: dir,
        stem: 'probe',
        concurrentFragments: 16,
      );
      final elapsed = DateTime.now().difference(started);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      final size = file.lengthSync();
      // ignore: avoid_print
      print('DOWNLOADED: ${file.path} ($size bytes) via "$selector" '
          'in ${elapsed.inMilliseconds}ms');
      expect(size, greaterThan(100000));
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)), skip: !live);
}
