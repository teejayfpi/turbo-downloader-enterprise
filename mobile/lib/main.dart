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

  static const _titles = ['Downloads', 'New Download', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bolt_rounded, color: accent, size: 26),
            const SizedBox(width: 6),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          if (_index == 0 && state.serverConfigured)
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_rounded),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            label: 'Add',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Live' : 'Offline',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
