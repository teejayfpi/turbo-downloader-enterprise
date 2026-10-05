import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// A YouTube video surfaced in the Browse tab: enough metadata to render a
/// card and to hand the watch URL to the normal download flow.
class BrowseVideo {
  final String id;
  final String title;
  final String author;
  final String channelId;
  final int? durationSeconds;
  final String thumbnailUrl;
  final int viewCount;
  final String? uploadDate;
  final bool isLive;

  const BrowseVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.channelId,
    required this.thumbnailUrl,
    this.durationSeconds,
    this.viewCount = 0,
    this.uploadDate,
    this.isLive = false,
  });

  /// Canonical watch URL, used as the download input.
  String get watchUrl => 'https://www.youtube.com/watch?v=$id';
}

/// A channel result shown in search and used to open its uploads.
class BrowseChannel {
  final String id;
  final String name;
  final String description;
  final int videoCount;
  final String? thumbnailUrl;

  const BrowseChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.videoCount,
    this.thumbnailUrl,
  });
}

/// A playlist result shown in search and used to open its videos.
class BrowsePlaylist {
  final String id;
  final String title;
  final int videoCount;
  final String? thumbnailUrl;

  const BrowsePlaylist({
    required this.id,
    required this.title,
    required this.videoCount,
    this.thumbnailUrl,
  });
}

/// One page of videos plus the cursor needed to fetch the next one.
///
/// [nextPage] is null once YouTube has no more results for the query. The
/// cursor is opaque; callers just hand it back to the browser.
class BrowsePage {
  final List<BrowseVideo> videos;
  final BrowsePageCursor? nextPage;

  const BrowsePage({required this.videos, this.nextPage});

  bool get hasMore => nextPage != null;
}

/// Opaque continuation token for a paged listing.
class BrowsePageCursor {
  final Object _inner;
  const BrowsePageCursor(this._inner);
}

/// Search results split by type: videos to download, plus matching channels
/// and playlists the user can open.
class BrowseSearchResults {
  final List<BrowseVideo> videos;
  final List<BrowseChannel> channels;
  final List<BrowsePlaylist> playlists;
  final BrowsePageCursor? nextPage;

  const BrowseSearchResults({
    this.videos = const [],
    this.channels = const [],
    this.playlists = const [],
    this.nextPage,
  });

  bool get isEmpty => videos.isEmpty && channels.isEmpty && playlists.isEmpty;
}

/// A kind of listing the Browse tab can show for a channel.
enum ChannelTab {
  videos,
  shorts;

  String get label => switch (this) {
        ChannelTab.videos => 'Videos',
        ChannelTab.shorts => 'Shorts',
      };
}

/// Raised for a browse failure with a message safe to show the user.
class BrowseException implements Exception {
  final String message;
  const BrowseException(this.message);

  @override
  String toString() => message;
}

/// Read-only YouTube browsing: search, channel uploads, and playlists.
///
/// This is the discovery half of the app - it never downloads. A tapped
/// result yields a plain watch URL that flows into the same
/// `TurboState.addLink` path as a pasted link, so quality selection, muxing,
/// and history all behave identically.
class YoutubeBrowser {
  /// [client] is injectable so tests can supply a stub without the network.
  YoutubeBrowser({yt.YoutubeExplode? client})
      : _client = client ?? yt.YoutubeExplode();

  final yt.YoutubeExplode _client;

  void dispose() => _client.close();

  // ---------------------------------------------------------------- search

