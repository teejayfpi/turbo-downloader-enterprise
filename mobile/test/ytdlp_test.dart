import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/ytdlp.dart';

/// Parsing yt-dlp's `-J` output into the format list the picker shows.
void main() {
  final engine = YtdlpEngine();

  test('a combined stream becomes a single downloadable format', () {
    final probe = engine.parseProbe({
      'title': 'Clip',
      'uploader': 'Someone',
      'formats': [
        {
          'format_id': '22',
          'ext': 'mp4',
          'vcodec': 'avc1.64001f',
          'acodec': 'mp4a.40.2',
          'height': 720,
          'filesize': 1000,
        },
      ],
    }, false);

    expect(probe.title, 'Clip');
    expect(probe.author, 'Someone');
    expect(probe.formats, hasLength(1));
    final f = probe.formats.single;
    expect(f.kind, 'video');
    expect(f.selector, '22');
    expect(f.requiresMux, isFalse);
    expect(f.height, 720);
  });

  test('a plain media file with unknown codecs is still offered', () {
    // This is the shape the generic extractor emits for a direct .mp4 link:
    // both codecs are null, so a naive parser drops the only format.
    final probe = engine.parseProbe({
      'title': 'sample-5s',
      'formats': [
        {
          'format_id': 'mp4',
          'ext': 'mp4',
          'vcodec': null,
          'acodec': null,
          'height': null,
        },
      ],
    }, false);

    expect(probe.formats, isNotEmpty);
    final f = probe.formats.single;
    expect(f.selector, 'mp4');
    expect(f.requiresMux, isFalse);
    expect(f.extension, 'mp4');
  });

  test('a video-only stream is marked as needing a mux', () {
    final probe = engine.parseProbe({
      'title': 'HD',
      'formats': [
        {
          'format_id': '137',
          'ext': 'mp4',
          'vcodec': 'avc1.640028',
          'acodec': 'none',
          'height': 1080,
          'filesize': 5000,
        },
      ],
    }, true);

    final f = probe.formats.single;
    expect(f.kind, 'video-only');
    expect(f.requiresMux, isTrue);
    expect(f.selector, '137+bestaudio/137');
  });

  test('formats are ordered best-first by resolution', () {
    final probe = engine.parseProbe({
      'title': 'Sorted',
      'formats': [
        {
          'format_id': '134',
          'ext': 'mp4',
          'vcodec': 'avc1',
          'acodec': 'none',
          'height': 240,
        },
        {
          'format_id': '137',
          'ext': 'mp4',
          'vcodec': 'avc1',
          'acodec': 'none',
          'height': 1080,
        },
        {
          'format_id': '136',
          'ext': 'mp4',
          'vcodec': 'avc1',
          'acodec': 'none',
          'height': 720,
        },
      ],
    }, true);

    expect(probe.formats.map((f) => f.height).toList(), [1080, 720, 240]);
  });

  test('storyboards are never offered as download formats', () {
    // yt-dlp lists thumbnail sprite sheets as formats with no codecs and an
    // `mhtml` container. On a video with no combined stream they would sort to
    // the top and become the default pick — downloading a storyboard image
    // instead of the video.
    final probe = engine.parseProbe({
      'title': 'No combined stream',
      'formats': [
        {'format_id': 'sb0', 'ext': 'mhtml', 'vcodec': 'none', 'acodec': 'none', 'height': 90},
        {'format_id': 'sb1', 'ext': 'mhtml', 'vcodec': null, 'acodec': null, 'height': 45},
        {'format_id': '137', 'ext': 'mp4', 'vcodec': 'avc1', 'acodec': 'none', 'height': 1080},
        {'format_id': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a', 'height': 0},
      ],
    }, true);

    expect(probe.formats.any((f) => f.extension == 'mhtml'), isFalse);
    expect(probe.formats.first.kind, 'video-only');
    expect(probe.formats.first.height, 1080);
  });

  test('a direct media link is still offered despite mhtml filtering', () {
    // The mhtml skip must not swallow a genuine codec-less media file.
    final probe = engine.parseProbe({
      'title': 'sample-5s',
      'formats': [
        {'format_id': 'mp4', 'ext': 'mp4', 'vcodec': null, 'acodec': null, 'height': null},
      ],
    }, false);
    expect(probe.formats, hasLength(1));
    expect(probe.formats.single.extension, 'mp4');
  });
}
