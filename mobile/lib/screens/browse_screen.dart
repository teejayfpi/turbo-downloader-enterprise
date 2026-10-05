import 'package:flutter/material.dart';

import '../contact.dart';
import '../credits.dart';
import '../format.dart';
import '../services/youtube_browser.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/media_download_sheet.dart';

/// In-app YouTube discovery: search, browse channels and playlists, and send
/// any video straight to the on-device download queue.
///
/// The Browse tab only reads YouTube. Tapping a video opens the same quality
/// picker as a pasted link, so downloads honour the HD/mux pipeline.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

enum _View { home, results, channel, playlist }

/// Curated entry points shown on the Browse home screen.
class _Category {
  final String label;
  final IconData icon;
  final String query;
  const _Category(this.label, this.icon, this.query);
}

const _categories = <_Category>[
  _Category('Trending', Icons.local_fire_department_rounded, 'trending'),
  _Category('Music', Icons.music_note_rounded, 'music videos'),
  _Category('Gaming', Icons.sports_esports_rounded, 'gaming'),
  _Category('News', Icons.newspaper_rounded, 'news'),
  _Category('Sports', Icons.sports_soccer_rounded, 'sports highlights'),
  _Category('Movies', Icons.movie_rounded, 'full movies'),
  _Category('Education', Icons.school_rounded, 'educational videos'),
  _Category('Comedy', Icons.theater_comedy_rounded, 'comedy'),
  _Category('Tech', Icons.memory_rounded, 'technology reviews'),
  _Category('Live', Icons.podcasts_rounded, 'live stream'),
];

class _BrowseScreenState extends State<BrowseScreen> {
  final _browser = YoutubeBrowser();
  final _searchController = TextEditingController();

  _View _view = _View.home;
  String _heading = '';

  bool _loading = false;
  String? _error;

  // Results state.
  List<BrowseVideo> _videos = [];
  List<BrowseChannel> _channels = [];
  List<BrowsePlaylist> _playlists = [];
  BrowsePageCursor? _cursor;

  // Channel state.
  String _channelId = '';
  String _channelName = '';
  ChannelTab _channelTab = ChannelTab.videos;

  // Playlist state.
  String _playlistId = '';
  String _playlistTitle = '';

  @override
  void dispose() {
    _browser.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on BrowseException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    _searchController.text = q;
    FocusScope.of(context).unfocus();
    return _run(() async {
      final results = await _browser.searchAll(q);
      if (!mounted) return;
      setState(() {
        _view = _View.results;
        _heading = q;
        _videos = results.videos;
        _channels = results.channels;
        _playlists = results.playlists;
        _cursor = results.nextPage;
      });
    });
  }

  Future<void> _loadMoreResults() => _run(() async {
        final cursor = _cursor;
        if (cursor == null) return;
        final results = await _browser.searchAllNext(cursor);
        if (!mounted) return;
        setState(() {
          _videos = [..._videos, ...results.videos];
          _channels = [..._channels, ...results.channels];
          _playlists = [..._playlists, ...results.playlists];
          _cursor = results.nextPage;
        });
      });

  Future<void> _openChannel(BrowseChannel channel) => _run(() async {
        final page = await _browser.channelUploads(channel.id);
        if (!mounted) return;
        setState(() {
          _view = _View.channel;
          _channelId = channel.id;
          _channelName = channel.name;
          _channelTab = ChannelTab.videos;
          _videos = page.videos;
          _cursor = page.nextPage;
        });
      });

  Future<void> _openPlaylist(BrowsePlaylist playlist) => _run(() async {
        final page = await _browser.playlistVideos(playlist.id);
        if (!mounted) return;
        setState(() {
          _view = _View.playlist;
          _playlistId = playlist.id;
          _playlistTitle = playlist.title;
          _videos = page.videos;
          _cursor = page.nextPage;
        });
      });

