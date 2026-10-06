import 'dart:convert';
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

  const Licence({
    required this.tier,
    this.expiresAt,
    this.issuedAt,
    this.holder,
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

  static Uint8List _decode(String value) {
    final pad = (4 - value.length % 4) % 4;
    return base64Url.decode(value + '=' * pad);
  }
}
