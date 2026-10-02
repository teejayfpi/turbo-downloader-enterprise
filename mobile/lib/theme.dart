import 'package:flutter/material.dart';

/// Palette mirrored from the web client so both surfaces read as one product.
class TurboColors {
  static const bgPrimary = Color(0xFF0A0A0F);
  static const bgSecondary = Color(0xFF12121A);
  static const bgTertiary = Color(0xFF1A1A24);
  static const borderSubtle = Color(0xFF2A2A3A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9494A8);
  static const textMuted = Color(0xFF6A6A7E);
  static const accent = Color(0xFF00D4FF);
  static const success = Color(0xFF00FF88);
  static const warning = Color(0xFFFFAA00);
  static const error = Color(0xFFFF4466);
  static const speedUltra = Color(0xFF00FFCC);

  /// The user-selectable accents offered by the web client.
  static const accents = <String, Color>{
    'cyan': Color(0xFF00D4FF),
    'green': Color(0xFF00E082),
    'purple': Color(0xFFA855F7),
    'orange': Color(0xFFFF8800),
  };
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

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TurboColors.bgPrimary,
    canvasColor: TurboColors.bgPrimary,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: TurboColors.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: TurboColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardTheme(
      color: TurboColors.bgSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TurboColors.borderSubtle),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TurboColors.bgSecondary,
      hintStyle: const TextStyle(color: TurboColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: TurboColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: TurboColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TurboColors.bgSecondary,
      indicatorColor: accent.withOpacity(0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
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
      contentTextStyle: const TextStyle(color: TurboColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    dividerTheme: const DividerThemeData(color: TurboColors.borderSubtle, thickness: 1),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: TurboColors.textPrimary),
      bodySmall: TextStyle(color: TurboColors.textSecondary),
      titleMedium: TextStyle(color: TurboColors.textPrimary, fontWeight: FontWeight.w600),
    ),
  );
}
