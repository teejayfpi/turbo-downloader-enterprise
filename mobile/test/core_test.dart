import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/format.dart';
import 'package:turbo_downloader/media_url.dart';
import 'package:turbo_downloader/models.dart';
import 'package:turbo_downloader/state.dart';

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

  group('normalizeUrl', () {
    test('adds https to a bare host', () {
      expect(TurboState.normalizeUrl('turbo.example.com'),
          'https://turbo.example.com');
    });

    test('keeps an explicit scheme', () {
      expect(TurboState.normalizeUrl('http://10.0.2.2:12000'),
          'http://10.0.2.2:12000');
    });

    test('strips trailing slashes', () {
      expect(TurboState.normalizeUrl('https://x.dev///'), 'https://x.dev');
    });

    test('returns empty for blank input', () {
      expect(TurboState.normalizeUrl('   '), '');
    });
  });

  group('DownloadTask', () {
    test('parses a serialized task', () {
      final task = DownloadTask.fromJson({
        'id': 'abc',
        'url': 'https://example.com/a.zip',
        'filename': 'a.zip',
        'filepath': '/downloads/a.zip',
        'total': 1000,
        'downloaded': 500,
        'speed': 100,
        'progress': 50.0,
        'status': 'active',
        'platform': 'generic',
        'kind': 'archive',
        'connections': 8,
        'priority': 0,
        'resumeSupported': true,
        'segments': 8,
      });

      expect(task.id, 'abc');
      expect(task.isActive, isTrue);
      expect(task.canRetrieve, isFalse);
      expect(task.kind, 'archive');
      expect(task.connections, 8);
    });

    test('a completed task with a path can be retrieved', () {
      final task = DownloadTask.fromJson({
        'id': 'x',
        'status': 'completed',
        'filepath': '/downloads/x.mp4',
      });
      expect(task.canRetrieve, isTrue);
    });

    test('a completed task without a path cannot be retrieved', () {
      final task = DownloadTask.fromJson({'id': 'x', 'status': 'completed'});
      expect(task.canRetrieve, isFalse);
    });
  });

  group('MediaFormat', () {
    test('detects a progressive stream', () {
      final fmt = MediaFormat.fromJson({
        'formatId': '18',
        'ext': 'mp4',
        'type': 'video',
        'label': '360p',
        'acodec': 'mp4a.40.2',
        'vcodec': 'avc1',
      });
      expect(fmt.isVideo, isTrue);
      expect(fmt.isProgressive, isTrue);
    });

    test('video-only is not progressive', () {
      final fmt = MediaFormat.fromJson({
        'formatId': '137',
        'type': 'video',
        'acodec': 'none',
      });
      expect(fmt.isProgressive, isFalse);
    });
  });
}