  /// Searches YouTube and returns the first page of matching videos.
  Future<BrowsePage> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const BrowsePage(videos: []);
    }
    try {
      final list = await _client.search.search(
        trimmed,
        filter: yt.TypeFilters.video,
      );
      return _pageFromVideos(list);
    } catch (e) {
      throw BrowseException('Could not search YouTube: $e');
    }
  }

  /// Searches YouTube and returns videos plus matching channels and playlists,
  /// so the user can open a channel or playlist directly from the results.
  Future<BrowseSearchResults> searchAll(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const BrowseSearchResults();
    try {
      final list = await _client.search.searchContent(trimmed);
      final videos = <BrowseVideo>[];
      final channels = <BrowseChannel>[];
      final playlists = <BrowsePlaylist>[];
      for (final r in list) {
        if (r is yt.SearchVideo) {
          videos.add(_videoFromSearch(r));
        } else if (r is yt.SearchChannel) {
          channels.add(channelFrom(r));
        } else if (r is yt.SearchPlaylist) {
          playlists.add(playlistFrom(r));
        }
      }
      return BrowseSearchResults(
        videos: videos,
        channels: channels,
        playlists: playlists,
        nextPage: list.isEmpty ? null : BrowsePageCursor(list),
      );
    } catch (e) {
      throw BrowseException('Could not search YouTube: $e');
    }
  }

  /// Fetches the next page of a [searchAll] result set.
  Future<BrowseSearchResults> searchAllNext(BrowsePageCursor cursor) async {
    try {
      final list = cursor._inner as yt.SearchList;
      final next = await list.nextPage();
      if (next == null) return const BrowseSearchResults();
      final videos = <BrowseVideo>[];
      final channels = <BrowseChannel>[];
      final playlists = <BrowsePlaylist>[];
      for (final r in next) {
        if (r is yt.SearchVideo) {
          videos.add(_videoFromSearch(r));
        } else if (r is yt.SearchChannel) {
          channels.add(channelFrom(r));
        } else if (r is yt.SearchPlaylist) {
          playlists.add(playlistFrom(r));
        }
      }
      return BrowseSearchResults(
        videos: videos,
        channels: channels,
        playlists: playlists,
        nextPage: next.isEmpty ? null : BrowsePageCursor(next),
      );
    } catch (e) {
      throw BrowseException('Could not load more results: $e');
    }
  }

  // --------------------------------------------------------------- channel

  /// Lists a channel's uploads, one page at a time.
  ///
  /// [cursor] is null for the first page. [tab] selects videos or shorts;
  /// YouTube treats these as separate listings, so a fresh tab always starts
  /// without a cursor.
  Future<BrowsePage> channelUploads(
    String channelId, {
    ChannelTab tab = ChannelTab.videos,
    BrowsePageCursor? cursor,
  }) async {
    try {
      if (cursor != null) {
        final list = cursor._inner as yt.ChannelUploadsList;
        final next = await list.nextPage();
        if (next == null) return const BrowsePage(videos: []);
        return _pageFromUploads(next);
      }
      final list = await _client.channels.getUploadsFromPage(
        channelId,
        videoSorting: yt.VideoSorting.newest,
        videoType: _videoType(tab),
      );
      return _pageFromUploads(list);
    } catch (e) {
      throw BrowseException('Could not open this channel: $e');
    }
  }

  // -------------------------------------------------------------- playlist

  /// Lists the videos in a playlist, one page at a time.
  ///
  /// Playlists are exposed as a stream, so a cursor caches the stream iterator
  /// to resume where the previous page stopped.
  Future<BrowsePage> playlistVideos(
    String playlistId, {
    BrowsePageCursor? cursor,
  }) async {
    try {
      final state = cursor?.playlistCursor() ??
          _PlaylistCursor(
            StreamIterator(_client.playlists.getVideos(playlistId)),
          );
      final videos = <BrowseVideo>[];
      // A bounded batch keeps the first screen responsive; the stream yields
      // videos as it walks the playlist's pages.
      while (videos.length < 20) {
        final hasNext = await state.iterator.moveNext();
        if (!hasNext) return BrowsePage(videos: videos);
        videos.add(_videoFrom(state.iterator.current));
      }
      return BrowsePage(videos: videos, nextPage: BrowsePageCursor(state));
    } catch (e) {
      throw BrowseException('Could not open this playlist: $e');
    }
  }

  // ------------------------------------------------------------ bulk listing

  /// Walks a channel's uploads until [limit] videos are collected or the
  /// listing ends. Used by "download all" to enumerate a channel up front.
  Future<List<BrowseVideo>> collectChannel(
    String channelId, {
    ChannelTab tab = ChannelTab.videos,
    int limit = 100,
  }) async {
    final videos = <BrowseVideo>[];
    try {
      var list = await _client.channels.getUploadsFromPage(
        channelId,
        videoSorting: yt.VideoSorting.newest,
        videoType: _videoType(tab),
      );
      while (true) {
        for (final v in list) {
          videos.add(_videoFrom(v));
          if (videos.length >= limit) return videos;
        }
        final next = await list.nextPage();
        if (next == null) return videos;
        list = next;
      }
    } catch (e) {
      throw BrowseException('Could not list this channel: $e');
    }
  }

  /// Collects a playlist's videos up to [limit]. Used by "download all".
  Future<List<BrowseVideo>> collectPlaylist(
    String playlistId, {
    int limit = 100,
  }) async {
    final videos = <BrowseVideo>[];
    try {
      await for (final v in _client.playlists.getVideos(playlistId)) {
        videos.add(_videoFrom(v));
        if (videos.length >= limit) break;
      }
      return videos;
    } catch (e) {
      throw BrowseException('Could not list this playlist: $e');
    }
  }

  // ---------------------------------------------------------------- mapping

  BrowsePage _pageFromVideos(yt.VideoSearchList list) => BrowsePage(
        videos: list.map(_videoFrom).toList(),
        nextPage: BrowsePageCursor(list),
      );

  BrowsePage _pageFromUploads(yt.ChannelUploadsList list) => BrowsePage(
        videos: list.map(_videoFrom).toList(),
        nextPage: BrowsePageCursor(list),
      );

  static yt.VideoType _videoType(ChannelTab tab) => switch (tab) {
        ChannelTab.videos => yt.VideoType.normal,
        ChannelTab.shorts => yt.VideoType.shorts,
      };

  static BrowseVideo _videoFrom(yt.Video v) => BrowseVideo(
        id: v.id.value,
        title: v.title,
        author: v.author,
        channelId: v.channelId.value,
        durationSeconds: v.duration?.inSeconds,
        thumbnailUrl: v.thumbnails.mediumResUrl,
        viewCount: v.engagement.viewCount,
        uploadDate: v.uploadDateRaw,
        isLive: v.isLive,
      );

  /// Search results carry duration as "HH:MM:SS" and a raw thumbnail list
  /// instead of a [yt.Video], so map them separately.
  static BrowseVideo _videoFromSearch(yt.SearchVideo v) => BrowseVideo(
        id: v.id.value,
        title: v.title,
        author: v.author,
        channelId: v.channelId,
        durationSeconds: parseClock(v.duration),
        thumbnailUrl: _firstThumb(v.thumbnails) ??
            'https://img.youtube.com/vi/${v.id.value}/mqdefault.jpg',
        viewCount: v.viewCount,
        uploadDate: v.uploadDate,
        isLive: v.isLive,
      );

  static int? parseClock(String value) {
    if (value.isEmpty) return null;
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    var total = 0;
    for (final p in parts) {
      total = total * 60 + p!;
    }
    return total;
  }

  /// Search results expose channels and playlists as their own result types.
  static BrowseChannel channelFrom(yt.SearchChannel c) => BrowseChannel(
        id: c.id.value,
        name: c.name,
        description: c.description,
        videoCount: c.videoCount,
        thumbnailUrl: _firstThumb(c.thumbnails),
      );

  static BrowsePlaylist playlistFrom(yt.SearchPlaylist p) => BrowsePlaylist(
        id: p.id.value,
        title: p.title,
        videoCount: p.videoCount,
        thumbnailUrl: _firstThumb(p.thumbnails),
      );

  static String? _firstThumb(List<yt.Thumbnail> thumbs) =>
      thumbs.isEmpty ? null : thumbs.first.url.toString();
}

/// Caches a playlist stream iterator so successive pages resume the stream.
class _PlaylistCursor {
  final StreamIterator<yt.Video> iterator;
  _PlaylistCursor(this.iterator);
}

extension on BrowsePageCursor {
  _PlaylistCursor? playlistCursor() {
    final inner = _inner;
    return inner is _PlaylistCursor ? inner : null;
  }
}
