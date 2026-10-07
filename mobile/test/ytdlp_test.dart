import 'dart:io';

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
    // Prefer the direct (https) stream over YouTube's HLS variant, then fall
    // back to the plain format id so non-YouTube sources still resolve.
    expect(
      f.selector,
      'bv*[format_id="137"][protocol^=https]+ba[protocol^=https]/'
      'bv*[format_id="137"]+ba',
    );
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

  test('a storyboard-only response explains the JavaScript-runtime remedy', () {
    // Reproduces the signed-in-but-unsolved YouTube case: valid cookies, no JS
    // runtime, so only mhtml storyboards come back. The user must be told what
    // is actually missing rather than seeing an empty video list.
    expect(
      () => engine.parseProbe({
        'title': 'Signed in but unsolved',
        'formats': [
          {'format_id': 'sb0', 'ext': 'mhtml', 'vcodec': 'none', 'acodec': 'none', 'height': 180},
          {'format_id': 'sb1', 'ext': 'mhtml', 'vcodec': 'none', 'acodec': 'none', 'height': 45},
        ],
      }, true),
      throwsA(isA<YtdlpException>().having(
        (e) => e.message,
        'message',
        contains('JavaScript runtime'),
      )),
    );
  });

  test('transient network text is recognised separately from a sign-in wall',
      () {
    // A dropped connection must not be reported as "add your cookies".
    expect(
      YtdlpEngine.looksLikeTransientNetwork(
          'ERROR: unable to download video data: <urlopen error timed out>'),
      isTrue,
    );
    expect(
      YtdlpEngine.looksLikeTransientNetwork('ERROR: Connection reset by peer'),
      isTrue,
    );
    expect(
      YtdlpEngine.looksLikeTransientNetwork('ERROR: HTTP Error 403: Forbidden'),
      isFalse,
    );
    // The friendly 403 sentence mentions cookies as a remedy; it must not be
    // mistaken for a genuine sign-in wall.
    expect(
      YtdlpEngine.looksLikeSignInRequired(
          'The site refused to serve this download (HTTP 403). Retry in a '
          'moment; if it keeps failing, add cookies in Settings.'),
      isFalse,
    );
    expect(
      YtdlpEngine.looksLikeSignInRequired(
          'Sign in to confirm you are not a bot'),
      isTrue,
    );
  });

  test('the engine default selector avoids HLS in favour of direct streams',
      () {
    expect(YtdlpEngine.defaultSelector, contains('[protocol^=https]'));
  });

  test('access-denied matches real 403/429 text but not stray digits', () {
    // Real refusals are recognised.
    expect(
      YtdlpEngine.looksLikeAccessDenied(
          'ERROR: unable to download video data: HTTP Error 403: Forbidden'),
      isTrue,
    );
    expect(
      YtdlpEngine.looksLikeAccessDenied('ERROR: HTTP Error 429: Too Many Requests'),
      isTrue,
    );
    // A bare status code delimited from other digits still counts.
    expect(YtdlpEngine.looksLikeAccessDenied('server said 403'), isTrue);
    // Numbers that merely contain 403/429 must not be mistaken for a refusal,
    // or a permanent error would be retried as a transient one.
    expect(
      YtdlpEngine.looksLikeAccessDenied('wrote 1403328 bytes to disk'),
      isFalse,
    );
    expect(
      YtdlpEngine.looksLikeAccessDenied('video 4031 is unavailable in your country'),
      isFalse,
    );
    expect(YtdlpEngine.looksLikeAccessDenied('port 42900 refused'), isFalse);
  });

  test('yt-dlp is never told to skip TLS verification', () async {
    // Assert the real argument vectors directly, on every OS, rather than
    // spawning a fake binary (a `#!/bin/sh` script is not portable to Windows).
    final dir = Directory.systemTemp.createTempSync('ytdlp-args');
    final engine = YtdlpEngine();

    for (final args in [
      await engine.probeArgs('https://example.com/watch'),
      await engine.downloadArgs(
        url: 'https://example.com/watch',
        selector: 'best',
        dir: dir,
        stem: 'clip',
      ),
    ]) {
      expect(args, isNot(contains('--no-check-certificates')));
      expect(args, contains('--no-warnings'));
      expect(args, contains('--no-playlist'));
    }
  });
}
