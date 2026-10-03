import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:turbo_downloader/credits.dart';
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
          theme: buildTurboTheme(TurboAccents.of('cyan')),
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

    testWidgets('add screen detects links and has no server switch',
        (tester) async {
      await pumpScreen(tester, const AddScreen());
      expect(find.text('Link or file URL'.toUpperCase()), findsOneWidget);
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
      // The accent picker sits below the fold on a short test surface.
      await tester.scrollUntilVisible(
        find.text('ACCENT COLOUR'.toUpperCase()),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('ACCENT COLOUR'.toUpperCase()), findsOneWidget);
      // No server or token fields any more.
      expect(find.text('SERVER'.toUpperCase()), findsNothing);
    });

    testWidgets('home shell boots with four tabs and a ready chip',
        (tester) async {
      final state = TurboState()..loading = false;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTurboTheme(TurboAccents.of('cyan')),
            home: const HomeShell(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Downloads'), findsWidgets);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('History'), findsWidgets);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
    });
  });

  group('splash screen', () {
    testWidgets('shows the brand and designer, then hands off to home',
        (tester) async {
      final state = TurboState()
        ..loading = false
        ..onboardingDone = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTurboTheme(TurboAccents.of('cyan')),
            home: const SplashScreen(),
          ),
        ),
      );

      expect(find.text('TURBO'), findsOneWidget);
      expect(find.text('ENTERPRISE DOWNLOAD OPERATIONS'), findsOneWidget);
      expect(find.text('designed by:'), findsOneWidget);
      expect(find.text(Designer.name), findsOneWidget);

      // Wait out the minimum display, then let the transition settle.
      await tester.pump(SplashScreen.minimumDisplay);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
    });
  });
}
