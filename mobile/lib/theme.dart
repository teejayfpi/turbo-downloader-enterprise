import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand fonts. Bundled in `pubspec.yaml` so the app carries its own voice on
/// every device and needs no font download or licence tracking.
class TurboFonts {
  static const display = 'ChakraPetch';
  static const body = 'Sora';
  static const mono = 'JetBrainsMono';
}

/// The selectable accent colours. Each drives the whole scheme.
class TurboAccents {
  static const Map<String, Color> all = {
    'cyan': Color(0xFF22D3EE),
    'blue': Color(0xFF3B82F6),
    'violet': Color(0xFF8B5CF6),
    'magenta': Color(0xFFEC4899),
    'amber': Color(0xFFF59E0B),
    'lime': Color(0xFF84CC16),
    'emerald': Color(0xFF10B981),
    'orange': Color(0xFFF97316),
  };

  static Color of(String key) => all[key] ?? all['cyan']!;

  static List<String> get keys => all.keys.toList();
}

/// The palette every widget reads. A `ThemeExtension` so light, dark, and
/// high-contrast variants can coexist and animate between each other.
@immutable
class TurboPalette extends ThemeExtension<TurboPalette> {
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color bgElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color error;
  final Color speedFast;
  final Color speedUltra;
  final Color scrim;
  final bool isDark;

  const TurboPalette({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.borderSubtle,
    required this.borderStrong,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
    required this.speedFast,
    required this.speedUltra,
    required this.scrim,
    required this.isDark,
  });

  static TurboPalette dark(Color accent) => TurboPalette(
        bgPrimary: const Color(0xFF0A0E14),
        bgSecondary: const Color(0xFF111823),
        bgTertiary: const Color(0xFF1A2330),
        bgElevated: const Color(0xFF202B3A),
        textPrimary: const Color(0xFFE6EDF3),
        textSecondary: const Color(0xFF9BA9B8),
        textMuted: const Color(0xFF5E6C7C),
        borderSubtle: const Color(0xFF1F2A38),
        borderStrong: const Color(0xFF2E3B4D),
        accent: accent,
        accentSoft: accent.withOpacity(0.14),
        success: const Color(0xFF34D399),
        warning: const Color(0xFFFBBF24),
        error: const Color(0xFFF87171),
        speedFast: const Color(0xFF38BDF8),
        speedUltra: const Color(0xFFA78BFA),
        scrim: const Color(0xCC05080C),
        isDark: true,
      );

  static TurboPalette light(Color accent) => TurboPalette(
        bgPrimary: const Color(0xFFF6F8FB),
        bgSecondary: const Color(0xFFFFFFFF),
        bgTertiary: const Color(0xFFEDF1F6),
        bgElevated: const Color(0xFFFFFFFF),
        textPrimary: const Color(0xFF11161D),
        textSecondary: const Color(0xFF48525F),
        textMuted: const Color(0xFF7A8593),
        borderSubtle: const Color(0xFFDCE3EB),
        borderStrong: const Color(0xFFC3CDD9),
        accent: accent,
        accentSoft: accent.withOpacity(0.12),
        success: const Color(0xFF059669),
        warning: const Color(0xFFD97706),
        error: const Color(0xFFDC2626),
        speedFast: const Color(0xFF0284C7),
        speedUltra: const Color(0xFF7C3AED),
        scrim: const Color(0x66000000),
        isDark: false,
      );

  /// A variant that raises text and border contrast for accessibility.
  TurboPalette toHighContrast() => isDark
      ? copyWith(
          textSecondary: const Color(0xFFC9D4DF),
          textMuted: const Color(0xFF9BA9B8),
          borderSubtle: const Color(0xFF3A4759),
          borderStrong: const Color(0xFF5A6B80),
        )
      : copyWith(
          textSecondary: const Color(0xFF2B333D),
          textMuted: const Color(0xFF5A6472),
          borderSubtle: const Color(0xFFB4BFCC),
          borderStrong: const Color(0xFF8A97A6),
        );

