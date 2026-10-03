import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_downloader.dart';

/// Application state for the on-device download manager.
///
/// Everything runs on the device: the phone or computer opens the connections,
/// writes the bytes to its own storage, and needs no server, account, or key.
class TurboState extends ChangeNotifier {
  static const _kAccent = 'turbo.accent';
  static const _kConnections = 'turbo.connections';
  static const _kPlaySound = 'turbo.playSound';

  String accentKey = 'cyan';

  /// Default segment count applied to new downloads.
  int defaultConnections = 4;

  /// Play the system completion sound when a download finishes.
  bool playSound = true;

  bool loading = true;

  final local = LocalDownloadManager();

  bool _disposed = false;

  TurboState() {
    local.addListener(_safeNotify);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    accentKey = prefs.getString(_kAccent) ?? 'cyan';
    defaultConnections = prefs.getInt(_kConnections) ?? 4;
    playSound = prefs.getBool(_kPlaySound) ?? true;
    await local.init();
    loading = false;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
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

  Future<void> setPlaySound(bool value) async {
    playSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlaySound, value);
    _safeNotify();
  }

  /// Queues a download that runs and is stored on this device. Media pages are
  /// resolved on-device by the extractor, so they are queued with
  /// `kind: 'media'`; everything else is fetched as a direct file.
  void addToDevice(
    String url, {
    String? filename,
    int connections = 4,
    String kind = 'http',
  }) {
    local.add(url, filename: filename, connections: connections, kind: kind);
  }

  @override
  void dispose() {
    _disposed = true;
    local.removeListener(_safeNotify);
    local.dispose();
    super.dispose();
  }
}
