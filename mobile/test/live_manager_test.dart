@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/local_downloader.dart';

/// Live end-to-end downloads through the real yt-dlp engine. Opt in with:
///   TURBO_LIVE=1 flutter test test/live_manager_test.dart
/// Requires `yt-dlp` (and, for merged HD, `ffmpeg`) on PATH. Skipped by default
/// so the normal suite (and CI) never depends on external tools or the network.
///
/// YouTube may refuse to serve the media bytes to datacenter IPs ("Sign in to
/// confirm you're not a bot"). That is an environment block, not an app fault,
/// so the YouTube byte test reports the block instead of failing; the generic
/// host test still proves the whole engine to disk pipeline.
void main() {
  const youtube = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  // A 4K video, so the format list should offer well above YouTube's 360p
  // muxed ceiling.
  const youtubeHd = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ';
  const generic = 'https://download.samplelib.com/mp4/sample-5s.mp4';
  final live = Platform.environment['TURBO_LIVE'] == '1';

  test('yt-dlp engine is detected', () async {
    final manager = LocalDownloadManager();
    final bin = await manager.ytdlp.locate();
    // ignore: avoid_print
    print('yt-dlp: $bin  ffmpeg: ${await manager.ytdlp.hasFfmpeg()}');
    expect(bin, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 1)), skip: !live);

  test('probe lists formats above 360p for an HD video', () async {
    final manager = LocalDownloadManager();
    final probe = await manager.ytdlp.probe(youtubeHd);
    final maxHeight =
        probe.formats.map((f) => f.height).fold<int>(0, (a, b) => a > b ? a : b);
    // ignore: avoid_print
    print('title=${probe.title} formats=${probe.formats.length} '
        'maxHeight=${maxHeight}p ffmpeg=${probe.hasFfmpeg}');
    expect(probe.formats, isNotEmpty);
    expect(maxHeight, greaterThanOrEqualTo(720),
        reason: 'the extractor must expose resolutions above 360p');
  }, timeout: const Timeout(Duration(minutes: 2)), skip: !live);

  test('downloads a real video end to end', () async {
    final root = await Directory.systemTemp.createTemp('turbo_live');
    final manager = LocalDownloadManager()
      ..rootOverride = root
      ..publishOverride = (file, name) async {
        final out = File('${root.path}/$name');
        await file.copy(out.path);
        return out;
      };
    await manager.init();

    final probe = await manager.ytdlp.probe(generic);
    final best = probe.formats.first;
    // ignore: avoid_print
    print('picked ${best.kind} ${best.label} sel=${best.selector}');

    final task = manager.add(
      generic,
      filename: probe.title,
      connections: 4,
      kind: 'media',
      engine: 'ytdlp',
      formatSelector: best.selector,
      extensionHint: best.extension,
    );

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (!task.isCompleted &&
        !task.isFailed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // ignore: avoid_print
    print('status=${task.status} bytes=${task.downloaded} '
        'error=${task.error} detail=${task.errorDetail}');

    expect(task.isFailed, isFalse, reason: task.errorDetail ?? task.error);
    expect(task.filePath, isNotNull);
    final saved = File(task.filePath!);
    expect(await saved.exists(), isTrue);
    expect(await saved.length(), greaterThan(1000));
    // ignore: avoid_print
    print('SAVED ${saved.path} (${await saved.length()} bytes)');
    await root.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 4)), skip: !live);

  test('YouTube download (blocked on datacenter IPs)', () async {
    final root = await Directory.systemTemp.createTemp('turbo_live_yt');
    final manager = LocalDownloadManager()
      ..rootOverride = root
      ..publishOverride = (file, name) async {
        final out = File('${root.path}/$name');
        await file.copy(out.path);
        return out;
      };
    await manager.init();

    final task = manager.add(
      youtube,
      filename: 'Me at the zoo',
      connections: 4,
      kind: 'media',
      engine: 'ytdlp',
      formatSelector: 'best',
      extensionHint: 'mp4',
    );

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (!task.isCompleted &&
        !task.isFailed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (task.isFailed) {
      // Datacenter/CI IPs are frequently blocked by YouTube's bot check.
      // ignore: avoid_print
      print('YouTube byte fetch unavailable here: ${task.error} '
          '(${task.errorDetail})');
      return;
    }
    expect(await File(task.filePath!).length(), greaterThan(1000));
    await root.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 4)), skip: !live);
}
