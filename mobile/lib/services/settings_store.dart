import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// Persists user preferences.
///
/// Non-sensitive settings use `SharedPreferences`; anything secret (API tokens,
/// cookies, credentials) is routed to [SecureStore] so it is never written in
/// plain text. This split is the rule going forward: add new keys to the right
/// side of it.
class SettingsStore {
  SettingsStore({SecureStore? secure}) : secure = secure ?? SecureStore();

  final SecureStore secure;

  static const kThemeMode = 'turbo.themeMode';
  static const kLocale = 'turbo.locale';
  static const kOnboardingDone = 'turbo.onboardingDone';
  static const kMaxConcurrent = 'turbo.maxConcurrent';
  static const kWifiOnly = 'turbo.wifiOnly';
  static const kBatteryAware = 'turbo.batteryAware';
  static const kNotifyComplete = 'turbo.notifyComplete';
  static const kNotifyProgress = 'turbo.notifyProgress';
  static const kHighContrast = 'turbo.highContrast';
  static const kReducedMotion = 'turbo.reducedMotion';
  static const kTextScale = 'turbo.textScale';
  static const kAutoRetry = 'turbo.autoRetry';
  static const kAdaptiveConnections = 'turbo.adaptiveConnections';
  static const kRememberHostSpeed = 'turbo.rememberHostSpeed';
  static const kScheduleEnabled = 'turbo.scheduleEnabled';
  static const kScheduleStart = 'turbo.scheduleStart';
  static const kScheduleEnd = 'turbo.scheduleEnd';
  static const kSpeedLimitBps = 'turbo.speedLimitBps';
  static const kUpdateChannel = 'turbo.updateChannel';
  static const kCheckUpdates = 'turbo.checkUpdates';
  static const kClipboardMonitor = 'turbo.clipboardMonitor';

  /// A secret's storage key, namespaced so the secure index stays readable.
  static String secretKey(String name) => 'turbo.secret.$name';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<T?> _read<T>(String key) async => (await _prefs).get(key) as T?;

  Future<void> setString(String key, String value) async =>
      (await _prefs).setString(key, value);

  Future<void> setBool(String key, bool value) async =>
      (await _prefs).setBool(key, value);

  Future<void> setInt(String key, int value) async =>
      (await _prefs).setInt(key, value);

  Future<void> setDouble(String key, double value) async =>
      (await _prefs).setDouble(key, value);

  Future<String?> getString(String key) => _read<String>(key);

  Future<bool?> getBool(String key) => _read<bool>(key);

  Future<int?> getInt(String key) => _read<int>(key);

  Future<double?> getDouble(String key) => _read<double>(key);

  Future<void> remove(String key) async => (await _prefs).remove(key);
}
