import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// A quiet view of the local diagnostic log, with a one-tap copyable bundle.
/// Nothing here leaves the device unless the user copies and shares it.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final p = context.palette;
    final events = state.diagnostics.events;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy bundle',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(
                ClipboardData(text: state.diagnosticsBundle()),
              );
              messenger.showSnackBar(
                const SnackBar(content: Text('Diagnostic bundle copied.')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TurboPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('Privacy', letterSpacing: 2.0),
                const SizedBox(height: 10),
                Text(
                  'Diagnostics stay on this device. The log records error '
                  'categories and platform facts only — never URLs, filenames, '
                  'or file contents. Copying the bundle is always your choice.',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: p.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                TurboButton(
                  label: 'Copy diagnostic bundle',
                  icon: Icons.copy_all_rounded,
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(text: state.diagnosticsBundle()),
                    );
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text('Diagnostic bundle copied.')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Kicker('Recent events', letterSpacing: 2.0),
              const Spacer(),
              if (events.isNotEmpty)
                TextButton(
                  onPressed: () => state.clearDiagnostics(),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (events.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No events',
              message: 'Nothing to report — the engine is running cleanly.',
            )
          else
            for (final e in events)
              _EventRow(
                at: e.at,
                level: e.level,
                code: e.code,
                message: e.message,
              ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final DateTime at;
  final String level;
  final String code;
  final String message;
  const _EventRow({
    required this.at,
    required this.level,
    required this.code,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = switch (level) {
      'error' => p.error,
      'warning' => p.warning,
      _ => p.textSecondary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(code,
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                    const Spacer(),
                    Text(_time(at),
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: p.textMuted,
                          fontSize: 9.5,
                        )),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(message,
                      style: TextStyle(
                        fontFamily: TurboFonts.body,
                        color: p.textMuted,
                        fontSize: 11,
                        height: 1.4,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
