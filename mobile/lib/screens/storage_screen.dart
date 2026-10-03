import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../state.dart';
import '../theme.dart';

/// A focused storage view: how much room is left, what Turbo has downloaded,
/// what partial data can be reclaimed, and one tap to clean it up.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final p = context.palette;
    final stats = state.storageStats;
    final usedFraction =
        stats.totalBytes > 0 ? 1 - stats.freeFraction : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.refreshStorage,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TurboPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('Device volume', letterSpacing: 2.0),
                const SizedBox(height: 14),
                if (stats.totalBytes > 0) ...[
                  ClipRRect(
                    borderRadius: TurboRadius.all(TurboRadius.pill),
                    child: LinearProgressIndicator(
                      value: usedFraction.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: p.bgTertiary,
                      valueColor: AlwaysStoppedAnimation(stats.isCritical
                          ? p.error
                          : stats.isLow
                              ? p.warning
                              : p.accent),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _Row(
                  label: 'Available',
                  value: stats.freeBytes > 0
                      ? formatBytes(stats.freeBytes)
                      : 'Unknown',
                  tone: stats.isCritical
                      ? p.error
                      : stats.isLow
                          ? p.warning
                          : p.success,
                ),
                if (stats.totalBytes > 0)
                  _Row(
                    label: 'Total',
                    value: formatBytes(stats.totalBytes),
                    tone: p.textSecondary,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TurboPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('Turbo usage', letterSpacing: 2.0),
                const SizedBox(height: 12),
                _Row(
                  label: 'Downloaded',
                  value: formatBytes(stats.downloadedBytes),
                  tone: p.textPrimary,
                ),
                _Row(
                  label: 'Temporary (partial)',
                  value: formatBytes(stats.temporaryBytes),
                  tone: p.textPrimary,
                ),
                _Row(
                  label: 'App data',
                  value: formatBytes(stats.appDataBytes),
                  tone: p.textPrimary,
                ),
                _Row(
                  label: 'Partial files',
                  value: '${stats.partialFileCount}',
                  tone: p.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TurboButton(
            label: 'Clean up partial files',
            icon: Icons.cleaning_services_rounded,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final reclaimed = await state.cleanUpPartials();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(reclaimed > 0
                      ? 'Reclaimed ${formatBytes(reclaimed)}.'
                      : 'Nothing to clean up.'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Partial files are the pieces of interrupted or cancelled '
            'downloads. Removing them frees space; completed downloads are '
            'never touched.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;
  const _Row({required this.label, required this.value, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: context.palette.textSecondary,
                fontSize: 13,
              )),
          Text(value,
              style: TextStyle(
                fontFamily: TurboFonts.mono,
                color: tone,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
