import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a server-side artifact to the phone and opens it.
///
/// Streams to a temp file first, then moves it into the public Downloads
/// collection via MediaStore. Writing straight into Downloads is not portable
/// across API levels, whereas MediaStore handles scoped storage for us and
/// makes the file visible to other apps.
class FileDownloader {
  static const _channel = MethodChannel('turbo_downloader/files');

  /// Returns the saved file, or throws with a human-readable reason.
  static Future<File> saveAndOpen({
    required String url,
    required String filename,
    void Function(int received, int? total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeName = _sanitize(filename);
    final tempFile = File('${tempDir.path}/$safeName');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final sink = tempFile.openWrite();
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
    } finally {
      client.close();
    }

    final saved = await _publish(tempFile, safeName);
    await OpenFilex.open(saved.path);
    return saved;
  }

  /// Hands the finished file to MediaStore so it appears in the Downloads app.
  /// Public so the on-device engine can use the same path as the server fetch.
  static Future<File> publish(File tempFile, String filename) =>
      _publish(tempFile, filename);

  /// Hands the finished file to MediaStore so it appears in the Downloads app.
  static Future<File> _publish(File tempFile, String filename) async {
    try {
      // On Android 9 and below the shared Downloads folder needs the legacy
      // storage permission, which is granted at runtime. Ask first; if the
      // user declines, keep the file app-private rather than losing it.
      final allowed =
          await _channel.invokeMethod<bool>('ensureStorage') ?? true;
      if (!allowed) {
        return _appPrivate(tempFile, filename);
      }
    } on MissingPluginException {
      // Not an Android host (desktop/tests): use the app-private location.
      return _appPrivate(tempFile, filename);
    } catch (_) {
      // Any other bridge error falls through to the publish attempt below.
    }

    try {
      final path = await _channel.invokeMethod<String>('publishDownload', {
        'path': tempFile.path,
        'filename': filename,
      });
      if (path != null && path.isNotEmpty) {
        // MediaStore took ownership; the temp copy is no longer needed.
        try {
          await tempFile.delete();
        } catch (_) {}
        return File(path);
      }
    } on MissingPluginException {
      // Fall through to the app-private location below.
    } catch (_) {
      // Fall through as well — a failed publish should not lose the file.
    }

    return _appPrivate(tempFile, filename);
  }

  /// Last-resort location when the shared Downloads folder is unavailable.
  static Future<File> _appPrivate(File tempFile, String filename) async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/$filename');
    if (await dest.exists()) {
      await dest.delete();
    }
    return tempFile.rename(dest.path);
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'turbo-download' : cleaned;
  }
}
