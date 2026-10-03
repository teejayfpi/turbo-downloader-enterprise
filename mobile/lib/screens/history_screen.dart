import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../file_store.dart';
import '../format.dart';
import '../media_url.dart';
import '../services/history_store.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The record of finished and failed transfers, with search, date filters,
/// per-entry actions, and CSV/JSON export.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _DateFilter { all, today, week, month }

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  _DateFilter _date = _DateFilter.all;
  FileKind? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  HistoryFilter get _filter {
    final now = DateTime.now();
    DateTime? from;
    switch (_date) {
      case _DateFilter.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case _DateFilter.week:
        from = now.subtract(const Duration(days: 7));
        break;
      case _DateFilter.month:
        from = now.subtract(const Duration(days: 30));
        break;
      case _DateFilter.all:
        break;
    }
    return HistoryFilter(
      query: _search.text,
      kind: _kind,
      from: from,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final p = context.palette;
    final entries = state.historyEntries(_filter);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search name, URL, or folder',
              prefixIcon: Icon(Icons.search_rounded,
                  color: p.textMuted, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: p.textMuted, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        _FilterRow(
          date: _date,
          kind: _kind,
          onDate: (d) => setState(() => _date = d),
          onKind: (k) => setState(() => _kind = k),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: entries.isEmpty
                    ? null
                    : () => _export(context, state, entries, csv: true),
                icon: const Icon(Icons.table_chart_outlined, size: 16),
                label: const Text('CSV'),
              ),
              TextButton.icon(
                onPressed: entries.isEmpty
                    ? null
                    : () => _export(context, state, entries, csv: false),
                icon: const Icon(Icons.data_object_rounded, size: 16),
                label: const Text('JSON'),
              ),
              const Spacer(),
              if (entries.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClear(context, state),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No history yet',
                  message: 'Finished and failed transfers appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, i) =>
                      _HistoryCard(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    TurboState state,
    List<HistoryEntry> rows, {
    required bool csv,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = csv ? state.history.toCsv(rows) : state.history.toJson(rows);
    await Clipboard.setData(ClipboardData(text: data));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${rows.length} entr${rows.length == 1 ? 'y' : 'ies'} as '
          '${csv ? 'CSV' : 'JSON'} to the clipboard.',
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, TurboState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes the record of past transfers. Downloaded files are not '
          'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await state.clearHistory();
  }
}

class _FilterRow extends StatelessWidget {
  final _DateFilter date;
  final FileKind? kind;
  final ValueChanged<_DateFilter> onDate;
  final ValueChanged<FileKind?> onKind;

  const _FilterRow({
    required this.date,
    required this.kind,
    required this.onDate,
    required this.onKind,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        children: [
          for (final d in _DateFilter.values) ...[
            _Pill(
              label: switch (d) {
                _DateFilter.all => 'All time',
                _DateFilter.today => 'Today',
                _DateFilter.week => '7 days',
                _DateFilter.month => '30 days',
              },
              selected: date == d,
              onTap: () => onDate(d),
            ),
            const SizedBox(width: 8),
          ],
          if (kind != null) ...[
            _Pill(
              label: '${kind!.label} ✕',
              selected: true,
              onTap: () => onKind(null),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
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
          color: selected ? p.accent.withOpacity(0.16) : p.bgSecondary,
          borderRadius: TurboRadius.all(TurboRadius.sm),
          border: Border.all(color: selected ? p.accent : p.borderSubtle),
        ),
        child: Text(
          label,
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

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final completed = entry.isCompleted;
    final tone = completed ? p.success : p.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withOpacity(0.12),
                    borderRadius: TurboRadius.all(TurboRadius.sm),
                  ),
                  child: Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: tone,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.filename,
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
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: p.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                _actions(context),
              ],
            ),
            if (!completed && entry.errorMessage != null) ...[
              const SizedBox(height: 10),
              Notice(
                icon: Icons.error_outline_rounded,
                color: p.error,
                text: entry.errorMessage!,
              ),
            ],
            if (completed && entry.filePath != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved to ${entry.destination ?? 'Downloads'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => FileStore.open(entry.filePath!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Open'),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.ios_share_rounded,
                        color: p.textSecondary, size: 18),
                    onPressed: () => FileStore.share(entry.filePath!,
                        filename: entry.filename),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      formatRelative(entry.finishedAt),
      if (entry.size > 0) formatBytes(entry.size),
      if (entry.averageSpeed != null && entry.averageSpeed! > 0)
        formatSpeed(entry.averageSpeed!),
    ];
    return parts.join(' · ');
  }

  Widget _actions(BuildContext context) {
    final state = context.read<TurboState>();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          color: context.palette.textSecondary, size: 20),
      color: context.palette.bgTertiary,
      onSelected: (value) {
        switch (value) {
          case 'retry':
            final task = state.local.add(
              entry.url,
              filename: entry.filename,
            );
            // The task id is generated by the manager; retry uses the live id.
            state.local.retry(task.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Re-queued this download.')),
            );
            break;
          case 'copy':
            Clipboard.setData(ClipboardData(text: entry.url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link copied.')),
            );
            break;
          case 'delete':
            state.deleteHistoryEntry(entry.id);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'retry',
          child: Text('Download again',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: context.palette.textPrimary,
                  fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Text('Copy link',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: context.palette.textPrimary,
                  fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text('Remove from history',
              style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: context.palette.textPrimary,
                  fontSize: 13)),
        ),
      ],
    );
  }
}
