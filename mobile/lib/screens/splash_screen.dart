import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import 'home_shell.dart';

/// Branded first screen shown on every platform while the engine loads.
///
/// It is more than a placeholder: it plays a short animated reveal, then hands
/// off to the home shell as soon as state initialisation finishes, so a fast
/// start is not padded with an artificial wait.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Lower bound on how long the reveal is shown, so it never flashes.
  static const minimumDisplay = Duration(milliseconds: 1500);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _barGrow;

  bool _navigated = false;
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _logoScale = Tween(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _wordFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.7, curve: Curves.easeOut),
    );
    _wordSlide = Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
    );
    _barGrow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
    );

    _controller.forward();

    Future.delayed(SplashScreen.minimumDisplay, () {
      if (!mounted) return;
      _minElapsed = true;
      _maybeNavigate();
    });
  }

  void _maybeNavigate() {
    if (_navigated || !_minElapsed) return;
    final ready = !context.read<TurboState>().loading;
    if (!ready) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;
    // Navigate the moment both the reveal and initialisation are done.
    if (!state.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNavigate());
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.8),
            radius: 1.5,
            colors: [accent.withOpacity(0.14), TurboColors.bgPrimary],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GridPainter(accent)),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  _Reveal(
                    scale: _logoScale,
                    fade: _logoFade,
                    child: _Logo(accent: accent),
                  ),
                  const SizedBox(height: 26),
                  FadeTransition(
                    opacity: _wordFade,
                    child: SlideTransition(
                      position: _wordSlide,
                      child: const Text(
                        'TURBO',
                        style: TextStyle(
                          fontFamily: TurboFonts.display,
                          color: TurboColors.textPrimary,
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: const Kicker(
                      'Offline download manager',
                      align: TextAlign.center,
                      letterSpacing: 3.0,
                      size: 10,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _GrowBar(grow: _barGrow, accent: accent),
                  const Spacer(flex: 4),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: const Column(
                      children: [
                        Kicker(
                          'Designed & engineered by',
                          align: TextAlign.center,
                          size: 9,
                          letterSpacing: 1.6,
                        ),
                        SizedBox(height: 5),
                        Kicker(
                          Designer.name,
                          align: TextAlign.center,
                          size: 10,
                          letterSpacing: 0.8,
                          color: TurboColors.textSecondary,
                        ),
                        SizedBox(height: 6),
                        Kicker(
                          'v$appVersion',
                          align: TextAlign.center,
                          size: 9,
                          letterSpacing: 1.2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Applies the scale + fade entrance used for the logo.
class _Reveal extends StatelessWidget {
  final Animation<double> scale;
  final Animation<double> fade;
  final Widget child;
  const _Reveal({required this.scale, required this.fade, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}

/// The Turbo mark: a gradient tile with a glow ring that breathes.
class _Logo extends StatefulWidget {
  final Color accent;
  const _Logo({required this.accent});

  @override
  State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.accent.withOpacity(0.18 + 0.16 * t),
                blurRadius: 34 + 18 * t,
                spreadRadius: 2 + 4 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [widget.accent, TurboColors.success],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(Icons.bolt_rounded,
            color: TurboColors.bgPrimary, size: 60),
      ),
    );
  }
}

/// A slim accent bar that fills from the centre as the reveal completes.
class _GrowBar extends StatelessWidget {
  final Animation<double> grow;
  final Color accent;
  const _GrowBar({required this.grow, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: grow,
      builder: (context, _) {
        return Container(
          width: 168,
          height: 3,
          decoration: BoxDecoration(
            color: TurboColors.bgTertiary,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: grow.value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, TurboColors.success],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Faint instrument grid behind the splash, evoking the console aesthetic.
class _GridPainter extends CustomPainter {
  final Color accent;
  _GridPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withOpacity(0.05)
      ..strokeWidth = 1;
    const step = 44.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.accent != accent;
}
