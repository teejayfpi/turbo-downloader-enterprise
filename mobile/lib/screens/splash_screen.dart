import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import 'home_shell.dart';

/// A standard, no-frills launch screen: the Turbo mark, the app name, a
/// loading indicator, and the designer credit. It hands off to the home shell
/// as soon as the engine has finished initialising, so a fast start is not
/// padded with an artificial wait.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Lower bound on how long the screen is shown, so it never flashes.
  static const minimumDisplay = Duration(milliseconds: 900);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(SplashScreen.minimumDisplay, () {
      if (!mounted) return;
      _minElapsed = true;
      _maybeNavigate();
    });
  }

  void _maybeNavigate() {
    if (_navigated || !_minElapsed) return;
    if (context.read<TurboState>().loading) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
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
    // Navigate the moment both the minimum display and initialisation are done.
    if (!state.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNavigate());
    }

    return Scaffold(
      backgroundColor: TurboColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, TurboColors.success],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: TurboColors.bgPrimary, size: 54),
              ),
              const SizedBox(height: 22),
              const Text(
                'Turbo Downloader',
                style: TextStyle(
                  fontFamily: TurboFonts.display,
                  color: TurboColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Offline download manager',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const Spacer(flex: 4),
              const Text(
                'Designed by',
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                Designer.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: TurboFonts.body,
                  color: TurboColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'v$appVersion',
                style: TextStyle(
                  fontFamily: TurboFonts.mono,
                  color: TurboColors.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
