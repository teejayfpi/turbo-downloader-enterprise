import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// A media page that has been inspected, without downloading anything.
///
/// Produced by [MediaExtractor.describe] so the UI can show the title,
/// duration, thumbnail, and the list of formats the user can pick from. The
/// bytes are never fetched here; this is metadata only.
class MediaInfo {
  /// Human title of the media.
  final String title;

  /// Uploader / channel / artist name, when known.
  final String? author;

  /// Length in seconds, when known.
  final int? durationSeconds;

  /// Best thumbnail URL, when known.
  final String? thumbnailUrl;

  /// Selectable formats, best first.
  final List<MediaFormat> formats;

  const MediaInfo({
    required this.title,
    this.author,
    this.durationSeconds,
    this.thumbnailUrl,
    required this.formats,
  });
}

/// One downloadable rendition of a media page.
class MediaFormat {
  /// Stable identifier for this format, surfaced to the extractor when the
  /// task actually runs (e.g. `muxed:720p:mp4`, or `video:1080p:mp4`).
  final String id;

  /// Short label for the picker, e.g. "1080p" or "128 kbps".
  final String label;

  /// "video" | "video-only" | "audio".
  final String kind;

  /// Container extension without the dot, e.g. "mp4" or "m4a".
  final String extension;

  /// File size in bytes when known, otherwise 0.
  final int size;

  /// Video height in pixels for video renditions, otherwise 0.
  final int height;

  /// True when this format needs a separate audio track merged in, which
  /// only the yt-dlp engine (bundled binary) can do. The pure-Dart fallback
  /// can only save combined (`muxed`) formats.
  final bool requiresMux;

  const MediaFormat({
    required this.id,
    required this.label,
    required this.kind,
    required this.extension,
    required this.size,
    this.height = 0,
    this.requiresMux = false,
  });

  /// True when this is a combined audio+video stream.
  bool get muxed => !requiresMux && kind == 'video';

