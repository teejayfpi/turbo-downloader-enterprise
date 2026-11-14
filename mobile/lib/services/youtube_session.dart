import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'session_store.dart';

/// Process-wide cookie header for the built-in YouTube extractor.
///
/// The pure-Dart extractor (`youtube_explode_dart`) reads YouTube directly and
/// only sends a hardcoded consent cookie, so a signed-in session from the
/// in-app login never reached it — the gate on mobile stored cookies that did
/// nothing. yt-dlp is handed the session through `--cookies`, but on a phone
/// yt-dlp cannot run, so the built-in extractor is the only path and it must
/// carry the session itself.
///
/// The value is a ready-to-send `Cookie:` header, cached here so a browse
/// client and a one-shot resolver share the same session without threading it
/// through every call.
class YouTubeSession {
  YouTubeSession._();

  static String? _header;
  static int _revision = 0;

  /// The current `Cookie:` header, or null when no session is configured.
  static String? get header => _header;

  /// Bumped whenever the session changes, so a client that caches its
  /// underlying connection can tell it is stale and rebuild.
  static int get revision => _revision;

  /// Replaces the header from a stored Netscape jar (null or empty clears it).
  static void setFromJar(String? jar) {
    _header = SessionStore.cookieHeaderFromJar(jar);
    _revision++;
  }

  /// A YouTube client that sends [header] on every request, or null when no
  /// session is set (callers then use the default client).
  static yt.YoutubeExplode? client() {
    final cookie = _header;
    if (cookie == null || cookie.isEmpty) return null;
    return yt.YoutubeExplode(
      httpClient: _CookieHttpClient(cookie),
    );
  }

  /// Headers a direct fetch of a signed media stream must send.
  ///
  /// The extractor validates a `googlevideo.com` URL with the library's own
  /// client, but the engine then fetches the bytes itself with a generic
  /// browser User-Agent and no cookie — so YouTube's bot check answers 403 even
  /// though the URL is valid, and signing in never helped because the session
  /// cookie never reached the bytes. Replay the exact headers the library's own
  /// downloader uses (its browser agent, `CONSENT`, and the signed-in cookie),
  /// so the fetch carries the identity the URL was signed for. This is what a
  /// browser (and IDM) does implicitly: it downloads with the session that made
  /// the stream playable.
  static Map<String, String> streamHeaders() {
    final headers = Map<String, String>.from(yt.YoutubeHttpClient.defaultHeaders);
    final cookie = _header;
    if (cookie != null && cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
    return headers;
  }
}

/// Adds a fixed `Cookie:` header to every request. Extends the package's own
/// [yt.YoutubeHttpClient] so its retry and response validation are preserved.
class _CookieHttpClient extends yt.YoutubeHttpClient {
  _CookieHttpClient(this._cookie);

  final String _cookie;

  @override
  Map<String, String> get headers => {
        ...super.headers,
        'cookie': _cookie,
      };
}
