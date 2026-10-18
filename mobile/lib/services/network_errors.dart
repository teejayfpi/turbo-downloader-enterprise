/// Recognises a name-resolution failure — the OS could not turn a hostname
/// into an IP address.
///
/// This is distinct from a connection that opened and then dropped, and from a
/// site refusing a request. The usual causes are the device being offline, a
/// captive portal or DNS outage, or a VPN/ad-blocker that filters the host. The
/// wording differs per platform, so every spelling is matched:
///   * Android/Linux: `Failed host lookup: 'host'` / `No address associated
///     with hostname`
///   * Python (the embedded engine): `Name or service not known` /
///     `Temporary failure in name resolution`
///   * macOS/iOS: `nodename nor servname provided, or not known`
///
/// Kept here rather than in either extractor because both the pure-Dart and the
/// embedded-yt-dlp paths have to turn it into the same advice.
bool looksLikeOfflineOrDns(String message) {
  final m = message.toLowerCase();
  return m.contains('failed host lookup') ||
      m.contains('no address associated with hostname') ||
      m.contains('name or service not known') ||
      m.contains('temporary failure in name resolution') ||
      m.contains('nodename nor servname') ||
      m.contains('server not found') ||
      m.contains('unknown host') ||
      m.contains('errno = 7');
}

/// What to show when a hostname cannot be resolved. Names the common causes so
/// the user can act, instead of surfacing a raw `SocketException`.
const offlineOrDnsMessage =
    'Could not reach the site — its address could not be looked up. Check your '
    'internet connection (Wi-Fi or mobile data), and turn off any VPN or '
    'ad-blocker that may be filtering it, then retry.';
