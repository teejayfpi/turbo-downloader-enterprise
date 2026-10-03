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
Color kindColor(FileKind kind) => switch (kind) {
      FileKind.video => TurboColors.accent,
      FileKind.audio => TurboColors.speedUltra,
      FileKind.image => TurboColors.warning,
      FileKind.archive => const Color(0xFFB98CFF),
      FileKind.document => TurboColors.textSecondary,
      FileKind.app => TurboColors.success,
      FileKind.other => TurboColors.textSecondary,
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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: TurboColors.bgSecondary,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: TurboColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12, color: TurboColors.textMuted),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Kicker(label, size: 9, letterSpacing: 1.4),
                  ),
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

/// Colour-coded status chip shared by both the on-device and server lists.
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill({super.key, required this.status});

  static (Color, String) resolve(String status) => switch (status) {
        'active' => (TurboColors.accent, 'Active'),
        'completed' => (TurboColors.success, 'Completed'),
        'failed' => (TurboColors.error, 'Failed'),
        'paused' => (TurboColors.warning, 'Paused'),
        'scheduled' => (TurboColors.speedUltra, 'Scheduled'),
        _ => (TurboColors.textMuted, 'Queued'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: TurboFonts.mono,
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: TurboColors.textMuted),
          const SizedBox(width: 8),
          Kicker(title, letterSpacing: 2.2),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(color: TurboColors.borderSubtle, height: 1),
          ),
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
        borderRadius: BorderRadius.circular(4),
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
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: TurboColors.borderSubtle),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                option: options[i],
                selected: value == options[i].value,
                accent: accent,
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: selected ? accent.withOpacity(0.7) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(option.icon,
                size: 16, color: selected ? accent : TurboColors.textMuted),
            const SizedBox(width: 8),
            Text(
              option.label,
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color:
                    selected ? TurboColors.textPrimary : TurboColors.textMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a download `kind` to an icon + tone, shared by both list cards.
class KindMeta {
  final IconData icon;
  final Color color;
  const KindMeta(this.icon, this.color);

  static KindMeta forKind(String kind) => switch (kind) {
        'media' => const KindMeta(Icons.movie_rounded, TurboColors.accent),
        'archive' =>
          const KindMeta(Icons.folder_zip_rounded, TurboColors.warning),
        'image' => const KindMeta(Icons.image_rounded, TurboColors.speedUltra),
        'document' =>
          const KindMeta(Icons.description_rounded, TurboColors.textSecondary),
        _ => const KindMeta(
            Icons.insert_drive_file_rounded, TurboColors.textSecondary),
      };
}

/// A progress bar with an animated stripe overlay while a transfer runs.
class TurboProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const TurboProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.isFinite ? value.clamp(0.0, 1.0) : null,
        minHeight: height,
        backgroundColor: TurboColors.bgTertiary,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
