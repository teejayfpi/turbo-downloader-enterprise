import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/youtube_browser.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() {
  group('YoutubeBrowser.parseClock', () {
    test('parses HH:MM:SS', () {
      expect(YoutubeBrowser.parseClock('1:02:03'), 3723);
    });

    test('parses MM:SS', () {
      expect(YoutubeBrowser.parseClock('4:35'), 275);
    });

    test('parses a bare seconds value', () {
      expect(YoutubeBrowser.parseClock('45'), 45);
    });

    test('returns null for an empty or non-numeric value', () {
      expect(YoutubeBrowser.parseClock(''), isNull);
      expect(YoutubeBrowser.parseClock('live'), isNull);
      expect(YoutubeBrowser.parseClock('1:xx'), isNull);
    });
  });

  group('BrowseVideo', () {
    test('exposes a canonical watch URL for the download flow', () {
      const v = BrowseVideo(
        id: 'dQw4w9WgXcQ',
        title: 'A clip',
        author: 'Someone',
        channelId: 'UC123',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
      expect(v.watchUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });
  });

  group('YoutubeBrowser.channelFrom', () {
    test('maps a search channel into a BrowseChannel', () {
      final channel = YoutubeBrowser.channelFrom(
        yt.SearchChannel(
          yt.ChannelId('UCsXVk37bltHxD1rDPwtNM8Q'),
          'Test Channel',
          'A description',
          42,
          [yt.Thumbnail(Uri.parse('https://example.com/logo.jpg'), 88, 88)],
        ),
      );
      expect(channel.name, 'Test Channel');
      expect(channel.videoCount, 42);
      expect(channel.thumbnailUrl, 'https://example.com/logo.jpg');
    });
  });

  group('YoutubeBrowser.playlistFrom', () {
    test('maps a search playlist into a BrowsePlaylist', () {
      final playlist = YoutubeBrowser.playlistFrom(
        yt.SearchPlaylist(
          yt.PlaylistId('PL123'),
          'My Playlist',
          7,
          const [],
        ),
      );
      expect(playlist.title, 'My Playlist');
      expect(playlist.videoCount, 7);
      expect(playlist.thumbnailUrl, isNull);
    });
  });

  group('BrowseSearchResults', () {
    test('reports emptiness across all three result kinds', () {
      const empty = BrowseSearchResults();
      expect(empty.isEmpty, isTrue);

      const withVideo = BrowseSearchResults(videos: [
        BrowseVideo(
          id: 'x',
          title: 't',
          author: 'a',
          channelId: 'c',
          thumbnailUrl: 'u',
        ),
      ]);
      expect(withVideo.isEmpty, isFalse);
    });
  });
}
