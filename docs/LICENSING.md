# Licensing and access

Turbo Downloader gives every install a timed trial and unlocks full features
with a signed licence key. There is no server, no account, and no API key: the
app verifies keys offline with an Ed25519 public key baked into the build.

This document is for you, the operator. It covers how access works, how to
issue keys, and how to ship a build that accepts them.

## How access works

A fresh install starts a **trial** the first time it runs. The trial lasts 7
days. While it is running, every feature is available and the app shows a
countdown. When it ends, the app drops to the **free** tier:

| Feature | Free / trial | Pro |
| --- | --- | --- |
| Single downloads, resume, pause | Yes | Yes |
| Built-in engine, quality picking | Yes | Yes |
| Simultaneous downloads | 1 | Up to 6 |
| Batch / playlist downloads | First video only | All |
| Scheduled ("download later") | No | Yes |

Entering a valid Pro key restores full access until the key's own expiry (or
forever, if it has none). Removing the key returns the app to the trial or free
tier.

### The countdown cannot be cheated by the clock

The app records the latest wall-clock time it has ever seen and treats "now" as
the later of the system clock and that high-water mark. Winding the system clock
backwards therefore does not extend a trial or a licence — the countdown keeps
running from the highest time seen. This is deliberately simple and needs no
network.

## Setting up your keypair (once)

From the `mobile/` directory:

```bash
dart run tools/license_tool.dart keygen
```

This prints two values:

- **Public key** — bake this into the app. It only verifies; it cannot sign.
- **Private seed** — keep this secret. Anyone with it can mint licences.

Store the seed in a password manager, not in the repository.

## Shipping a build that accepts keys

Pass the public key at build time with `--dart-define`:

```bash
flutter build apk --release \
  --dart-define=TURBO_LICENCE_PUBLIC_KEY=<public key>
```

```bash
flutter build windows --release \
  --dart-define=TURBO_LICENCE_PUBLIC_KEY=<public key>
```

In CI the same value comes from the `TURBO_LICENCE_PUBLIC_KEY` repository
secret, which both the Android and desktop workflows already pass through. If
the secret is unset, the build still succeeds and simply runs on the trial
alone — the app hides the key-entry controls in that case.

## Issuing a licence

Time-limited key (counts from now):

```bash
dart run tools/license_tool.dart issue \
  --seed <private seed> \
  --days 365 \
  --holder "Ada Lovelace"
```

Fixed expiry date:

```bash
dart run tools/license_tool.dart issue \
  --seed <private seed> \
  --expires 2027-01-01T00:00:00Z \
  --holder "Ada Lovelace"
```

Perpetual key (no expiry):

```bash
dart run tools/license_tool.dart issue --seed <private seed> --holder "Ada"
```

The command prints the key on stdout and a human-readable summary on stderr.
Send the key to the user; they paste it in **Settings → Access → Enter licence
key**.

## Verifying a key

```bash
dart run tools/license_tool.dart inspect <key> --public <public key>
```

This reports the tier, holder, issue and expiry dates, and days remaining, or
says the signature does not match.

## Key format

```
base64url(json claims).base64url(ed25519 signature)
```

The claims are:

| Field | Meaning |
| --- | --- |
| `v` | Format version (currently `1`) |
| `tier` | `pro` |
| `iat` | Issued-at, UTC ISO-8601 |
| `exp` | Expires-at, UTC ISO-8601 (omitted for perpetual) |
| `sub` | Holder name (optional) |

The signature covers the exact payload bytes, so editing any claim invalidates
the key. The app rejects malformed keys without throwing.

## What is not protected

- Keys are not bound to a device. A user could share a key. At this price that
  is an acceptable trade; device binding can be added later by storing a local
  fingerprint alongside the key.
- The trial clock is local. A determined user with a rooted device could clear
  app data to restart it. Server-side enforcement would fix this but would
  break the offline-first promise, so it is intentionally not done.

## Tests

`mobile/test/access_test.dart` covers signing and verification, tampered and
mismatched keys, trial start and expiry, clock-rollback resistance, activation,
deactivation, persistence across restarts, and the state-level enforcement of
concurrency, batch, and scheduling limits.
