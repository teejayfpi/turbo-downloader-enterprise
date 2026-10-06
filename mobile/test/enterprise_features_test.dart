import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/credits.dart';
import 'package:turbo_downloader/file_store.dart';

/// Guards the identity constants and the desktop share hand-off that the
/// splash, Settings, and downloads screen depend on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('app identity', () {
    test('appVersion matches the version in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
              .firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
      // The splash and Settings show appVersion; a stale value would also make
      // the update checker offer a downgrade or miss a real update.
      expect(appVersion, match!.group(1));
    });

    test('the designer credit and WhatsApp number are well-formed', () {
      expect(Designer.name, isNotEmpty);
      expect(Designer.whatsappNumber, matches(RegExp(r'^[0-9]+$')),
          reason: 'wa.me needs an international number with no + or spaces');
      expect(Designer.whatsappUri.scheme, 'https');
      expect(Designer.whatsappUri.host, 'wa.me');
      expect(Designer.whatsappUri.pathSegments.single, Designer.whatsappNumber);
      expect(Designer.phoneDisplay, isNotEmpty);
    });
  });

  group('FileStore.share', () {
    late List<MethodCall> calls;

    setUp(() {
      // The share sheet is the Android path; pin the platform so the test does
      // not take the desktop reveal branch when it runs on a Windows/macOS host.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('turbo_downloader/files'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('turbo_downloader/files'),
        null,
      );
    });

    test('hands the file and its name to the platform share sheet', () async {
      final ok = await FileStore.share('/tmp/clip.mp4', filename: 'clip.mp4');

      expect(ok, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareFile');
      expect(calls.single.arguments['path'], '/tmp/clip.mp4');
      expect(calls.single.arguments['filename'], 'clip.mp4');
    });

    test('falls back to the file own name when none is given', () async {
      await FileStore.share('/tmp/movie.mkv');
      expect(calls.single.arguments['filename'], 'movie.mkv');
    });

    test('derives the name from a Windows path too', () async {
      await FileStore.share(r'C:\Users\me\Downloads\Turbo\Videos\clip.mp4');
      expect(calls.single.arguments['filename'], 'clip.mp4');
    });

    test('reports failure instead of throwing when no handler is installed',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('turbo_downloader/files'),
        null,
      );
      // No platform implementation (e.g. a desktop test host): a share must
      // degrade to false, never crash the downloads screen.
      expect(await FileStore.share('/tmp/x.mp4'), isFalse);
    });
  });
}
