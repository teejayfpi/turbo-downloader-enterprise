import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How a finished transfer should announce itself.
enum NotificationStyle {
  /// Only when the whole queue goes idle.
  onQueueComplete,

  /// For every finished download.
  everyDownload,

  /// Silent.
  off,
}

/// Bridges to the platform's notification centre through the
/// `turbo_downloader/notify` channel implemented in `PlatformChannels.kt`.
///
/// On desktop the channel is absent, so calls are no-ops; the app surfaces
/// completion with its in-app banner instead.
class Notifications {
  const Notifications({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('turbo_downloader/notify');

  final MethodChannel _channel;

  /// Ensures the Android notification channel exists. Safe to call repeatedly.
  Future<void> ensureChannel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('ensureChannel');
    } on MissingPluginException {
      // Desktop: no notification centre to prepare.
    } catch (_) {}
  }

  /// Shows a completion notification. [title] and [body] are plain text.
  Future<void> show({
    required String title,
    required String body,
    bool ongoing = false,
    int? progressPercent,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('notify', {
        'title': title,
        'body': body,
        'ongoing': ongoing,
        'progress': progressPercent,
      });
    } on MissingPluginException {
      // Desktop: nothing to do.
    } catch (_) {}
  }

  /// Updates or clears the persistent "N downloads running" notification.
  Future<void> setProgress({
    required int active,
    required int percent,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('progress', {
        'active': active,
        'percent': percent,
      });
    } on MissingPluginException {
      // Desktop: nothing to do.
    } catch (_) {}
  }
}
