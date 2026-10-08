import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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

  group('YtdlpEngine access-denied detection', () {
    test('recognises a hard 403 and DASH segment refusal', () {
      expect(
        YtdlpEngine.looksLikeAccessDenied('HTTP Error 403: Forbidden'),
        isTrue,
      );
      expect(
        YtdlpEngine.looksLikeAccessDenied(
            'unable to download video data: HTTP Error 403: Forbidden'),
        isTrue,
      );
    });

    test('recognises rate limiting', () {
      expect(YtdlpEngine.looksLikeAccessDenied('HTTP Error 429: Too Many Requests'),
          isTrue);
    });

    test('leaves a plain format error alone', () {
      expect(
        YtdlpEngine.looksLikeAccessDenied(
            'Requested format is not available. Use --list-formats'),
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

    test('rejects a download whose checksum does not match', () async {
      // flutter_test's binding installs a mock HttpClient that rejects all
      // real requests; these tests exercise an actual loopback server.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final tmp = await Directory.systemTemp.createTemp('turbo_upd_test');
      addTearDown(() => tmp.delete(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);

      final body = latin1.encode('not the real bytes');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      await expectLater(
        installer.download(
          'http://127.0.0.1:${server.port}/turbo.apk',
          expectedSha256: '0' * 64,
        ),
        throwsA(isA<HttpException>()),
      );
      // Nothing must be left behind for the installer to pick up.
      expect(tmp.listSync(), isEmpty);
    });

    test('accepts a download whose checksum matches', () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final tmp = await Directory.systemTemp.createTemp('turbo_upd_ok');
      addTearDown(() => tmp.delete(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);

      final body = latin1.encode('the genuine bytes');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = body.length
          ..add(body);
        await req.response.close();
      });

      final digest = sha256.convert(body).toString();
      final file = await installer.download(
        'http://127.0.0.1:${server.port}/turbo.apk',
        expectedSha256: digest,
      );
      expect(await file.readAsBytes(), equals(body));
    });

    test('refuses a download when no manifest lists the asset', () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final tmp = await Directory.systemTemp.createTemp('turbo_upd_manifest');
      addTearDown(() => tmp.delete(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);

      final body = latin1.encode('the genuine bytes');
      // A manifest that covers a different asset must not wave this download
      // through unverified: blocking the manifest would otherwise downgrade the
      // integrity check to nothing.
      final manifest = utf8.encode('${'a' * 64}  Turbo-some-other-file.exe\n');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final isManifest = req.uri.path.contains('SHA256SUMS');
        final payload = isManifest ? manifest : body;
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = payload.length
          ..add(payload);
        await req.response.close();
      });

      final base = 'http://127.0.0.1:${server.port}';
      await expectLater(
        installer.download(
          '$base/turbo.apk',
          checksumUrls: ['$base/SHA256SUMS.desktop'],
        ),
        throwsA(isA<HttpException>()),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('allows an unverified download only when explicitly opted in',
        () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final tmp = await Directory.systemTemp.createTemp('turbo_upd_optin');
      addTearDown(() => tmp.delete(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);

      final body = latin1.encode('the genuine bytes');
      final manifest = utf8.encode('${'a' * 64}  Turbo-some-other-file.exe\n');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final isManifest = req.uri.path.contains('SHA256SUMS');
        final payload = isManifest ? manifest : body;
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = payload.length
          ..add(payload);
        await req.response.close();
      });

      final base = 'http://127.0.0.1:${server.port}';
      final file = await installer.download(
        '$base/turbo.apk',
        checksumUrls: ['$base/SHA256SUMS.desktop'],
        allowUnverified: true,
      );
      expect(await file.readAsBytes(), equals(body));
    });

    test('verifies against the manifest entry when the asset is listed',
        () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);

      final tmp = await Directory.systemTemp.createTemp('turbo_upd_listed');
      addTearDown(() => tmp.delete(recursive: true));
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);

      final body = latin1.encode('the genuine bytes');
      final digest = sha256.convert(body).toString();
      final manifest = utf8.encode('$digest  Turbo-android.apk\n');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final isManifest = req.uri.path.contains('SHA256SUMS');
        final payload = isManifest ? manifest : body;
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = payload.length
          ..add(payload);
        await req.response.close();
      });

      final base = 'http://127.0.0.1:${server.port}';
      final file = await installer.download(
        '$base/Turbo-android.apk',
        checksumUrls: ['$base/SHA256SUMS.android'],
      );
      expect(await file.readAsBytes(), equals(body));
    });
  });
}

/// Minimal path_provider stand-in that returns a fixed temporary directory.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getTemporaryPath() async => dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}
