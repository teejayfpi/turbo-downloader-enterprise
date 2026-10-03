import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import 'downloads_screen.dart';
import 'add_screen.dart';
import 'settings_screen.dart';

/// The main tabbed surface shown after the splash: the queue, the add form,
/// and settings, all operating on this device.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Downloads', 'New Transfer', 'Settings'];
  static const _subtitles = [
    'Queue & live telemetry',
    'Paste a link to download',
    'Tune the engine',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;
    final activeCount = state.local.activeCount + state.local.queuedCount;

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
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _StatusChip(active: state.local.activeCount),
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

/// Local-first status: reports whether transfers are running on this device.
class _StatusChip extends StatelessWidget {
  final int active;
  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active > 0 ? TurboColors.success : TurboColors.textMuted;
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
            active > 0 ? 'ACTIVE' : 'READY',
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
