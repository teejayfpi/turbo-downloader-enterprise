import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../services/youtube_browser.dart';
import '../state.dart';
import '../theme.dart';

/// Collects and queue a whole channel, playlist, or multi-selection.
///
/// Opens a sheet that enumerates the listing, shows what will be queued, lets
/// the user cap how many to grab, then hands the batch to [TurboState.addBatch].
/// Returns the [BatchResult] when something was queued, otherwise null.
Future<BatchResult?> showBatchDownloadSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<List<BrowseVideo>> Function(int limit) collect,
  List<BrowseVideo>? preselected,
}) {
  return showModalBottomSheet<BatchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BatchDownloadSheet(
      title: title,
      subtitle: subtitle,
      collect: collect,
      preselected: preselected,
    ),
  );
}

/// Counts offered in the batch sheet.
const _countChoices = [10, 25, 50, 100];

class _BatchDownloadSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<List<BrowseVideo>> Function(int limit) collect;
  final List<BrowseVideo>? preselected;

  const _BatchDownloadSheet({
    required this.title,
    required this.subtitle,
    required this.collect,
    this.preselected,
  });

  @override
  State<_BatchDownloadSheet> createState() => _BatchDownloadSheetState();
}

class _BatchDownloadSheetState extends State<_BatchDownloadSheet> {
  List<BrowseVideo> _videos = [];
  int _limit = 25;
  bool _loading = true;
  bool _queueing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pre = widget.preselected;
    if (pre != null) {
      _videos = pre;
      _limit = pre.length;
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final videos = await widget.collect(_limit);
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is BrowseException ? e.message : 'Could not list: $e';
        _loading = false;
      });
    }
  }

  Future<void> _changeLimit(int limit) async {
    setState(() => _limit = limit);
    await _load();
  }

  Future<void> _queue() async {
    if (_videos.isEmpty) return;
    setState(() => _queueing = true);
    final state = context.read<TurboState>();
    final result = await state.addBatch(_videos);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = _videos.length > _limit ? _limit : _videos.length;
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: p.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.library_add_rounded, color: p.accent, size: 18),
                  const SizedBox(width: 8),
                  const Kicker('Batch download', letterSpacing: 1.6),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: p.textMuted, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(scrollController, shown)),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController scrollController, int shown) {
    final p = context.palette;
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.accent),
            const SizedBox(height: 14),
            Text(
              'Collecting videos…',
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: p.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: p.warning, size: 34),
              const SizedBox(height: 12),
              Text(
                _error!,
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
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    if (_videos.isEmpty) {
      return Center(
        child: Text(
          'Nothing to download here.',
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: p.textMuted,
            fontSize: 12.5,
          ),
        ),
      );
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: TurboFonts.display,
            color: p.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitle,
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: p.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 16),
        const Kicker('How many', letterSpacing: 1.6),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _countChoices
              .map((c) => _CountChip(
                    count: c,
                    selected: _limit == c,
                    onTap: () => _changeLimit(c),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.playlist_add_check_rounded,
                size: 15, color: p.textMuted),
            const SizedBox(width: 8),
            Kicker('$shown of ${_videos.length} videos', letterSpacing: 1.2),
          ],
        ),
        const SizedBox(height: 10),
        ..._videos.take(shown).map((v) => _BatchRow(video: v)),
        const SizedBox(height: 20),
        TurboButton(
          busy: _queueing,
          icon: Icons.download_for_offline_rounded,
          label: 'Download $shown to this device',
          onPressed: _queueing ? null : _queue,
        ),
        const SizedBox(height: 8),
        Text(
          'Videos download one after another at the best available quality. '
          'You can pause, reorder, or remove any of them from the queue.',
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: p.textMuted,
            fontSize: 10,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _CountChip({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.accent.withOpacity(0.16) : p.bgTertiary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? p.accent : p.borderSubtle,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontFamily: TurboFonts.mono,
            color: selected ? p.textPrimary : p.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  final BrowseVideo video;
  const _BatchRow({required this.video});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              width: 64,
              height: 36,
              color: p.bgTertiary,
              child: video.thumbnailUrl.isEmpty
                  ? Icon(Icons.movie_rounded, color: p.textMuted, size: 16)
                  : Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.movie_rounded, color: p.textMuted),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: p.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
          if (video.durationSeconds != null) ...[
            const SizedBox(width: 8),
            Text(
              formatDuration(video.durationSeconds),
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: p.textMuted,
                fontSize: 9.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
