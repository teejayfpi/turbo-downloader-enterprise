import 'package:flutter_test/flutter_test.dart';
import 'package:turbo_downloader/services/cookie_jar.dart';

void main() {
  group('CookieJar.toNetscape', () {
    test('writes a header and tab-separated fields', () {
      final text = CookieJar.toNetscape(const [
        JarCookie(
          name: 'PREF',
          value: 'f6=400',
          domain: '.youtube.com',
          expiresMs: 1700000000000,
        ),
      ]);
      final lines = text.split('\n');
      expect(lines.first, '# Netscape HTTP Cookie File');
      expect(lines[1], '.youtube.com\tTRUE\t/\tFALSE\t1700000000\tPREF\tf6=400');
    });

    test('marks HttpOnly cookies with the #HttpOnly_ prefix', () {
      final text = CookieJar.toNetscape(const [
        JarCookie(
          name: 'SID',
          value: 'secret',
          domain: '.youtube.com',
          secure: true,
          httpOnly: true,
          expiresMs: 1700000000000,
        ),
      ]);
      // Without this prefix yt-dlp skips the line, so the signed-in session
      // never reaches YouTube — the exact bug this guards against.
      expect(text, contains('#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t'));
    });

    test('a session cookie (no expiry) is written as 0', () {
      final text = CookieJar.toNetscape(const [
        JarCookie(name: 'a', value: 'b', domain: 'youtube.com'),
      ]);
      expect(text, contains('youtube.com\tFALSE\t/\tFALSE\t0\ta\tb'));
    });

    test('drops cookies with an empty name or domain', () {
      final text = CookieJar.toNetscape(const [
        JarCookie(name: '', value: 'x', domain: 'youtube.com'),
        JarCookie(name: 'y', value: 'x', domain: ''),
      ]);
      expect(text.split('\n').length, 1);
    });
  });

  group('CookieJar.onlyYouTube', () {
    test('keeps youtube and google cookies, drops everything else', () {
      final kept = CookieJar.onlyYouTube(const [
        JarCookie(name: 'SID', value: '1', domain: '.youtube.com'),
        JarCookie(name: 'SAPISID', value: '2', domain: '.google.com'),
        JarCookie(name: 'tracker', value: '3', domain: '.example.com'),
      ]).map((c) => c.name).toList();
      expect(kept, ['SID', 'SAPISID']);
    });
  });
}