  Future<void> _loadMoreChannel(ChannelTab tab) => _run(() async {
        final cursor = _cursor;
        if (cursor == null) return;
        final page = await _browser.channelUploads(
          _channelId,
          tab: tab,
          cursor: cursor,
        );
        if (!mounted) return;
        setState(() {
          _videos = [..._videos, ...page.videos];
          _cursor = page.nextPage;
        });
      });

  Future<void> _switchChannelTab(ChannelTab tab) => _run(() async {
        final page =
            await _browser.channelUploads(_channelId, tab: tab);
        if (!mounted) return;
        setState(() {
          _channelTab = tab;
          _videos = page.videos;
          _cursor = page.nextPage;
        });
      });

  Future<void> _loadMorePlaylist() => _run(() async {
        final cursor = _cursor;
        if (cursor == null) return;
        final page = await _browser.playlistVideos(
          _playlistId,
          cursor: cursor,
        );
        if (!mounted) return;
        setState(() {
          _videos = [..._videos, ...page.videos];
          _cursor = page.nextPage;
        });
      });

  Future<void> _openVideo(BrowseVideo video) async {
    final queued = await showMediaDownloadSheet(
      context,
      video.watchUrl,
      suggestedName: video.title,
    );
    if (queued && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to the download queue')),
      );
    }
  }

  void _back() {
    setState(() {
      _view = _View.home;
      _videos = [];
      _channels = [];
      _playlists = [];
      _cursor = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          onSubmitted: _search,
          onBack: _view == _View.home ? null : _back,
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading && _videos.isEmpty && _channels.isEmpty && _playlists.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.palette.accent),
      );
    }
    if (_error != null && _videos.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _retry);
    }
    return switch (_view) {
      _View.home => _HomeBody(onSearch: _search),
      _View.results => _ResultsBody(
          heading: _heading,
          videos: _videos,
          channels: _channels,
          playlists: _playlists,
          hasMore: _cursor != null,
          loading: _loading,
          onOpenVideo: _openVideo,
          onOpenChannel: _openChannel,
          onOpenPlaylist: _openPlaylist,
          onLoadMore: _loadMoreResults,
        ),
      _View.channel => _ChannelBody(
          name: _channelName,
          tab: _channelTab,
          videos: _videos,
          hasMore: _cursor != null,
          loading: _loading,
          onTab: _switchChannelTab,
          onOpenVideo: _openVideo,
          onLoadMore: () => _loadMoreChannel(_channelTab),
        ),
      _View.playlist => _PlaylistBody(
          title: _playlistTitle,
          videos: _videos,
          hasMore: _cursor != null,
          loading: _loading,
          onOpenVideo: _openVideo,
          onLoadMore: _loadMorePlaylist,
        ),
    };
  }

  void _retry() {
    if (_view == _View.results) {
      _search(_heading);
    } else if (_view == _View.channel) {
      _switchChannelTab(_channelTab);
    } else if (_view == _View.playlist) {
      _run(() async {
        final page = await _browser.playlistVideos(_playlistId);
        if (!mounted) return;
        setState(() {
          _videos = page.videos;
          _cursor = page.nextPage;
        });
      });
    }
  }
}

