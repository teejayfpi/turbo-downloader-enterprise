import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'local_downloader.dart';
import 'models.dart';

class TurboState extends ChangeNotifier {
  static const _kBaseUrl = 'turbo.baseUrl';
  static const _kAccent = 'turbo.accent';
  static const _kMode = 'turbo.mode';
  static const _kConnections = 'turbo.connections';
  static const _kToken = 'turbo.apiToken';

  String baseUrl = '';
  String accentKey = 'cyan';

  /// Shared secret for servers started with TURBO_API_TOKEN.
  String apiToken = '';

  /// Default segment count applied to new device downloads.
  int defaultConnections = 4;

  /// Where downloads happen: `device` stores them on the phone, `server`
  /// leaves them on the Turbo server for later retrieval.
  String mode = 'device';
  List<DownloadTask> downloads = const [];
  TurboStats stats = const TurboStats();
  bool connected = false;
  bool loading = true;
  String? lastError;

  /// Whether a server address has been chosen. Until it has, the app shows
  /// setup rather than a screen full of connection errors. Device mode does
  /// not require a server at all.
  bool get configured => baseUrl.isNotEmpty || mode == 'device';
  bool get serverConfigured => baseUrl.isNotEmpty;

  final local = LocalDownloadManager();

  late TurboApi api;
  io.Socket? _socket;
  bool _disposed = false;

  TurboState() {
    api = TurboApi(baseUrl, apiToken: apiToken);
    local.addListener(_safeNotify);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_kBaseUrl) ?? '';
    accentKey = prefs.getString(_kAccent) ?? 'cyan';
    mode = prefs.getString(_kMode) ?? 'device';
    defaultConnections = prefs.getInt(_kConnections) ?? 4;
    apiToken = prefs.getString(_kToken) ?? '';
    api = TurboApi(baseUrl, apiToken: apiToken);
    await local.init();
    if (serverConfigured) {
      _connect();
      await refresh();
    }
    loading = false;
    _safeNotify();
  }

  Future<void> setMode(String value) async {
    if (value == mode) return;
    mode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, value);
    if (value == 'server' && serverConfigured && _socket == null) {
      _connect();
      await refresh();
    }
    _safeNotify();
  }

  // ------------------------------------------------------------------ socket

  void _connect() {
    _socket?.dispose();
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': apiToken})
          .enableReconnection()
          .enableForceNew()
          .build(),
    );

    _socket!.onConnect((_) {
      connected = true;
      _safeNotify();
      refresh();
    });
    _socket!.onDisconnect((_) {
      connected = false;
      _safeNotify();
    });
    _socket!.onConnectError((_) {
      connected = false;
      _safeNotify();
    });
    // The server pushes the full list on every change, so there is no
    // per-task reconciliation to get wrong.
    _socket!.on('downloads:update', (payload) {
      if (payload is! Map) return;
      final list = ((payload['downloads'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      downloads = list;
      if (payload['stats'] is Map) {
        stats = TurboStats.fromJson(Map<String, dynamic>.from(payload['stats']));
      }
      _safeNotify();
    });
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------------ actions

  Future<void> refresh() async {
    if (!serverConfigured) {
      loading = false;
      _safeNotify();
      return;
    }
    try {
      final result = await api.getDownloads();
      downloads = result.downloads;
      stats = result.stats;
      lastError = null;
    } on ApiException catch (e) {
      lastError = e.message;
    } finally {
      loading = false;
      _safeNotify();
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = normalizeUrl(url);
    api = TurboApi(baseUrl, apiToken: apiToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    loading = true;
    _safeNotify();
    _connect();
    await refresh();
  }

  /// Stores the shared secret and reconnects so REST and socket calls pick it
  /// up immediately. Passing an empty string clears it.
  Future<void> setApiToken(String token) async {
    apiToken = token.trim();
    api = TurboApi(baseUrl, apiToken: apiToken);
    final prefs = await SharedPreferences.getInstance();
    if (apiToken.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, apiToken);
    }
    if (serverConfigured) {
      _connect();
      await refresh();
    }
    _safeNotify();
  }

  Future<void> setAccent(String key) async {
    accentKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, key);
    _safeNotify();
  }

  Future<void> setDefaultConnections(int value) async {
    defaultConnections = value.clamp(1, 16);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConnections, defaultConnections);
    _safeNotify();
  }

  Future<String?> add(String url, {String? formatId, int? connections}) async {
    try {
      await api.addDownload(
          url: url.trim(), formatId: formatId, connections: connections);
      await refresh();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Queues a download that runs and is stored on this device.
  void addToDevice(String url, {String? filename, int connections = 4}) {
    local.add(url, filename: filename, connections: connections);
  }

  Future<String?> run(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
      return null;
    } on ApiException catch (e) {
      lastError = e.message;
      _safeNotify();
      return e.message;
    }
  }

  /// Strips a trailing slash and adds a scheme when the user types a bare host,
  /// which is the common case when pasting an address from a browser.
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  @override
  void dispose() {
    _disposed = true;
    local.removeListener(_safeNotify);
    local.dispose();
    _socket?.dispose();
    super.dispose();
  }
}
