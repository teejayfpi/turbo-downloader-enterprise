// Offline licence tooling for Turbo Downloader.
//
// The app verifies licence keys with a bundled Ed25519 public key; it never
// holds the private key. This tool is how you, the owner, hold the other half:
// generate a keypair once, then issue time-limited keys to users.
//
// Run it from the `mobile/` directory with plain Dart:
//
//   dart run tools/license_tool.dart keygen
//   dart run tools/license_tool.dart issue --seed <b64> --days 365 --holder "Ada"
//   dart run tools/license_tool.dart inspect <key> --public <b64>
//
// Then ship the app with your public key baked in:
//
//   flutter build apk --dart-define=TURBO_LICENCE_PUBLIC_KEY=<b64 public key>
//
// Keep the seed secret. Anyone holding it can mint licences.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:turbo_downloader/services/licence.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }
  switch (args.first) {
    case 'keygen':
      await _keygen();
    case 'public':
      await _public(args.skip(1).toList());
    case 'issue':
      await _issue(args.skip(1).toList());
    case 'inspect':
      await _inspect(args.skip(1).toList());
    case '-h':
    case '--help':
    case 'help':
      _usage();
    default:
      stderr.writeln('Unknown command: ${args.first}\n');
      _usage();
      exit(64);
  }
}

void _usage() {
  stdout.writeln('''
Turbo licence tool

  keygen
      Generate a new Ed25519 keypair. Print the public key (bake it into the
      app) and the private seed (keep it secret, never ship it).

  public --seed <b64>
      Print the public key for a seed, e.g. to rebuild the app for verification.

  issue --seed <b64> --holder <name> [--plan <plan>] [--days N | --expires <iso>]
        [--device <id>]
      Sign a licence key. --plan is one of daily, weekly, monthly, quarterly,
      yearly (default), or custom. A plan sets the length; --days/--expires
      override it. --device binds the key to one device id.

  inspect <key> --public <b64>
      Verify a key and print its claims.
''');
}

Future<void> _keygen() async {
  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes();
  final public = await keyPair.extractPublicKey();
  stdout.writeln('Public key (bake into the app):');
  stdout.writeln('  ${_b64(public.bytes)}');
  stdout.writeln();
  stdout.writeln('Private seed (KEEP SECRET):');
  stdout.writeln('  ${_b64(seed)}');
}

Future<void> _public(List<String> args) async {
  final opts = _parse(args);
  final seed = opts['seed'];
  if (seed == null) {
    stderr.writeln('Missing --seed.');
    exit(64);
  }
  final issuer = await LicenceIssuer.fromSeed(seed);
  stdout.writeln(await issuer.publicKeyBase64());
}

Future<void> _issue(List<String> args) async {
  final opts = _parse(args);
  final seed = opts['seed'];
  if (seed == null) {
    stderr.writeln('Missing --seed.');
    exit(64);
  }
  final holder = opts['holder'];
  if (holder == null || holder.trim().isEmpty) {
    stderr.writeln('Missing --holder.');
    exit(64);
  }
  final plan = opts['plan'] == null
      ? BillingPlan.monthly
      : BillingPlan.fromName(opts['plan']);
  if (opts['plan'] != null &&
      plan == BillingPlan.custom &&
      opts['plan'] != 'custom') {
    stderr.writeln('Unknown --plan. Use daily, weekly, monthly, quarterly, '
        'yearly, or custom.');
    exit(64);
  }

  final now = DateTime.now().toUtc();
  DateTime? expires;
  if (opts['expires'] != null) {
    expires = DateTime.tryParse(opts['expires']!)?.toUtc();
    if (expires == null) {
      stderr.writeln(
          '--expires must be an ISO-8601 date, e.g. 2027-01-01T00:00:00Z');
      exit(64);
    }
  } else if (opts['days'] != null) {
    final days = int.tryParse(opts['days']!);
    if (days == null || days <= 0) {
      stderr.writeln('--days must be a positive integer.');
      exit(64);
    }
    expires = now.add(Duration(days: days));
  }

  final issuer = await LicenceIssuer.fromSeed(seed);
  final result = await issuer.issue(
    holder: holder,
    plan: plan,
    now: now,
    expiresAt: expires,
    deviceId: opts['device'],
  );
  final sub = result.subscription;
  stdout.writeln(sub.key);
  stderr.writeln('Subscription ${sub.id} · ${plan.label}');
  if (sub.expiresAt != null) {
    stderr.writeln('Expires ${sub.expiresAt!.toIso8601String()}');
  } else {
    stderr.writeln('Perpetual licence (no expiry).');
  }
  if (sub.deviceId != null) stderr.writeln('Bound to device ${sub.deviceId}');
}

Future<void> _inspect(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('Usage: inspect <key> --public <b64>');
    exit(64);
  }
  final key = args.first;
  final opts = _parse(args.skip(1).toList());
  final public = opts['public'];
  if (public == null) {
    stderr.writeln('Missing --public <b64>.');
    exit(64);
  }
  final licence = await LicenceCodec.verify(
    key,
    publicKey: LicenceCodec.publicKeyFromBase64(public),
  );
  if (licence == null) {
    stdout.writeln('INVALID - signature does not match this public key.');
    exit(1);
  }
  stdout.writeln('Valid licence');
  stdout.writeln('  tier:    ${licence.tier.label}');
  stdout.writeln('  holder:  ${licence.holder ?? '-'}');
  stdout.writeln('  plan:    ${licence.plan ?? '-'}');
  stdout.writeln('  id:      ${licence.id ?? '-'}');
  stdout.writeln('  device:  ${licence.device ?? 'any'}');
  stdout.writeln('  issued:  ${licence.issuedAt?.toIso8601String() ?? '-'}');
  stdout.writeln(
      '  expires: ${licence.expiresAt?.toIso8601String() ?? 'never'}');
  final remaining = licence.remainingAt(DateTime.now().toUtc());
  if (remaining != null) {
    stdout.writeln('  left:    ${remaining.inDays} days');
  }
}

Map<String, String> _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[name] = args[++i];
    } else {
      out[name] = '';
    }
  }
  return out;
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
