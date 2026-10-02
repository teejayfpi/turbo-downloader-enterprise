# Turbo — Android app

Native Flutter client for the Turbo Downloader server, packaged for the Google
Play Store.

Turbo downloads in one of two places, chosen with a switch on the Add tab and
under **Settings → Download location**:

- **This device** — the phone downloads directly, in parallel segments, and
  saves the file to its own Downloads folder. Nothing is sent anywhere else and
  no server is required.
- **Server** — the Turbo server fetches and merges the file, and the phone
  retrieves it later. Useful for jobs that must outlive the app being closed.

Device downloads use Dart's `HttpClient`, probe the URL for range support, split
the transfer into up to 16 connections, stream each part to app-private storage,
and merge the parts into one file that is handed to Android's MediaStore. A
paused or interrupted download keeps its parts and resumes from where it stopped.
Media pages (YouTube and similar) are only handled in Server mode, because they
need yt-dlp and ffmpeg, which do not run on the phone.

## Requirements

- Flutter 3.24.x (Dart 3.5.4)
- JDK 17 (JDK 21 breaks the Android Gradle Plugin's `jlink` step)
- Android SDK 35 with build-tools 35.0.0
- A reachable Turbo server (only for Server mode)

## Build

```bash
cd mobile
flutter pub get
flutter build apk --release        # installable APK  -> build/app/outputs/flutter-apk/
flutter build appbundle --release  # Play Store AAB  -> build/app/outputs/bundle/release/
```

## Release signing

Release builds are signed from `android/key.properties`, which is git-ignored
because it points at a keystore:

```properties
storePassword=…
keyPassword=…
keyAlias=turbo
storeFile=/absolute/path/to/turbo-release.jks
```

If the file is absent the build still succeeds, signed with the debug key — fine
for local testing, rejected by Play. Keep the keystore and its password out of
version control; losing them means you can no longer update the app under the
same listing.

## Configuration

Device mode needs no configuration. Server mode has no production URL baked into
the binary: choose **Server** on the Add tab (or in Settings) and enter the
address, which is verified with a `GET /health` probe and stored with
`shared_preferences`. A bare host like `turbo.example.com` is assumed to be
`https://`. Clearing the address switches the app back to device-only use.

## Layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App shell, bottom navigation, setup-vs-home routing |
| `lib/state.dart` | `ChangeNotifier` holding the mode, server queue, live Socket.IO updates, settings |
| `lib/api.dart` | REST client (`TurboApi`) |
| `lib/models.dart` | `DownloadTask`, `TurboStats`, `MediaInfo`, `MediaFormat` |
| `lib/local_downloader.dart` | On-device engine: ranged/segmented fetch, resume, persistence |
| `lib/screens/` | Downloads, Add, Settings, first-run Setup |
| `lib/downloader.dart` | Streams a server file, hands it to MediaStore, opens it |
| `android/…/MainActivity.kt` | `publishDownload` method channel (Android 10+ MediaStore) |

## Verifying

```bash
flutter test                                   # logic + on-device engine (real HTTP)
flutter analyze
# end-to-end against a running server:
dart run tool/integration_check.dart http://localhost:3001
```

`test/local_downloader_test.dart` spins up a real `HttpServer` and exercises the
device engine against it: multi-segment transfer with exact-byte verification,
single-connection fallback for servers without range support, a server that
advertises ranges then ignores them, an unknown-length body, resume without
duplicating bytes, queue persistence, and unreachable hosts. The `publish` step
(MediaStore) is the only part faked, so nothing misses the Android channel.

`tool/integration_check.dart` drives the real `TurboApi` through a complete
server round-trip — ping, create, poll to completion, list, retrieve the bytes,
clean up. Run it with a server started per the root `README.md`.

## Play Store notes

- `applicationId` is `com.turbodl.turbo_downloader`.
- `minSdk` 23, `targetSdk` 35.
- Release builds run R8 (`minifyEnabled` + `shrinkResources`); keep rules live in
  `android/app/proguard-rules.pro`.
- The launcher icon and splash come from the same brand art as the web app
  (`assets/icon/`), applied with `dart run flutter_launcher_icons`.
- Cleartext HTTP is permitted only for loopback/emulator addresses
  (`res/xml/network_security_config.xml`); public hosts must use TLS.

**Content policy risk:** apps whose primary purpose is downloading media from
platforms such as YouTube can be removed under Play's IP/DMCA and
device-abuse policies. Position the listing around general file downloads and
the self-hosted server, and expect review scrutiny.