/// Search field with an optional back affordance when inside a sub-listing.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onBack;

  const _SearchBar({
    required this.controller,
    required this.onSubmitted,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded, color: p.textMuted),
              ),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textPrimary,
                fontSize: 13.5,
              ),
              decoration: InputDecoration(
                hintText: 'Search YouTube channels and videos',
                prefixIcon: Icon(Icons.search_rounded,
                    color: p.textMuted, size: 20),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: () => onSubmitted(controller.text),
                  icon: Icon(Icons.arrow_forward_rounded,
                      color: p.accent, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  final ValueChanged<String> onSearch;
  const _HomeBody({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        TurboPanel(
          padding: const EdgeInsets.all(16),
          accentColor: p.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.travel_explore_rounded,
                      color: p.accent, size: 20),
                  const SizedBox(width: 8),
                  const Kicker('Browse & download', letterSpacing: 1.6),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Search YouTube or open a channel, then download any video '
                'straight to this device — up to 1080p and beyond.',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Kicker('Categories', letterSpacing: 2.0),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories
              .map((c) => _CategoryChip(category: c, onTap: () => onSearch(c.query)))
              .toList(),
        ),
        const SizedBox(height: 24),
        const Kicker('Eng. by ${Designer.name}', size: 9, letterSpacing: 1.4),
        const SizedBox(height: 10),
        const WhatsAppTile(
          label: 'Questions? Chat with the designer',
          compact: true,
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final _Category category;
  final VoidCallback onTap;
  const _CategoryChip({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: p.bgSecondary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 15, color: p.accent),
            const SizedBox(width: 7),
            Text(
              category.label,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final String heading;
  final List<BrowseVideo> videos;
  final List<BrowseChannel> channels;
  final List<BrowsePlaylist> playlists;
  final bool hasMore;
  final bool loading;
  final ValueChanged<BrowseVideo> onOpenVideo;
  final ValueChanged<BrowseChannel> onOpenChannel;
  final ValueChanged<BrowsePlaylist> onOpenPlaylist;
  final VoidCallback onLoadMore;

  const _ResultsBody({
    required this.heading,
    required this.videos,
    required this.channels,
    required this.playlists,
    required this.hasMore,
    required this.loading,
    required this.onOpenVideo,
    required this.onOpenChannel,
    required this.onOpenPlaylist,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty && channels.isEmpty && playlists.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results',
        message: 'Try a different search term or a category.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        if (channels.isNotEmpty) ...[
          const _SectionHeader('Channels', Icons.account_circle_rounded),
          ...channels.map((c) => _ChannelTile(
                channel: c,
                onTap: () => onOpenChannel(c),
              )),
          const SizedBox(height: 18),
        ],
        if (playlists.isNotEmpty) ...[
          const _SectionHeader('Playlists', Icons.playlist_play_rounded),
          ...playlists.map((p) => _PlaylistTile(
                playlist: p,
                onTap: () => onOpenPlaylist(p),
              )),
          const SizedBox(height: 18),
        ],
        if (videos.isNotEmpty) ...[
          const _SectionHeader('Videos', Icons.videocam_rounded),
          ...videos.map((v) => _VideoCard(
                video: v,
                onTap: () => onOpenVideo(v),
                onDownload: () => onOpenVideo(v),
              )),
        ],
        if (hasMore)
          _LoadMoreButton(loading: loading, onPressed: onLoadMore),
      ],
    );
  }
}

class _ChannelBody extends StatelessWidget {
  final String name;
  final ChannelTab tab;
  final List<BrowseVideo> videos;
  final bool hasMore;
  final bool loading;
  final ValueChanged<ChannelTab> onTab;
  final ValueChanged<BrowseVideo> onOpenVideo;
  final VoidCallback onLoadMore;

  const _ChannelBody({
    required this.name,
    required this.tab,
    required this.videos,
    required this.hasMore,
    required this.loading,
    required this.onTab,
    required this.onOpenVideo,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        Text(
          name,
          style: TextStyle(
            fontFamily: TurboFonts.display,
            color: context.palette.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ModeSegment(
          options: ChannelTab.values
              .map((t) => ModeSegmentOption(t.name, Icons.videocam_rounded, t.label))
              .toList(),
          value: tab.name,
          onChanged: (v) => onTab(
            ChannelTab.values.firstWhere((t) => t.name == v, orElse: () => tab),
          ),
        ),
        const SizedBox(height: 16),
        if (videos.isEmpty)
          const _EmptyState(
            icon: Icons.video_library_outlined,
            title: 'Nothing here',
            message: 'This channel has no items in this tab.',
          )
        else
          ...videos.map((v) => _VideoCard(
                video: v,
                onTap: () => onOpenVideo(v),
                onDownload: () => onOpenVideo(v),
              )),
        if (hasMore)
          _LoadMoreButton(loading: loading, onPressed: onLoadMore),
      ],
    );
  }
}

class _PlaylistBody extends StatelessWidget {
  final String title;
  final List<BrowseVideo> videos;
  final bool hasMore;
  final bool loading;
  final ValueChanged<BrowseVideo> onOpenVideo;
  final VoidCallback onLoadMore;

  const _PlaylistBody({
    required this.title,
    required this.videos,
    required this.hasMore,
    required this.loading,
    required this.onOpenVideo,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        Row(
          children: [
            Icon(Icons.playlist_play_rounded,
                color: context.palette.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: TurboFonts.display,
                  color: context.palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (videos.isEmpty)
          const _EmptyState(
            icon: Icons.playlist_remove_rounded,
            title: 'Empty playlist',
            message: 'This playlist has no downloadable videos.',
          )
        else
          ...videos.map((v) => _VideoCard(
                video: v,
                onTap: () => onOpenVideo(v),
                onDownload: () => onOpenVideo(v),
              )),
        if (hasMore)
          _LoadMoreButton(loading: loading, onPressed: onLoadMore),
      ],
    );
  }
}

/// A video row: thumbnail with duration badge, title, author, and download.
class _VideoCard extends StatelessWidget {
  final BrowseVideo video;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _VideoCard({
    required this.video,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: TurboPanel(
          padding: const EdgeInsets.all(10),
          accentColor: p.accent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 124,
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: p.bgTertiary),
                      Image.network(
                        video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.movie_rounded,
                            color: p.textMuted),
                      ),
                      if (video.durationSeconds != null || video.isLive)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              video.isLive
                                  ? 'LIVE'
                                  : formatDuration(video.durationSeconds),
                              style: const TextStyle(
                                fontFamily: TurboFonts.mono,
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _metaLine(video),
                      style: TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: p.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TurboButton(
                        expand: false,
                        icon: Icons.download_rounded,
                        label: 'Download',
                        onPressed: onDownload,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _metaLine(BrowseVideo v) {
    final parts = <String>[];
    if (v.viewCount > 0) parts.add('${_compact(v.viewCount)} views');
    if (v.uploadDate != null && v.uploadDate!.isNotEmpty) {
      parts.add(v.uploadDate!);
    }
    return parts.join(' · ');
  }

  static String _compact(int n) {
    if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _ChannelTile extends StatelessWidget {
  final BrowseChannel channel;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: TurboPanel(
          padding: const EdgeInsets.all(10),
          accentColor: p.accent,
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: channel.thumbnailUrl == null
                      ? Container(
                          color: p.bgTertiary,
                          child: Icon(Icons.person_rounded, color: p.textMuted),
                        )
                      : Image.network(
                          channel.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: p.bgTertiary,
                            child: Icon(Icons.person_rounded,
                                color: p.textMuted),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      channel.videoCount > 0
                          ? '${channel.videoCount} videos'
                          : 'Channel',
                      style: TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: p.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final BrowsePlaylist playlist;
  final VoidCallback onTap;
  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: TurboPanel(
          padding: const EdgeInsets.all(10),
          accentColor: p.accent,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 64,
                  height: 40,
                  child: playlist.thumbnailUrl == null
                      ? Container(
                          color: p.bgTertiary,
                          child: Icon(Icons.playlist_play_rounded,
                              color: p.textMuted),
                        )
                      : Image.network(
                          playlist.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: p.bgTertiary,
                            child: Icon(Icons.playlist_play_rounded,
                                color: p.textMuted),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${playlist.videoCount} videos',
                      style: TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: p.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.textMuted),
          const SizedBox(width: 8),
          Kicker(title, letterSpacing: 1.6),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _LoadMoreButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TurboButton(
        outline: true,
        busy: loading,
        icon: Icons.expand_more_rounded,
        label: 'Load more',
        onPressed: loading ? null : onPressed,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: p.textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontFamily: TurboFonts.display,
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: p.warning),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TurboButton(
              expand: false,
              outline: true,
              icon: Icons.refresh_rounded,
              label: 'Retry',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
