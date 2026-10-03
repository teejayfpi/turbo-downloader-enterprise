import '../media_url.dart';

/// The outcome of checking a URL before a download starts.
class UrlValidation {
  final bool valid;
  final Uri? uri;

  /// A plain-language reason when [valid] is false.
  final String? problem;

  const UrlValidation._(this.valid, this.uri, this.problem);

  static const _allowedSchemes = {'http', 'https'};

  /// Schemes the app recognises but deliberately does not fetch, so the user
  /// gets a clear message instead of a confusing engine error.
  static const _blockedSchemes = {
    'ftp': 'FTP links are not supported. Use an http(s) link.',
    'file': 'Local file paths are not supported.',
    'data': 'Data URIs are not supported.',
    'javascript': 'That is a script, not a download link.',
    'mailto': 'That is an email address, not a download link.',
    'magnet': 'Magnet links are not supported.',
  };

  /// Validates [input] as a download URL.
  factory UrlValidation.check(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) {
      return const UrlValidation._(false, null, 'Enter a URL.');
    }
    if (raw.contains(RegExp(r'\s'))) {
      return const UrlValidation._(
          false, null, 'The URL contains spaces. Check it was copied fully.');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return const UrlValidation._(false, null, 'That is not a valid URL.');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) {
      return const UrlValidation._(
          false, null, 'The URL is missing http:// or https://.');
    }
    final blocked = _blockedSchemes[scheme];
    if (blocked != null) {
      return UrlValidation._(false, null, blocked);
    }
    if (!_allowedSchemes.contains(scheme)) {
      return UrlValidation._(
          false, null, 'The "$scheme" scheme is not supported.');
    }
    if (uri.host.isEmpty) {
      return const UrlValidation._(false, null, 'The URL has no host.');
    }
    return UrlValidation._(true, uri, null);
  }

  /// True for a plain http link, which is allowed only for local testing.
  bool get isInsecure => uri?.scheme.toLowerCase() == 'http';
}

/// True when [candidate] targets the same resource as one of [existingUrls].
///
/// Comparison ignores the scheme case and a trailing slash, so pasting the same
/// link twice is caught, while genuinely different links are not.
bool isDuplicateDownload(String candidate, Iterable<String> existingUrls) {
  final normalised = _normalise(candidate);
  if (normalised == null) return false;
  for (final url in existingUrls) {
    if (_normalise(url) == normalised) return true;
  }
  return false;
}

String? _normalise(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  final query = uri.query.isEmpty ? '' : '?${uri.query}';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$path$query';
}

/// Whether a host advertises support for HTTP range requests, from the
/// `Accept-Ranges` header.
bool supportsRanges(String? acceptRangesHeader) =>
    (acceptRangesHeader ?? '').toLowerCase().contains('bytes');

/// A stable, cross-platform-safe filename derived from a URL or title.
///
/// Delegates to the same rules used when publishing a file, so a name shown in
/// the UI is the name that lands on disk on every OS.
String safeFilename(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final trimmed = cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
  return trimmed.isEmpty ? 'turbo-download' : trimmed;
}

/// The best filename to show for a URL before the server is asked.
String filenameFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return 'download';
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return 'download';
  return safeFilename(Uri.decodeComponent(segments.last));
}

/// Classifies what kind of content a URL likely points at, for the pre-flight
/// summary.
FileKind guessKind(String url) => kindOf(filenameFromUrl(url));
