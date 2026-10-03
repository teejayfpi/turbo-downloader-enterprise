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
import '../widgets.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final local = state.local.tasks;
    final server = state.downloads;

    if (state.loading && local.isEmpty && server.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
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
              SliverToBoxAdapter(
                child: SectionLabel(
                  icon: Icons.phone_android_rounded,
                  title: 'On this device',
                  trailing: '${local.length}',
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
              SliverToBoxAdapter(
                child: SectionLabel(
                  icon: Icons.dns_rounded,
                  title: 'On the server',
                  trailing: '${server.length}',
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
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        children: [
          StatTile(
            label: 'Active',
            value: '$active',
            color: TurboColors.accent,
            icon: Icons.bolt_rounded,
          ),
          StatTile(
            label: 'Speed',
            value: formatSpeed(speed),
            color: TurboColors.speedUltra,
            icon: Icons.speed_rounded,
          ),
          StatTile(
            label: 'Done',
            value: '$done',
            color: TurboColors.success,
            icon: Icons.check_rounded,
          ),
          StatTile(
            label: 'Total',
            value: formatBytes(bytes),
            color: TurboColors.textSecondary,
            icon: Icons.sd_storage_rounded,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Notice(
        icon: Icons.wifi_off_rounded,
        color: TurboColors.error,
        text: message,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: TurboColors.bgSecondary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: TurboColors.borderSubtle),
            ),
            child: Icon(
              Icons.download_for_offline_outlined,
              size: 32,
              color: accent.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          const Kicker('Queue empty', letterSpacing: 2.4, size: 11),
          const SizedBox(height: 8),
          const Text(
            'Open the Add tab to start a transfer.\nFiles land in your Downloads folder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: TurboColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
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
                style: const TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textPrimary,
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

class _LocalCard extends StatelessWidget {
  final LocalTask task;
  const _LocalCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    final railColor = meta.$2;

    return _TaskCard(
      railColor: railColor,
      railStrong: task.isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: meta.$1,
            color: railColor,
            filename: task.filename,
            subtitle: Row(
              children: [
                StatusPill(status: task.status),
                const SizedBox(width: 6),
                Kicker('${task.connections} conn', size: 9, letterSpacing: 1.0),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: TurboColors.textSecondary, size: 20),
              color: TurboColors.bgTertiary,
              onSelected: (value) {
                final state = context.read<TurboState>();
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
                  _menuItem('pause', Icons.pause_rounded, 'Pause'),
                if (task.isPaused)
                  _menuItem('resume', Icons.play_arrow_rounded, 'Resume'),
                if (task.isFailed)
                  _menuItem('retry', Icons.refresh_rounded, 'Retry'),
                if (task.canOpen)
                  _menuItem('open', Icons.open_in_new_rounded, 'Open'),
                _menuItem('remove', Icons.delete_outline_rounded, 'Delete'),
              ],
            ),
          ),
          if (task.isActive || task.isPaused) ...[
            const SizedBox(height: 12),
            TurboProgressBar(
              value: task.progress,
              color: task.isPaused
                  ? TurboColors.warning
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / '
                  '${task.total > 0 ? formatBytes(task.total) : '—'}',
                  style: const TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: TurboColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  task.isActive ? formatSpeed(task.speed) : 'Paused',
                  style: TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: task.isActive
                        ? Theme.of(context).colorScheme.primary
                        : TurboColors.warning,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (task.isFailed && task.error != null) ...[
            const SizedBox(height: 10),
            Notice(
              icon: Icons.error_outline_rounded,
              color: TurboColors.error,
              text: task.error!,
            ),
          ],
          if (task.canOpen) ...[
            const SizedBox(height: 12),
            _SavedRow(
              onOpen: () => _open(context),
              meta: task.filePath != null && task.filePath!.isNotEmpty
                  ? task.filePath!
                  : null,
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

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: TurboColors.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontFamily: TurboFonts.body,
                    color: TurboColors.textPrimary,
                    fontSize: 13)),
          ],
        ),
      );
}

/// "Saved to your Downloads" strip shown on completed device downloads.
class _SavedRow extends StatelessWidget {
  final VoidCallback onOpen;
  final String? meta;
  const _SavedRow({required this.onOpen, this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: TurboColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: TurboColors.success.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded,
              color: TurboColors.success, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saved to your Downloads folder',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: TurboColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: TurboColors.textMuted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
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

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  const _DownloadCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(task);

    return _TaskCard(
      railColor: meta.color,
      railStrong: task.isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: meta.icon,
            color: meta.color,
            filename: task.filename,
            subtitle: Row(
              children: [
                StatusPill(status: task.status),
                if (task.platform.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Kicker(task.platform, size: 9, letterSpacing: 1.0),
                ],
                if (task.kind == 'media') ...[
                  const SizedBox(width: 6),
                  const _MediaTag(),
                ],
              ],
            ),
            trailing: _actions(context),
          ),
          if (task.isActive) ...[
            const SizedBox(height: 12),
            TurboProgressBar(
              value: task.progress / 100,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / ${formatBytes(task.total)}',
                  style: const TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: TurboColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${formatSpeed(task.speed)}'
                  '${task.eta != null ? ' · ${formatDuration(task.eta)}' : ''}',
                  style: const TextStyle(
                    fontFamily: TurboFonts.mono,
                    color: TurboColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (task.isFailed && task.error != null) ...[
            const SizedBox(height: 10),
            Notice(
              icon: Icons.error_outline_rounded,
              color: TurboColors.error,
              text: task.error!,
            ),
          ],
          if (task.canRetrieve) ...[
            const SizedBox(height: 12),
            _SaveToDeviceButton(onTap: () => _saveToDevice(context)),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final state = context.read<TurboState>();
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
        if (task.isActive) _menuItem('pause', Icons.pause_rounded, 'Pause'),
        if (task.isPaused)
          _menuItem('resume', Icons.play_arrow_rounded, 'Resume'),
        if (task.isFailed) _menuItem('retry', Icons.refresh_rounded, 'Retry'),
        if (task.isQueued)
          _menuItem('start', Icons.play_arrow_rounded, 'Start now'),
        if (task.canRetrieve)
          _menuItem('save', Icons.download_rounded, 'Save to device'),
        if (task.isCompleted)
          _menuItem(
              'delete_file', Icons.delete_forever_rounded, 'Delete file'),
        _menuItem('remove', Icons.close_rounded, 'Remove from list'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: TurboColors.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontFamily: TurboFonts.body,
                    color: TurboColors.textPrimary,
                    fontSize: 13)),
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
        title: const Text('Saving to device'),
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
                    fontFamily: TurboFonts.body,
                    color: TurboColors.textSecondary,
                    fontSize: 12),
              ),
              const SizedBox(height: 14),
              TurboProgressBar(
                value: value ?? 0,
                color: Theme.of(context).colorScheme.primary,
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

  KindMeta _metaFor(DownloadTask task) {
    if (task.isFailed) {
      return const KindMeta(Icons.error_outline_rounded, TurboColors.error);
    }
    if (task.isCompleted) {
      return const KindMeta(Icons.check_circle_rounded, TurboColors.success);
    }
    if (task.isPaused) {
      return const KindMeta(Icons.pause_circle_rounded, TurboColors.warning);
    }
    if (task.isActive) {
      return const KindMeta(Icons.downloading_rounded, TurboColors.accent);
    }
    return KindMeta.forKind(task.kind);
  }
}

class _MediaTag extends StatelessWidget {
  const _MediaTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: TurboColors.warning.withOpacity(0.16),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'MEDIA',
        style: TextStyle(
          fontFamily: TurboFonts.mono,
          color: TurboColors.warning,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SaveToDeviceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SaveToDeviceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.download_rounded, color: accent, size: 17),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Save to this device',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  color: accent.withOpacity(0.6), size: 15),
            ],
          ),
        ),
      ),
    );
  }
}
