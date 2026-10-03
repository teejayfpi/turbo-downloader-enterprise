import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The result of asking yt-dlp to describe a page.
///
/// [formats] are ordered best-first and each carries a ready-to-use yt-dlp
/// `-f` selector, so the UI can offer them directly.
class YtdlpProbe {
  final String title;
  final String? author;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final List<YtdlpFormat> formats;
  final bool hasFfmpeg;

  const YtdlpProbe({
    required this.title,
    required this.formats,
    this.author,
    this.durationSeconds,
    this.thumbnailUrl,
    this.hasFfmpeg = false,
  });
}

/// One yt-dlp format.
class YtdlpFormat {
  final String formatId;
  final String label;
  final String kind; // video | video-only | audio
  final String extension;
  final int size;
  final int height;

  /// `-f` selector that yields this rendition, including a merged audio track
  /// for video-only formats when ffmpeg is available.
  final String selector;

  /// True when this rendition must be merged with a separate audio stream.
  final bool requiresMux;

  const YtdlpFormat({
    required this.formatId,
    required this.label,
    required this.kind,
    required this.extension,
    required this.size,
    required this.height,
    required this.selector,
    required this.requiresMux,
  });
}

/// Raised for a yt-dlp failure with a message that is safe to show the user.
class YtdlpException implements Exception {
  final String message;
  const YtdlpException(this.message);
  @override
  String toString() => message;
}

/// Drives the external [yt-dlp](https://github.com/yt-dlp/yt-dlp) binary for
/// sites beyond YouTube and for high-resolution (merged) downloads.
///
/// Everything still runs on the device: yt-dlp is an ordinary program that
/// writes to this machine's disk, and the app only reads its output. No
/// server, account, or key is involved.
class YtdlpEngine {
  /// Optional explicit path to the binary, set from Settings.
  String? overridePath;

  String? _cachedBinary;
  bool _searched = false;

  /// The binary in use, or null when yt-dlp is not installed.
  String? get binary => _cachedBinary;

  /// True when a usable yt-dlp binary is present.
  bool get isAvailable => _cachedBinary != null;

  /// Finds the yt-dlp binary once and caches the answer. A [overridePath] from
  /// Settings wins; otherwise `PATH` and the usual install locations are tried.
  Future<String?> locate() async {
    final explicit = overridePath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (await _isRunnable(explicit)) {
        _cachedBinary = explicit;
        _searched = true;
        return _cachedBinary;
      }
    }
    if (_searched && _cachedBinary != null) return _cachedBinary;
    _searched = true;

    // `PATH` first.
    final onPath = await _which('yt-dlp');
    if (onPath != null) {
      _cachedBinary = onPath;
      return _cachedBinary;
    }

