import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

/// A muxing failure with a message that is safe to show the user.
class MediaMuxException implements Exception {
  final String message;
  const MediaMuxException(this.message);

  @override
  String toString() => message;
}

/// Merges a video-only stream and an audio-only stream into a single file with
/// the bundled FFmpeg, so a download can exceed YouTube's 360p muxed ceiling.
///
/// The merge is a container remux (`-c copy`): no re-encoding, so it is fast,
/// lossless, and needs no codec support beyond the container muxer. Runs
/// entirely on the device through FFmpegKit's native libraries.
class FfmpegMuxer {
  FfmpegMuxer();

  bool? _available;
  Future<void>? _init;

  /// True when the bundled FFmpeg responds. Cached after the first probe.
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      _init ??= FFmpegKitConfig.init();
      await _init;
      final session = await FFmpegKit.execute('-version');
      final code = await session.getReturnCode();
      _available = ReturnCode.isSuccess(code);
    } catch (_) {
      // Desktop builds without the native bundle, or tests with no plugin.
      _available = false;
    }
    return _available!;
  }

  /// Remuxes [videoPath] and [audioPath] into [outPath], copying both streams
  /// without re-encoding. The video stream decides the container.
  ///
  /// Throws [MediaMuxException] when FFmpeg is unavailable or the merge fails.
  Future<void> mux({
    required String videoPath,
    required String audioPath,
    required String outPath,
    String container = 'mp4',
  }) async {
    if (!await isAvailable()) {
      throw const MediaMuxException(
        'Merging video and audio needs the bundled FFmpeg, which is not '
        'available on this build.',
      );
    }

    final muxer = container == 'webm' ? 'matroska' : container;
    final args = <String>[
      '-y',
      '-i', videoPath,
      '-i', audioPath,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c', 'copy',
      // Keep MP4 playable on the widest range of players.
      if (container == 'mp4') ...['-movflags', '+faststart'],
      '-f', muxer,
      outPath,
    ];

    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getOutput() ?? '';
      throw MediaMuxException(
        'Could not merge the video and audio tracks. ${_tail(logs)}',
      );
    }

    final out = File(outPath);
    if (!await out.exists() || await out.length() == 0) {
      throw const MediaMuxException(
        'The merge produced no output file. The source streams may be '
        'incomplete; retry the download.',
      );
    }
  }

  /// Stops any running FFmpeg session, used when a download is cancelled.
  Future<void> cancel() async {
    try {
      await FFmpegKit.cancel();
    } catch (_) {}
  }

  /// Last meaningful line of FFmpeg's log, kept short for the error message.
  static String _tail(String logs) {
    final lines = logs
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    final last = lines.last;
    return last.length > 200 ? last.substring(last.length - 200) : last;
  }
}
