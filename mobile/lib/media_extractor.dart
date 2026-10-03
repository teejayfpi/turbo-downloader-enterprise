import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

/// A media page resolved to a direct stream the phone can fetch on its own.
///
/// The bytes are never proxied through a server: the extractor only turns a
/// page URL into a stream URL, then the on-device engine downloads that URL
/// straight to this device.
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

/// Turns a media page into a direct stream using an on-device extractor.
///
/// Only the public page URL is sent to the platform; the returned stream URL
/// is fetched by this device with its own storage and bandwidth.
class MediaExtractor {
  const MediaExtractor();

  /// Resolves [pageUrl] to the best stream that can be saved as a single file.
  ///
  /// Combined (muxed) streams are preferred because they play standalone.
  /// Separate high-resolution video and audio streams cannot be merged without
  /// an on-device muxer, so they are deliberately not offered; the fallbacks
  /// are an HLS combined stream and, last, audio-only.
  Future<ResolvedMedia> resolve(String pageUrl) async {
    final client = yt.YoutubeExplode();
    try {
      final video = await client.videos.get(pageUrl);
      final manifest = await client.videos.streamsClient.getManifest(
        video.id,
        // Several clients are queried and merged; more of them means a better
        // chance one returns a combined stream from this network.
        ytClients: [
          yt.YoutubeApiClient.ios,
          yt.YoutubeApiClient.androidVr,
          yt.YoutubeApiClient.androidSdkless,
          yt.YoutubeApiClient.tv,
        ],
      );

      final muxed = manifest.muxed.toList()
        ..sort((a, b) =>
            b.videoResolution.height.compareTo(a.videoResolution.height));
      if (muxed.isNotEmpty) {
        final stream = muxed.first;
        return ResolvedMedia(
          url: stream.url.toString(),
          title: video.title,
          extension: _extensionFor(stream.container.name),
          size: stream.size.totalBytes,
          qualityLabel: stream.qualityLabel,
          kind: 'video',
        );
      }

      // HLS carries combined audio+video as fragments the client concatenates
      // into one stream. It is the next best standalone file.
      final hls = manifest.hls;
      if (hls.isNotEmpty) {
        final stream = hls.first;
        return ResolvedMedia(
          url: stream.url.toString(),
          title: video.title,
          extension: 'ts',
          size: stream.size.totalBytes,
          qualityLabel: '${stream.qualityLabel} (combined)',
          kind: 'video',
        );
      }

      final audio = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      if (audio.isNotEmpty) {
        final stream = audio.first;
        final ext = stream.container.name == 'webm' ? 'webm' : 'm4a';
        return ResolvedMedia(
          url: stream.url.toString(),
          title: video.title,
          extension: ext,
          size: stream.size.totalBytes,
          qualityLabel: stream.qualityLabel,
          kind: 'audio',
        );
      }

      throw const MediaResolveException(
        'No downloadable stream was found for this video.',
      );
    } on yt.VideoUnavailableException {
      throw const MediaResolveException(
        'YouTube would not serve this video. It may be private, '
        'age-restricted, or blocked in your region.',
      );
    } on yt.YoutubeExplodeException catch (e) {
      throw MediaResolveException('Could not read this video: ${e.message}');
    } on MediaResolveException {
      rethrow;
    } catch (e) {
      throw MediaResolveException('Could not resolve this video: $e');
    } finally {
      client.close();
    }
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
