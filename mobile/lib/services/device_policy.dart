import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A snapshot of the conditions that can gate downloads.
class DeviceState {
  /// True when the active connection looks like Wi-Fi (or a wired desktop link).
  final bool onWifi;

  /// True when the device is plugged in or has ample charge.
  final bool charging;

  /// Battery percentage, or -1 when unknown (desktop).
  final int batteryLevel;

  const DeviceState({
    this.onWifi = true,
    this.charging = true,
    this.batteryLevel = -1,
  });

  static const unknown = DeviceState();
}

/// Reads connectivity and power state, and decides whether a download may run
/// under the user's Wi-Fi-only / battery-aware preferences.
///
/// On Android the figures come from the `turbo_downloader/device` channel in
/// `PlatformChannels.kt`. On desktop there is no metered connection and usually no
/// battery, so Wi-Fi is assumed and downloads are never gated.
class DevicePolicy {
  DevicePolicy({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('turbo_downloader/device');

  final MethodChannel _channel;

  Future<DeviceState> read() async {
    if (kIsWeb) return DeviceState.unknown;
    if (!Platform.isAndroid) {
      return DeviceState(
        onWifi: await _looksWired(),
        charging: true,
        batteryLevel: -1,
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('state');
      if (result == null) return DeviceState.unknown;
      return DeviceState(
        onWifi: result['wifi'] as bool? ?? true,
        charging: result['charging'] as bool? ?? true,
        batteryLevel: (result['battery'] as num?)?.toInt() ?? -1,
      );
    } on MissingPluginException {
      return DeviceState.unknown;
    } catch (_) {
      return DeviceState.unknown;
    }
  }

  /// True when downloads should be held back.
  bool blocksDownloads(
    DeviceState state, {
    required bool wifiOnly,
    required bool batteryAware,
  }) {
    if (wifiOnly && !state.onWifi) return true;
    // Battery-aware only blocks on a low, unplugged battery.
    if (batteryAware &&
        !state.charging &&
        state.batteryLevel >= 0 &&
        state.batteryLevel < 20) {
      return true;
    }
    return false;
  }

  Future<bool> _looksWired() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      // Any live non-loopback interface is treated as an unmetered link.
      return interfaces.isNotEmpty;
    } catch (_) {
      return true;
    }
  }
}
