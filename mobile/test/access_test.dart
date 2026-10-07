import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbo_downloader/format.dart';
import 'package:turbo_downloader/services/access.dart';
import 'package:turbo_downloader/services/licence.dart';
import 'package:turbo_downloader/services/secure_store.dart';
import 'package:turbo_downloader/state.dart';
import 'package:turbo_downloader/theme.dart';
import 'package:turbo_downloader/widgets/access_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleKeyPair keyPair;
  late SimplePublicKey publicKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keyPair = await Ed25519().newKeyPair();
    publicKey = await keyPair.extractPublicKey();
  });

  Future<Licence?> roundTrip(Licence licence) async {
    final token = await LicenceCodec.sign(licence, keyPair: keyPair);
    return LicenceCodec.verify(token, publicKey: publicKey);
  }

  group('LicenceCodec', () {
    test('signs and verifies a time-limited licence', () async {
      final expires = DateTime.utc(2027, 1, 1);
      final licence = Licence(
        tier: AccessTier.pro,
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: expires,
        holder: 'Ada',
      );
      final decoded = await roundTrip(licence);
      expect(decoded, isNotNull);
      expect(decoded!.tier, AccessTier.pro);
      expect(decoded.holder, 'Ada');
      expect(decoded.expiresAt, expires);
    });

    test('rejects a tampered payload', () async {
      final token = await LicenceCodec.sign(
        Licence(tier: AccessTier.pro, expiresAt: DateTime.utc(2030)),
        keyPair: keyPair,
      );
      // Flip the last character of the payload half.
      final dot = token.indexOf('.');
      final payload = token.substring(0, dot);
      final flipped = payload.substring(0, payload.length - 1) +
          (payload.endsWith('A') ? 'B' : 'A');
      final tampered = '$flipped${token.substring(dot)}';
      expect(await LicenceCodec.verify(tampered, publicKey: publicKey), isNull);
    });

    test('rejects a licence signed by another key', () async {
      final other = await Ed25519().newKeyPair();
      final token = await LicenceCodec.sign(
        Licence(tier: AccessTier.pro, expiresAt: DateTime.utc(2030)),
        keyPair: other,
      );
      expect(await LicenceCodec.verify(token, publicKey: publicKey), isNull);
    });

    test('rejects malformed keys without throwing', () async {
      for (final bad in ['', 'not-a-key', 'a.b', '!!!.???', '.', 'a.']) {
        expect(await LicenceCodec.verify(bad, publicKey: publicKey), isNull,
            reason: 'should reject "$bad"');
      }
    });

    test('a perpetual licence has no expiry', () async {
      final decoded = await roundTrip(const Licence(tier: AccessTier.pro));
      expect(decoded!.isPerpetual, isTrue);
      expect(decoded.isActiveAt(DateTime.utc(2099)), isTrue);
    });
  });

  group('AccessManager trial', () {
    late Directory tmp;
    late DateTime now;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('turbo-access-test');
      now = DateTime.utc(2026, 1, 1, 12);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    AccessManager build() => AccessManager(
          store: SecureStore(rootOverride: tmp),
          publicKey: publicKey,
          trialLength: const Duration(days: 7),
          clock: () => now,
        );

    test('starts a fresh trial on first run', () async {
      final manager = build();
      await manager.init();
      expect(await manager.ensureStarted(), isTrue);
      final status = manager.status();
      expect(status.isTrial, isTrue);
      expect(status.hasAccess, isTrue);
      expect(status.expiresAt, now.add(const Duration(days: 7)));
    });

    test('the trial clock is persisted across restarts', () async {
      final first = build();
      await first.init();
      await first.ensureStarted();
      final start = first.status().issuedAt;

      final second = build();
      await second.init();
      expect(await second.ensureStarted(), isFalse);
      expect(second.status().issuedAt, start);
    });

    test('access ends when the trial window elapses', () async {
      final manager = build();
      await manager.init();
      await manager.ensureStarted();

      now = now.add(const Duration(days: 6, hours: 23));
      expect(manager.status().isTrial, isTrue);

      now = now.add(const Duration(hours: 2));
      final status = manager.status();
      expect(status.isTrial, isFalse);
      expect(status.isFree, isTrue);
      expect(status.hasAccess, isFalse);
    });

    test('rolling the clock back does not extend access', () async {
      final manager = build();
      await manager.init();
      await manager.ensureStarted();

      // Use the app for three days, then wind the clock back a week.
      now = now.add(const Duration(days: 3));
      await manager.markSeen();
      now = DateTime.utc(2025, 12, 25);

      // Effective time stays at the high-water mark, so the trial does not reset.
      expect(manager.effectiveNow(), DateTime.utc(2026, 1, 4, 12));
      expect(manager.status().remainingAt(manager.effectiveNow())!.inDays, 4);
    });
  });

  group('AccessManager licence', () {
    late Directory tmp;
    late DateTime now;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('turbo-access-test');
      now = DateTime.utc(2026, 6, 1);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    AccessManager build() => AccessManager(
          store: SecureStore(rootOverride: tmp),
          publicKey: publicKey,
          clock: () => now,
        );

    Future<String> key({
      DateTime? expires,
      String? holder,
    }) =>
        LicenceCodec.sign(
          Licence(
            tier: AccessTier.pro,
            issuedAt: now,
            expiresAt: expires,
            holder: holder,
          ),
          keyPair: keyPair,
        );

    test('activating a valid key grants Pro', () async {
      final manager = build();
      await manager.init();
      final error = await manager.activate(await key(holder: 'Ada'));
      expect(error, isNull);
      final status = manager.status();
      expect(status.isPro, isTrue);
      expect(status.holder, 'Ada');
    });

    test('rejects an expired key', () async {
      final manager = build();
      await manager.init();
      final error = await manager.activate(
        await key(expires: now.subtract(const Duration(days: 1))),
      );
      expect(error, 'That key has expired.');
      expect(manager.status().isPro, isFalse);
    });

    test('rejects a key signed by another key', () async {
      final manager = build();
      await manager.init();
      final other = await Ed25519().newKeyPair();
      final token = await LicenceCodec.sign(
        Licence(tier: AccessTier.pro, expiresAt: now.add(const Duration(days: 30))),
        keyPair: other,
      );
      expect(await manager.activate(token), 'That key is not valid.');
    });

    test('a stored key survives a restart', () async {
      final first = build();
      await first.init();
      await first.activate(await key(expires: now.add(const Duration(days: 30))));

      final second = build();
      await second.init();
      expect(second.status().isPro, isTrue);
    });

    test('deactivating returns to trial or free', () async {
      final manager = build();
      await manager.init();
      await manager.ensureStarted();
      await manager.activate(await key(expires: now.add(const Duration(days: 30))));
      expect(manager.status().isPro, isTrue);

      await manager.deactivate();
      expect(manager.status().isPro, isFalse);
    });

    test('an empty key is rejected with a hint', () async {
      final manager = build();
      await manager.init();
      expect(await manager.activate('   '), 'Enter a licence key.');
    });
  });

  group('AccessStatus', () {
    test('reports the fraction of the window used', () {
      final status = AccessStatus(
        tier: AccessTier.pro,
        licensed: true,
        trialActive: false,
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 11),
      );
      expect(status.usedFractionAt(DateTime.utc(2026, 1, 1)), 0);
      expect(status.usedFractionAt(DateTime.utc(2026, 1, 6)), closeTo(0.5, 1e-9));
      expect(status.usedFractionAt(DateTime.utc(2026, 1, 11)), 1);
      // Past the end, still clamped.
      expect(status.usedFractionAt(DateTime.utc(2026, 2, 1)), 1);
    });
  });

  group('formatRemaining', () {
    test('renders days, hours, minutes, and perpetual access', () {
      expect(formatRemaining(null), 'Never expires');
      expect(formatRemaining(const Duration(days: 6)), '6 days left');
      expect(formatRemaining(const Duration(days: 1, hours: 5)), '1 d 5 h left');
      expect(formatRemaining(const Duration(hours: 2, minutes: 5)),
          '2 h 05 min left');
      expect(formatRemaining(const Duration(minutes: 9)), '9 min left');
      expect(formatRemaining(const Duration(seconds: 30)), 'Under a minute left');
      expect(formatRemaining(const Duration(seconds: -1)), 'Expired');
    });
  });

  group('TurboState access enforcement', () {
    late Directory tmp;
    late DateTime now;
    late SimpleKeyPair kp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('turbo-access-state');
      now = DateTime.utc(2026, 3, 1);
      kp = await Ed25519().newKeyPair();
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    TurboState build(SimplePublicKey pub) {
      final manager = AccessManager(
        store: SecureStore(rootOverride: tmp),
        publicKey: pub,
        clock: () => now,
      );
      return TurboState(access: manager);
    }

    test('locks concurrency and scheduling once the trial ends', () async {
      final pub = await kp.extractPublicKey();
      final state = build(pub);
      addTearDown(state.dispose);
      await state.init();
      state.setMaxConcurrent(4);
      expect(state.hasAccess, isTrue);
      expect(state.canSchedule, isTrue);
      expect(state.effectiveMaxConcurrent, 4);

      // Move past the trial window and refresh.
      now = now.add(const Duration(days: 9));
      state.refreshAccess();
      expect(state.hasAccess, isFalse);
      expect(state.canSchedule, isFalse);
      expect(state.effectiveMaxConcurrent, 1);
    });

    test('a Pro licence restores full access', () async {
      final pub = await kp.extractPublicKey();
      final state = build(pub);
      addTearDown(state.dispose);
      await state.init();
      now = now.add(const Duration(days: 9));
      state.refreshAccess();
      expect(state.hasAccess, isFalse);

      final token = await LicenceCodec.sign(
        Licence(
          tier: AccessTier.pro,
          issuedAt: now,
          expiresAt: now.add(const Duration(days: 365)),
          holder: 'Grace',
        ),
        keyPair: kp,
      );
      expect(await state.activateLicence(token), isNull);
      expect(state.isPro, isTrue);
      expect(state.hasAccess, isTrue);
      expect(state.accessStatus!.holder, 'Grace');
      expect(state.timeRemaining()!.inDays, 365);

      await state.deactivateLicence();
      expect(state.isPro, isFalse);
    });

    test('an invalid key is rejected and leaves access unchanged', () async {
      final pub = await kp.extractPublicKey();
      final state = build(pub);
      addTearDown(state.dispose);
      await state.init();
      final other = await Ed25519().newKeyPair();
      final token = await LicenceCodec.sign(
        Licence(tier: AccessTier.pro, expiresAt: now.add(const Duration(days: 5))),
        keyPair: other,
      );
      expect(await state.activateLicence(token), 'That key is not valid.');
      expect(state.isPro, isFalse);
    });
  });

  group('access UI', () {
    late Directory tmp;
    late DateTime now;
    late SimpleKeyPair kp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('turbo-access-ui');
      now = DateTime.utc(2026, 5, 1);
      kp = await Ed25519().newKeyPair();
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<TurboState> mounted(WidgetTester tester, Widget child) async {
      final pub = await kp.extractPublicKey();
      final manager = AccessManager(
        store: SecureStore(rootOverride: tmp),
        publicKey: pub,
        clock: () => now,
      );
      final state = TurboState(access: manager)..loading = false;
      addTearDown(state.dispose);
      // Initialise only the access layer; the full TurboState.init() does device
      // I/O that is not part of this test. runAsync lets the real file I/O
      // complete inside the widget-test fake-async zone.
      await tester.runAsync(() async {
        await manager.init();
        await manager.ensureStarted();
      });
      state.refreshAccess();
      await tester.pumpWidget(
        ChangeNotifierProvider<TurboState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTurboTheme(TurboAccents.of('cyan')),
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('banner and chip show the trial countdown', (tester) async {
      await mounted(tester, const AccessBanner());
      expect(find.textContaining('Trial · 7 days left'), findsOneWidget);

      await mounted(tester, const AccessChip());
      expect(find.text('TRIAL · 7 days left'), findsOneWidget);
    });

    testWidgets('the banner disappears once a Pro key is active',
        (tester) async {
      final state = await mounted(tester, const AccessBanner());
      final token = await LicenceCodec.sign(
        Licence(
          tier: AccessTier.pro,
          issuedAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          holder: 'Ada',
        ),
        keyPair: kp,
      );
      await tester.runAsync(() => state.activateLicence(token));
      await tester.pump();
      // Pro is active, so the banner renders nothing.
      expect(find.textContaining('Trial'), findsNothing);

      // A fresh mount reads the persisted key and shows the Pro chip.
      await mounted(tester, const AccessChip());
      expect(find.textContaining('PRO ·'), findsOneWidget);
    });

    testWidgets('the licence dialog rejects a bad key and accepts a good one',
        (tester) async {
      final state = await mounted(tester, const AccessBanner());
      // Fire-and-forget: the future completes only when the dialog closes.
      showLicenceDialog(tester.element(find.byType(AccessBanner)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'not-a-key');
      await tester.runAsync(() async {
        await tester.tap(find.text('Activate'));
        // Let the real crypto + store write finish before leaving runAsync.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('That key is not valid.'), findsOneWidget);

      final token = await LicenceCodec.sign(
        Licence(
          tier: AccessTier.pro,
          issuedAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          holder: 'Ada',
        ),
        keyPair: kp,
      );
      await tester.enterText(find.byType(TextField), token);
      await tester.runAsync(() async {
        await tester.tap(find.text('Activate'));
        // Let the real crypto + store write finish before leaving runAsync.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(state.isPro, isTrue);
    });
  });
}
