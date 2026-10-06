import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// What a licence grants.
///
/// `free` is the always-available tier; `trial` and `pro` carry a time window.
enum AccessTier {
  free,
  trial,
  pro;

  static AccessTier fromName(String? name) => switch (name) {
        'pro' => AccessTier.pro,
        'trial' => AccessTier.trial,
        _ => AccessTier.free,
      };

  String get label => switch (this) {
        AccessTier.free => 'Free',
        AccessTier.trial => 'Trial',
        AccessTier.pro => 'Pro',
      };
}

/// The claims carried inside a signed licence key.
///
/// A key is `base64url(payload).base64url(signature)`, where the payload is the
/// JSON form of this object and the signature is Ed25519 over those exact bytes.
/// Because the private key never ships, a licence can be verified on-device with
/// no server in the loop.
class Licence {
  final AccessTier tier;

  /// When access ends. Null means the licence never expires.
  final DateTime? expiresAt;

  /// When the licence was issued, used to size the progress bar.
  final DateTime? issuedAt;

  /// Who the licence was issued to, shown in Settings.
  final String? holder;

  /// The subscription this key belongs to, so an admin can find and revoke it.
  final String? id;

  /// The billing plan that produced this key (monthly, quarterly, yearly, ...).
  final String? plan;

  /// When set, the key only unlocks on this device fingerprint.
  final String? device;

  const Licence({
    required this.tier,
    this.expiresAt,
    this.issuedAt,
    this.holder,
    this.id,
    this.plan,
    this.device,
  });

  bool get isPerpetual => expiresAt == null;

  /// True when this licence grants access at [now].
  bool isActiveAt(DateTime now) {
    if (tier != AccessTier.pro) return false;
    final exp = expiresAt;
    return exp == null || !exp.isBefore(now);
  }

  /// Time left before [expiresAt], or null for a perpetual licence.
  Duration? remainingAt(DateTime now) => expiresAt?.difference(now);

  /// The full window this licence covers, when it is bounded.
  Duration? get total {
    final exp = expiresAt, iat = issuedAt;
    if (exp == null || iat == null) return null;
    final span = exp.difference(iat);
    return span.isNegative ? null : span;
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'tier': tier.name,
        if (id != null && id!.isNotEmpty) 'id': id,
        if (plan != null && plan!.isNotEmpty) 'plan': plan,
        if (device != null && device!.isNotEmpty) 'dev': device,
        if (expiresAt != null) 'exp': expiresAt!.toUtc().toIso8601String(),
        if (issuedAt != null) 'iat': issuedAt!.toUtc().toIso8601String(),
        if (holder != null && holder!.isNotEmpty) 'sub': holder,
      };

  /// Parses a decoded payload. Returns null when it is not a usable licence.
  static Licence? fromJson(Map<String, Object?> json) {
    final tier = AccessTier.fromName(json['tier'] as String?);
    if (tier != AccessTier.pro) return null;
    return Licence(
      tier: tier,
      expiresAt: _parse(json['exp']),
      issuedAt: _parse(json['iat']),
      holder: json['sub'] as String?,
      id: json['id'] as String?,
      plan: json['plan'] as String?,
      device: json['dev'] as String?,
    );
  }

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// Signs and verifies licence keys. Pure Dart, so the same code runs in the app
/// and in the offline signing tool.
class LicenceCodec {
  static final Ed25519 _ed = Ed25519();

  /// Signs [licence] with [keyPair] and returns a portable key string.
  static Future<String> sign(
    Licence licence, {
    required KeyPair keyPair,
  }) async {
    final payload = utf8.encode(jsonEncode(licence.toJson()));
    final signature = await _ed.sign(payload, keyPair: keyPair);
    return '${_encode(payload)}.${_encode(signature.bytes)}';
  }

  /// Verifies [token] against [publicKey]. Returns the licence, or null when the
  /// key is malformed, unsigned, or signed by a different key.
  static Future<Licence?> verify(
    String token, {
    required SimplePublicKey publicKey,
  }) async {
    final trimmed = token.trim();
    final dot = trimmed.indexOf('.');
    if (dot <= 0 || dot == trimmed.length - 1) return null;

    final Uint8List payload;
    final Uint8List signature;
    try {
      payload = _decode(trimmed.substring(0, dot));
      signature = _decode(trimmed.substring(dot + 1));
    } catch (_) {
      return null;
    }
    if (signature.length != 64) return null;

    final bool ok;
    try {
      ok = await _ed.verify(
        payload,
        signature: Signature(signature, publicKey: publicKey),
      );
    } catch (_) {
      return null;
    }
    if (!ok) return null;

    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) return null;
      return Licence.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// Builds a public key from the base64 form bundled with the app.
  static SimplePublicKey publicKeyFromBase64(String value) =>
      SimplePublicKey(_decode(value), type: KeyPairType.ed25519);

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Decodes unpadded base64url, tolerating either padding style.
  static Uint8List decodeBase64(String value) {
    final pad = (4 - value.length % 4) % 4;
    return base64Url.decode(value + '=' * pad);
  }

