import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Where finished downloads are stored, per platform.
///
/// - Android hands the file to MediaStore so it lands in the shared Downloads
///   collection and is visible to every app.
/// - Desktop platforms copy it into the OS Downloads directory.
/// - Anything else falls back to the app's own storage so a file is never lost.
class FileStore {
  static const _channel = MethodChannel('turbo_downloader/files');

  /// Moves a finished temp file into its final, user-visible location and
  /// returns it. The temp file is consumed.
  static Future<File> publish(File tempFile, String filename) async {
    final safe = sanitize(filename);

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _publishAndroid(tempFile, safe);
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return _publishDesktop(tempFile, safe);
      default:
        return _appPrivate(tempFile, safe);
    }
  }

  /// Opens a saved file with the platform's default application. On Android
  /// and iOS this goes through `open_filex`; on desktop it hands the path to
  /// the OS opener, because `open_filex` has no desktop implementation.
  static Future<void> open(String path) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await Process.start('cmd', ['/c', 'start', '', path],
            runInShell: true, mode: ProcessStartMode.detached);
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        await Process.start('xdg-open', [path],
            mode: ProcessStartMode.detached);
        return;
      }
      await OpenFilex.open(path);
    } catch (_) {
      // No handler installed; the file is still saved and can be opened by hand.
    }
  }

  static Future<File> _publishAndroid(File tempFile, String filename) async {
    try {
      // Android 9 and below need legacy storage to write into the shared
      // Downloads folder; Android 10+ writes through MediaStore and does not.
      final allowed =
          await _channel.invokeMethod<bool>('ensureStorage') ?? true;
      if (!allowed) return _appPrivate(tempFile, filename);
    } on MissingPluginException {
      return _appPrivate(tempFile, filename);
    } catch (_) {
      // Fall through to the publish attempt below.
    }

    try {
      final path = await _channel.invokeMethod<String>('publishDownload', {
        'path': tempFile.path,
        'filename': filename,
      });
      if (path != null && path.isNotEmpty) {
        // MediaStore copied the bytes; the temp copy is no longer needed.
        try {
          await tempFile.delete();
        } catch (_) {}
        return File(path);
      }
    } on MissingPluginException {
      // Fall through to the app-private location below.
    } catch (_) {
      // A failed publish should not lose the file.
    }

    return _appPrivate(tempFile, filename);
  }

  static Future<File> _publishDesktop(File tempFile, String filename) async {
    final dir = await _downloadsDir();
    if (dir == null) return _appPrivate(tempFile, filename);
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = _unique(File('${dir.path}/$filename'));
    return tempFile.rename(dest.path);
  }

  /// The user's Downloads folder, derived from the documents directory so it
  /// works the same on Windows, Linux, and macOS without extra plugins.
  static Future<Directory?> _downloadsDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.parent.path}${Platform.pathSeparator}Downloads');
    } catch (_) {
      return null;
    }
  }

  /// Last-resort location when the user-visible folder is unavailable.
  static Future<File> _appPrivate(File tempFile, String filename) async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dest = _unique(File('${dir.path}/$filename'));
    return tempFile.rename(dest.path);
  }

  /// Appends ` (n)` before the extension so an existing file is never clobbered.
  static File _unique(File file) {
    if (!file.existsSync()) return file;
    final dot = file.path.lastIndexOf('.');
    final stem = dot > 0 ? file.path.substring(0, dot) : file.path;
    final ext = dot > 0 ? file.path.substring(dot) : '';
    var n = 1;
    while (true) {
      final candidate = File('$stem ($n)$ext');
      if (!candidate.existsSync()) return candidate;
      n++;
    }
  }

  /// Strips characters that are illegal in filenames on any platform.
  static String sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'turbo-download' : cleaned;
  }
}
