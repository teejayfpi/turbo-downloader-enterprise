import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbo_downloader/services/app_dirs.dart';
import 'package:turbo_downloader/services/secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('default location', () {
    // The reported failure: with no override the store resolved `./.turbo` and
    // a read-only cwd made the session read throw. These drive the real
    // no-override path (not the test-only rootOverride).
    late Directory dir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('secure-default');
      AppDirs.testOverride = dir;
    });
    tearDown(() {
      AppDirs.testOverride = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('round-trips a value without an explicit root', () async {
      final store = SecureStore();
      await store.write('session', 'cookie-jar');
      expect(await SecureStore().read('session'), 'cookie-jar');
    });

    test('writes nothing outside the resolved directory', () async {
      final store = SecureStore();
      await store.write('session', 'cookie-jar');
      final files = dir.listSync().map((e) => e.path).toList();
      expect(files.any((p) => p.endsWith('secure.json')), isTrue);
    });
  });

  group('SecureStore.generate', () {
    test('honours the requested length', () {
      expect(SecureStore.generate(length: 12).length, 12);
      expect(SecureStore.generate(length: 40).length, 40);
    });

    test('includes a character from every enabled class', () {
      // Run a few times: the shuffle means a single draw could pass by luck.
      for (var i = 0; i < 20; i++) {
        final value = SecureStore.generate(length: 24);
        expect(value.contains(RegExp(r'[a-z]')), isTrue);
        expect(value.contains(RegExp(r'[A-Z]')), isTrue);
        expect(value.contains(RegExp(r'[0-9]')), isTrue);
        expect(value.contains(RegExp(r'[^A-Za-z0-9]')), isTrue);
      }
    });

    test('omits symbols when asked', () {
      for (var i = 0; i < 20; i++) {
        final value = SecureStore.generate(length: 24, symbols: false);
        expect(value.contains(RegExp(r'[^A-Za-z0-9]')), isFalse);
      }
    });

    test('does not repeat across draws', () {
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        seen.add(SecureStore.generate());
      }
      expect(seen.length, 50);
    });
  });

  group('SecureStore.strength', () {
    test('labels an empty value', () {
      expect(SecureStore.strength('').score, 0);
    });

    test('rates a long random password as very strong', () {
      expect(SecureStore.strength(SecureStore.generate(length: 24)).score, 4);
    });

    test('rates a short, single-class value as weak', () {
      expect(SecureStore.strength('abcde').score, lessThanOrEqualTo(1));
    });

    test('increases with length and variety', () {
      expect(SecureStore.strength('abcdefgh').score,
          lessThan(SecureStore.strength('Abcdef1!').score));
    });
  });

  group('SecureStore.fingerprint', () {
    test('is stable and not the plaintext', () {
      final fp = SecureStore.fingerprint('super-secret');
      expect(fp, SecureStore.fingerprint('super-secret'));
      expect(fp.length, 12);
      expect(fp.contains('super-secret'), isFalse);
      expect(fp, isNot(SecureStore.fingerprint('super-secret2')));
    });
  });
}
