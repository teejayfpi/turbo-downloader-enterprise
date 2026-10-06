import 'dart:async';

import 'package:cryptography/cryptography.dart';

import 'licence.dart';
import 'secure_store.dart';

/// A snapshot of the user's access at a point in time.
class AccessStatus {
  final AccessTier tier;

  /// Null only for the free tier (which never expires).
  final DateTime? expiresAt;
  final DateTime? issuedAt;
  final String? holder;

  /// True when a signed Pro licence is currently within its window.
  final bool licensed;

  /// True when the built-in trial is still running.
  final bool trialActive;

  const AccessStatus({
    required this.tier,
    required this.licensed,
    required this.trialActive,
    this.expiresAt,
    this.issuedAt,
    this.holder,
  });

  bool get isPro => licensed;
  bool get isTrial => !licensed && trialActive;
  bool get isFree => !licensed && !trialActive;
  bool get hasAccess => licensed || trialActive;

  /// Access ends at this time, or null when it never does.
  DateTime? get endAt => expiresAt;

  Duration? remainingAt(DateTime now) => endAt?.difference(now);

  /// 0..1 of the access window already used, for a progress bar.
  double usedFractionAt(DateTime now) {
    final end = endAt, start = issuedAt;
    if (end == null || start == null) return 0;
    final span = end.difference(start).inMilliseconds;
    if (span <= 0) return 1;
    final used = now.difference(start).inMilliseconds;
    return (used / span).clamp(0.0, 1.0);
  }
}

/// Tracks how long the app is usable and enforces the time limit.
///
/// Access comes from two places, both measured on-device:
///
///  * the **trial**, a fixed window that starts the first time the app runs;
///  * a **signed licence key**, which may carry its own expiry.
///
/// To stop the clock being rolled back to extend access, the manager remembers
/// the latest wall-clock time it has ever seen. "Now" is the later of the system
/// clock and that high-water mark, so winding the clock back cannot buy extra
/// time. The same value is what a countdown is measured against.
class AccessManager {
  AccessManager({
    SecureStore? store,
    SimplePublicKey? publicKey,
    this.trialLength = const Duration(days: 7),
    DateTime Function()? clock,
  })  : _store = store ?? SecureStore(),
        _publicKey = publicKey ?? _bundledKey(),
        _clock = clock ?? _utcNow;

  final SecureStore _store;

  /// Null when the build was not given a licence public key.
  final SimplePublicKey? _publicKey;
  final DateTime Function() _clock;

  /// How long a fresh install can use the app before it locks.
  final Duration trialLength;

  /// The public half of the licence-signing keypair, from
  /// `--dart-define=TURBO_LICENCE_PUBLIC_KEY=...`. Null when unset.
  static const defaultLicencePublicKey =
      String.fromEnvironment('TURBO_LICENCE_PUBLIC_KEY', defaultValue: '');

  static SimplePublicKey? _bundledKey() {
    if (defaultLicencePublicKey.isEmpty) return null;
    try {
      return LicenceCodec.publicKeyFromBase64(defaultLicencePublicKey);
    } catch (_) {
      return null;
    }
  }

  /// The default clock. UTC so the high-water mark read back from storage (which
  /// is epoch milliseconds) compares cleanly with the live clock.
  static DateTime _utcNow() => DateTime.now().toUtc();

  /// True when this build can accept licence keys.
  bool get isLicensingEnabled => _publicKey != null;

  static const _kToken = 'licence.token';
  static const _kFirstSeen = 'access.firstSeen';
  static const _kMaxSeen = 'access.maxSeen';

  DateTime? _firstSeen;
  DateTime? _maxSeen;
  Licence? _licence;
  bool _ready = false;

  /// Last time the high-water mark was persisted, so a long-running app does
  /// not rewrite the secure store on every tick.
  DateTime? _lastTouchWrite;

  bool get isReady => _ready;