  static Uint8List _decode(String value) => decodeBase64(value);
}

/// The billing cadence a subscription is sold on.
///
/// The owner (admin) picks one when issuing a key; the length in days becomes
/// the licence's expiry, so a "monthly" key really is one month long.
enum BillingPlan {
  daily('Daily', 1),
  weekly('Weekly', 7),
  monthly('Monthly', 30),
  quarterly('Quarterly', 90),
  yearly('Yearly', 365),
  custom('Custom', 0);

  const BillingPlan(this.label, this.days);

  final String label;

  /// Days the plan covers. Zero for [custom], which supplies its own end date.
  final int days;

  static BillingPlan fromName(String? name) => switch (name) {
        'daily' => BillingPlan.daily,
        'weekly' => BillingPlan.weekly,
        'monthly' => BillingPlan.monthly,
        'quarterly' => BillingPlan.quarterly,
        'yearly' => BillingPlan.yearly,
        _ => BillingPlan.custom,
      };
}

/// A single subscription the owner has sold: who it is for, on what plan, and
/// the signed key the user was given.
class Subscription {
  final String id;
  final String holder;
  final BillingPlan plan;
  final DateTime issuedAt;
  final DateTime? expiresAt;

  /// The signed key handed to the user. Kept so the owner can re-copy it.
  final String key;

  /// The device the key was bound to, when the owner chose to bind it.
  final String? deviceId;

  const Subscription({
    required this.id,
    required this.holder,
    required this.plan,
    required this.issuedAt,
    required this.key,
    this.expiresAt,
    this.deviceId,
  });

  bool get isPerpetual => expiresAt == null;

  bool isActiveAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  Duration? remainingAt(DateTime now) => expiresAt?.difference(now);

  Map<String, Object?> toJson() => {
        'id': id,
        'holder': holder,
        'plan': plan.name,
        'iat': issuedAt.toUtc().toIso8601String(),
        if (expiresAt != null) 'exp': expiresAt!.toUtc().toIso8601String(),
        if (deviceId != null) 'dev': deviceId,
        'key': key,
      };

  static Subscription? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final holder = json['holder'];
    final key = json['key'];
    if (id is! String || holder is! String || key is! String) return null;
    return Subscription(
      id: id,
      holder: holder,
      plan: BillingPlan.fromName(json['plan'] as String?),
      issuedAt: _parse(json['iat']) ?? DateTime.now().toUtc(),
      expiresAt: _parse(json['exp']),
      deviceId: json['dev'] as String?,
      key: key,
    );
  }

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// Signs licence keys for a given keypair and plan. Shared by the admin panel
/// and the `tools/license_tool.dart` CLI so both mint identical keys.
class LicenceIssuer {
  const LicenceIssuer(this.keyPair);

  final KeyPair keyPair;

  /// Rebuilds an issuer from a base64 private seed.
  static Future<LicenceIssuer> fromSeed(String base64Seed) async {
    final bytes = LicenceCodec.decodeBase64(base64Seed.trim());
    return LicenceIssuer(await Ed25519().newKeyPairFromSeed(bytes));
  }

  /// Builds a public key string from the seed's matching keypair.
  Future<String> publicKeyBase64() async {
    final pub = await keyPair.extractPublicKey() as SimplePublicKey;
    return base64Url.encode(pub.bytes).replaceAll('=', '');
  }

  /// Builds and signs a key for [holder] on [plan]. [now] is the issue time and
  /// [deviceId] optionally binds the key to one device.
  Future<({Subscription subscription, Licence licence})> issue({
    required String holder,
    required BillingPlan plan,
    DateTime? now,
    DateTime? expiresAt,
    String? deviceId,
    String? id,
  }) async {
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final end = expiresAt?.toUtc() ??
        (plan == BillingPlan.custom
            ? null
            : issuedAt.add(Duration(days: plan.days)));
    final subId = id ?? newId(issuedAt);
    final licence = Licence(
      tier: AccessTier.pro,
      issuedAt: issuedAt,
      expiresAt: end,
      holder: holder,
      id: subId,
      plan: plan.name,
      device: deviceId,
    );
    final token = await LicenceCodec.sign(licence, keyPair: keyPair);
    return (
      subscription: Subscription(
        id: subId,
        holder: holder,
        plan: plan,
        issuedAt: issuedAt,
        expiresAt: end,
        deviceId: deviceId,
        key: token,
      ),
      licence: licence,
    );
  }

  /// A short, sortable, collision-resistant id: `SUB-<yyMMdd>-<6 base32>`.
  static String newId(DateTime now) {
    final rng = math.Random.secure();
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final tail = List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
    final y = now.year % 100;
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'SUB-$y$m$d-$tail';
  }
}
