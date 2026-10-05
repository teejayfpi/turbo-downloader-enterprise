import 'package:flutter/material.dart';

import '../format.dart';
import '../media_extractor.dart';
import '../state.dart';
import '../theme.dart';

/// Thumbnail + title + author + duration summary for a probed media page.
///
/// Shared by the Add screen and the in-app Browse download sheet so the
/// preview looks identical wherever a link is confirmed.
class MediaPreviewPanel extends StatelessWidget {
  final ProbeResult info;
  const MediaPreviewPanel({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final thumb = info.thumbnailUrl;
    return TurboPanel(
      padding: const EdgeInsets.all(12),
      accentColor: Theme.of(context).colorScheme.primary,
      clip: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 96,
              height: 56,
              color: context.palette.bgTertiary,
              child: thumb == null
                  ? Icon(Icons.movie_rounded, color: context.palette.textMuted)
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.movie_rounded,
                          color: context.palette.textMuted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    color: context.palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (info.author != null && info.author!.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          info.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: TurboFonts.body,
                            color: context.palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (info.durationSeconds != null) ...[
                      Icon(Icons.schedule_rounded,
                          size: 12, color: context.palette.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        formatDuration(info.durationSeconds),
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: context.palette.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (info.usedYtdlp
                                ? context.palette.accent
                                : context.palette.speedUltra)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        info.usedYtdlp ? 'ENGINE · YT-DLP' : 'ENGINE · BUILT-IN',
                        style: TextStyle(
                          fontFamily: TurboFonts.mono,
                          color: info.usedYtdlp
                              ? context.palette.accent
                              : context.palette.speedUltra,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${info.formats.length} formats',
                      style: TextStyle(
                        fontFamily: TurboFonts.mono,
                        color: context.palette.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of selectable renditions with a short explanation of the engine.
class FormatPickerPanel extends StatelessWidget {
  final List<MediaFormat> formats;
  final MediaFormat? selected;
  final bool canMux;
  final bool usedYtdlp;
  final ValueChanged<MediaFormat> onChanged;

  const FormatPickerPanel({
    super.key,
    required this.formats,
    required this.selected,
    required this.canMux,
    required this.usedYtdlp,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return TurboPanel(
      padding: const EdgeInsets.all(14),
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded,
                  color: context.palette.textMuted, size: 15),
              const SizedBox(width: 8),
              const Kicker('Quality', letterSpacing: 1.6),
              const Spacer(),
              if (!canMux && formats.any((f) => f.requiresMux))
                const Kicker('HD needs ffmpeg', size: 8.5, letterSpacing: 0.8),
            ],
          ),
          const SizedBox(height: 10),
          if (formats.isEmpty)
            Text(
              'No downloadable formats were listed for this page.',
              style: TextStyle(
                fontFamily: TurboFonts.body,
                color: context.palette.textMuted,
                fontSize: 11,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: formats.map((f) {
                final isSelected = selected?.id == f.id;
                final disabled = f.requiresMux && !canMux;
                return FormatChip(
                  format: f,
                  selected: isSelected,
                  disabled: disabled,
                  accent: accent,
                  onTap: disabled ? null : () => onChanged(f),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Text(
            usedYtdlp
                ? 'Powered by the yt-dlp engine on this device. HD options '
                    'merge separate video and audio tracks when ffmpeg is '
                    'available.'
                : canMux
                    ? 'Resolved on this device. HD options download the video '
                        'and audio tracks separately and merge them with the '
                        'bundled FFmpeg, so 720p, 1080p, and higher are '
                        'available.'
                    : 'Resolved on this device. The built-in engine saves a '
                        'combined stream, so quality tops out around 360p.',
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: context.palette.textMuted,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single rendition chip: label, container, size, and merge hint.
class FormatChip extends StatelessWidget {
  final MediaFormat format;
  final bool selected;
  final bool disabled;
  final Color accent;
  final VoidCallback? onTap;

  const FormatChip({
    super.key,
    required this.format,
    required this.selected,
    required this.disabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled ? context.palette.textMuted : accent;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? color.withOpacity(0.16) : context.palette.bgTertiary,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? color : context.palette.borderSubtle,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    format.isAudio
                        ? Icons.music_note_rounded
                        : Icons.high_quality_rounded,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    format.label,
                    style: TextStyle(
                      fontFamily: TurboFonts.body,
                      color: selected
                          ? context.palette.textPrimary
                          : context.palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  format.extension.toUpperCase(),
                  if (format.size > 0) formatBytes(format.size),
                  if (format.requiresMux) 'merge',
                ].join(' · '),
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: context.palette.textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
