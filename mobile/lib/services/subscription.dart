import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'licence.dart';
import 'secure_store.dart';

export 'licence.dart' show BillingPlan, Licence, LicenceIssuer, Subscription;

/// The owner's ledger of issued subscriptions, held in the secure store.
///
/// It is the admin's own record: who has access, on what plan, and the key they
/// were given. It is never needed to *verify* a licence — the app checks the
/// signature alone — so a user can hold a valid key without the ledger.
class SubscriptionLedger {
  SubscriptionLedger({SecureStore? store})
      : _store = store ?? SecureStore();

  final SecureStore _store;

  static const _kLedger = 'licence.ledger';

  final List<Subscription> _items = [];
  bool _ready = false;

  bool get isReady => _ready;

  List<Subscription> get all => List.unmodifiable(_items);

  Future<void> init() async {
    try {
      final raw = await _store.read(_kLedger);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              final sub = Subscription.fromJson(entry.cast<String, Object?>());
              if (sub != null) _items.add(sub);
            }
          }
        }
      }
    } catch (_) {
      // A corrupt ledger must not break the app; start empty.
    }
    _items.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    _ready = true;
  }

  Future<void> _persist() =>
      _store.write(_kLedger, jsonEncode([for (final s in _items) s.toJson()]));

  Future<void> add(Subscription sub) async {
    _items.removeWhere((s) => s.id == sub.id);
    _items.insert(0, sub);
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((s) => s.id == id);
    await _persist();
  }

  Subscription? byId(String id) {
    for (final s in _items) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Finds the ledger entry that matches a licence's id, holder, or exact key.
  Subscription? lookup(Licence licence, String rawKey) {
    for (final s in _items) {
      if (licence.id != null && s.id == licence.id) return s;
      if (s.key == rawKey) return s;
    }
    return null;
  }

  /// Counts, by status, at [now].
  ({int total, int active, int expired, int perpetual}) stats(DateTime now) {
    var active = 0, expired = 0, perpetual = 0;
    for (final s in _items) {
      if (s.isPerpetual) {
        perpetual++;
        active++;
      } else if (s.isActiveAt(now)) {
        active++;
      } else {
        expired++;
      }
    }
    return (total: _items.length, active: active, expired: expired, perpetual: perpetual);
  }
}

/// Gates the admin tools behind an owner passphrase.
///
/// The passphrase is not a security boundary against a determined attacker who
/// owns the device — it stops a casual user from issuing themselves keys. Only a
/// salted SHA-256 digest is stored, and unlocking lasts for the session.
class AdminGate {
  AdminGate({SecureStore? store}) : _store = store ?? SecureStore();

  final SecureStore _store;

  static const _kHash = 'admin.passHash';
  static const _kSalt = 'admin.passSalt';
  static const _kSeed = 'admin.seed';

  bool _unlocked = false;
  bool _hasPassphrase = false;
  String? _seed;

  bool get isUnlocked => _unlocked;
  bool get hasPassphrase => _hasPassphrase;

  /// True when the owner's signing seed has been stored, so keys can be minted.
  bool get hasSeed => _seed != null && _seed!.isNotEmpty;

  /// The owner's private seed, only meaningful once [isUnlocked].
  String? get seed => _unlocked ? _seed : null;

  Future<void> init() async {
    _hasPassphrase = (await _store.read(_kHash))?.isNotEmpty ?? false;
    _seed = await _store.read(_kSeed);
  }

  /// Sets (or replaces) the owner passphrase and unlocks the session.
  Future<void> setPassphrase(String passphrase) async {
    final salt = SecureStore.generate(length: 16, symbols: false);
    await _store.write(_kSalt, salt);
    await _store.write(_kHash, _digest(salt, passphrase));
    _hasPassphrase = true;
    _unlocked = true;
  }

  /// Returns true and unlocks when [passphrase] matches.
  Future<bool> unlock(String passphrase) async {
    final salt = await _store.read(_kSalt);
    final hash = await _store.read(_kHash);
    if (salt == null || hash == null) return false;
    if (_digest(salt, passphrase) != hash) return false;
    _unlocked = true;
    return true;
  }

  /// Stores the owner's signing seed. Kept in the secure store, never logged.
  Future<void> setSeed(String base64Seed) async {
    final trimmed = base64Seed.trim();
    await _store.write(_kSeed, trimmed);
    _seed = trimmed;
  }

  /// Clears the passphrase and signing seed, for a forgotten passphrase. The
  /// subscription ledger is left intact so issued keys can still be reviewed.
  Future<void> reset() async {
    await _store.delete(_kHash);
    await _store.delete(_kSalt);
    await _store.delete(_kSeed);
    _hasPassphrase = false;
    _unlocked = false;
    _seed = null;
  }

  void lock() => _unlocked = false;

  static String _digest(String salt, String passphrase) =>
      sha256.convert(utf8.encode('$salt:$passphrase')).toString();
}