  bool get isAudio => kind == 'audio';

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind,
        'extension': extension,
        'size': size,
        'height': height,
        'requiresMux': requiresMux,
      };

  static MediaFormat fromJson(Map<String, dynamic> json) => MediaFormat(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: json['kind'] as String? ?? 'video',
        extension: json['extension'] as String? ?? 'mp4',
        size: (json['size'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        requiresMux: json['requiresMux'] as bool? ?? false,
      );
}

/// A media page resolved to a direct stream the device can fetch on its own.
class ResolvedMedia {
  /// Direct, fetchable stream URL.
  final String url;

  /// Human title, used for the saved filename.
  final String title;

  /// File extension for the saved container (mp4, webm, m4a, ts).
  final String extension;

  /// Size in bytes when the extractor knows it, otherwise 0.
  final int size;

  /// Resolution/quality label for display, e.g. "360p" or "128kbps".
  final String qualityLabel;

  /// "video" for a combined stream, "audio" for an audio-only stream.
  final String kind;

  const ResolvedMedia({
    required this.url,
    required this.title,
    required this.extension,
    required this.size,
    required this.qualityLabel,
    required this.kind,
  });
}

/// A resolution failure with a message that is safe to show the user.
class MediaResolveException implements Exception {
  final String message;
  const MediaResolveException(this.message);

  @override
  String toString() => message;
}

/// Metadata and stream-URL lookups for supported media pages.
///
/// Backed by `youtube_explode_dart`, which covers YouTube. Pages on other
/// platforms, and high-resolution muxed renditions, are handed to the yt-dlp
/// engine in `lib/ytdlp.dart` instead.
class MediaExtractor {
  const MediaExtractor();

  /// Inspects a media page and returns its title, duration, thumbnail and the
  /// formats that can be downloaded. Nothing is downloaded here.
  ///
  /// The optional overrides let tests supply canned metadata instead of
  /// reaching the network.
  Future<MediaInfo> describe(
    String pageUrl, {
    yt.Video? videoOverride,
    yt.StreamManifest? manifestOverride,
  }) async {
    final client = yt.YoutubeExplode();
    try {
      final video = videoOverride ?? await client.videos.get(pageUrl);
      final manifest = manifestOverride ??
          await client.videos.streamsClient.getManifest(
            video.id,
            ytClients: _apiClients,
          );

      final formats = <MediaFormat>[];

      final muxed = manifest.muxed.toList()
        ..sort((a, b) =>
            b.videoResolution.height.compareTo(a.videoResolution.height));
      for (final s in muxed) {
        formats.add(MediaFormat(
          id: 'muxed:${s.qualityLabel}:${s.container.name}',
          label: _videoLabel(s.qualityLabel, s.videoResolution.height),
          kind: 'video',
          extension: _extensionFor(s.container.name),
          size: s.size.totalBytes,
          height: s.videoResolution.height,
        ));
      }

      final videoOnly = manifest.videoOnly.toList()
        ..sort((a, b) =>
            b.videoResolution.height.compareTo(a.videoResolution.height));
      for (final s in videoOnly) {
        formats.add(MediaFormat(
          id: 'video:${s.qualityLabel}:${s.container.name}',
          label: '${_videoLabel(s.qualityLabel, s.videoResolution.height)} HD',
          kind: 'video-only',
          extension: _extensionFor(s.container.name),
          size: s.size.totalBytes,
          height: s.videoResolution.height,
          requiresMux: true,
        ));
      }

      final audio = manifest.audioOnly.toList()
        ..sort(
            (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      for (final s in audio) {
        final kbps = s.bitrate.kiloBitsPerSecond.round();
        final ext = s.container.name == 'webm' ? 'webm' : 'm4a';
        formats.add(MediaFormat(
          id: 'audio:$kbps:$ext',
          label: '$kbps kbps audio',
          kind: 'audio',
          extension: ext,
          size: s.size.totalBytes,
        ));
      }

      return MediaInfo(
        title: video.title,
        author: video.author,
        durationSeconds: video.duration?.inSeconds,
        thumbnailUrl: video.thumbnails.highResUrl,
        formats: formats,
      );
    } on yt.VideoUnavailableException {
      throw const MediaResolveException(
        'YouTube would not serve this page. It may be private, '
        'age-restricted, or blocked in your region.',
      );
    } on yt.YoutubeExplodeException catch (e) {
      throw MediaResolveException('Could not read this page: ${e.message}');
    } on MediaResolveException {
      rethrow;
    } catch (e) {
      throw MediaResolveException('Could not read this page: $e');
    } finally {
      client.close();
    }
  }

  /// Resolves [pageUrl] to a single stream that can be saved standalone.
  ///
  /// When [formatId] matches one of the formats from [describe], that
  /// rendition is returned. Otherwise a combined (muxed) stream is preferred,
  /// then audio-only. Separate high-resolution tracks cannot be merged without
  /// an on-device muxer, and an HLS manifest is a playlist rather than a file,
  /// so neither is offered here.
  Future<ResolvedMedia> resolve(String pageUrl, {String? formatId}) async {
    final client = yt.YoutubeExplode();
    try {
      final video = await client.videos.get(pageUrl);
      final manifest = await client.videos.streamsClient.getManifest(
        video.id,
        ytClients: _apiClients,
      );

      if (formatId != null) {
        final picked = _pick(manifest, formatId);
        if (picked != null) return _toResolved(picked, video.title, formatId);
      }

      final muxed = manifest.muxed.toList()
        ..sort((a, b) =>
            b.videoResolution.height.compareTo(a.videoResolution.height));
      if (muxed.isNotEmpty) return _toResolved(muxed.first, video.title, null);

      final audio = manifest.audioOnly.toList()
        ..sort(
            (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      if (audio.isNotEmpty) return _toResolved(audio.first, video.title, null);

      throw const MediaResolveException(
        'No downloadable stream was found for this page.',
      );
    } on yt.VideoUnavailableException {
      throw const MediaResolveException(
        'YouTube would not serve this page. It may be private, '
        'age-restricted, or blocked in your region.',
      );
    } on yt.YoutubeExplodeException catch (e) {
      throw MediaResolveException('Could not read this page: ${e.message}');
    } on MediaResolveException {
      rethrow;
    } catch (e) {
      throw MediaResolveException('Could not resolve this page: $e');
    } finally {
      client.close();
    }
  }

  static final _apiClients = [
    yt.YoutubeApiClient.ios,
    yt.YoutubeApiClient.androidVr,
    yt.YoutubeApiClient.androidSdkless,
    yt.YoutubeApiClient.tv,
  ];

  /// Matches a format id from [describe] back to a concrete stream. Only
  /// combined (`muxed:`) and audio (`audio:`) ids resolve to a standalone
  /// file; `video:` ids need muxing and are declined here.
  static yt.StreamInfo? _pick(yt.StreamManifest manifest, String formatId) {
    final parts = formatId.split(':');
    if (parts.length < 3) return null;
    final group = parts[0];
    final quality = parts[1];
    final container = parts[2];

    Iterable<yt.StreamInfo> pool;
    switch (group) {
      case 'muxed':
        pool = manifest.muxed;
        break;
      case 'audio':
        pool = manifest.audioOnly;
        break;
      default:
        return null; // video-only requires muxing
    }
    for (final s in pool) {
      final label = group == 'audio'
          ? '${s.bitrate.kiloBitsPerSecond.round()}'
          : s.qualityLabel;
      if (label == quality && s.container.name == container) return s;
    }
    return pool.isEmpty ? null : pool.first;
  }

  static ResolvedMedia _toResolved(
      yt.StreamInfo stream, String title, String? formatId) {
    final isAudio = stream is yt.AudioOnlyStreamInfo;
    final ext = isAudio
        ? (stream.container.name == 'webm' ? 'webm' : 'm4a')
        : _extensionFor(stream.container.name);
    return ResolvedMedia(
      url: stream.url.toString(),
      title: title,
      extension: ext,
      size: stream.size.totalBytes,
      qualityLabel: isAudio
          ? '${stream.bitrate.kiloBitsPerSecond.round()} kbps'
          : stream.qualityLabel,
      kind: isAudio ? 'audio' : 'video',
    );
  }

  static String _videoLabel(String qualityLabel, int height) {
    return height > 0 ? '${height}p' : qualityLabel;
  }

  static String _extensionFor(String container) {
    switch (container) {
      case 'webm':
        return 'webm';
      case 'mp4':
      case 'm4v':
        return 'mp4';
      default:
        return container.isEmpty ? 'mp4' : container;
    }
  }
}
