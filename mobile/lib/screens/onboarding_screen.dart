import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../credits.dart';
import '../state.dart';
import '../theme.dart';
import 'home_shell.dart';

/// A short first-run tour. It explains the local-first model, points out the
/// optional yt-dlp engine, and confirms where files are saved. Nothing here is
/// required to start downloading; it can be skipped at any point.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardPage>[
    _OnboardPage(
      icon: Icons.bolt_rounded,
      title: 'Welcome to Turbo',
      body: 'An enterprise-grade download manager that runs entirely on your '
          'device. No server, no account, no key — open it and download.',
    ),
    _OnboardPage(
      icon: Icons.shield_rounded,
      title: 'Private by design',
      body: 'Your links, files, and history never leave this device. Nothing is '
          'proxied through a remote server, and no analytics are collected.',
    ),
    _OnboardPage(
      icon: Icons.speed_rounded,
      title: 'Fast and resumable',
      body: 'Turbo splits downloads across several connections, resumes after a '
          'drop, and verifies the bytes it writes. Pause or cancel any time.',
    ),
    _OnboardPage(
      icon: Icons.folder_special_rounded,
      title: 'Saved where you expect',
      body: 'Files land in your Downloads folder, sorted into Videos, Documents, '
          'Music, and other subfolders. Share or open them from the queue.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await context.read<TurboState>().completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeShell()),
    );
  }

  void _next() {
    if (_page >= _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'SKIP',
                  style: TextStyle(
                    fontFamily: TurboFonts.body,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: p.textMuted,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _PageView(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? p.accent : p.borderStrong,
                            borderRadius: TurboRadius.all(TurboRadius.pill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TurboButton(
                    label: last ? 'Start downloading' : 'Next',
                    icon: last ? Icons.download_rounded : Icons.arrow_forward,
                    onPressed: _next,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Designed & engineered by ${Designer.name}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: TurboFonts.mono,
                      color: p.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage {
  final IconData icon;
  final String title;
  final String body;
  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _OnboardPage page;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: p.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 44, color: p.accent),
          ),
          const SizedBox(height: 30),
          Text(
            page.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TurboFonts.display,
              color: p.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TurboFonts.body,
              color: p.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
