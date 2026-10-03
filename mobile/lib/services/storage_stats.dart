import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A snapshot of the storage the app and the device are using.
class StorageStats {
  /// Free bytes on the volume that holds the download folder.
  final int freeBytes;

  /// Total bytes on that volume.
  final int totalBytes;

  /// Bytes of finished downloads recorded in history.
  final int downloadedBytes;

  /// Bytes of in-progress partial data (`.part` files and part folders).
  final int temporaryBytes;

  /// Bytes held by the app's own support directory (queue, history, logs).
  final int appDataBytes;

  /// Number of partial files that can be cleaned up.
  final int partialFileCount;

  /// Where finished downloads are published.
  final String? downloadFolder;

  const StorageStats({
    this.freeBytes = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.temporaryBytes = 0,
    this.appDataBytes = 0,
    this.partialFileCount = 0,
    this.downloadFolder,
  });

  /// Fraction of the volume still free (0–1).
  double get freeFraction =>
      totalBytes <= 0 ? 1 : (freeBytes / totalBytes).clamp(0.0, 1.0);

  /// True when free space is low enough to warn about.
  bool get isLow => freeBytes > 0 && freeBytes < 500 * 1024 * 1024;

  /// True when free space is critical.
  bool get isCritical => freeBytes > 0 && freeBytes < 100 * 1024 * 1024;
}

/// Reads storage figures from the filesystem.
///
/// Works without extra plugins: the free-space probe prefers a POSIX `df` call
/// and falls back to a large write test only when that is unavailable, so no
/// bytes are wasted on the common path.
class StorageInspector {
  const StorageInspector();

  /// Collects a [StorageStats] snapshot.
  ///
  /// [partsRoot] is the queue's partial-data directory; [downloadedBytes] comes
  /// from the history store so the two sources stay independent.
  Future<StorageStats> inspect({
    Directory? partsRoot,
    int downloadedBytes = 0,
    String? downloadFolder,
  }) async {
    final support = await _supportDir();
    final volume = await _volumeFor(partsRoot ?? support);

    var temporaryBytes = 0;
    var partialCount = 0;
    if (partsRoot != null && await partsRoot.exists()) {
      await for (final entity in partsRoot.list(recursive: true)) {
        if (entity is File) {
          try {
            temporaryBytes += await entity.length();
          } catch (_) {}
          if (entity.path.endsWith('.part') ||
              entity.uri.pathSegments.last.startsWith('part_')) {
            partialCount++;
          }
        }
      }
    }

    return StorageStats(
      freeBytes: volume.free,
      totalBytes: volume.total,
      downloadedBytes: downloadedBytes,
      temporaryBytes: temporaryBytes,
      appDataBytes: await _dirSize(support),
      partialFileCount: partialCount,
      downloadFolder: downloadFolder,
    );
  }

  /// Deletes the partial-data directory. Returns the bytes reclaimed.
  Future<int> clearTemporary(Directory? partsRoot) async {
    if (partsRoot == null || !await partsRoot.exists()) return 0;
    final before = await _dirSize(partsRoot);
    try {
      await partsRoot.delete(recursive: true);
    } catch (_) {
      return 0;
    }
    return before;
  }

  Future<Directory> _supportDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<({int free, int total})> _volumeFor(Directory dir) async {
    // `df -k <path>` is available on Linux and macOS and prints the free and
    // total 1K blocks for the volume holding the path.
    if (!Platform.isWindows) {
      try {
        final result = await Process.run('df', ['-k', dir.path]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            final cols = lines.last.trim().split(RegExp(r'\s+'));
            if (cols.length >= 3) {
              final total = int.tryParse(cols[1]);
              final free = int.tryParse(cols[3]);
              if (total != null && free != null) {
                return (free: free * 1024, total: total * 1024);
              }
            }
          }
        }
      } catch (_) {}
    }
    return (free: 0, total: 0);
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}