    // Common install locations, including the `yt-dlp[.exe]` a user drops next
    // to the app or in their home/bin folder.
    for (final candidate in _candidates()) {
      if (await _isRunnable(candidate)) {
        _cachedBinary = candidate;
        return _cachedBinary;
      }
    }
    return _cachedBinary;
  }

  /// Re-runs detection, e.g. after the user installs yt-dlp or edits the path.
  Future<String?> refresh() async {
    _searched = false;
    _cachedBinary = null;
    return locate();
  }

  Iterable<String> _candidates() sync* {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final exe = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    if (Platform.isWindows) {
      for (final root in [
        Platform.environment['LOCALAPPDATA'],
        Platform.environment['APPDATA'],
        Platform.environment['ProgramFiles'],
      ]) {
        if (root != null && root.isNotEmpty) {
          yield '$root\\yt-dlp\\$exe';
          yield '$root\\Programs\\$exe';
        }
      }
      if (home.isNotEmpty) yield '$home\\$exe';
    } else {
      yield '/usr/local/bin/yt-dlp';
      yield '/usr/bin/yt-dlp';
      yield '/opt/homebrew/bin/yt-dlp';
      yield '/snap/bin/yt-dlp';
      if (home.isNotEmpty) {
        yield '$home/.local/bin/yt-dlp';
        yield '$home/bin/yt-dlp';
      }
    }
  }

  Future<bool> hasFfmpeg() async => (await _which('ffmpeg')) != null;

  /// Describes [url]: title, author, duration, thumbnail, and formats.
  Future<YtdlpProbe> probe(String url) async {
    final bin = await locate();
    if (bin == null) {
      throw const YtdlpException(
        'The download engine (yt-dlp) is not installed.',
      );
    }
    final result = await Process.run(
      bin,
      [
        '-J',
        '--no-warnings',
        '--no-playlist',
        '--no-check-certificates',
        url,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw YtdlpException(_friendly(result.stderr?.toString() ?? ''));
    }
    try {
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      return _parseProbe(json, await hasFfmpeg());
    } catch (e) {
      throw YtdlpException('Could not read this page: $e');
    }
  }

  /// Downloads [url] into [dir] with the given [selector], reporting progress.
  ///
  /// The merged output is allowed to keep whatever container yt-dlp picks; the
  /// caller finds the resulting file with [findResult]. [onProgress] receives
  /// (downloaded, total, bytesPerSecond); total is 0 when unknown. When
  /// [isCancelled] returns true the process is killed and this returns null.
  Future<File?> download({
    required String url,
    required String selector,
    required Directory dir,
    required String stem,
    void Function(int downloaded, int total, int speed)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final bin = await locate();
    if (bin == null) {
      throw const YtdlpException(
        'The download engine (yt-dlp) is not installed.',
      );
    }
    if (!await dir.exists()) await dir.create(recursive: true);

    final args = <String>[
      url,
      '-f', selector,
      '--no-playlist',
      '--no-warnings',
      '--newline',
      '--no-check-certificates',
      '-P', dir.path,
      '-o', '$stem.%(ext)s',
      '--progress-template',
      'download:PROG %(progress.downloaded_bytes)s %(progress.total_bytes)s '
          '%(progress.total_bytes_estimate)s %(progress.speed)s',
    ];

    final process = await Process.start(bin, args);

    var cancelled = false;
    var lastBytes = 0;
    var lastAt = DateTime.now();
    var speed = 0;

    final stderrBuf = StringBuffer();

    final stdoutDone =
        process.stdout.transform(const Utf8Decoder()).listen((chunk) {
      for (final line in chunk.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('PROG ')) continue;
        final parts = trimmed.substring(5).split(RegExp(r'\s+'));
        if (parts.length < 4) continue;
        final downloaded = _num(parts[0]);
        var total = _num(parts[1]);
        if (total <= 0) total = _num(parts[2]);
        final now = DateTime.now();
        final ms = now.difference(lastAt).inMilliseconds;
        if (ms >= 400) {
          final delta = downloaded - lastBytes;
          speed = ms == 0 ? 0 : (delta * 1000 / ms).round();
          lastBytes = downloaded;
          lastAt = now;
        }
        onProgress?.call(downloaded, total, speed);
      }
    }).asFuture<void>();

    final stderrDone = process.stderr
        .transform(const Utf8Decoder())
        .listen(stderrBuf.write)
        .asFuture<void>();

    Timer? poll;
    if (isCancelled != null) {
      poll = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (isCancelled()) {
          cancelled = true;
          process.kill(ProcessSignal.sigterm);
        }
      });
    }

    final code = await process.exitCode;
    poll?.cancel();
    await stdoutDone;
    await stderrDone;

    if (cancelled) return null;
    if (code != 0) {
      throw YtdlpException(_friendly(stderrBuf.toString()));
    }
    return findResult(dir, stem);
  }

  /// Finds the file yt-dlp produced for [stem] in [dir], preferring a merged
  /// media file over leftover fragments.
  File? findResult(Directory dir, String stem) {
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => _baseName(f.path).startsWith(stem))
        .toList();
    if (files.isEmpty) return null;
    // Prefer a playable container, then the largest file.
    files.sort((a, b) {
      final pa = _isPlayableExt(a.path) ? 0 : 1;
      final pb = _isPlayableExt(b.path) ? 0 : 1;
      if (pa != pb) return pa - pb;
      return b.lengthSync().compareTo(a.lengthSync());
    });
    return files.first;
  }

  static bool _isPlayableExt(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mkv') ||
        p.endsWith('.webm') ||
        p.endsWith('.mov') ||
        p.endsWith('.m4a') ||
        p.endsWith('.mp3') ||
        p.endsWith('.opus') ||
        p.endsWith('.ogg');
  }

  YtdlpProbe _parseProbe(Map<String, dynamic> json, bool ffmpeg) {
    final raw = (json['formats'] as List?)?.whereType<Map>().toList() ?? [];
    final formats = <YtdlpFormat>[];

    for (final f in raw) {
      final map = Map<String, dynamic>.from(f);
      final formatId = map['format_id'].toString();
      final ext = '${map['ext'] ?? 'mp4'}';
      final vcodec = '${map['vcodec'] ?? 'none'}';
      final acodec = '${map['acodec'] ?? 'none'}';
      final hasVideo = vcodec != 'none' && vcodec.isNotEmpty;
      final hasAudio = acodec != 'none' && acodec.isNotEmpty;
      final height = (map['height'] as num?)?.toInt() ?? 0;
      final size = (map['filesize'] as num?)?.toInt() ??
          (map['filesize_approx'] as num?)?.toInt() ??
          0;

      if (hasVideo && hasAudio) {
        formats.add(YtdlpFormat(
          formatId: formatId,
          label: height > 0 ? '${height}p' : ext,
          kind: 'video',
          extension: ext,
          size: size,
          height: height,
          selector: formatId,
          requiresMux: false,
        ));
      } else if (hasVideo) {
        formats.add(YtdlpFormat(
          formatId: formatId,
          label: height > 0 ? '${height}p HD' : '$ext HD',
          kind: 'video-only',
          extension: ext,
          size: size,
          height: height,
          // Merge in the best audio; falls back to the video-only stream if
          // there is no separate audio.
          selector: '$formatId+bestaudio/$formatId',
          requiresMux: true,
        ));
      } else if (hasAudio) {
        final abr = (map['abr'] as num?)?.round() ?? 0;
        formats.add(YtdlpFormat(
          formatId: formatId,
          label: abr > 0 ? '$abr kbps audio' : 'audio',
          kind: 'audio',
          extension: ext,
          size: size,
          height: 0,
          selector: formatId,
          requiresMux: false,
        ));
      }
    }

    // Best-first: highest combined resolution, then audio bitrate.
    formats.sort((a, b) {
      final ka = _rank(a), kb = _rank(b);
      if (ka != kb) return kb - ka;
      return b.size.compareTo(a.size);
    });
    _dedupe(formats);

    return YtdlpProbe(
      title: '${json['title'] ?? 'media'}',
      author: json['uploader'] as String? ?? json['channel'] as String?,
      durationSeconds: (json['duration'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnail'] as String?,
      formats: formats,
      hasFfmpeg: ffmpeg,
    );
  }

  /// Combined video ranks highest, then video-only, then audio.
  static int _rank(YtdlpFormat f) {
    final base = f.height * 1000;
    switch (f.kind) {
      case 'video':
        return base + 100;
      case 'video-only':
        return base + 50;
      default:
        return 0;
    }
  }

  /// Drops duplicate labels at the same height/kind, keeping the first.
  static void _dedupe(List<YtdlpFormat> formats) {
    final seen = <String>{};
    formats.retainWhere((f) {
      final key = '${f.kind}:${f.height}:${f.label}:${f.extension}';
      return seen.add(key);
    });
  }

  static int _num(String s) {
    if (s == 'NA' || s == 'None' || s.isEmpty) return 0;
    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
  }

  static String _baseName(String path) {
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static Future<String?> _which(String name) async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('where', [name]);
        if (r.exitCode == 0) {
          final first = r.stdout.toString().trim().split('\n').first.trim();
          if (first.isNotEmpty) return first;
        }
      } else {
        final r = await Process.run('sh', ['-c', 'command -v $name']);
        if (r.exitCode == 0) {
          final path = r.stdout.toString().trim();
          if (path.isNotEmpty) return path;
        }
      }
    } catch (_) {
      // `which`/`where` missing is not fatal; fall back to candidate paths.
    }
    return null;
  }

  static Future<bool> _isRunnable(String path) async {
    try {
      final result = await Process.run(path, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Turns yt-dlp's stderr into a short, human message.
  static String _friendly(String stderr) {
    final trimmed = stderr.trim();
    if (trimmed.isEmpty) return 'The download engine failed.';
    final lines = trimmed
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // yt-dlp prefixes errors with "ERROR:".
    final error = lines.lastWhere(
      (l) => l.toUpperCase().startsWith('ERROR'),
      orElse: () => lines.last,
    );
    final text = error.replaceFirst(RegExp(r'^ERROR:\s*'), '');
    if (text.toLowerCase().contains('ffmpeg')) {
      return 'This format needs ffmpeg to merge audio and video, which is not '
          'installed. Pick a combined format or install ffmpeg.';
    }
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  @visibleForTesting
  void setBinaryForTest(String? path) {
    _cachedBinary = path;
    _searched = true;
  }
}
