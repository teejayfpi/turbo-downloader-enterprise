import 'dart:convert';
import 'dart:io';

import '../media_url.dart';

/// One finished or failed transfer, kept for the history screen.
///
/// History is intentionally separate from the live queue: clearing the queue
/// must not erase the record, and history survives restarts.
class HistoryEntry {
  final String id;
  final String url;
  final String filename;
  final String status; // completed | failed
  final String? filePath;

  /// Destination folder as the user sees it, e.g. `Downloads/Turbo/Videos`.
  final String? destination;

  final int size;
  final int? durationMs;
  final int? averageSpeed;
  final String? errorKind;
  final String? errorMessage;
  final DateTime finishedAt;

  const HistoryEntry({
    required this.id,
    required this.url,
    required this.filename,
    required this.status,
    required this.finishedAt,
    this.filePath,
    this.destination,
    this.size = 0,
    this.durationMs,
    this.averageSpeed,
    this.errorKind,
    this.errorMessage,
  });

  FileKind get kind => kindOf(filename);
  bool get isCompleted => status == 'completed';

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'status': status,
        'filePath': filePath,
        'destination': destination,
        'size': size,
        'durationMs': durationMs,
        'averageSpeed': averageSpeed,
        'errorKind': errorKind,
        'errorMessage': errorMessage,
        'finishedAt': finishedAt.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'].toString(),
        url: json['url']?.toString() ?? '',
        filename: json['filename']?.toString() ?? 'download',
        status: json['status']?.toString() ?? 'completed',
        filePath: json['filePath']?.toString(),
        destination: json['destination']?.toString(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        averageSpeed: (json['averageSpeed'] as num?)?.toInt(),
        errorKind: json['errorKind']?.toString(),
        errorMessage: json['errorMessage']?.toString(),
        finishedAt:
            DateTime.tryParse(json['finishedAt']?.toString() ?? '') ??
                DateTime.now(),
      );

  /// CSV header matching [toCsvRow].
  static const csvHeader =
      'finished_at,status,filename,kind,size_bytes,duration_ms,'
      'average_speed_bps,destination,url';

  /// A single CSV row. Fields are quoted and internal quotes doubled.
  String toCsvRow() {
    String q(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';
    return [
      q(finishedAt.toIso8601String()),
      q(status),
      q(filename),
      q(kind.name),
      q(size),
      q(durationMs ?? ''),
      q(averageSpeed ?? ''),
      q(destination ?? ''),
      q(url),
    ].join(',');
  }
}

/// Filters applied to the history list.
class HistoryFilter {
  final String query;
  final FileKind? kind;
  final DateTime? from;
  final DateTime? to;

  const HistoryFilter({this.query = '', this.kind, this.from, this.to});

  bool get isEmpty =>
      query.trim().isEmpty && kind == null && from == null && to == null;

  bool matches(HistoryEntry e) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final haystack =
          '${e.filename} ${e.url} ${e.destination ?? ''}'.toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    if (kind != null && e.kind != kind) return false;
    if (from != null && e.finishedAt.isBefore(from!)) return false;
    if (to != null) {
      final endOfDay = DateTime(to!.year, to!.month, to!.day)
          .add(const Duration(days: 1));
      if (!e.finishedAt.isBefore(endOfDay)) return false;
    }
    return true;
  }
}

/// Persistent download history with search, filtering, and export.
class HistoryStore {
  HistoryStore({Directory? rootOverride, int maxEntries = 2000})
      : _rootOverride = rootOverride,
        _maxEntries = maxEntries;

  final Directory? _rootOverride;
  final int _maxEntries;
  final List<HistoryEntry> _entries = [];
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<Directory> _root() async {
    final dir = _rootOverride ??
        Directory(
            '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.turbo');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async => File('${(await _root()).path}/history.json');

  Future<void> init() async {
    if (_loaded) return;
    final file = await _file();
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        for (final e in (raw as List).whereType<Map>()) {
          _entries.add(HistoryEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (_) {
        // A corrupt history file must not stop the app from starting.
      }
    }
    _loaded = true;
  }

  Future<void> add(HistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  /// Entries matching [filter], newest first.
  List<HistoryEntry> query(HistoryFilter filter) =>
      _entries.where(filter.matches).toList();

  /// Total bytes of completed entries.
  int get totalBytes => _entries
      .where((e) => e.isCompleted)
      .fold(0, (sum, e) => sum + e.size);

  String toCsv(List<HistoryEntry> rows) => [
        HistoryEntry.csvHeader,
        ...rows.map((e) => e.toCsvRow()),
      ].join('\n');

  String toJson(List<HistoryEntry> rows) =>
      const JsonEncoder.withIndent('  ')
          .convert(rows.map((e) => e.toJson()).toList());

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
