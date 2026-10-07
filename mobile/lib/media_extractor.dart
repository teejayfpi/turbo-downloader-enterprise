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
  /// Direct, fetchable stream URL for the video (or the sole stream).
  final String url;

  /// Human title, used for the saved filename.
  final String title;

  /// File extension for the saved container (mp4, webm, m4a, ts).
  final String extension;

  /// Size in bytes when the extractor knows it, otherwise 0. When [audioUrl]
  /// is set this is the sum of the video and audio sizes.
  final int size;

  /// Resolution/quality label for display, e.g. "360p" or "128kbps".
  final String qualityLabel;

  /// "video" for a combined stream, "audio" for an audio-only stream.
  final String kind;

  /// A separate audio-only track that must be merged into [url] before the
  /// file is usable. Set only for video-only renditions above YouTube's 360p
  /// muxed ceiling; the device muxes the two streams with the bundled FFmpeg.
  final String? audioUrl;

  /// Container extension for [audioUrl] (m4a or webm).
  final String? audioExtension;

  /// Size of [audioUrl] in bytes when known, otherwise 0.
  final int audioSize;

  const ResolvedMedia({
    required this.url,
    required this.title,
    required this.extension,
    required this.size,
    required this.qualityLabel,
    required this.kind,
    this.audioUrl,
    this.audioExtension,
    this.audioSize = 0,
  });

  /// True when this rendition needs a separate audio track merged in.
  bool get needsMux => audioUrl != null;
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

      // Combined streams are the only ones a device without a muxer can save
      // directly; YouTube caps them at 360p.
      final muxed = manifest.muxed.toList()
        ..sort((a, b) =>
            b.videoResolution.height.compareTo(a.videoResolution.height));
      final muxedHeights = <int>{};
      final videoFormats = <MediaFormat>[];
      for (final s in muxed) {
        muxedHeights.add(s.videoResolution.height);
        videoFormats.add(MediaFormat(
          id: 'muxed:${s.qualityLabel}:${s.container.name}',
          label: _videoLabel(s.qualityLabel, s.videoResolution.height),
          kind: 'video',
          extension: _extensionFor(s.container.name),
          size: s.size.totalBytes,
          height: s.videoResolution.height,
        ));
      }

      // Video-only streams carry every resolution above 360p. Keep one per
      // height (YouTube serves each as AVC/MP4 and VP9/WebM), preferring MP4
      // so the merged file plays everywhere, and skip heights already covered
      // by a muxed stream so the picker lists each quality once.
      final videoOnlyByHeight = <int, MediaFormat>{};
      for (final s in manifest.videoOnly) {
        final h = s.videoResolution.height;
        if (h <= 0 || muxedHeights.contains(h)) continue;
        final f = MediaFormat(
          id: 'video:${s.qualityLabel}:${s.container.name}',
          label: _videoLabel(s.qualityLabel, h),
          kind: 'video-only',
          extension: _extensionFor(s.container.name),
          size: s.size.totalBytes,
          height: h,
          requiresMux: true,
        );
        final existing = videoOnlyByHeight[h];
        if (existing == null || _preferContainer(f, existing)) {
          videoOnlyByHeight[h] = f;
        }
      }
      videoFormats.addAll(videoOnlyByHeight.values);
      videoFormats.sort((a, b) => b.height.compareTo(a.height));
      formats.addAll(videoFormats);

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
        'YouTube refused to serve this video. It may need a signed-in '
        'session, or the network you are on is blocked by YouTube. Add your '
        'YouTube cookies in Settings → Sign-in & cookies and retry; the '
        'HD/merged engine can then sign in.',
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
  /// rendition is returned. A `video:` id (a video-only stream above 360p)
  /// resolves to the video plus a separate audio track in [ResolvedMedia], so
  /// the caller can merge them with the bundled FFmpeg. Otherwise a combined
  /// (muxed) stream is preferred, then audio-only.
  ///
  /// The optional overrides let tests supply canned metadata instead of
  /// reaching the network.
  Future<ResolvedMedia> resolve(
    String pageUrl, {
    String? formatId,
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

      if (formatId != null) {
        final picked = _pick(manifest, formatId);
        if (picked != null) {
          if (picked is yt.VideoOnlyStreamInfo) {
            return _muxedResolved(picked, manifest, video.title);
          }
          return _toResolved(picked, video.title, formatId);
        }
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
        'YouTube refused to serve this video. It may need a signed-in '
        'session, or the network you are on is blocked by YouTube. Add your '
        'YouTube cookies in Settings → Sign-in & cookies and retry; the '
        'HD/merged engine can then sign in.',
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

  /// Matches a format id from [describe] back to a concrete stream. Combined
  /// (`muxed:`), audio (`audio:`) and video-only (`video:`) ids all resolve;
  /// a video-only id is paired with an audio track by the caller.
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
      case 'video':
        pool = manifest.videoOnly;
        break;
      case 'audio':
        pool = manifest.audioOnly;
        break;
      default:
        return null;
    }
    yt.StreamInfo? match;
    for (final s in pool) {
      final label = group == 'audio'
          ? '${s.bitrate.kiloBitsPerSecond.round()}'
          : s.qualityLabel;
      // Ids use the saved extension ("m4a" for an MP4 audio track), not the
      // raw container name, so compare the same normalised token.
      if (label == quality && _containerToken(group, s.container.name) == container) {
        // Prefer the AVC/MP4 rendition when a height is served twice.
        if (group == 'video' && _containerRank(s.container.name) >= 2) return s;
        match ??= s;
      }
    }
    // No exact match: return null so the caller falls back to the best muxed
    // stream instead of saving an arbitrary resolution.
    return match;
  }

  /// Maps a container to the token used in format ids. Audio-only MP4 streams
  /// are saved as `.m4a`, so they use that extension in their id.
  static String _containerToken(String group, String container) {
    if (group == 'audio') return container == 'webm' ? 'webm' : 'm4a';
    return _extensionFor(container);
  }

  /// Builds a [ResolvedMedia] for a video-only stream, pairing it with the
  /// best audio track so the caller can mux them. Prefers an AAC/MP4 audio
  /// track for an MP4 video, since that pair remuxes without re-encoding.
  static ResolvedMedia _muxedResolved(
    yt.VideoOnlyStreamInfo video,
    yt.StreamManifest manifest,
    String title,
  ) {
    final container = video.container.name;
    final audio = _bestAudio(manifest, preferMp4: container != 'webm');
    return ResolvedMedia(
      url: video.url.toString(),
      title: title,
      extension: _extensionFor(container),
      size: video.size.totalBytes + (audio?.size.totalBytes ?? 0),
      qualityLabel: video.qualityLabel,
      kind: 'video',
      audioUrl: audio?.url.toString(),
      audioExtension: audio == null
          ? null
          : (audio.container.name == 'webm' ? 'webm' : 'm4a'),
      audioSize: audio?.size.totalBytes ?? 0,
    );
  }

  /// Picks the highest-bitrate audio track, preferring MP4/AAC when the video
  /// is MP4 so the pair remuxes cleanly.
  static yt.AudioOnlyStreamInfo? _bestAudio(
    yt.StreamManifest manifest, {
    required bool preferMp4,
  }) {
    final audio = manifest.audioOnly.toList()
      ..sort(
          (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    if (audio.isEmpty) return null;
    if (preferMp4) {
      final mp4 = audio.where((a) => a.container.name == 'mp4').toList();
      if (mp4.isNotEmpty) return mp4.first;
    }
    return audio.first;
  }

  /// Ranks containers for the picker; MP4/AVC first so merged files play on
  /// the widest range of devices.
  static bool _preferContainer(MediaFormat candidate, MediaFormat current) {
    final c = _containerRank(candidate.extension);
    final k = _containerRank(current.extension);
    if (c != k) return c > k;
    return candidate.size > current.size;
  }

  static int _containerRank(String extension) {
    switch (extension) {
      case 'mp4':
      case 'm4v':
        return 2;
      case 'webm':
        return 1;
      default:
        return 0;
    }
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
