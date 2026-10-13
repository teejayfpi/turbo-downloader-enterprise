import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turbo_downloader/screens/home_shell.dart';
import 'package:turbo_downloader/screens/onboarding_screen.dart';
import 'package:turbo_downloader/screens/splash_screen.dart';
import 'package:turbo_downloader/services/settings_store.dart';
import 'package:turbo_downloader/state.dart';
import 'package:turbo_downloader/theme.dart';

/// A settings store whose writes never complete, standing in for a wedged
/// platform channel: the tap lands, but the screen would never change if
/// leaving the tour waited on the write.
class _HangingSettings extends SettingsStore {
  final _never = Completer<void>();

  @override
  Future<void> setBool(String key, bool value) => _never.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TurboState> pumpTour(WidgetTester tester, {SettingsStore? settings}) async {
    final state = TurboState(settings: settings)..loading = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TurboState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTurboTheme(TurboAccents.of('cyan')),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  group('onboarding tour', () {
    testWidgets('SKIP leaves the tour and marks it done', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = await pumpTour(tester);

      await tester.tap(find.text('SKIP'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(state.onboardingDone, isTrue);
    });

    testWidgets('the last page advances via Start downloading',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpTour(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('NEXT'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('START DOWNLOADING'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('SKIP still navigates when the settings write hangs',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = await pumpTour(tester, settings: _HangingSettings());

      await tester.tap(find.text('SKIP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.onboardingDone, isTrue,
          reason: 'the flag flips at once, before any write');
      expect(find.byType(HomeShell), findsOneWidget,
          reason: 'a slow write must not block leaving the tour');
    });
  });

  group('onboarding persistence', () {
    test('completeOnboarding persists and a fresh state reads it back',
        () async {
      SharedPreferences.setMockInitialValues({});
      final first = TurboState();
      addTearDown(first.dispose);
      await first.init();
      expect(first.onboardingDone, isFalse);

      await first.completeOnboarding();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SettingsStore.kOnboardingDone), isTrue);

      final second = TurboState();
      addTearDown(second.dispose);
      await second.init();
      expect(second.onboardingDone, isTrue,
          reason: 'the tour must be shown only once');
    });

    testWidgets('first run goes splash -> onboarding -> home, then the next '
        'launch goes straight to home', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = TurboState();
      addTearDown(state.dispose);
      await tester.runAsync(() => state.init());

      // Mirror main.dart: a Consumer above MaterialApp rebuilds on notify.
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: Consumer<TurboState>(
            builder: (context, s, _) => MaterialApp(
              theme: buildTurboTheme(TurboAccents.of(s.accentKey)),
              home: const SplashScreen(),
            ),
          ),
        ),
      );
      await tester.pump(SplashScreen.minimumDisplay);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.tap(find.text('SKIP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HomeShell), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SettingsStore.kOnboardingDone), isTrue);

      final relaunch = TurboState();
      addTearDown(relaunch.dispose);
      await tester.runAsync(() => relaunch.init());
      expect(relaunch.onboardingDone, isTrue,
          reason: 'a relaunch must skip the tour');
    });
  });
}
