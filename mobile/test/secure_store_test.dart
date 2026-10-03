import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/secure_store.dart';

void main() {
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
