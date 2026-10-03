import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:turbo_downloader/screens/add_screen.dart';
import 'package:turbo_downloader/screens/downloads_screen.dart';
import 'package:turbo_downloader/screens/home_shell.dart';
import 'package:turbo_downloader/screens/settings_screen.dart';
import 'package:turbo_downloader/screens/splash_screen.dart';
import 'package:turbo_downloader/state.dart';
import 'package:turbo_downloader/theme.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    final state = TurboState()..loading = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TurboState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTurboTheme(TurboColors.accent),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  group('device-only screens', () {
    testWidgets('downloads screen shows the empty state', (tester) async {
      await pumpScreen(tester, const DownloadsScreen());
      expect(find.text('QUEUE EMPTY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('add screen has no server switch and renders the device form',
        (tester) async {
      await pumpScreen(tester, const AddScreen());
      expect(find.text('Target URL'.toUpperCase()), findsOneWidget);
      expect(find.text('Parallel connections'.toUpperCase()), findsOneWidget);
      expect(find.text('DOWNLOAD TO THIS DEVICE'.toUpperCase()), findsWidgets);
      // The old device/server segmented control is gone.
      expect(find.text('Server'), findsNothing);
    });

    testWidgets('settings screen has engine, accent, and about panels',
        (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('DEVICE ENGINE'.toUpperCase()), findsOneWidget);
      expect(find.text('Default connections'.toUpperCase()), findsOneWidget);
      expect(find.text('ACCENT COLOUR'.toUpperCase()), findsOneWidget);
      // No server or token fields any more.
      expect(find.text('SERVER'.toUpperCase()), findsNothing);
    });

    testWidgets('home shell boots with three tabs and a ready chip',
        (tester) async {
      final state = TurboState()..loading = false;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTurboTheme(TurboColors.accent),
            home: const HomeShell(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Downloads'), findsWidgets);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
    });
  });

  group('splash screen', () {
    testWidgets('shows the brand and hands off to the home shell',
        (tester) async {
      final state = TurboState()..loading = false;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTurboTheme(TurboColors.accent),
            home: const SplashScreen(),
          ),
        ),
      );

      expect(find.text('TURBO'), findsOneWidget);
      expect(find.text('OFFLINE DOWNLOAD MANAGER'), findsOneWidget);

      // Wait out the minimum reveal, then let the transition settle.
      await tester.pump(SplashScreen.minimumDisplay);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
    });
  });
}
