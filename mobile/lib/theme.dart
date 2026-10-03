import 'package:flutter/material.dart';

/// Palette mirrored from the web client so both surfaces read as one product.
class TurboColors {
  static const bgPrimary = Color(0xFF080A10);
  static const bgSecondary = Color(0xFF0F121B);
  static const bgTertiary = Color(0xFF171B26);
  static const borderSubtle = Color(0xFF222836);
  static const textPrimary = Color(0xFFF0F4FC);
  static const textSecondary = Color(0xFF969EB0);
  static const textMuted = Color(0xFF6C7488);
  static const accent = Color(0xFF22E0FF);
  static const success = Color(0xFF2FFFC8);
  static const warning = Color(0xFFFFB020);
  static const error = Color(0xFFFF526E);
  static const speedUltra = Color(0xFF78F0FF);

  /// The user-selectable accents offered by the web client.
  static const accents = <String, Color>{
    'cyan': Color(0xFF22E0FF),
    'green': Color(0xFF2FFFC8),
    'amber': Color(0xFFFFC43C),
    'orange': Color(0xFFFF8A30),
    'rose': Color(0xFFFF5C8C),
    'purple': Color(0xFFAA7AFF),
  };
}

/// Type families bundled in `pubspec.yaml`. These match the web client so the
/// two surfaces share one voice.
class TurboFonts {
  static const display = 'ChakraPetch';
  static const body = 'Sora';
  static const mono = 'JetBrainsMono';
}

/// Small-caps instrument label used for section and field headers.
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
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: TextStyle(
        fontFamily: TurboFonts.mono,
        color: color ?? TurboColors.textMuted,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: letterSpacing,
        height: 1.1,
      ),
    );
  }
}

/// Hairline-cornered panel: a bordered surface with an accent tick in the
/// top-left and bottom-right corners. Mirrors `.panel` on the web client.
class TurboPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color accentColor;
  final double radius;
  final bool clip;

  const TurboPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.accentColor = TurboColors.accent,
    this.radius = 4,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CornerPainter(accentColor),
      child: Container(
        padding: padding,
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        decoration: BoxDecoration(
          color: TurboColors.bgSecondary,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? TurboColors.borderSubtle),
        ),
        child: child,
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const tick = 10.0;
    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, tick)
        ..lineTo(0, 0)
        ..lineTo(tick, 0),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - tick, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - tick),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => old.color != color;
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
    final accent = tone ?? Theme.of(context).colorScheme.primary;
    final disabled = onPressed == null || busy;

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outline ? accent : TurboColors.bgPrimary,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: outline ? accent : TurboColors.bgPrimary),
        if (busy || icon != null) const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: TurboFonts.body,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: outline ? accent : TurboColors.bgPrimary,
          ),
        ),
      ],
    );

    if (outline) {
      return Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accent.withOpacity(0.5)),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

ThemeData buildTurboTheme(Color accent) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    surface: TurboColors.bgSecondary,
    error: TurboColors.error,
  );

  const textTheme = TextTheme(
    bodyMedium: TextStyle(
        fontFamily: TurboFonts.body, color: TurboColors.textPrimary),
    bodySmall: TextStyle(
        fontFamily: TurboFonts.body, color: TurboColors.textSecondary),
    titleMedium: TextStyle(
        fontFamily: TurboFonts.body,
        color: TurboColors.textPrimary,
        fontWeight: FontWeight.w600),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TurboColors.bgPrimary,
    canvasColor: TurboColors.bgPrimary,
    fontFamily: TurboFonts.body,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: TurboColors.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: TurboFonts.display,
        color: TurboColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
      ),
    ),
    cardTheme: CardTheme(
      color: TurboColors.bgSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: TurboColors.borderSubtle),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TurboColors.bgSecondary,
      hintStyle: const TextStyle(
          fontFamily: TurboFonts.mono, color: TurboColors.textMuted),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: TurboColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: TurboColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TurboColors.bgSecondary,
      indicatorColor: accent.withOpacity(0.14),
      height: 66,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: TurboFonts.body,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: states.contains(WidgetState.selected)
                ? accent
                : TurboColors.textMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : TurboColors.textMuted,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: TurboColors.bgTertiary,
      contentTextStyle: const TextStyle(
          fontFamily: TurboFonts.body, color: TurboColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: TurboColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: TurboColors.borderSubtle),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: TurboFonts.display,
        color: TurboColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    dividerTheme:
        const DividerThemeData(color: TurboColors.borderSubtle, thickness: 1),
    textTheme: textTheme,
  );
}
