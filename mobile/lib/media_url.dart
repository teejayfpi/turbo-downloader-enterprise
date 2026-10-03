/// Hosts whose pages are media, not files. Pasting one of these into the
/// direct downloader would save an HTML page, so the UI steers them to the
/// server's yt-dlp pipeline instead.
const _mediaHosts = <String>[
  'youtube.com',
  'youtu.be',
  'music.youtube.com',
  'm.youtube.com',
  'vimeo.com',
  'dailymotion.com',
  'dai.ly',
  'tiktok.com',
  'instagram.com',
  'facebook.com',
  'fb.watch',
  'twitter.com',
  'x.com',
  'twitch.tv',
  'soundcloud.com',
  'bandcamp.com',
  'mixcloud.com',
  'reddit.com',
  'redd.it',
  'bilibili.com',
  'vk.com',
  'spotify.com',
];

/// True when [url] points at a streaming/media site rather than a plain file.
/// Only the hostname is inspected; the path is irrelevant.
bool isMediaUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  for (final domain in _mediaHosts) {
    if (host == domain || host.endsWith('.$domain')) return true;
  }
  return false;
}

/// YouTube is the one platform that reliably refuses datacenter IPs unless the
/// server is configured with cookies, so it gets its own check for the hint.
bool isYouTubeUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com');
}
