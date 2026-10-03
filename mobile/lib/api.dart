import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Thin REST client for the Turbo server. The Android app is a remote control:
/// all fetching, segmenting, and merging happens server-side, so the phone
/// never has to run yt-dlp or ffmpeg.
class TurboApi {
  String baseUrl;

  /// Shared secret for servers started with TURBO_API_TOKEN. Empty when the
  /// server is open, in which case no auth header is sent.
  String apiToken;

  TurboApi(this.baseUrl, {this.apiToken = ''});

  Map<String, String> _headers({bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
      };

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path')
      .replace(queryParameters: query == null || query.isEmpty ? null : query);

  Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final uri = _uri(path, query);
    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http
              .get(uri, headers: _headers())
              .timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          res = await http
              .post(uri,
                  headers: _headers(json: true),
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          res = await http
              .put(uri,
                  headers: _headers(json: true),
                  body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          res = await http
              .delete(uri, headers: _headers())
              .timeout(const Duration(seconds: 30));
          break;
        default:
          throw ApiException('Unsupported method $method');
      }
    } on SocketException {
      throw ApiException('Cannot reach the server. Check the address and your connection.');
    } on HttpException {
      throw ApiException('Network error while contacting the server.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Request failed: $e');
    }

    final text = res.body;
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }

    if (res.statusCode >= 400) {
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Request failed (${res.statusCode})';
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }

  Future<({List<DownloadTask> downloads, TurboStats stats})> getDownloads() async {
    final data = await _send('GET', '/api/downloads');
    final list = ((data['downloads'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final stats = TurboStats.fromJson(
        Map<String, dynamic>.from((data['stats'] as Map?) ?? const {}));
    return (downloads: list, stats: stats);
  }

  Future<DownloadTask> getDownload(String id) async {
    final data = await _send('GET', '/api/downloads/$id');
    return DownloadTask.fromJson(Map<String, dynamic>.from(data['download']));
  }

  Future<List<DownloadTask>> addDownload({
    required String url,
    String? formatId,
    int? connections,
    String? filename,
    String? scheduledAt,
  }) async {
    final data = await _send('POST', '/api/downloads', body: {
      'url': url,
      if (formatId != null && formatId.isNotEmpty) 'formatId': formatId,
      if (connections != null) 'connections': connections,
      if (filename != null && filename.isNotEmpty) 'filename': filename,
      if (scheduledAt != null) 'scheduledAt': scheduledAt,
    });
    return ((data['downloads'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> pause(String id) => _send('POST', '/api/downloads/$id/pause');
  Future<void> resume(String id) => _send('POST', '/api/downloads/$id/resume');
  Future<void> retry(String id) => _send('POST', '/api/downloads/$id/retry');
  Future<void> start(String id) => _send('POST', '/api/downloads/$id/start');
  Future<void> pauseAll() => _send('POST', '/api/downloads/pause-all');
  Future<void> resumeAll() => _send('POST', '/api/downloads/resume-all');
  Future<void> clearCompleted() => _send('POST', '/api/downloads/clear-completed');

  Future<void> remove(String id, {bool deleteFile = false}) =>
      _send('DELETE', '/api/downloads/$id', query: {'deleteFile': '$deleteFile'});

  Future<MediaInfo> getMediaInfo(String url) async {
    final data = await _send('GET', '/api/media/info', query: {'url': url});
    return MediaInfo.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> getSystem() async =>
      Map<String, dynamic>.from(await _send('GET', '/api/system'));

  Future<Map<String, dynamic>> getSettings() async =>
      Map<String, dynamic>.from(await _send('GET', '/api/settings'));

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> patch) async =>
      Map<String, dynamic>.from(await _send('PUT', '/api/settings', body: patch));

  /// Direct URL for streaming a completed file back to the device. The token
  /// rides in the query because the system downloader cannot set headers.
  String fileUrl(String id) {
    final base = '$baseUrl/api/downloads/$id/file';
    if (apiToken.isEmpty) return base;
    return '$base?token=${Uri.encodeQueryComponent(apiToken)}';
  }

  /// Confirms the address points at a Turbo server before we commit to it.
  Future<bool> ping() async {
    try {
      final data = await _send('GET', '/health');
      return data is Map && data['status'] != null;
    } catch (_) {
      return false;
    }
  }
}
