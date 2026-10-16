/// A cookie read out of an embedded browser, reduced to the fields a Netscape
/// `cookies.txt` line needs.
///
/// Deliberately plugin-agnostic: the WebView screen converts its platform
/// `Cookie` objects into [JarCookie] so the serialisation can be unit-tested
/// without a running browser.
class JarCookie {
  const JarCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.expiresMs,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;

  /// Expiry in milliseconds since the epoch, or null for a session cookie
  /// (Netscape writes `0`, which yt-dlp treats as "session").
  final int? expiresMs;
}

/// The domains a YouTube session is carried on. yt-dlp needs the
/// `youtube.com` cookies; the `.google.com` ones keep the login itself valid.
const youtubeCookieDomains = <String>{
  'youtube.com',
  '.youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  '.google.com',
  'google.com',
  'accounts.google.com',
};

/// Serialises browser cookies into the Netscape format yt-dlp reads.
///
/// HttpOnly cookies are prefixed with `#HttpOnly_` on the domain field, which
/// is how a Netscape jar marks them; without the prefix yt-dlp skips them, and
/// the signed-in session cookies (SID, HSID, SSID, …) are exactly the HttpOnly
/// ones — so the login would silently not take. Fields are tab-separated and
/// empty names/values are dropped because a blank field makes yt-dlp reject
/// the line.
class CookieJar {
  const CookieJar._();

  static String toNetscape(Iterable<JarCookie> cookies) {
    final lines = <String>['# Netscape HTTP Cookie File'];
    for (final c in cookies) {
      final domain = c.domain.trim();
      final name = c.name.trim();
      if (domain.isEmpty || name.isEmpty) continue;
      final includeSub = domain.startsWith('.') ? 'TRUE' : 'FALSE';
      final prefix = c.httpOnly ? '#HttpOnly_' : '';
      final expiry = ((c.expiresMs ?? 0) / 1000).floor().clamp(0, 1 << 62);
      final path = c.path.trim().isEmpty ? '/' : c.path.trim();
      final secure = c.secure ? 'TRUE' : 'FALSE';
      lines.add('$prefix$domain\t$includeSub\t$path\t$secure\t$expiry\t'
          '$name\t${c.value}');
    }
    return lines.join('\n');
  }

  /// Keeps only the cookies that belong to the YouTube / Google login, so the
  /// vault does not accumulate unrelated browsing cookies from the WebView.
  static List<JarCookie> onlyYouTube(Iterable<JarCookie> cookies) {
    return cookies.where((c) {
      final d = c.domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      return youtubeCookieDomains.any((k) {
        final bare = k.replaceFirst(RegExp(r'^\.'), '');
        return d == bare || d.endsWith('.$bare');
      });
    }).toList();
  }
}