  /// Loads the stored licence and trial clock. Never throws.
  Future<void> init() async {
    try {
      _firstSeen = await _readDate(_kFirstSeen);
      _maxSeen = await _readDate(_kMaxSeen);
      _lastTouchWrite = _maxSeen;
      final token = await _store.read(_kToken);
      final key = _publicKey;
      if (token != null && token.isNotEmpty && key != null) {
        _licence = await LicenceCodec.verify(token, publicKey: key);
      }
    } catch (_) {
      // A corrupt store must not brick the app; fall back to a fresh trial.
    }
    _ready = true;
  }

  /// The effective current time: never earlier than the last time we saw, so a
  /// backward clock change cannot extend a trial or a licence.
  DateTime effectiveNow() {
    final system = _clock();
    final seen = _maxSeen;
    if (seen != null && seen.isAfter(system)) return seen;
    return system;
  }

  /// Starts the trial clock on first run and advances the high-water mark.
  /// Returns true when the trial was started by this call.
  Future<bool> ensureStarted() async {
    final now = _clock();
    var started = false;
    if (_firstSeen == null) {
      _firstSeen = now;
      await _writeDate(_kFirstSeen, now);
      started = true;
    }
    await _touch(now, force: true);
    return started;
  }

  Future<void> _touch(DateTime now, {bool force = false}) async {
    if (_maxSeen == null || now.isAfter(_maxSeen!)) {
      _maxSeen = now;
      final last = _lastTouchWrite;
      if (force || last == null || now.difference(last).inSeconds >= 30) {
        _lastTouchWrite = now;
        await _writeDate(_kMaxSeen, now);
      }
    }
  }

  /// Records that the app is being used right now. Persists at most every 30s.
  Future<void> markSeen() async {
    await _touch(_clock());
  }

  /// Verifies and stores [token]. Returns null on success, or a short reason the
  /// key was rejected.
  Future<String?> activate(String token) async {
    if (token.trim().isEmpty) return 'Enter a licence key.';
    final key = _publicKey;
    if (key == null) {
      return 'This build does not accept licence keys.';
    }
    final licence = await LicenceCodec.verify(token.trim(), publicKey: key);
    if (licence == null) return 'That key is not valid.';
    final now = effectiveNow();
    if (!licence.isActiveAt(now)) {
      return 'That key has expired.';
    }
    _licence = licence;
    await _store.write(_kToken, token.trim());
    await markSeen();
    return null;
  }

  /// Removes any stored licence, returning to trial/free access.
  Future<void> deactivate() async {
    _licence = null;
    await _store.delete(_kToken);
  }

  /// The stored licence's holder, if any.
  String? get holder => _licence?.holder;

  /// The stored licence's expiry, if any.
  DateTime? get licenceExpiry => _licence?.expiresAt;

  AccessStatus status() {
    final now = effectiveNow();
    final licensed = _licence?.isActiveAt(now) ?? false;
    if (licensed) {
      final licence = _licence!;
      return AccessStatus(
        tier: AccessTier.pro,
        licensed: true,
        trialActive: false,
        expiresAt: licence.expiresAt,
        issuedAt: licence.issuedAt,
        holder: licence.holder,
      );
    }

    final start = _firstSeen;
    if (start == null) {
      // Clock has not started yet; treat the app as freshly in-trial.
      return AccessStatus(
        tier: AccessTier.trial,
        licensed: false,
        trialActive: true,
        issuedAt: _clock(),
        expiresAt: _clock().add(trialLength),
      );
    }
    final end = start.add(trialLength);
    final active = end.isAfter(now);
    return AccessStatus(
      tier: active ? AccessTier.trial : AccessTier.free,
      licensed: false,
      trialActive: active,
      issuedAt: start,
      expiresAt: end,
    );
  }

  Future<DateTime?> _readDate(String key) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    final millis = int.tryParse(raw);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  Future<void> _writeDate(String key, DateTime value) =>
      _store.write(key, value.millisecondsSinceEpoch.toString());
}
