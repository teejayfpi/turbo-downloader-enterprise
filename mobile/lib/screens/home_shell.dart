import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../link_inbox.dart';
import '../state.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'downloads_screen.dart';
import 'add_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// The main tabbed surface shown after the splash: the queue, the add form,
/// history, and settings, all operating on this device.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _dragging = false;

  static const _titles = ['Downloads', 'Browse', 'New Transfer', 'History', 'Settings'];
  static const _subtitles = [
    'Queue & live telemetry',
    'Find videos to download',
    'Paste a link to download',
    'Completed & failed transfers',
    'Tune the engine',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TurboState>();
    final p = context.palette;
    final activeCount = state.local.activeCount + state.local.queuedCount;

    // A link that arrived from anywhere (deep link, share sheet, launch arg)
    // brings the Add tab forward so the user sees it land.
    if (state.pendingUrl != null && _index != 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = 2);
      });
    }

    final shell = Scaffold(
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
                  colors: [p.accent, p.success],
                ),
                borderRadius: TurboRadius.all(TurboRadius.sm),
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: p.isDark ? p.bgPrimary : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[_index],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: TurboFonts.display,
                      color: p.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Kicker(_subtitles[_index], size: 9, letterSpacing: 1.2),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _StatusChip(
              active: state.local.activeCount,
              blocked: state.local.networkBlocked,
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DownloadsScreen(),
          BrowseScreen(),
          AddScreen(),
          HistoryScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.borderSubtle)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeCount > 0,
                backgroundColor: p.accent,
                label: Text('$activeCount'),
                child: const Icon(Icons.download_rounded),
              ),
              label: 'Downloads',
            ),
            const NavigationDestination(
              icon: Icon(Icons.travel_explore_rounded),
              label: 'Browse',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_circle_outline_rounded),
              label: 'Add',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            const NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );

    if (!_supportsDrop) return shell;
    return _DropSurface(
      dragging: _dragging,
      onDragEntered: () => setState(() => _dragging = true),
      onDragExited: () => setState(() => _dragging = false),
      onDrop: (url) {
        setState(() => _dragging = false);
        state.receiveLink(url);
        setState(() => _index = 2);
      },
      child: shell,
    );
  }

  static bool get _supportsDrop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}

/// Wraps the shell so a link dragged from a browser lands in the Add screen.
class _DropSurface extends StatelessWidget {
  final bool dragging;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ValueChanged<String> onDrop;
  final Widget child;

  const _DropSurface({
    required this.dragging,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDrop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: (detail) {
        for (final file in detail.files) {
          final url = extractUrl(file.path);
          if (url != null) {
            onDrop(url);
            return;
          }
        }
      },
      child: Stack(
        children: [
          child,
          if (dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: p.bgPrimary.withOpacity(0.82),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 22),
                      decoration: BoxDecoration(
                        color: p.bgSecondary,
                        borderRadius: TurboRadius.all(TurboRadius.md),
                        border: Border.all(color: p.accent, width: 1.4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_rounded,
                              color: p.accent, size: 34),
                          const SizedBox(height: 12),
                          const Kicker('Drop a link to download',
                              letterSpacing: 2.0, size: 11),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Local-first status: reports whether transfers are running on this device.
class _StatusChip extends StatelessWidget {
  final int active;
  final bool blocked;
  const _StatusChip({required this.active, this.blocked = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = blocked
        ? p.warning
        : (active > 0 ? p.success : p.textMuted);
    final label = blocked
        ? 'PAUSED'
        : (active > 0 ? 'ACTIVE' : 'READY');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: TurboRadius.all(TurboRadius.sm),
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
            label,
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
