import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbo_downloader/services/session_store.dart';
import 'package:turbo_downloader/services/secure_store.dart';
import 'package:turbo_downloader/services/update_checker.dart';
import 'package:turbo_downloader/ytdlp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionStore', () {
    late Directory dir;
    late SecureStore secure;
    late SessionStore session;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('turbo_session_test');
      secure = SecureStore(rootOverride: dir);
      session = SessionStore(secure: secure, rootOverride: dir);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('is empty by default', () async {
      expect(await session.hasSession, isFalse);
      expect(await session.cookies(), isNull);
      expect(await session.browser(), isNull);
    });

    test('stores a cookie jar and reports it', () async {
      await session.setCookies('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc');
      expect(await session.hasSession, isTrue);
      expect(await session.cookies(), contains('SID'));
    });

    test('an empty jar clears rather than stores', () async {
      await session.setCookies('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc');
      await session.setCookies('   ');
      expect(await session.hasSession, isFalse);
    });

    test('a browser profile counts as a session', () async {
      await session.setBrowser('firefox');
      expect(await session.hasSession, isTrue);
      expect(await session.browser(), 'firefox');
    });

    test('clear removes both routes', () async {
      await session.setCookies('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc');
      await session.setBrowser('chrome');
      await session.clear();
      expect(await session.hasSession, isFalse);
    });

    test('applyTo writes a cookies.txt and points the engine at it', () async {
      final engine = YtdlpEngine();
      await session.setCookies('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc');
      final file = await session.applyTo(engine);

      expect(file, isNotNull);
      expect(engine.cookiesPath, file!.path);
      expect(engine.cookiesFromBrowser, isNull);
      final contents = await file.readAsString();
      expect(contents, startsWith('# Netscape HTTP Cookie File'));
      expect(contents, contains('SID'));
    });

    test('applyTo prefers a browser profile over a file', () async {
      final engine = YtdlpEngine();
      await session.setCookies('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc');
      await session.setBrowser('chrome');
      final file = await session.applyTo(engine);

      expect(file, isNull);
      expect(engine.cookiesFromBrowser, 'chrome');
      expect(engine.cookiesPath, isNull);
    });

    test('applyTo clears the engine when no session is set', () async {
      final engine = YtdlpEngine()..cookiesPath = '/stale';
      await session.applyTo(engine);
      expect(engine.cookiesPath, isNull);
      expect(engine.cookiesFromBrowser, isNull);
    });
  });

  group('SessionStore jar helpers', () {
    test('adds the Netscape header when missing', () {
      final out = SessionStore.ensureNetscapeHeader('a\tb\tc');
      expect(out, startsWith('# Netscape HTTP Cookie File\n'));
    });

    test('keeps an existing header', () {
      const jar = '# Netscape HTTP Cookie File\n.google.com\tTRUE\t/';
      expect(SessionStore.ensureNetscapeHeader(jar), jar);
    });

    test('counts only real cookie lines', () {
      const jar = '# Netscape HTTP Cookie File\n'
          '\n'
          '.youtube.com\tTRUE\t/\tTRUE\t0\tA\t1\n'
          '# a comment\n'
          '.youtube.com\tTRUE\t/\tTRUE\t0\tB\t2\n';
      expect(SessionStore.countCookies(jar), 2);
    });
  });

  group('YtdlpEngine cookie flags', () {
    test('adds nothing when no session is configured', () {
      expect(YtdlpEngine().cookieArguments, isEmpty);
    });

    test('adds --cookies for a jar file', () {
      final engine = YtdlpEngine()..cookiesPath = '/tmp/jar.txt';
      expect(engine.cookieArguments, ['--cookies', '/tmp/jar.txt']);
    });

    test('prefers --cookies-from-browser when both are set', () {
      final engine = YtdlpEngine()
        ..cookiesPath = '/tmp/jar.txt'
        ..cookiesFromBrowser = 'firefox';
      expect(engine.cookieArguments, ['--cookies-from-browser', 'firefox']);
    });
  });

  group('YtdlpEngine sign-in detection', () {
    test('recognises the YouTube bot check', () {
      expect(
        YtdlpEngine.looksLikeSignInRequired(
            'Sign in to confirm you\'re not a bot. Use --cookies.'),
        isTrue,
      );
    });

    test('recognises private and age-gated videos', () {
      expect(YtdlpEngine.looksLikeSignInRequired('This video is private'), isTrue);
      expect(YtdlpEngine.looksLikeSignInRequired('Age-restricted content'),
          isTrue);
      expect(
          YtdlpEngine.looksLikeSignInRequired('members-only video'), isTrue);
    });

    test('leaves ordinary network errors alone', () {
      expect(
        YtdlpEngine.looksLikeSignInRequired('Unable to download webpage: timeout'),
        isFalse,
      );
    });
  });

  group('UpdateChecker.pickAsset', () {
    const assets = [
      ReleaseAsset('Turbo-linux.tar.gz', 'https://x/linux'),
      ReleaseAsset('Turbo-macos.zip', 'https://x/macos'),
      ReleaseAsset('TurboSetup-windows.exe', 'https://x/windows'),
      ReleaseAsset('turbo-release.apk', 'https://x/android'),
    ];

    test('picks the APK on Android', () {
      expect(UpdateChecker.pickAsset(assets, platform: TargetPlatform.android),
          'https://x/android');
    });

    test('picks the EXE on Windows', () {
      expect(UpdateChecker.pickAsset(assets, platform: TargetPlatform.windows),
          'https://x/windows');
    });

    test('picks the ZIP on macOS', () {
      expect(UpdateChecker.pickAsset(assets, platform: TargetPlatform.macOS),
          'https://x/macos');
    });

    test('picks the tarball on Linux', () {
      expect(UpdateChecker.pickAsset(assets, platform: TargetPlatform.linux),
          'https://x/linux');
    });

    test('returns null when the platform has no asset', () {
      expect(
        UpdateChecker.pickAsset(
          const [ReleaseAsset('Turbo-macos.zip', 'https://x/macos')],
          platform: TargetPlatform.android,
        ),
        isNull,
      );
    });

    test('ignores an asset with an empty url', () {
      expect(
        UpdateChecker.pickAsset(
          const [ReleaseAsset('turbo.apk', '')],
          platform: TargetPlatform.android,
        ),
        isNull,
      );
    });
  });

  group('UpdateInstaller', () {
    const channel = MethodChannel('turbo_downloader/install_test');
    late UpdateInstaller installer;

    setUp(() {
      installer = UpdateInstaller(channel: channel);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reports a started install from the platform channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'installApk');
        return {'started': true};
      });

      final result = await installer.install(File('/tmp/turbo.apk'));
      expect(result.started, isTrue);
      expect(result.needsPermission, isFalse);
    });

    test('surfaces the unknown-apps permission request', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return {'started': false, 'needsPermission': true};
      });

      final result = await installer.install(File('/tmp/turbo.apk'));
      expect(result.started, isFalse);
      expect(result.needsPermission, isTrue);
    });

    test('a missing channel degrades to not-started', () async {
      final result = await installer.install(File('/tmp/turbo.apk'));
      expect(result.started, isFalse);
      expect(result.needsPermission, isFalse);
    });
  });
}
