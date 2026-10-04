import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:turbo_downloader/media_extractor.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

final _videoId = yt.VideoId('dQw4w9WgXcQ');
final _url = Uri.parse('https://example.com/stream');
yt.Video _video() => yt.Video(
      _videoId,
      'Test clip',
      'Test channel',
      yt.ChannelId('UCsXVk37bltHxD1rDPwtNM8Q'),
      null,
      null,
      null,
      'description',
      const Duration(seconds: 90),
      yt.ThumbnailSet(_videoId.value),
      const ['clip'],
      const yt.Engagement(1000, 10, 1),
      false,
    );

yt.MuxedStreamInfo _muxed(int tag, int height, yt.StreamContainer container) =>
    yt.MuxedStreamInfo(
      _videoId,
      tag,
      _url,
      container,
      yt.FileSize(1024 * 1024 * tag),
      const yt.Bitrate(700000),
      'mp4a.40.2',
      'avc1.42001e',
      '${height}p',
      yt.VideoQuality.medium360,
      yt.VideoResolution((height * 16 / 9).round(), height),
      const yt.Framerate(30),
      MediaType('video', 'mp4'),
    );

yt.VideoOnlyStreamInfo _videoOnly(
        int tag, int height, yt.StreamContainer container) =>
    yt.VideoOnlyStreamInfo(
      _videoId,
      tag,
      _url,
      container,
      yt.FileSize(1024 * 1024 * tag),
      const yt.Bitrate(2500000),
      'avc1.640028',
      '${height}p',
      yt.VideoQuality.high1080,
      yt.VideoResolution((height * 16 / 9).round(), height),
      const yt.Framerate(30),
      const [],
      MediaType('video', 'mp4'),
    );

yt.AudioOnlyStreamInfo _audio(int tag, int kbps, yt.StreamContainer container) =>
    yt.AudioOnlyStreamInfo(
      _videoId,
      tag,
      _url,
      container,
      const yt.FileSize(1024 * 1024),
      yt.Bitrate(kbps * 1024),
      'mp4a.40.2',
      '${kbps}kbps',
      const [],
      MediaType('audio', 'mp4'),
      null,
    );

yt.StreamManifest _manifest() => yt.StreamManifest([
      // A single combined stream, capped at 360p exactly like YouTube.
      _muxed(18, 360, yt.StreamContainer.mp4),
      // Higher resolutions, video-only. 720p comes as both WebM and MP4 so the
      // dedupe has to choose one.
      _videoOnly(247, 720, yt.StreamContainer.webM),
      _videoOnly(136, 720, yt.StreamContainer.mp4),
      _videoOnly(137, 1080, yt.StreamContainer.mp4),
      _videoOnly(248, 1080, yt.StreamContainer.webM),
      // Audio tracks, including a WebM one that should not be paired with MP4.
      _audio(140, 128, yt.StreamContainer.mp4),
      _audio(251, 160, yt.StreamContainer.webM),
    ]);

void main() {
  const extractor = MediaExtractor();

  group('describe', () {
    test('lists resolutions above 360p as mux-requiring formats', () async {
      final info = await extractor.describe(
        'https://youtu.be/dQw4w9WgXcQ',
        videoOverride: _video(),
        manifestOverride: _manifest(),
      );

      final videoFormats =
          info.formats.where((f) => f.kind != 'audio').toList();
      final heights = videoFormats.map((f) => f.height).toList();

      // One entry per height, best-first, and every height present exactly once.
      expect(heights, [1080, 720, 360]);
      expect(videoFormats[0].requiresMux, isTrue);
      expect(videoFormats[1].requiresMux, isTrue);
      // The combined 360p stream needs no muxing.
      expect(videoFormats[2].requiresMux, isFalse);
      expect(videoFormats[2].extension, 'mp4');

      // 720p/1080p are served as both MP4 and WebM; MP4 wins so the merged
      // file plays everywhere.
      expect(videoFormats[0].extension, 'mp4');
      expect(videoFormats[1].extension, 'mp4');
    });

    test('carries title, duration and thumbnail from the video', () async {
      final info = await extractor.describe(
        'https://youtu.be/dQw4w9WgXcQ',
        videoOverride: _video(),
        manifestOverride: _manifest(),
      );
      expect(info.title, 'Test clip');
      expect(info.author, 'Test channel');
      expect(info.durationSeconds, 90);
      expect(info.thumbnailUrl, contains(_videoId.value));
    });
  });

  group('resolve', () {
    test('a video-only pick returns the video plus an audio track', () async {
      final resolved = await extractor.resolve(
        'https://youtu.be/dQw4w9WgXcQ',
        formatId: 'video:1080p:mp4',
        videoOverride: _video(),
        manifestOverride: _manifest(),
      );

      expect(resolved.qualityLabel, '1080p');
      expect(resolved.extension, 'mp4');
      expect(resolved.url, _url.toString());
      // MP4 video must pair with the AAC/MP4 audio, not the WebM track.
      expect(resolved.audioUrl, _url.toString());
      expect(resolved.audioExtension, 'm4a');
      expect(resolved.needsMux, isTrue);
    });

    test('an unknown format id falls back to the combined stream', () async {
      final resolved = await extractor.resolve(
        'https://youtu.be/dQw4w9WgXcQ',
        formatId: 'video:4320p:mp4',
        videoOverride: _video(),
        manifestOverride: _manifest(),
      );

      expect(resolved.qualityLabel, '360p');
      expect(resolved.extension, 'mp4');
      expect(resolved.needsMux, isFalse);
      expect(resolved.audioUrl, isNull);
    });

    test('an audio pick returns just the audio track', () async {
      final resolved = await extractor.resolve(
        'https://youtu.be/dQw4w9WgXcQ',
        formatId: 'audio:128:m4a',
        videoOverride: _video(),
        manifestOverride: _manifest(),
      );

      expect(resolved.extension, 'm4a');
      expect(resolved.url, _url.toString());
      expect(resolved.needsMux, isFalse);
    });
  });
}
