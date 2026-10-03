# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately
through GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository, or contact the maintainer directly using the details in
[`mobile/lib/credits.dart`](mobile/lib/credits.dart). Include the affected
version, a description, and steps to reproduce. You can expect an initial
response within a few days.

## Supported versions

Security fixes are issued for the latest release on the `main` branch. There is
no long-term support for older builds; upgrade to the newest release.

## How Turbo handles data

Turbo is a **device-only** application. It has no server, no account, and no
telemetry. That removes most of the usual attack surface, and the design keeps
the rest small on purpose:

- **Nothing leaves the device.** Every transfer runs in the app on the device
  that started it, and saved files are written to that device's own storage.
  The app never uploads a file, a URL, or an identifier to a Turbo-operated
  service.
- **Outbound traffic is only what the user asked for.** The app fetches the URL
  the user supplied (and, for a media page, the stream that page resolves to),
  plus an anonymous read of the public GitHub releases API for update checks.
  Those are the only connections it makes.
- **Credentials never touch plain storage.** Secrets are held by
  `SecureStore`: the Android Keystore on mobile and an owner-only (`0600`) file
  on desktop. They are never written to `SharedPreferences`, never logged, and
  never displayed once saved — the settings UI shows only a key name and a
  one-way fingerprint.
- **File paths are treated as untrusted.** A stored download path is confined to
  the configured download directory before it is read or shared.
- **Downloads are gated on the user's terms.** Wi-Fi-only and battery-aware
  policies can hold a transfer back, and an optional clipboard suggestion is
  read only while the app is open and the user has opted in.

## Build integrity

Every release artifact is produced by the workflows in
[`.github/workflows`](.github/workflows) from a tagged commit on `main`, so a
build can be traced back to its source. Android release builds are signed with
the key held in the repository's encrypted secrets; desktop builds ship as a
signed installer (Windows) or a signed app bundle (macOS) where certificate
secrets are configured.

## Supply chain

The **Security** workflow runs on every push and pull request and weekly on a
schedule:

- **gitleaks** scans the full history for committed secrets.
- **dependency-review** blocks a pull request that introduces a package with a
  high-severity advisory or a disallowed licence.
- **CodeQL** analyses the JavaScript surfaces (server, client, browser
  extension) with the security-and-quality query set.

The Flutter app has no CodeQL language; it is covered by `flutter analyze` and
`flutter test` in the Android and Desktop workflows.
