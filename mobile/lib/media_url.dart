/// Detection of media pages versus direct file links, plus the file-kind
/// classification the UI uses for icons and labels.
///
/// Detection is heuristic and deliberately broad: it recognises the big
/// streaming platforms by name, but the app does not *depend* on that list. A
/// link that is not a plain file (no file extension, or an HTML response) is
/// offered to the extractor too, so a platform that is not listed still works.
library;

/// Well-known hosts whose pages are media, not files.
const _mediaHosts = <String>[
  // Video
  'youtube.com',
  'youtu.be',
  'youtube-nocookie.com',
  'vimeo.com',
  'dailymotion.com',
  'dai.ly',
  'twitch.tv',
  'bilibili.com',
  'nicovideo.jp',
  'rumble.com',
  'odysee.com',
  'lbry.tv',
  'streamable.com',
  'veoh.com',
  'metacafe.com',
  'break.com',
  'archive.org',
  'veoh.com',
  // Social / short-form
  'tiktok.com',
  'instagram.com',
  'facebook.com',
  'fb.watch',
  'twitter.com',
  'x.com',
  'reddit.com',
  'redd.it',
  'linkedin.com',
  'pinterest.com',
  'snapchat.com',
  'tumblr.com',
  'threads.net',
  // Audio / music
  'soundcloud.com',
  'bandcamp.com',
  'mixcloud.com',
  'spotify.com',
  'deezer.com',
  'audiomack.com',
  'boomplay.com',
  'anghami.com',
  'music.apple.com',
  'podcasts.apple.com',
  // Other regions / live
  'vk.com',
  'ok.ru',
  'weibo.com',
  'youku.com',
  'iqiyi.com',
  'naver.com',
  'kick.com',
  'trovo.live',
  'caffeine.tv',
];

/// True when [url] points at a known streaming/media site. Only the hostname
/// is inspected; the path is irrelevant.
bool isMediaUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  for (final domain in _mediaHosts) {
    if (host == domain || host.endsWith('.$domain')) return true;
  }
  return false;
}

/// True only for YouTube hosts, which get a dedicated on-device extractor.
bool isYouTubeUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
}

/// True when a link has no recognisable file extension, which usually means it
/// is a page (to be resolved by an extractor) rather than a file to fetch.
///
/// This is the safety net that keeps unlisted platforms working: a brand-new
/// site with no extension in its URLs is still routed to the extractor.
bool looksLikePage(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final last = segments.isEmpty ? '' : segments.last;
  if (last.isEmpty) return true;

  // A dotted suffix of 2–5 word/letter characters reads as a file extension.
  final dot = last.lastIndexOf('.');
  if (dot <= 0 || dot == last.length - 1) return true;
  final ext = last.substring(dot + 1);
  return !RegExp(r'^[A-Za-z0-9]{2,5}$').hasMatch(ext);
}

/// True when a pasted link should be handled by a media extractor.
///
/// Known platforms always qualify; anything else does when it looks like a page
/// rather than a file.
bool needsExtraction(String url) => isMediaUrl(url) || looksLikePage(url);

/// Broad classification of a download, used for the card icon and filter chips.
enum FileKind {
  video,
  audio,
  image,
  archive,
  document,
  app,
  other;

  String get label => switch (this) {
        FileKind.video => 'Video',
        FileKind.audio => 'Audio',
        FileKind.image => 'Image',
        FileKind.archive => 'Archive',
        FileKind.document => 'Document',
        FileKind.app => 'App',
        FileKind.other => 'File',
      };
}

const _videoExt = {
  'mp4', 'mkv', 'webm', 'mov', 'avi', 'flv', 'wmv', 'm4v', 'mpg', 'mpeg',
  '3gp', 'ts', 'm3u8', 'ogv', 'm2ts', 'vob',
};
const _audioExt = {
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'wma', 'aiff',
  'alac', 'mid', 'm3u',
};
const _imageExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'tiff', 'tif', 'ico',
  'heic', 'avif', 'raw',
};
const _archiveExt = {
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'iso', 'apk', 'ipa',
  'jar', 'cab', 'zst',
};
const _documentExt = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv',
  'md', 'epub', 'mobi', 'odt', 'ods', 'json', 'xml', 'html', 'htm',
};
const _appExt = {
  'exe', 'msi', 'dmg', 'pkg', 'deb', 'rpm', 'appimage', 'apk', 'bat', 'sh',
};

/// Classifies a filename (or URL) by its extension.
FileKind kindOf(String name) {
  var value = name.trim();
  try {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty);
      if (segs.isNotEmpty) value = segs.last;
    }
  } catch (_) {}
  final dot = value.lastIndexOf('.');
  if (dot <= 0 || dot == value.length - 1) return FileKind.other;
  final ext = value.substring(dot + 1).toLowerCase();
  if (_videoExt.contains(ext)) return FileKind.video;
  if (_audioExt.contains(ext)) return FileKind.audio;
  if (_imageExt.contains(ext)) return FileKind.image;
  if (_archiveExt.contains(ext)) return FileKind.archive;
  if (_documentExt.contains(ext)) return FileKind.document;
  if (_appExt.contains(ext)) return FileKind.app;
  return FileKind.other;
}

/// True when a completed file's name is a media container we can play.
bool isPlayable(String name) {
  final kind = kindOf(name);
  return kind == FileKind.video || kind == FileKind.audio;
}
