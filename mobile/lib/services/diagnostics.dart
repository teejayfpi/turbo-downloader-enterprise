import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../credits.dart';

/// One local diagnostic record. Deliberately free of URLs, filenames, and any
/// personal data: only error codes, categories, and platform facts.
class DiagnosticEvent {
  final DateTime at;
  final String level; // info | warning | error
  final String code;
  final String message;

  const DiagnosticEvent({
    required this.at,
    required this.level,
    required this.code,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'level': level,
        'code': code,
        'message': message,
      };
}

/// Privacy-conscious diagnostics: crash and error logs stay on the device and
/// are only ever exported when the user asks.
///
/// Nothing here uploads. A remote crash service is intentionally out of scope;
/// if one is ever added it must be opt-in.
class Diagnostics {
  Diagnostics({Directory? rootOverride}) : _rootOverride = rootOverride;

  final Directory? _rootOverride;
  final List<DiagnosticEvent> _events = [];
  bool _loaded = false;
  static const _maxEvents = 500;

  Future<Directory> _root() async {
    final dir = _rootOverride ??
        (await getApplicationSupportDirectory());
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _logFile() async => File('${(await _root()).path}/diagnostics.log');

  Future<void> init() async {
    if (_loaded) return;
    try {
      final file = await _logFile();
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            final map = jsonDecode(line) as Map<String, dynamic>;
            _events.add(DiagnosticEvent(
              at: DateTime.tryParse(map['at']?.toString() ?? '') ??
                  DateTime.now(),
              level: map['level']?.toString() ?? 'info',
              code: map['code']?.toString() ?? '',
              message: map['message']?.toString() ?? '',
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  Future<void> log(String level, String code, String message) async {
    // Scrub anything that looks like a URL so a stray message cannot leak a
    // link into the log.
    final safe = message.replaceAll(RegExp(r'https?://\S+'), '<url>');
    _events.insert(
      0,
      DiagnosticEvent(at: DateTime.now(), level: level, code: code, message: safe),
    );
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    await _persist();
  }

  Future<void> info(String code, String message) => log('info', code, message);
  Future<void> warn(String code, String message) => log('warning', code, message);
  Future<void> error(String code, String message) => log('error', code, message);

  Future<void> clear() async {
    _events.clear();
    await _persist();
  }

  /// Builds a copyable bundle describing the environment and recent errors.
  ///
  /// Contains the app version, platform, architecture, and recent error codes.
  /// It never contains URLs or filenames.
  String buildBundle({Map<String, String> extra = const {}}) {
    final buffer = StringBuffer()
      ..writeln('Turbo diagnostics')
      ..writeln('================')
      ..writeln('app_version: $appVersion')
      ..writeln('platform: ${_platformName()}')
      ..writeln('os_version: ${Platform.operatingSystemVersion}')
      ..writeln('dart: ${Platform.version}')
      ..writeln('locale: ${Platform.localeName}')
      ..writeln('architecture: ${_architecture()}');
    for (final entry in extra.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln();
    buffer.writeln('recent_events (${_events.length}):');
    for (final e in _events.take(100)) {
      buffer.writeln(
          '  ${e.at.toIso8601String()} [${e.level}] ${e.code}: ${e.message}');
    }
    return buffer.toString();
  }

  Future<void> _persist() async {
    try {
      final file = await _logFile();
      await file.writeAsString(
        _events.map((e) => jsonEncode(e.toJson())).join('\n'),
      );
    } catch (_) {}
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  static String _architecture() {
    // Best-effort; Dart does not expose the CPU architecture directly.
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return Platform.operatingSystem == 'windows' ? 'x86_64' : 'unknown';
  }
}