  @override
  TurboPalette copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? borderSubtle,
    Color? borderStrong,
  }) =>
      TurboPalette(
        bgPrimary: bgPrimary,
        bgSecondary: bgSecondary,
        bgTertiary: bgTertiary,
        bgElevated: bgElevated,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderStrong: borderStrong ?? this.borderStrong,
        accent: accent,
        accentSoft: accentSoft,
        success: success,
        warning: warning,
        error: error,
        speedFast: speedFast,
        speedUltra: speedUltra,
        scrim: scrim,
        isDark: isDark,
      );

  @override
  TurboPalette lerp(ThemeExtension<TurboPalette>? other, double t) {
    if (other is! TurboPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return TurboPalette(
      bgPrimary: c(bgPrimary, other.bgPrimary),
      bgSecondary: c(bgSecondary, other.bgSecondary),
      bgTertiary: c(bgTertiary, other.bgTertiary),
      bgElevated: c(bgElevated, other.bgElevated),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      borderSubtle: c(borderSubtle, other.borderSubtle),
      borderStrong: c(borderStrong, other.borderStrong),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      speedFast: c(speedFast, other.speedFast),
      speedUltra: c(speedUltra, other.speedUltra),
      scrim: c(scrim, other.scrim),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Spacing steps. Using named steps instead of magic numbers keeps rhythm
/// consistent as screens change.
@immutable
class TurboSpace extends ThemeExtension<TurboSpace> {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  const TurboSpace({
    this.xs = 4,
    this.sm = 8,
    this.md = 14,
    this.lg = 20,
    this.xl = 28,
    this.xxl = 40,
  });

  @override
  TurboSpace lerp(ThemeExtension<TurboSpace>? other, double t) => this;

  @override
  TurboSpace copyWith() => this;
}

/// Corner radii, kept in one place so controls stay visually related.
class TurboRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// Reads the palette from the current theme.
extension TurboThemeX on BuildContext {
  TurboPalette get palette => Theme.of(this).extension<TurboPalette>() ??
      TurboPalette.dark(TurboAccents.of('cyan'));

  TurboSpace get space =>
      Theme.of(this).extension<TurboSpace>() ?? const TurboSpace();

  Color get accent => palette.accent;
}

/// A small uppercase instrument label used for section and field headers.
class Kicker extends StatelessWidget {
  final String text;
  final Color? color;
  final double size;
  final double letterSpacing;
  final TextAlign align;

  const Kicker(
    this.text, {
    super.key,
    this.color,
    this.size = 10,
    this.letterSpacing = 1.8,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        textAlign: align,
        style: TextStyle(
          fontFamily: TurboFonts.mono,
          color: color ?? context.palette.textMuted,
          fontSize: size,
          fontWeight: FontWeight.w500,
          letterSpacing: letterSpacing,
          height: 1.1,
        ),
      );
}

/// Animated numeric value used on the dashboard.
class AnimatedMetric extends StatelessWidget {
  final String value;
  final TextStyle style;
  const AnimatedMetric({super.key, required this.value, required this.style});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Text(value, key: ValueKey(value), style: style),
      );
}

/// A thin header rule with the brand's clipped-corner motif.
class TurboDivider extends StatelessWidget {
  final Color? color;
  const TurboDivider({super.key, this.color});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        color: color ?? context.palette.borderSubtle,
      );
}

/// A small uppercase label used above sections and inside cards.
class TurboLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const TurboLabel(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: TurboFonts.body,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: c,
          ),
        ),
      ],
    );
  }
}

/// A status pill: solid for emphasis, tinted otherwise.
class TurboChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color tone;
  final bool solid;
  final bool dense;

  const TurboChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.solid = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = solid ? tone : tone.withOpacity(0.14);
    final fg = solid ? (ThemeData.estimateBrightnessForColor(tone) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF06121F)) : tone;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: TurboRadius.all(TurboRadius.pill),
        border: solid ? null : Border.all(color: tone.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: TurboFonts.body,
              fontSize: dense ? 9 : 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A framed surface with the brand's corner ticks, used for the main panels.
class TurboPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;

  /// Colour of the corner ticks. Defaults to the palette accent.
  final Color? accentColor;
  final double radius;
  final bool clip;
  final bool ticks;

  const TurboPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.borderColor,
    this.accentColor,
    this.radius = 4,
    this.clip = false,
    this.ticks = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      painter: ticks
          ? CornerTicksPainter(color: accentColor ?? p.accent)
          : null,
      child: Container(
        padding: padding,
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        decoration: BoxDecoration(
          color: background ?? p.bgSecondary,
          borderRadius: TurboRadius.all(radius),
          border: Border.all(color: borderColor ?? p.borderSubtle),
        ),
        child: child,
      ),
    );
  }
}

