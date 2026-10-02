import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../downloader.dart';
import '../format.dart';
import '../local_downloader.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final local = state.local.tasks;
    final server = state.downloads;

    if (state.loading && local.isEmpty && server.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _StatsBar(
              active: local.where((t) => t.isActive).length +
                  state.stats.activeCount,
              speed: local.fold<int>(0, (n, t) => n + t.speed) +
                  state.stats.totalSpeed,
              done: local.where((t) => t.isCompleted).length +
                  state.stats.completedCount,
              bytes: local.fold<int>(0, (n, t) => n + t.downloaded) +
                  state.stats.totalDownloaded,
            ),
          ),
          if (state.lastError != null)
            SliverToBoxAdapter(child: _ErrorBanner(message: state.lastError!)),
          if (local.isEmpty && server.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else ...[
            if (local.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(
                  icon: Icons.phone_android_rounded,
                  title: 'On this device',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                sliver: SliverList.builder(
                  itemCount: local.length,
                  itemBuilder: (context, i) => _LocalCard(task: local[i]),
                ),
              ),
            ],
            if (server.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(
                  icon: Icons.dns_rounded,
                  title: 'On the server',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverList.builder(
                  itemCount: server.length,
                  itemBuilder: (context, i) =>
                      _DownloadCard(task: server[i]),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: TurboColors.textMuted),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: TurboColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _Stat(
            label: 'Active',
            value: '$active',
            color: TurboColors.accent,
          ),
          _Stat(
            label: 'Speed',
            value: formatSpeed(speed),
            color: TurboColors.speedUltra,
          ),
          _Stat(
            label: 'Done',
            value: '$done',
            color: TurboColors.success,
          ),
          _Stat(
            label: 'Total',
            value: formatBytes(bytes),
            color: TurboColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: TurboColors.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TurboColors.borderSubtle),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: TurboColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurboColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TurboColors.error.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: TurboColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: TurboColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_for_offline_outlined,
            size: 64,
            color: TurboColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 14),
          const Text(
            'No downloads yet',
            style: TextStyle(
              color: TurboColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Open the Add tab to start one',
            style: TextStyle(color: TurboColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LocalCard extends StatelessWidget {
  final LocalTask task;
  const _LocalCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.read<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;
    final (icon, color) = _meta();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TurboColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _StatusPill(status: task.status),
                        const SizedBox(width: 6),
                        Text(
                          '${task.connections} conn',
                          style: const TextStyle(
                            color: TurboColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: TurboColors.textSecondary, size: 20),
                color: TurboColors.bgTertiary,
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
                    case 'remove':
                      state.local.remove(task.id);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (task.isActive || task.isQueued)
                    _item('pause', Icons.pause_rounded, 'Pause'),
                  if (task.isPaused)
                    _item('resume', Icons.play_arrow_rounded, 'Resume'),
                  if (task.isFailed)
                    _item('retry', Icons.refresh_rounded, 'Retry'),
                  if (task.canOpen) _item('open', Icons.open_in_new_rounded, 'Open'),
                  _item('remove', Icons.delete_outline_rounded, 'Delete'),
                ],
              ),
            ],
          ),
          if (task.isActive || task.isPaused) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 6,
                backgroundColor: TurboColors.bgTertiary,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / '
                  '${task.total > 0 ? formatBytes(task.total) : '—'}',
                  style: const TextStyle(
                      color: TurboColors.textSecondary, fontSize: 11),
                ),
                Text(
                  task.isActive ? formatSpeed(task.speed) : 'Paused',
                  style: const TextStyle(
                      color: TurboColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
          if (task.isFailed && task.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: TurboColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: TurboColors.error, fontSize: 11),
              ),
            ),
          ],
          if (task.canOpen) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: TurboColors.success, size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Saved to your Downloads',
                    style: TextStyle(
                        color: TurboColors.success, fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Open', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _meta() {
    if (task.isFailed) return (Icons.error_outline_rounded, TurboColors.error);
    if (task.isCompleted) {
      return (Icons.check_circle_rounded, TurboColors.success);
    }
    if (task.isPaused) {
      return (Icons.pause_circle_rounded, TurboColors.warning);
    }
    if (task.isActive) return (Icons.downloading_rounded, TurboColors.accent);
    return (Icons.schedule_rounded, TurboColors.textSecondary);
  }

  void _open(BuildContext context) {
    final path = task.filePath;
    if (path == null || path.isEmpty) return;
    OpenFilex.open(path);
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: TurboColors.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: TurboColors.textPrimary, fontSize: 13)),
          ],
        ),
      );
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  const _DownloadCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.read<TurboState>();
    final meta = _metaFor(task);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: meta.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meta.icon, color: meta.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TurboColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _StatusPill(status: task.status),
                        const SizedBox(width: 6),
                        if (task.platform.isNotEmpty)
                          Text(
                            task.platform,
                            style: const TextStyle(
                              color: TurboColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _actions(context, state),
            ],
          ),
          if (task.isActive) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (task.progress / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: TurboColors.bgTertiary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / ${formatBytes(task.total)}',
                  style: const TextStyle(
                    color: TurboColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${formatSpeed(task.speed)}'
                  '${task.eta != null ? ' · ${formatDuration(task.eta)} left' : ''}',
                  style: const TextStyle(
                    color: TurboColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (task.isFailed && task.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: TurboColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TurboColors.error,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, TurboState state) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded,
          color: TurboColors.textSecondary, size: 20),
      color: TurboColors.bgTertiary,
      onSelected: (value) async {
        switch (value) {
          case 'pause':
            await state.run(() => state.api.pause(task.id));
            break;
          case 'resume':
            await state.run(() => state.api.resume(task.id));
            break;
          case 'retry':
            await state.run(() => state.api.retry(task.id));
            break;
          case 'start':
            await state.run(() => state.api.start(task.id));
            break;
          case 'save':
            await _saveToDevice(context);
            break;
          case 'delete_file':
            await state.run(() => state.api.remove(task.id, deleteFile: true));
            break;
          case 'remove':
            await state.run(() => state.api.remove(task.id));
            break;
        }
      },
      itemBuilder: (context) => [
        if (task.isActive) _item('pause', Icons.pause_rounded, 'Pause'),
        if (task.isPaused) _item('resume', Icons.play_arrow_rounded, 'Resume'),
        if (task.isFailed) _item('retry', Icons.refresh_rounded, 'Retry'),
        if (task.isQueued) _item('start', Icons.play_arrow_rounded, 'Start now'),
        if (task.canRetrieve)
          _item('save', Icons.download_rounded, 'Save to device'),
        if (task.isCompleted)
          _item('delete_file', Icons.delete_forever_rounded, 'Delete file'),
        _item('remove', Icons.close_rounded, 'Remove from list'),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: TurboColors.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: TurboColors.textPrimary, fontSize: 13)),
          ],
        ),
      );

  Future<void> _saveToDevice(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double?>(null);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: TurboColors.bgSecondary,
        title: const Text('Saving to device',
            style: TextStyle(color: TurboColors.textPrimary, fontSize: 16)),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.filename,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: TurboColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: TurboColors.bgTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final state = context.read<TurboState>();
      await FileDownloader.saveAndOpen(
        url: state.api.fileUrl(task.id),
        filename: task.filename,
        onProgress: (received, total) {
          progress.value = total == null || total <= 0 ? null : received / total;
        },
      );
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${task.filename} to Downloads')),
      );
    } on ApiException catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('Could not save file: $e')));
    }
  }

  _KindMeta _metaFor(DownloadTask task) {
    if (task.isFailed) {
      return const _KindMeta(Icons.error_outline_rounded, TurboColors.error);
    }
    if (task.isCompleted) {
      return const _KindMeta(Icons.check_circle_rounded, TurboColors.success);
    }
    if (task.isPaused) {
      return const _KindMeta(Icons.pause_circle_rounded, TurboColors.warning);
    }
    if (task.isActive) {
      return const _KindMeta(Icons.downloading_rounded, TurboColors.accent);
    }
    switch (task.kind) {
      case 'media':
        return const _KindMeta(Icons.movie_rounded, TurboColors.accent);
      case 'archive':
        return const _KindMeta(Icons.folder_zip_rounded, TurboColors.warning);
      case 'image':
        return const _KindMeta(Icons.image_rounded, TurboColors.speedUltra);
      case 'document':
        return const _KindMeta(
            Icons.description_rounded, TurboColors.textSecondary);
      default:
        return const _KindMeta(
            Icons.insert_drive_file_rounded, TurboColors.textSecondary);
    }
  }
}

class _KindMeta {
  final IconData icon;
  final Color color;
  const _KindMeta(this.icon, this.color);
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'active' => (TurboColors.accent, 'Active'),
      'completed' => (TurboColors.success, 'Completed'),
      'failed' => (TurboColors.error, 'Failed'),
      'paused' => (TurboColors.warning, 'Paused'),
      'scheduled' => (TurboColors.speedUltra, 'Scheduled'),
      _ => (TurboColors.textMuted, 'Queued'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
