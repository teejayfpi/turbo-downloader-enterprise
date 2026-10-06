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

The easiest way is the **owner console** inside the app (see below). The
command-line tool can also mint keys.

Keys are sold on a plan — `daily`, `weekly`, `monthly`, `quarterly`, `yearly`,
or `custom`. The plan sets the length; `--days` or `--expires` override it.

```bash
# Monthly key (30 days)
dart run tools/license_tool.dart issue \
  --seed <private seed> --plan monthly --holder "Ada Lovelace"

# Yearly key (365 days)
dart run tools/license_tool.dart issue \
  --seed <private seed> --plan yearly --holder "Ada Lovelace"

# Fixed expiry date (custom plan)
dart run tools/license_tool.dart issue \
  --seed <private seed> --plan custom \
  --expires 2027-01-01T00:00:00Z --holder "Ada Lovelace"

# Perpetual key (no expiry)
dart run tools/license_tool.dart issue \
  --seed <private seed> --plan custom --holder "Ada"

# Locked to one device
dart run tools/license_tool.dart issue \
  --seed <private seed> --plan monthly --device <device id> --holder "Ada"
```

The command prints the key on stdout and a human-readable summary on stderr.
Send the key to the user; they paste it in **Settings → Access → Enter licence
key**.

## The owner console

Build the app once with the public key and keep that build for yourself. In
**Settings → Owner console** you can:

- Set an owner passphrase (first run) and paste the signing seed.
- Issue a key for a holder on any plan, with an optional custom end date and an
  optional device binding.
- See the ledger: who holds what, which keys are active or expired, and copy a
  key to send to a user.

The passphrase gates the console so a user of the same build cannot issue
themselves a key. Only a salted SHA-256 digest is stored, and unlocking lasts
for the session. The signing seed lives in the secure store and never leaves
the device.

Keep this build private. Ship users the build that carries only the **public**
key — it can verify keys but cannot mint them, and it hides the owner console
entirely.

## Verifying a key

```bash
dart run tools/license_tool.dart inspect <key> --public <public key>
```

This reports the tier, holder, plan, subscription id, device binding, issue and
expiry dates, and days remaining, or says the signature does not match.

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
| `id` | Subscription id, `SUB-<yyMMdd>-<code>` (optional) |
| `plan` | Plan name, e.g. `monthly` (optional) |
| `dev` | Device the key is locked to (optional) |

The signature covers the exact payload bytes, so editing any claim invalidates
the key. The app rejects malformed keys without throwing.

## Device binding

A key may carry a `dev` claim. When it does, the app only accepts it on the
device whose id matches. A user finds their id in **Settings → Access** (it is
shown under the trial/free state) and sends it to you; you pass it with
`--device` or in the owner console.

The id is a random value generated on first run and kept in local preferences —
not a hardware identifier, and not personal data. It does not survive clearing
app data or reinstalling. Leave `dev` off for a key that should work anywhere.

## What is not protected

- The trial clock is local. A determined user with a rooted device could clear
  app data to restart it. Server-side enforcement would fix this but would
  break the offline-first promise, so it is intentionally not done.
- Removing a key from the owner's ledger does not revoke it. Verification is
  offline, so a key a user already holds keeps working until it expires. The
  ledger is the owner's record, not a kill switch.

## Tests

`mobile/test/access_test.dart` covers signing and verification, tampered and
mismatched keys, trial start and expiry, clock-rollback resistance, activation,
deactivation, persistence across restarts, and the state-level enforcement of
concurrency, batch, and scheduling limits.
`mobile/test/subscription_test.dart` covers plans and their lengths, key
issuance, the ledger, the admin gate, and device binding.
