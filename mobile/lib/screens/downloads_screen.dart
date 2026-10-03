import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../file_store.dart';
import '../format.dart';
import '../local_downloader.dart';
import '../media_url.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final Set<String> _seenCompleted = {};
  bool _primed = false;

  /// Active type filter; null means "All".
  FileKind? _filter;

  /// Plays the completion chime when a task finishes, without firing for the
  /// tasks that were already complete when the app opened.
  void _maybeChime(TurboState state) {
    final completed =
        state.local.tasks.where((t) => t.isCompleted).map((t) => t.id).toSet();
    if (!_primed) {
      _seenCompleted.addAll(completed);
      _primed = true;
      return;
    }
    final fresh = completed.difference(_seenCompleted);
    if (fresh.isNotEmpty && state.playSound) {
      SystemSound.play(SystemSoundType.alert);
    }
    _seenCompleted
      ..clear()
      ..addAll(completed);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    _maybeChime(state);
    final all = state.local.tasks;
    final local = _filter == null
        ? all
        : all.where((t) => kindOf(t.filename) == _filter).toList();

    if (state.loading && all.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Re-read the device conditions and let the worker pick up again.
        await state.refreshDevice();
        state.local.resumeAll();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _StatsBar(
              active: all.where((t) => t.isRunning).length,
              speed: all.fold<int>(0, (n, t) => n + t.speed),
              done: all.where((t) => t.isCompleted).length,
              bytes: all.fold<int>(0, (n, t) => n + t.downloaded),
            ),
          ),
          if (state.local.networkBlocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Notice(
                  icon: Icons.wifi_off_rounded,
                  color: context.palette.warning,
                  text: state.wifiOnly && !state.deviceState.onWifi
                      ? 'Wi-Fi only is on and this device is not on Wi-Fi. '
                          'Transfers are paused.'
                      : 'Battery is low and the device is unplugged. Transfers '
                          'are paused to save power.',
                  trailing: TextButton(
                    onPressed: () async {
                      await state.setWifiOnly(false);
                      await state.setBatteryAware(false);
                    },
                    child: const Text('Allow'),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _Toolbar(
              hasCompleted: all.any((t) => t.isCompleted),
              anyPaused: all.any((t) => t.isPaused || t.isFailed),
              anyRunning: all.any((t) => t.isRunning || t.isQueued),
              onPauseAll: state.local.pauseAll,
              onResumeAll: state.local.resumeAll,
              onClearCompleted: state.local.clearCompleted,
              onCancelAll: state.local.cancelAll,
            ),
          ),
          SliverToBoxAdapter(
            child: _FilterBar(
              tasks: all,
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          if (local.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(filtered: _filter != null),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.builder(
                itemCount: local.length,
                itemBuilder: (context, i) => _DownloadCard(task: local[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Type chips derived from the kinds actually present in the queue.
class _FilterBar extends StatelessWidget {
  final List<LocalTask> tasks;
  final FileKind? selected;
  final ValueChanged<FileKind?> onChanged;

  const _FilterBar({
    required this.tasks,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final present = <FileKind>{};
    for (final t in tasks) {
      present.add(kindOf(t.filename));
    }
    final ordered = FileKind.values.where(present.contains).toList();
    if (ordered.length <= 1) return const SizedBox.shrink();

    final accent = context.palette.accent;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        children: [
          _Chip(
            label: 'All',
            count: tasks.length,
            selected: selected == null,
            accent: accent,
            onTap: () => onChanged(null),
          ),
          for (final kind in ordered) ...[
            const SizedBox(width: 8),
            _Chip(
              label: kind.label,
              count: tasks.where((t) => kindOf(t.filename) == kind).length,
              selected: selected == kind,
              accent: accent,
              onTap: () => onChanged(kind),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.16) : p.bgSecondary,
          borderRadius: TurboRadius.all(TurboRadius.sm),
          border: Border.all(
            color: selected ? accent : p.borderSubtle,
          ),
        ),
        child: Text(
          '$label · $count',
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: selected ? p.textPrimary : p.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool hasCompleted;
  final bool anyPaused;
  final bool anyRunning;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;
  final VoidCallback onClearCompleted;
  final VoidCallback onCancelAll;

  const _Toolbar({
    required this.hasCompleted,
    required this.anyPaused,
    required this.anyRunning,
    required this.onPauseAll,
    required this.onResumeAll,
    required this.onClearCompleted,
    required this.onCancelAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: anyRunning ? onPauseAll : null,
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
              label: const Text('Pause all'),
            ),
            TextButton.icon(
              onPressed: anyPaused ? onResumeAll : null,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
              label: const Text('Resume all'),
            ),
            if (anyRunning)
              TextButton.icon(
                onPressed: onCancelAll,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Cancel all'),
              ),
            if (hasCompleted)
              TextButton.icon(
                onPressed: onClearCompleted,
                icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                label: const Text('Clear done'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int active;
  final int speed;
  final int done;
  final int bytes;
  const _StatsBar({
    required this.active,
    required this.speed,
    required this.done,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        children: [
          StatTile(
            label: 'Active',
            value: '$active',
            color: p.accent,
            icon: Icons.bolt_rounded,
          ),
          StatTile(
            label: 'Speed',
            value: formatSpeed(speed),
            color: turboSpeedColor(context, speed),
            icon: Icons.speed_rounded,
          ),
          StatTile(
            label: 'Done',
            value: '$done',
            color: p.success,
            icon: Icons.check_rounded,
          ),
          StatTile(
            label: 'Total',
            value: formatBytes(bytes),
            color: p.textSecondary,
            icon: Icons.sd_storage_rounded,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.download_for_offline_outlined,
      title: filtered ? 'Nothing of this type' : 'Queue empty',
      message: filtered
          ? 'No downloads match this filter.'
          : 'Open the Add tab to start a transfer.\nFiles land in your '
              'Downloads folder.',
    );
  }
}

/// Shared card chrome: status rail on the left, hairline border, tight radius.
class _TaskCard extends StatelessWidget {
  final Color railColor;
  final bool railStrong;
  final Widget child;

  const _TaskCard({
    required this.railColor,
    required this.child,
    this.railStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: TurboRadius.all(TurboRadius.sm),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: railColor.withOpacity(railStrong ? 1.0 : 0.6),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String filename;
  final Widget subtitle;
  final Widget trailing;

  const _CardHeader({
    required this.icon,
    required this.color,
    required this.filename,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: TurboRadius.all(TurboRadius.sm),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: p.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 5),
              subtitle,
            ],
          ),
        ),
        const SizedBox(width: 6),
        trailing,
      ],
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final LocalTask task;
  const _DownloadCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kind = kindOf(task.filename);
    final meta = _meta(context);

    return _TaskCard(
      railColor: meta.$2,
      railStrong: task.isRunning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: kindIcon(kind),
            color: kindColor(context, kind),
            filename: task.filename,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(status: task.status),
                    Kicker('${task.connections} conn',
                        size: 9, letterSpacing: 1.0),
                    if (task.kind == 'media')
                      EngineTag(usesYtdlp: task.usesYtdlp),
                    if (task.attempts > 0 && !task.isCompleted)
                      TurboChip(
                        label: 'Attempt ${task.attempts}',
                        tone: p.warning,
                        dense: true,
                      ),
                  ],
                ),
                if (task.mediaAuthor != null &&
                    task.mediaAuthor!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      task.mediaAuthor!,
                      if (task.mediaDuration != null)
                        formatDuration(task.mediaDuration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: p.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
            trailing: _actions(context),
          ),
          if (task.isRunning || task.isPaused) ...[
            const SizedBox(height: 12),
            TurboProgressBar(
              value: task.progress,
              color: task.isPaused ? p.warning : p.accent,
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${formatBytes(task.downloaded)} / '
                    '${task.total > 0 ? formatBytes(task.total) : '—'}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: p.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  task.isPaused
                      ? 'Paused'
                      : (task.isPreparing
                          ? 'Connecting…'
                          : '${formatSpeed(task.speed)} · '
                              '${formatEta(task.total - task.downloaded, task.speed)}'),
                  style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: task.isPaused ? p.warning : p.accent,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (task.awaitingRetry) ...[
            const SizedBox(height: 10),
            Notice(
              icon: Icons.restart_alt_rounded,
              color: p.warning,
              text: 'Retrying automatically — attempt ${task.attempts + 1}.',
            ),
          ],
          if (task.isFailed && task.error != null) ...[
            const SizedBox(height: 10),
            _ErrorNotice(task: task),
          ],
          if (task.canOpen) ...[
            const SizedBox(height: 12),
            _SavedRow(
              onOpen: () => _open(context),
              onShare: () => _share(context),
              filename: task.filename,
              meta: task.filePath,
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _meta(BuildContext context) {
    final p = context.palette;
    if (task.isFailed) return (Icons.error_outline_rounded, p.error);
    if (task.isCompleted) return (Icons.check_circle_rounded, p.success);
    if (task.isPaused) return (Icons.pause_circle_rounded, p.warning);
    if (task.isRunning) return (Icons.downloading_rounded, p.accent);
    if (task.awaitingRetry) return (Icons.restart_alt_rounded, p.warning);
    return (Icons.schedule_rounded, p.textSecondary);
  }

  void _open(BuildContext context) {
    final path = task.filePath;
    if (path == null || path.isEmpty) return;
    FileStore.open(path);
  }

  Future<void> _share(BuildContext context) async {
    final path = task.filePath;
    if (path == null || path.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await FileStore.share(path, filename: task.filename);
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not share this file.')),
      );
    }
  }

  Widget _actions(BuildContext context) {
    final p = context.palette;
    final state = context.read<TurboState>();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textSecondary, size: 20),
      color: p.bgTertiary,
      onSelected: (value) {
        switch (value) {
          case 'pause':
            state.local.pause(task.id);
            break;
          case 'resume':
            state.local.resume(task.id);
            break;
          case 'retry':
            state.local.retry(task.id);
            break;
          case 'open':
            _open(context);
            break;
          case 'share':
            _share(context);
            break;
          case 'details':
            showDialog<void>(
              context: context,
              builder: (_) => _ErrorDialog(task: task),
            );
            break;
          case 'remove':
            state.local.remove(task.id);
            break;
        }
      },
      itemBuilder: (context) => [
        if (task.isRunning || task.isQueued)
          _menuItem(context, 'pause', Icons.pause_rounded, 'Pause'),
        if (task.isPaused)
          _menuItem(context, 'resume', Icons.play_arrow_rounded, 'Resume'),
        if (task.isFailed) _menuItem(context, 'retry', Icons.refresh_rounded, 'Retry'),
        if (task.canOpen) _menuItem(context, 'open', Icons.open_in_new_rounded, 'Open'),
        if (task.canOpen)
          _menuItem(context, 'share', Icons.ios_share_rounded, 'Share'),
        if (task.errorDetail != null)
          _menuItem(context, 'details', Icons.info_outline_rounded, 'Details'),
        _menuItem(context, 'remove', Icons.delete_outline_rounded, 'Delete'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
          BuildContext context, String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.palette.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textPrimary,
                    fontSize: 13)),
          ],
        ),
      );
}

/// The failure banner on a card, with an affordance for technical details.
class _ErrorNotice extends StatelessWidget {
  final LocalTask task;
  const _ErrorNotice({required this.task});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Notice(
      icon: Icons.error_outline_rounded,
      color: p.error,
      text: task.error!,
      trailing: task.errorDetail == null
          ? null
          : IconButton(
              tooltip: 'Technical details',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.info_outline_rounded, color: p.error, size: 18),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ErrorDialog(task: task),
              ),
            ),
    );
  }
}

class _ErrorDialog extends StatelessWidget {
  final LocalTask task;
  const _ErrorDialog({required this.task});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: const Text('Download error'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(task.error ?? 'Unknown error',
                style: TextStyle(
                    fontFamily: TurboFonts.body, color: p.textPrimary)),
            if (task.errorKind != null) ...[
              const SizedBox(height: 12),
              Kicker('Category: ${task.errorKind}'),
            ],
            if (task.errorDetail != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.bgTertiary,
                  borderRadius: TurboRadius.all(TurboRadius.sm),
                ),
                child: SelectableText(
                  task.errorDetail!,
                  style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: p.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// "Saved to your Downloads" strip shown on completed downloads.
class _SavedRow extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final String? meta;
  final String filename;
  const _SavedRow({
    required this.onOpen,
    required this.onShare,
    required this.filename,
    this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: p.success.withOpacity(0.08),
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.success.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, color: p.success, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved to Downloads/${FileStore.subfolderFor(filename)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: p.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta != null && meta!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: p.textMuted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: onShare,
            icon: Icon(Icons.ios_share_rounded, color: p.textSecondary, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open',
                style: TextStyle(
                    fontFamily: TurboFonts.body,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
