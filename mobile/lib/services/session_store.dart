import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ytdlp.dart';
import 'secure_store.dart';

/// Holds the optional signed-in session used for sites that demand one
/// (YouTube's bot check, age-restricted, private, or members-only videos).
///
/// The cookie jar itself lives in [SecureStore] — the Android Keystore on
/// mobile, an owner-only file on desktop. When downloads run it is written to a
/// short-lived Netscape `cookies.txt` that the on-device yt-dlp engine reads.
/// Nothing is sent to a server: the cookies travel straight from this device to
/// the site the user asked for, exactly like a browser would.
class SessionStore {
  SessionStore({SecureStore? secure, Directory? rootOverride})
      : _secure = secure ?? SecureStore(),
        _rootOverride = rootOverride;

  static const _cookiesKey = 'turbo.session.cookies';
  static const _browserKey = 'turbo.session.browser';

  final SecureStore _secure;
  final Directory? _rootOverride;

  /// The stored cookie-jar text (a Netscape `cookies.txt`), or null.
  Future<String?> cookies() => _secure.read(_cookiesKey);

  /// The browser whose local profile yt-dlp should read, or null.
  Future<String?> browser() async {
    final value = await _secure.read(_browserKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  /// True when any session is configured, so Settings can show it at a glance.
  Future<bool> get hasSession async =>
      (await browser()) != null ||
      ((await cookies())?.trim().isNotEmpty ?? false);

  Future<void> setCookies(String text) async {
    if (text.trim().isEmpty) {
      await _secure.delete(_cookiesKey);
    } else {
      await _secure.write(_cookiesKey, text);
    }
  }

  Future<void> setBrowser(String? name) async {
    if (name == null || name.trim().isEmpty) {
      await _secure.delete(_browserKey);
    } else {
      await _secure.write(_browserKey, name.trim());
    }
  }

  Future<void> clear() async {
    await _secure.delete(_cookiesKey);
    await _secure.delete(_browserKey);
  }

  /// Points [engine] at the configured session — a browser profile, or a
  /// freshly written `cookies.txt`. Returns the file it wrote, if any, so the
  /// caller can delete it once transfers are done.
  Future<File?> applyTo(YtdlpEngine engine) async {
    final fromBrowser = await browser();
    engine.cookiesFromBrowser = fromBrowser;
    if (fromBrowser != null) {
      engine.cookiesPath = null;
      return null;
    }
    final jar = (await cookies())?.trim();
    if (jar == null || jar.isEmpty) {
      engine.cookiesPath = null;
      return null;
    }
    final dir = _rootOverride ?? await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/turbo_cookies.txt');
    await file.writeAsString(ensureNetscapeHeader(jar), flush: true);
    engine.cookiesPath = file.path;
    return file;
  }

  /// A browser export or copy-paste may omit the Netscape header line, which
  /// yt-dlp requires; add it rather than rejecting the paste.
  static String ensureNetscapeHeader(String jar) =>
      jar.contains('# Netscape HTTP Cookie File')
          ? jar
          : '# Netscape HTTP Cookie File\n$jar';

  /// How many cookie lines the jar holds, for a status line. Header and blank
  /// lines are not counted.
  static int countCookies(String jar) => jar
      .split('\n')
      .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
      .length;

  /// The browsers yt-dlp can read directly from their local profile.
  static const browsers = <String, String>{
    'chrome': 'Chrome',
    'edge': 'Edge',
    'firefox': 'Firefox',
    'brave': 'Brave',
    'chromium': 'Chromium',
    'opera': 'Opera',
    'vivaldi': 'Vivaldi',
    'safari': 'Safari',
    'whale': 'Whale',
  };
}
