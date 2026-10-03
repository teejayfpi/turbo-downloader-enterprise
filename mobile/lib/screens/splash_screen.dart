import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import 'home_shell.dart';

/// The single, consistent launch experience shown while the local engine starts.
///
/// The native Android launch window uses the same palette and mark, then Flutter
/// takes over here so the app can show meaningful initialization state and the
/// required designer credit without introducing a second visual language.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Prevents a one-frame flash on fast devices while avoiding an artificial
  /// loading delay once the local engine is ready.
  static const minimumDisplay = Duration(milliseconds: 900);

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
    if (context.read<TurboState>().loading) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;
    if (!state.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNavigate());
    }

    return Scaffold(
      backgroundColor: TurboColors.bgPrimary,
      body: Stack(
        children: [
          const Positioned.fill(child: _LaunchBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: Column(
                children: [
                  const _LaunchHeader(),
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
                    child: _BrandMark(accent: accent),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'TURBO',
                    style: TextStyle(
                      fontFamily: TurboFonts.display,
                      color: TurboColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ENTERPRISE DOWNLOAD OPERATIONS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: TurboColors.textSecondary,
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
                      color: TurboColors.textMuted.withOpacity(0.8),
                      fontSize: 9,
                      letterSpacing: 0.9,
                    ),
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
  const _LaunchHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Kicker('SYSTEM BOOT', color: TurboColors.textMuted),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: TurboColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            const Kicker('DEVICE READY', color: TurboColors.success),
          ],
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [TurboColors.accent, TurboColors.success],
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
        child: const Icon(
          Icons.bolt_rounded,
          color: TurboColors.bgPrimary,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: TurboColors.bgSecondary.withOpacity(0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TurboColors.borderSubtle),
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
                  color: ready ? TurboColors.success : accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: ready ? 1 : null,
              backgroundColor: TurboColors.bgTertiary,
              valueColor: AlwaysStoppedAnimation<Color>(
                ready ? TurboColors.success : accent,
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
    return const Column(
      children: [
        Text(
          'designed by:',
          style: TextStyle(
            fontFamily: TurboFonts.mono,
            color: TurboColors.textMuted,
            fontSize: 10,
            letterSpacing: 1.3,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Ayanlowo Olatunji Ayobami',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: TurboFonts.body,
            color: TurboColors.textPrimary,
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
    return CustomPaint(painter: _BackdropPainter());
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = TurboColors.borderSubtle.withOpacity(0.35)
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
        colors: [TurboColors.accent.withOpacity(0.12), Colors.transparent],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.38),
          radius: size.width * 0.75,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
