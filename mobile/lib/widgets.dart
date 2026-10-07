import 'package:flutter/material.dart';

import 'media_url.dart';
import 'theme.dart';

/// Icon for a detected [FileKind], used across the queue and pickers.
IconData kindIcon(FileKind kind) => switch (kind) {
      FileKind.video => Icons.movie_rounded,
      FileKind.audio => Icons.music_note_rounded,
      FileKind.image => Icons.image_rounded,
      FileKind.archive => Icons.folder_zip_rounded,
      FileKind.document => Icons.description_rounded,
      FileKind.app => Icons.terminal_rounded,
      FileKind.other => Icons.insert_drive_file_rounded,
    };

/// Accent tone for a detected [FileKind].
Color kindColor(BuildContext context, FileKind kind) => switch (kind) {
      FileKind.video => context.palette.accent,
      FileKind.audio => context.palette.speedUltra,
      FileKind.image => context.palette.warning,
      FileKind.archive => const Color(0xFFB98CFF),
      FileKind.document => context.palette.textSecondary,
      FileKind.app => context.palette.success,
      FileKind.other => context.palette.textSecondary,
    };

/// A compact metric readout. Values are rendered in a tabular mono face so
/// digits do not jitter as they update.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: p.bgSecondary,
            borderRadius: TurboRadius.all(TurboRadius.sm),
            border: Border.all(color: p.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12, color: p.textMuted),
                    const SizedBox(width: 5),
                  ],
                  Expanded(child: Kicker(label, size: 9, letterSpacing: 1.4)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour-coded status chip shared by every download list.
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill({super.key, required this.status});

  static (Color, String) resolve(BuildContext context, String status) =>
      switch (status) {
        'active' => (context.palette.accent, 'Downloading'),
        'preparing' => (context.palette.speedFast, 'Connecting'),
        'completed' => (context.palette.success, 'Completed'),
        'failed' => (context.palette.error, 'Failed'),
        'paused' => (context.palette.warning, 'Paused'),
        'scheduled' => (context.palette.speedUltra, 'Scheduled'),
        _ => (context.palette.textMuted, 'Queued'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = resolve(context, status);
    return TurboChip(label: label, tone: color, dense: true);
  }
}

/// Uppercase section header with a hairline rule, matching the web console.
class SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const SectionLabel({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: p.textMuted),
          const SizedBox(width: 8),
          Kicker(title, letterSpacing: 2.2),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: p.borderSubtle, height: 1)),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Kicker(trailing!, letterSpacing: 1.6),
          ],
        ],
      ),
    );
  }
}

/// Inline informational banner.
class Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? trailing;

  const Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: TurboRadius.all(TurboRadius.sm),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: color,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Segmented control used to switch a choice between two options.
class ModeSegment extends StatelessWidget {
  final List<ModeSegmentOption> options;
  final String value;
  final ValueChanged<String> onChanged;

  const ModeSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: TurboRadius.all(TurboRadius.md),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                option: options[i],
                selected: value == options[i].value,
                accent: p.accent,
                onTap: () => onChanged(options[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ModeSegmentOption {
  final String value;
  final IconData icon;
  final String label;
  const ModeSegmentOption(this.value, this.icon, this.label);
}

class _Segment extends StatelessWidget {
  final ModeSegmentOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.14) : Colors.transparent,
          borderRadius: TurboRadius.all(TurboRadius.sm),
          border: Border.all(
              color: selected ? accent.withOpacity(0.7) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(option.icon, size: 16, color: selected ? accent : p.textMuted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: selected ? p.textPrimary : p.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a download `kind` to an icon + tone, shared by every list card.
class KindMeta {
  final IconData icon;
  final Color color;
  const KindMeta(this.icon, this.color);

  static KindMeta forKind(BuildContext context, String kind) =>
      switch (kind) {
        'media' => KindMeta(Icons.movie_rounded, context.palette.accent),
        'archive' =>
          KindMeta(Icons.folder_zip_rounded, context.palette.warning),
        'image' => KindMeta(Icons.image_rounded, context.palette.speedUltra),
        'document' =>
          KindMeta(Icons.description_rounded, context.palette.textSecondary),
        _ => KindMeta(
            Icons.insert_drive_file_rounded, context.palette.textSecondary),
      };
}

/// A centred empty state with an icon, title, message, and optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: p.accent),
            ),
            const SizedBox(height: 18),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TurboFonts.display,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                fontSize: 13,
                height: 1.5,
                color: p.textSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small label chip used on cards (engine, kind, etc.).
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => TurboChip(
        label: text,
        tone: color,
        dense: true,
      );
}

/// The engine tag shown on a task card: yt-dlp, or the built-in engine.
class EngineTag extends StatelessWidget {
  final bool usesYtdlp;
  const EngineTag({super.key, required this.usesYtdlp});

  @override
  Widget build(BuildContext context) => usesYtdlp
      ? _Tag('YT-DLP', context.palette.accent)
      : _Tag('BUILT-IN', context.palette.speedUltra);
}

/// Lightweight feedback helpers, so screens do not each build a SnackBar.
extension TurboFeedbackX on BuildContext {
  void showOk(String message) => ScaffoldMessenger.of(this).showSnackBar(
        SnackBar(content: Text(message)),
      );

  void showErr(String message) => ScaffoldMessenger.of(this).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: palette.error,
        ),
      );
}
