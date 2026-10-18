import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Dart side of the embedded yt-dlp engine on Android.
///
/// Android has no `yt-dlp` on `PATH`: the APK bundles CPython, yt-dlp, ffmpeg,
/// and a JavaScript runtime as native libraries and drives them through a
/// Kotlin method channel (`turbo_downloader/ytdlp`; see
/// `android/app/src/main/kotlin/.../YtdlpChannel.kt`). Desktop keeps spawning a
/// real binary from [YtdlpEngine]. Everything above this seam is shared — the
/// argument vectors, the `-J` parsing, and the friendly error text — so both
/// platforms behave identically apart from where the process runs.
///
/// Completion is polled rather than pushed: a download runs on a native worker
/// thread, and the UI thread stays free to answer the poll, which is also how
/// cancellation is delivered. The cost is up to one poll interval of latency
/// after the process ends, which is invisible next to a multi-second download.
class YtdlpAndroidBridge {
  YtdlpAndroidBridge._();

  static const MethodChannel _channel = MethodChannel('turbo_downloader/ytdlp');

  /// The yt-dlp version the embedded engine reports, or null until [init]
  /// succeeds. Until then [YtdlpEngine] treats yt-dlp as absent, which is the
  /// right answer while the interpreter is still unpacking on first launch.
  static String? _version;
  static bool get isReady => _version != null;

  /// Per-download output sinks, keyed by the native process id, so two
  /// concurrent downloads cannot report into each other's progress bar. Each
  /// receives the raw yt-dlp output line, parsed by the shared Dart parser.
  static final Map<String, void Function(String)> _sinks = {};

  static int _seq = 0;

  /// Unpacks CPython/ffmpeg on first call and returns the yt-dlp version, or
  /// null when there is no embedded engine (not Android, or init failed).
  static Future<String?> init() async {
    if (!Platform.isAndroid) return null;
    if (_version != null) return _version;
    try {
      _channel.setMethodCallHandler(_onNativeCall);
      final version = await _channel.invokeMethod<String>('init');
      if (version == null || version.isEmpty) return null;
      _version = version;
      return version;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// `yt-dlp -J <url>`; returns the parsed stdout JSON. [args] already ends
  /// with the url.
  static Future<Map<String, dynamic>> probe(List<String> args) async {
    try {
      final out = await _channel.invokeMethod<String>('probe', {'args': args});
      return jsonDecode(out ?? '{}') as Map<String, dynamic>;
    } on PlatformException catch (e) {
      throw YtdlpAndroidException(e.message ?? 'yt-dlp failed', e.details);
    }
  }

  /// Starts a download on a native worker thread and returns its process id
  /// immediately. Completion is read with [pollDownload].
  static Future<String> startDownload({
    required List<String> args,
    void Function(String line)? onOutput,
  }) async {
    final id = 'turbo-dl-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    if (onOutput != null) _sinks[id] = onOutput;
    try {
      final pid = await _channel.invokeMethod<String>('startDownload', {
        'args': args,
        'processId': id,
      });
      return pid ?? id;
    } on PlatformException catch (e) {
      _sinks.remove(id);
      throw YtdlpAndroidException(e.message ?? 'yt-dlp failed', e.details);
    }
  }

  /// Returns the finished result for [processId], or null while it is still
  /// running. Pass `cancel: true` to also ask the native side to stop it.
  static Future<Map<String, dynamic>?> pollDownload(
    String processId, {
    bool cancel = false,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pollDownload',
        {'processId': processId, 'cancel': cancel},
      );
      if (res == null) return null;
      return res.map((k, v) => MapEntry(k.toString(), v));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A poll failure must not look like a completed download; keep waiting
      // and let the process's own result arrive.
      return null;
    } finally {
      if (cancel) _sinks.remove(processId);
    }
  }

  static void forget(String processId) => _sinks.remove(processId);

  static Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'progress') return null;
    final a = call.arguments;
    if (a is! Map) return null;
    final sink = _sinks[a['processId'] as String?];
    final line = a['line'];
    if (sink != null && line is String) sink(line);
    return null;
  }
}

/// A failure reported by the native yt-dlp process, carrying its raw stderr so
/// [YtdlpEngine] can turn it into the same friendly text it uses on desktop.
class YtdlpAndroidException implements Exception {
  YtdlpAndroidException(this.message, [this.detail]);
  final String message;
  final String? detail;
  @override
  String toString() => message;
}
