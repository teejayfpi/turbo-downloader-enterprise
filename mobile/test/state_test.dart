import 'package:flutter_test/flutter_test.dart';

import 'package:turbo_downloader/media_extractor.dart';
import 'package:turbo_downloader/media_url.dart';
import 'package:turbo_downloader/services/youtube_browser.dart';
import 'package:turbo_downloader/state.dart';

BrowseVideo _video(String id) => BrowseVideo(
      id: id,
      title: 'Video $id',
      author: 'Channel',
      channelId: 'UC123',
      thumbnailUrl: 'https://img.youtube.com/vi/$id/mqdefault.jpg',
    );

MediaInfo _info(String title) => MediaInfo(
      title: title,
      author: 'Channel',
      formats: const [
        MediaFormat(
          id: 'muxed:720p:mp4',
          label: '720p',
          kind: 'video',
          extension: 'mp4',
          size: 100,
        ),
      ],
    );

void main() {
  group('TurboState is device-only', () {
    test('starts with no server, token, or account', () {
      final state = TurboState();
      addTearDown(state.dispose);

      // There is nothing to configure before downloading: no base URL, no key.
      expect(state.defaultConnections, 4);
      expect(state.accentKey, 'cyan');
      expect(state.playSound, isTrue);
      expect(state.local.tasks, isEmpty);
    });
  });

  group('media routing', () {
    test('a media page is detected so it is queued for on-device resolve', () {
      expect(isMediaUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isMediaUrl('https://example.com/file.zip'), isFalse);
    });
  });

  group('batch queueing', () {
    test('queues every video and reports the totals', () async {
      final state = TurboState();
      addTearDown(state.dispose);
      state.describeOverride = (url) async => _info('Probed title');

      final result = await state.addBatch(
        [_video('a'), _video('b'), _video('c')],
      );

      expect(result.total, 3);
      expect(result.queued, 3);
      expect(result.duplicates, 0);
      expect(state.local.tasks.length, 3);
      expect(result.summary, contains('3 queued'));
    });

    test('a duplicate link inside one batch is queued only once', () async {
      final state = TurboState();
      addTearDown(state.dispose);

      // probeLimit 0 keeps the loop synchronous, so the second sighting of the
      // same watch URL is still pending and is caught as a duplicate.
      final result = await state.addBatch(
        [_video('a'), _video('a'), _video('b')],
        probeLimit: 0,
      );

      expect(result.queued, 2);
      expect(result.duplicates, 1);
      expect(state.local.tasks.length, 2);
      expect(result.summary, contains('1 already queued'));
    });

    test('a probe failure still queues the video for on-device resolve',
        () async {
      final state = TurboState();
      addTearDown(state.dispose);
      var calls = 0;
      state.describeOverride = (url) async {
        calls++;
        throw const MediaResolveException('nope');
      };

      final result = await state.addBatch([_video('a')]);

      // Probe attempted, but the task is queued anyway.
      expect(calls, 1);
      expect(result.queued, 1);
      expect(state.local.tasks.single.url,
          'https://www.youtube.com/watch?v=a');
    });

    test('only the first probeLimit links are inspected up front', () async {
      final state = TurboState();
      addTearDown(state.dispose);
      var calls = 0;
      state.describeOverride = (url) async {
        calls++;
        return _info('Probed');
      };

      await state.addBatch(
        List.generate(8, (i) => _video('v$i')),
        probeLimit: 3,
      );

      expect(calls, 3);
      expect(state.local.tasks.length, 8);
    });
  });
}
