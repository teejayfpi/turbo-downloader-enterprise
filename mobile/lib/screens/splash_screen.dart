import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';

/// The launch experience shown while the local engine starts.
///
/// A clean, standard splash: the brand mark, the product name, a one-line
/// descriptor, live initialization state, and the designer credit. It hands off
/// to onboarding on first run, then to the home shell once the engine is ready.
/// The branded hold is brief and skippable, so it never delays a user who wants
/// to start a download.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// The maximum time the branded launch screen is held before handing off.
  /// Kept short: a long, unskippable splash is pure friction at every launch.
  static const minimumDisplay = Duration(milliseconds: 1200);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _navigated = false;
  bool _minElapsed = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    Future.delayed(SplashScreen.minimumDisplay, () {
      if (!mounted) return;
      _minElapsed = true;
      _maybeNavigate();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _maybeNavigate() {
    if (_navigated || !_minElapsed) return;
    final state = context.read<TurboState>();
    if (state.loading) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => state.onboardingDone
            ? const HomeShell()
            : const OnboardingScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Drops the branded hold immediately. The engine-readiness wait still
  /// applies, so this only removes the artificial delay, never races startup.
  void _skip() {
    if (_navigated || _minElapsed) return;
    setState(() => _minElapsed = true);
    _maybeNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final p = context.palette;
    final accent = p.accent;
    if (!state.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNavigate());
    }

    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: Stack(
        children: [
          const Positioned.fill(child: _LaunchBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: Column(
                children: [
                  _LaunchHeader(ready: !state.loading),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final glow = 0.10 + (_pulseController.value * 0.10);
                      return Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withOpacity(glow),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(glow),
                              blurRadius: 42,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: _BrandMark(accent: accent, palette: p),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'TURBO',
                    style: TextStyle(
                      fontFamily: TurboFonts.display,
                      color: p.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ENTERPRISE DOWNLOAD OPERATIONS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: p.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 38),
                  _InitializationCard(accent: accent, ready: !state.loading),
                  const Spacer(),
                  const _LaunchCredit(),
                  const SizedBox(height: 18),
                  Text(
                    'v$appVersion  •  LOCAL-FIRST  •  SECURE',
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: p.textMuted.withOpacity(0.8),
                      fontSize: 9,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: p.textSecondary,
                      minimumSize: const Size(88, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchHeader extends StatelessWidget {
  const _LaunchHeader({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Kicker('SYSTEM BOOT', color: p.textMuted),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: ready ? p.success : p.warning,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Kicker(
              ready ? 'DEVICE READY' : 'STARTING',
              color: ready ? p.success : p.warning,
            ),
          ],
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.accent, required this.palette});

  final Color accent;
  final TurboPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, palette.success],
          ),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.30),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          Icons.bolt_rounded,
          color: palette.isDark ? palette.bgPrimary : Colors.white,
          size: 50,
        ),
      ),
    );
  }
}

class _InitializationCard extends StatelessWidget {
  const _InitializationCard({required this.accent, required this.ready});

  final Color accent;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: p.bgSecondary.withOpacity(0.92),
        borderRadius: TurboRadius.all(TurboRadius.md),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Kicker('INITIALIZING LOCAL ENGINE', size: 9),
              Text(
                ready ? 'READY' : 'PLEASE WAIT',
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: ready ? p.success : accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: TurboRadius.all(2),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: ready ? 1 : null,
              backgroundColor: p.bgTertiary,
              valueColor: AlwaysStoppedAnimation<Color>(
                ready ? p.success : accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchCredit extends StatelessWidget {
  const _LaunchCredit();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Text(
          'designed by:',
          style: TextStyle(
            fontFamily: TurboFonts.mono,
            color: p.textMuted,
            fontSize: 10,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Designer.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: p.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _LaunchBackdrop extends StatelessWidget {
  const _LaunchBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter(context.palette));
  }
}

class _BackdropPainter extends CustomPainter {
  final TurboPalette palette;
  _BackdropPainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = palette.borderSubtle.withOpacity(0.35)
      ..strokeWidth = 1;
    const grid = 34.0;
    for (double x = 0; x <= size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [palette.accent.withOpacity(0.12), Colors.transparent],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.38),
          radius: math.max(size.width * 0.75, 1),
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.palette != palette;
}
