/// Mirrors `DownloadEngine.serialize()` on the server. Unknown fields are
/// ignored so the app keeps working when the server adds new ones.
class DownloadTask {
  final String id;
  final String url;
  final String filename;
  final String? filepath;
  final int total;
  final int downloaded;
  final int speed;
  final double progress;
  final String status;
  final String? error;
  final String platform;
  final String kind;
  final String? format;
  final int connections;
  final int priority;
  final bool resumeSupported;
  final int segments;
  final String? checksum;
  final String? checksumAlgo;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final int? eta;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.filename,
    this.filepath,
    required this.total,
    required this.downloaded,
    required this.speed,
    required this.progress,
    required this.status,
    this.error,
    required this.platform,
    required this.kind,
    this.format,
    required this.connections,
    required this.priority,
    required this.resumeSupported,
    required this.segments,
    this.checksum,
    this.checksumAlgo,
    this.scheduledAt,
    this.startedAt,
    this.completedAt,
    this.createdAt,
    this.eta,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    return DownloadTask(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      filename: json['filename']?.toString() ?? 'download',
      filepath: json['filepath']?.toString(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      downloaded: (json['downloaded'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'queued',
      error: json['error']?.toString(),
      platform: json['platform']?.toString() ?? 'generic',
      kind: json['kind']?.toString() ?? 'file',
      format: json['format']?.toString(),
      connections: (json['connections'] as num?)?.toInt() ?? 1,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      resumeSupported: json['resumeSupported'] == true,
      segments: (json['segments'] as num?)?.toInt() ?? 1,
      checksum: json['checksum']?.toString(),
      checksumAlgo: json['checksumAlgo']?.toString(),
      scheduledAt: parseDate(json['scheduledAt']),
      startedAt: parseDate(json['startedAt']),
      completedAt: parseDate(json['completedAt']),
      createdAt: parseDate(json['createdAt']),
      eta: (json['eta'] as num?)?.toInt(),
    );
  }

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPaused => status == 'paused';
  bool get isQueued => status == 'queued' || status == 'scheduled';
  bool get canRetrieve => isCompleted && (filepath?.isNotEmpty ?? false);
}

class TurboStats {
  final int totalDownloaded;
  final int totalSpeed;
  final int peakSpeed;
  final int activeCount;
  final int completedCount;
  final int failedCount;
  final int queuedCount;
  final int totalCount;

  const TurboStats({
    this.totalDownloaded = 0,
    this.totalSpeed = 0,
    this.peakSpeed = 0,
    this.activeCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.queuedCount = 0,
    this.totalCount = 0,
  });

  factory TurboStats.fromJson(Map<String, dynamic> json) => TurboStats(
        totalDownloaded: (json['totalDownloaded'] as num?)?.toInt() ?? 0,
        totalSpeed: (json['totalSpeed'] as num?)?.toInt() ?? 0,
        peakSpeed: (json['peakSpeed'] as num?)?.toInt() ?? 0,
        activeCount: (json['activeCount'] as num?)?.toInt() ?? 0,
        completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
        queuedCount: (json['queuedCount'] as num?)?.toInt() ?? 0,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      );
}

class MediaInfo {
  final String title;
  final String? uploader;
  final int? duration;
  final String? thumbnail;
  final List<MediaFormat> formats;

  const MediaInfo({
    required this.title,
    this.uploader,
    this.duration,
    this.thumbnail,
    this.formats = const [],
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) => MediaInfo(
        title: json['title']?.toString() ?? 'Untitled',
        uploader: json['uploader']?.toString(),
        duration: (json['duration'] as num?)?.toInt(),
        thumbnail: json['thumbnail']?.toString(),
        formats: ((json['formats'] as List?) ?? const [])
            .whereType<Map>()
            .map((f) => MediaFormat.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
      );
}

class MediaFormat {
  final String formatId;
  final String ext;
  final String type;
  final String label;
  final int width;
  final int height;
  final int fps;
  final int filesize;
  final String vcodec;
  final String acodec;

  const MediaFormat({
    required this.formatId,
    required this.ext,
    required this.type,
    required this.label,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.filesize = 0,
    this.vcodec = 'none',
    this.acodec = 'none',
  });

  factory MediaFormat.fromJson(Map<String, dynamic> json) => MediaFormat(
        formatId: json['formatId']?.toString() ?? '',
        ext: json['ext']?.toString() ?? 'mp4',
        type: json['type']?.toString() ?? 'video',
        label: json['label']?.toString() ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        fps: (json['fps'] as num?)?.toInt() ?? 0,
        filesize: (json['filesize'] as num?)?.toInt() ?? 0,
        vcodec: json['vcodec']?.toString() ?? 'none',
        acodec: json['acodec']?.toString() ?? 'none',
      );

  bool get isVideo => type == 'video';

  /// A single progressive stream (video + audio) is the only kind that plays
  /// standalone. The server withholds separate HD streams from datacenter IPs,
  /// so a "video only" entry cannot be requested on its own.
  bool get isProgressive => isVideo && acodec != 'none';

  String get display => label.isNotEmpty ? label : formatId;
}