/// Paints short brackets in the corners of a panel.
class CornerTicksPainter extends CustomPainter {
  final Color color;
  final double tick;
  const CornerTicksPainter({required this.color, this.tick = 10});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawPath(
      Path()
        ..moveTo(0, tick)
        ..lineTo(0, 0)
        ..lineTo(tick, 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - tick, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - tick),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CornerTicksPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Primary action button styled as a compact instrument control.
class TurboButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outline;
  final bool expand;
  final Color? tone;

  const TurboButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.outline = false,
    this.expand = true,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = tone ?? p.accent;
    final disabled = onPressed == null || busy;
    final fg = outline
        ? accent
        : (ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : const Color(0xFF06121F));

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TurboFonts.body,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: fg,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: outline ? Colors.transparent : accent,
        borderRadius: TurboRadius.all(TurboRadius.sm),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: TurboRadius.all(TurboRadius.sm),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: outline ? 14 : 15,
              horizontal: 16,
            ),
            decoration: outline
                ? BoxDecoration(
                    borderRadius: TurboRadius.all(TurboRadius.sm),
                    border: Border.all(color: accent.withOpacity(0.5)),
                  )
                : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A small progress bar used in cards and the running notification.
class TurboProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;
  const TurboProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: TurboRadius.all(TurboRadius.pill),
      child: Stack(
        children: [
          Container(height: height, color: p.bgTertiary),
          FractionallySizedBox(
            widthFactor: (value.isFinite ? value : 0.0).clamp(0.0, 1.0).toDouble(),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color ?? p.accent, p.speedUltra],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The accent-aware speed colour: the faster the transfer, the hotter.
Color turboSpeedColor(BuildContext context, int bytesPerSecond) {
  final p = context.palette;
  if (bytesPerSecond <= 0) return p.textMuted;
  if (bytesPerSecond < 256 * 1024) return p.textSecondary;
  if (bytesPerSecond < 2 * 1024 * 1024) return p.speedFast;
  return p.speedUltra;
}

ThemeData buildTurboTheme(
  Color accent, {
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
}) {
  var palette =
      brightness == Brightness.dark ? TurboPalette.dark(accent) : TurboPalette.light(accent);
  if (highContrast) palette = palette.toHighContrast();

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    primary: accent,
    surface: palette.bgSecondary,
    error: palette.error,
  );

  final textTheme = TextTheme(
    bodyMedium: TextStyle(
      fontFamily: TurboFonts.body,
      color: palette.textPrimary,
      fontSize: 14,
      height: 1.35,
    ),
    bodySmall: TextStyle(
      fontFamily: TurboFonts.body,
      color: palette.textSecondary,
      fontSize: 12,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontFamily: TurboFonts.body,
      color: palette.textPrimary,
      fontWeight: FontWeight.w600,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bgPrimary,
    canvasColor: palette.bgPrimary,
    fontFamily: TurboFonts.body,
    splashFactory: InkSparkle.splashFactory,
    extensions: [palette, const TurboSpace()],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: TurboFonts.display,
        color: palette.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
      ),
    ),
    cardTheme: CardTheme(
      color: palette.bgSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: TurboRadius.all(TurboRadius.md),
        side: BorderSide(color: palette.borderSubtle),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.bgSecondary,
      hintStyle: TextStyle(
        fontFamily: TurboFonts.mono,
        color: palette.textMuted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: TurboRadius.all(TurboRadius.sm),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TurboRadius.all(TurboRadius.sm),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TurboRadius.all(TurboRadius.sm),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.bgSecondary,
      indicatorColor: palette.accentSoft,
      height: 66,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: TurboFonts.body,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: states.contains(WidgetState.selected)
                ? accent
                : palette.textMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : palette.textMuted,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.bgTertiary,
      contentTextStyle: TextStyle(
        fontFamily: TurboFonts.body,
        color: palette.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: TurboRadius.all(TurboRadius.sm),
      ),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: palette.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: TurboRadius.all(TurboRadius.lg),
        side: BorderSide(color: palette.borderSubtle),
      ),
      titleTextStyle: TextStyle(
        fontFamily: TurboFonts.display,
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    dividerTheme: DividerThemeData(color: palette.borderSubtle, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? accent : palette.textMuted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? accent.withOpacity(0.35)
              : palette.bgTertiary),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: palette.bgTertiary,
      thumbColor: accent,
    ),
    textTheme: textTheme,
  );
}

/// How long a transfer is expected to take, for the ETA line.
String formatEta(int remainingBytes, int bytesPerSecond) {
  if (bytesPerSecond <= 0 || remainingBytes <= 0) return '--';
  final seconds = (remainingBytes / bytesPerSecond).ceil();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  final hours = minutes ~/ 60;
  return '${hours}h ${minutes % 60}m';
}

/// A tiny sparkline of recent throughput samples, drawn without dependencies.
class TurboSparkline extends StatelessWidget {
  final List<int> samples;
  final Color? color;
  final double height;
  const TurboSparkline({
    super.key,
    required this.samples,
    this.color,
    this.height = 26,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(samples: samples, color: c),
        size: Size.infinite,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<int> samples;
  final Color color;
  const _SparkPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final maxV = samples.reduce(math.max);
    if (maxV <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = size.height * (1 - samples[i] / maxV);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.samples != samples || old.color != color;
}
