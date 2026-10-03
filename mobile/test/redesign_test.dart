import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:turbo_downloader/main.dart';
import 'package:turbo_downloader/media_url.dart';
import 'package:turbo_downloader/screens/add_screen.dart';
import 'package:turbo_downloader/screens/downloads_screen.dart';
import 'package:turbo_downloader/screens/settings_screen.dart';
import 'package:turbo_downloader/state.dart';
import 'package:turbo_downloader/theme.dart';

void main() {
  group('media detection drives the UI guard', () {
    test('media pages are flagged so device mode can refuse them', () {
      expect(isMediaUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isYouTubeUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isYouTubeUrl('https://soundcloud.com/a/b'), isFalse);
      // A host merely ending in the name must not be treated as YouTube.
      expect(isMediaUrl('https://notyoutube.com/watch'), isFalse);
      expect(isMediaUrl('https://example.com/file.zip'), isFalse);
    });
  });

  group('redesigned screens', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      final state = TurboState()
        ..mode = 'device'
        ..loading = false;
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

    testWidgets('downloads screen shows the empty state', (tester) async {
      await pumpScreen(tester, const DownloadsScreen());
      expect(find.text('QUEUE EMPTY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('add screen defaults to device mode and renders', (tester) async {
      await pumpScreen(tester, const AddScreen());
      expect(find.text('Target URL'.toUpperCase()), findsOneWidget);
      expect(find.text('Parallel connections'.toUpperCase()), findsOneWidget);
      expect(find.text('DOWNLOAD TO THIS DEVICE'.toUpperCase()), findsWidgets);
    });

    testWidgets('settings screen renders engine and about panels',
        (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('DOWNLOAD LOCATION'.toUpperCase()), findsOneWidget);
      expect(find.text('DEVICE ENGINE'.toUpperCase()), findsOneWidget);
      expect(find.text('Default connections'.toUpperCase()), findsOneWidget);
    });

    testWidgets('app boots into the home shell in device mode',
        (tester) async {
      final state = TurboState()..mode = 'device';
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
    });
  });
}
