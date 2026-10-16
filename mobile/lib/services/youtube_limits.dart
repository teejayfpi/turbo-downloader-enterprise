/// Recognition and wording for YouTube's IP rate-limit notice.
///
/// `youtube_explode_dart` throws this when YouTube answers the page request
/// with a "too many requests from this IP" page. It is not the signed-in bot
/// check and not a per-video problem: the same response comes back for every
/// video until the network's request rate drops, so the advice has to be
/// "wait", not "add cookies".
library;

/// True when [message] is YouTube's rate-limit notice rather than a bot check,
/// a private video, or a plain network failure.
///
/// Matched on the wording the library uses so a version bump that reflows the
/// sentence still trips on at least one phrase.
bool isYouTubeRateLimit(String message) {
  final m = message.toLowerCase();
  return m.contains('rate limiting') ||
      m.contains('rate-limit') ||
      m.contains('too many request');
}

/// What to show the user when YouTube rate-limits this network. Kept free of
/// the library's internal advice ("inject an HttpClient...") because the app
/// cannot act on it here, and free of the raw URL/response dump.
const youTubeRateLimitMessage =
    'YouTube is rate-limiting this network — it has seen too many requests '
    'from your IP and is treating them as suspicious. Wait a few minutes, then '
    'retry. If it keeps happening, switch networks (e.g. from Wi-Fi to mobile '
    'data) or sign in under Settings → Sign-in & cookies, which lets the '
    'yt-dlp engine send an authenticated request instead.';
