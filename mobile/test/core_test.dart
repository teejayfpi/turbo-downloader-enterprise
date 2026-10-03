import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/file_store.dart';
import 'package:turbo_downloader/format.dart';
import 'package:turbo_downloader/media_url.dart';

void main() {
  group('isMediaUrl', () {
    test('detects known media hosts and subdomains', () {
      expect(isMediaUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isMediaUrl('https://youtu.be/abc'), isTrue);
      expect(isMediaUrl('https://m.youtube.com/watch?v=abc'), isTrue);
      expect(isMediaUrl('https://soundcloud.com/artist/track'), isTrue);
      expect(isMediaUrl('https://x.com/user/status/1'), isTrue);
    });

    test('leaves direct file links alone', () {
      expect(isMediaUrl('https://example.com/file.zip'), isFalse);
      expect(isMediaUrl('https://raw.githubusercontent.com/a/b/README.md'),
          isFalse);
      expect(isMediaUrl('https://cdn.example.com/video.mp4'), isFalse);
    });

    test('does not match a lookalike host', () {
      expect(isMediaUrl('https://notyoutube.com/watch?v=abc'), isFalse);
      expect(isMediaUrl('https://youtube.com.evil.test/x'), isFalse);
    });

    test('rejects malformed input', () {
      expect(isMediaUrl('not a url'), isFalse);
      expect(isMediaUrl(''), isFalse);
    });
  });

  group('isYouTubeUrl', () {
    test('recognises YouTube and its subdomains', () {
      expect(isYouTubeUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isYouTubeUrl('https://youtu.be/abc'), isTrue);
      expect(isYouTubeUrl('https://music.youtube.com/watch?v=abc'), isTrue);
    });

    test('excludes other media sites', () {
      expect(isYouTubeUrl('https://soundcloud.com/artist/track'), isFalse);
      expect(isYouTubeUrl('https://example.com/file.zip'), isFalse);
    });
  });

  group('formatBytes', () {
    test('scales through units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(1073741824), '1.0 GB');
    });

    test('treats negative as empty', () {
      expect(formatBytes(-5), '0 B');
    });
  });

  group('formatSpeed', () {
    test('renders a dash when idle', () {
      expect(formatSpeed(0), '—');
    });

    test('appends per second', () {
      expect(formatSpeed(2048), '2.0 KB/s');
    });
  });

  group('FileStore.sanitize', () {
    test('replaces characters illegal on any platform', () {
      expect(FileStore.sanitize('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('falls back when the name is empty', () {
      expect(FileStore.sanitize('   '), 'turbo-download');
    });

    test('keeps ordinary names untouched', () {
      expect(FileStore.sanitize('video 1080p.mp4'), 'video 1080p.mp4');
    });
  });

  group('platform detection', () {
    test('recognises a broad set of media platforms', () {
      for (final url in [
        'https://www.youtube.com/watch?v=abc',
        'https://youtu.be/abc',
        'https://vimeo.com/12345',
        'https://www.tiktok.com/@user/video/1',
        'https://open.spotify.com/track/x',
        'https://soundcloud.com/artist/song',
        'https://www.twitch.tv/videos/1',
        'https://instagram.com/reel/x',
        'https://archive.org/details/item',
      ]) {
        expect(isMediaUrl(url), isTrue, reason: url);
      }
    });

    test('does not treat ordinary hosts as media', () {
      expect(isMediaUrl('https://example.com/file.zip'), isFalse);
      expect(isMediaUrl('https://notyoutube.com.evil.test/x'), isFalse);
    });

    test('a page-looking link without an extension needs extraction', () {
      expect(needsExtraction('https://newsite.example/watch/xyz'), isTrue);
      expect(looksLikePage('https://newsite.example/video'), isTrue);
      expect(looksLikePage('https://cdn.example.com/movie.mkv'), isFalse);
      expect(needsExtraction('https://cdn.example.com/movie.mkv'), isFalse);
      expect(needsExtraction('https://vimeo.com/123'), isTrue);
    });

    test('separates YouTube from other platforms', () {
      expect(isYouTubeUrl('https://youtube.com/watch?v=x'), isTrue);
      expect(isYouTubeUrl('https://vimeo.com/1'), isFalse);
    });
  });

  group('file kind detection', () {
    test('classifies common extensions', () {
      expect(kindOf('a.mp4'), FileKind.video);
      expect(kindOf('a.mkv'), FileKind.video);
      expect(kindOf('a.mp3'), FileKind.audio);
      expect(kindOf('a.flac'), FileKind.audio);
      expect(kindOf('a.png'), FileKind.image);
      expect(kindOf('a.zip'), FileKind.archive);
      expect(kindOf('a.pdf'), FileKind.document);
      expect(kindOf('a.exe'), FileKind.app);
      expect(kindOf('a.unknownext'), FileKind.other);
    });

    test('uses the path segment of a URL', () {
      expect(kindOf('https://cdn.example.com/a/b/clip.webm'), FileKind.video);
    });

    test('reports playability only for media containers', () {
      expect(isPlayable('song.mp3'), isTrue);
      expect(isPlayable('clip.mp4'), isTrue);
      expect(isPlayable('doc.pdf'), isFalse);
    });
  });
}
