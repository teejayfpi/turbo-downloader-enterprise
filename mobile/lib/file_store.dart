import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'media_url.dart';

/// Where finished downloads are stored, per platform.
///
/// Everything is filed under a single `Turbo` folder inside the device's shared
/// Downloads folder, split into a subfolder per kind (Videos, Music, Documents,
/// …) so media and documents are easy to tell apart.
///
/// - Android hands the file to MediaStore with a relative path so it lands in
///   `Downloads/Turbo/<kind>` and is visible to every app.
/// - Desktop platforms copy it into the OS Downloads directory the same way.
/// - Anything else falls back to the app's own storage so a file is never lost.
class FileStore {
  static const _channel = MethodChannel('turbo_downloader/files');

  /// The single top-level folder all downloads live under.
  static const turboFolder = 'Turbo';

  /// The subfolder (relative to the Downloads root) a file of this name goes
  /// into, e.g. `Turbo/Videos`.
  static String subfolderFor(String filename) =>
      '$turboFolder/${folderNameFor(kindOf(filename))}';

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

  /// Hands a saved file to another app.
  ///
  /// On Android this opens the system share sheet (WhatsApp, Bluetooth, Drive,
  /// …). Desktop platforms have no share sheet, so they reveal the file in the
  /// file manager instead, which is where a share would start from anyway.
  /// Returns true when a hand-off was triggered.
  static Future<bool> share(String path, {String? filename}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _channel.invokeMethod<bool>('shareFile', {
          'path': path,
          'filename': filename ?? path.split(Platform.pathSeparator).last,
        });
        return ok ?? false;
      }
      await reveal(path);
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the file's containing folder with the file selected where the
  /// platform supports it.
  static Future<void> reveal(String path) async {
    try {
      final dir = File(path).parent.path;
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await Process.start('explorer.exe', ['/select,', path],
            mode: ProcessStartMode.detached);
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await Process.start('open', ['-R', path],
            mode: ProcessStartMode.detached);
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        await Process.start('xdg-open', [dir],
            mode: ProcessStartMode.detached);
        return;
      }
    } catch (_) {
      // No file manager available; nothing else to do.
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
        'subfolder': subfolderFor(filename),
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
    final downloads = await _downloadsDir();
    if (downloads == null) return _appPrivate(tempFile, filename);
    // File into Downloads/Turbo/<kind>, creating the folders as needed.
    final dir = Directory(
      '${downloads.path}${Platform.pathSeparator}'
      '${subfolderFor(filename).replaceAll('/', Platform.pathSeparator)}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = _unique(File('${dir.path}${Platform.pathSeparator}$filename'));
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

/// The subfolder name a [FileKind] is filed under.
String folderNameFor(FileKind kind) => switch (kind) {
      FileKind.video => 'Videos',
      FileKind.audio => 'Music',
      FileKind.image => 'Pictures',
      FileKind.archive => 'Archives',
      FileKind.document => 'Documents',
      FileKind.app => 'Apps',
      FileKind.other => 'Other',
    };
