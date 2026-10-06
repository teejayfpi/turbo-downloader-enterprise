import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbo_downloader/services/access.dart';
import 'package:turbo_downloader/services/licence.dart';
import 'package:turbo_downloader/services/secure_store.dart';
import 'package:turbo_downloader/services/subscription.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late SimpleKeyPair keyPair;
  late SimplePublicKey publicKey;
  late LicenceIssuer issuer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('turbo-sub-test');
    keyPair = await Ed25519().newKeyPair();
    publicKey = await keyPair.extractPublicKey();
    issuer = LicenceIssuer(keyPair);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SecureStore store() => SecureStore(rootOverride: tmp);

  group('BillingPlan', () {
    test('maps names and lengths', () {
      expect(BillingPlan.fromName('daily'), BillingPlan.daily);
      expect(BillingPlan.fromName('yearly'), BillingPlan.yearly);
      expect(BillingPlan.fromName('nonsense'), BillingPlan.custom);
      expect(BillingPlan.monthly.days, 30);
      expect(BillingPlan.yearly.days, 365);
    });
  });

  group('LicenceIssuer', () {
    test('a monthly key expires one plan-length out', () async {
      final now = DateTime.utc(2026, 3, 1);
      final result = await issuer.issue(
        holder: 'Ada',
        plan: BillingPlan.monthly,
        now: now,
      );
      expect(result.subscription.expiresAt, now.add(const Duration(days: 30)));
      expect(result.subscription.id, startsWith('SUB-260301-'));
      final verified = await LicenceCodec.verify(
        result.subscription.key,
        publicKey: publicKey,
      );
      expect(verified!.plan, 'monthly');
      expect(verified.id, result.subscription.id);
    });

    test('a yearly key lasts 365 days', () async {
      final now = DateTime.utc(2026, 1, 1);
      final result = await issuer.issue(
        holder: 'Bo',
        plan: BillingPlan.yearly,
        now: now,
      );
      expect(result.subscription.expiresAt, now.add(const Duration(days: 365)));
    });

    test('a custom plan uses the supplied end date', () async {
      final end = DateTime.utc(2026, 12, 25);
      final result = await issuer.issue(
        holder: 'Cy',
        plan: BillingPlan.custom,
        now: DateTime.utc(2026, 1, 1),
        expiresAt: end,
      );
      expect(result.subscription.expiresAt, end);
    });

    test('a custom plan without an end date is perpetual', () async {
      final result = await issuer.issue(
        holder: 'Di',
        plan: BillingPlan.custom,
        now: DateTime.utc(2026, 1, 1),
      );
      expect(result.subscription.isPerpetual, isTrue);
    });

    test('a device-bound key carries the device claim', () async {
      final result = await issuer.issue(
        holder: 'Eve',
        plan: BillingPlan.daily,
        now: DateTime.utc(2026, 1, 1),
        deviceId: 'device-123',
      );
      final verified = await LicenceCodec.verify(
        result.subscription.key,
        publicKey: publicKey,
      );
      expect(verified!.device, 'device-123');
    });

    test('fromSeed round-trips the public key', () async {
      final seed = await keyPair.extractPrivateKeyBytes();
      final encoded = base64Url.encode(seed).replaceAll('=', '');
      final rebuilt = await LicenceIssuer.fromSeed(encoded);
      final expected = await keyPair.extractPublicKey();
      expect(await rebuilt.publicKeyBase64(),
          base64Url.encode(expected.bytes).replaceAll('=', ''));
    });
  });

  group('Subscription', () {
    test('survives a JSON round-trip', () async {
      final result = await issuer.issue(
        holder: 'Ada',
        plan: BillingPlan.quarterly,
        now: DateTime.utc(2026, 1, 1),
      );
      final decoded = Subscription.fromJson(result.subscription.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.id, result.subscription.id);
      expect(decoded.holder, 'Ada');
      expect(decoded.plan, BillingPlan.quarterly);
      expect(decoded.key, result.subscription.key);
    });
  });

  group('SubscriptionLedger', () {
    test('persists entries across instances', () async {
      final ledger = SubscriptionLedger(store: store());
      await ledger.init();
      final result = await issuer.issue(
        holder: 'Ada',
        plan: BillingPlan.monthly,
        now: DateTime.utc(2026, 1, 1),
      );
      await ledger.add(result.subscription);

      final reopened = SubscriptionLedger(store: store());
      await reopened.init();
      expect(reopened.all, hasLength(1));
      expect(reopened.byId(result.subscription.id)!.holder, 'Ada');
    });

    test('counts active and expired subscriptions', () async {
      final ledger = SubscriptionLedger(store: store());
      await ledger.init();
      final now = DateTime.utc(2026, 6, 1);
      final live = await issuer.issue(
          holder: 'Live', plan: BillingPlan.yearly, now: now);
      final dead = await issuer.issue(
        holder: 'Dead',
        plan: BillingPlan.daily,
        now: now.subtract(const Duration(days: 5)),
      );
      await ledger.add(live.subscription);
      await ledger.add(dead.subscription);

      final stats = ledger.stats(now);
      expect(stats.total, 2);
      expect(stats.active, 1);
      expect(stats.expired, 1);
    });

    test('remove forgets an entry', () async {
      final ledger = SubscriptionLedger(store: store());
      await ledger.init();
      final result = await issuer.issue(
          holder: 'Ada', plan: BillingPlan.monthly, now: DateTime.utc(2026, 1, 1));
      await ledger.add(result.subscription);
      await ledger.remove(result.subscription.id);
      expect(ledger.all, isEmpty);
    });
  });

  group('AdminGate', () {
    test('sets, verifies, locks, and resets the passphrase', () async {
      final gate = AdminGate(store: store());
      await gate.init();
      expect(gate.hasPassphrase, isFalse);

      await gate.setPassphrase('hunter2!');
      expect(gate.hasPassphrase, isTrue);
      expect(gate.isUnlocked, isTrue);

      gate.lock();
      expect(gate.isUnlocked, isFalse);
      expect(await gate.unlock('wrong'), isFalse);
      expect(gate.isUnlocked, isFalse);
      expect(await gate.unlock('hunter2!'), isTrue);
      expect(gate.isUnlocked, isTrue);

      await gate.reset();
      expect(gate.hasPassphrase, isFalse);
      expect(gate.hasSeed, isFalse);
    });

    test('stores a seed and only exposes it when unlocked', () async {
      final gate = AdminGate(store: store());
      await gate.init();
      await gate.setPassphrase('pass');
      await gate.setSeed('SEED-VALUE');
      expect(gate.hasSeed, isTrue);
      expect(gate.seed, 'SEED-VALUE');
      gate.lock();
      expect(gate.seed, isNull);
    });
  });

  group('AccessManager device binding', () {
    test('accepts a key bound to this device', () async {
      final manager = AccessManager(
        store: store(),
        publicKey: publicKey,
        clock: () => DateTime.utc(2026, 6, 1),
        deviceId: () async => 'this-device',
      );
      await manager.init();
      final result = await issuer.issue(
        holder: 'Ada',
        plan: BillingPlan.monthly,
        now: DateTime.utc(2026, 6, 1),
        deviceId: 'this-device',
      );
      expect(await manager.activate(result.subscription.key), isNull);
      expect(manager.status().isPro, isTrue);
    });

    test('rejects a key bound to another device', () async {
      final manager = AccessManager(
        store: store(),
        publicKey: publicKey,
        clock: () => DateTime.utc(2026, 6, 1),
        deviceId: () async => 'this-device',
      );
      await manager.init();
      final result = await issuer.issue(
        holder: 'Ada',
        plan: BillingPlan.monthly,
        now: DateTime.utc(2026, 6, 1),
        deviceId: 'some-other-device',
      );
      expect(await manager.activate(result.subscription.key),
          'That key is locked to a different device.');
      expect(manager.status().isPro, isFalse);
    });
  });
}
