import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state.dart';
import 'theme.dart';
import 'screens/downloads_screen.dart';
import 'screens/add_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TurboApp());
}

class TurboApp extends StatelessWidget {
  const TurboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TurboState()..init(),
      child: Consumer<TurboState>(
        builder: (context, state, _) {
          final accent =
              TurboColors.accents[state.accentKey] ?? TurboColors.accent;
          return MaterialApp(
            title: 'Turbo',
            debugShowCheckedModeBanner: false,
            theme: buildTurboTheme(accent),
            home: state.configured ? const HomeShell() : const SetupScreen(),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Downloads', 'New Transfer', 'Configuration'];
  static const _subtitles = [
    'Queue & live telemetry',
    'Start a device or server transfer',
    'Tune the engine',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;

    final localActive = state.local.activeCount;
    final activeCount = localActive + state.stats.activeCount;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, TurboColors.success],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.bolt_rounded,
                  color: TurboColors.bgPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[_index],
                  style: const TextStyle(
                    fontFamily: TurboFonts.display,
                    color: TurboColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 1),
                Kicker(_subtitles[_index], size: 9, letterSpacing: 1.2),
              ],
            ),
          ],
        ),
        actions: [
          if (state.serverConfigured && _index != 2)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _ConnectionChip(connected: state.connected),
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DownloadsScreen(),
          AddScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: TurboColors.borderSubtle)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeCount > 0,
                backgroundColor: accent,
                label: Text('$activeCount'),
                child: const Icon(Icons.download_rounded),
              ),
              label: 'Downloads',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_circle_outline_rounded),
              label: 'Add',
            ),
            const NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final bool connected;
  const _ConnectionChip({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? TurboColors.success : TurboColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              fontFamily: TurboFonts.mono,
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
