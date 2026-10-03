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

Device mode also downloads media without a server. A YouTube or similar page is
resolved on the phone by `youtube_explode_dart` (`lib/media_extractor.dart`),
which turns the page into a direct stream URL; the on-device engine then fetches
that URL with the phone's own connection and storage. A combined audio+video
stream is used because a phone cannot mux separate HD tracks without ffmpeg, so
the practical ceiling is around 360p (the extractor falls back to an HLS or
audio-only stream when no muxed one exists). The page URL is what is stored, so a
resume re-resolves rather than reusing an expired stream URL. Server mode still
exists for higher-resolution jobs, where yt-dlp and ffmpeg run. YouTube on a
hosted server is gated and needs `YT_DLP_COOKIES_DATA` — see "YouTube on a hosted
server" in the root `README.md`.

## Requirements

- Flutter 3.24.x (Dart 3.5.4)
- JDK 17 (JDK 21 breaks the Android Gradle Plugin's `jlink` step)
- Android SDK 35 with build-tools 35.0.0
- A reachable Turbo server (only for Server mode)

## Build

### In CI (GitHub Actions)

`.github/workflows/android.yml` runs on every push or pull request that touches
`mobile/`, and can be started by hand from the Actions tab. It runs
`flutter analyze` and `flutter test`, then builds the release APK and AAB and
uploads them as the `turbo-apk` and `turbo-aab` artifacts. Download them from
the run summary. This is the easiest way to get an installable APK without a
local Android toolchain.

The build is signed with the debug key unless you add these repository secrets
(Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 turbo-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias (e.g. `turbo`) |

With them set, the workflow writes `android/key.properties` and signs the
release build properly, so the AAB is Play-ready.

### Locally

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

The app is a project of the same "precision instrument console" language as the
web client: a dark, panel-based shell with corner-tick frames, uppercase mono
kickers, a left status rail on every task card, and a user-selectable accent.
Type is bundled (Sora for UI, ChakraPetch for the display face, JetBrains Mono
for numbers and identifiers) so the two surfaces share one voice.

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App shell, bottom navigation, setup-vs-home routing |
| `lib/theme.dart` | Palette, type families, `TurboPanel`/`TurboButton`/`Kicker` design primitives |
| `lib/widgets.dart` | Shared UI: stat tiles, status pills, section labels, notices, segmented control, progress bar |
| `lib/credits.dart` | Designer attribution + app version, kept in sync with the web client |
| `lib/state.dart` | `ChangeNotifier` holding the mode, server queue, live Socket.IO updates, settings |
| `lib/api.dart` | REST client (`TurboApi`) |
| `lib/models.dart` | `DownloadTask`, `TurboStats`, `MediaInfo`, `MediaFormat` |
| `lib/media_url.dart` | Detects media pages (YouTube and similar) to drive UI hints |
| `lib/local_downloader.dart` | On-device engine: ranged/segmented fetch, resume, persistence |
| `lib/screens/` | Downloads, Add, Settings, first-run Setup |
| `lib/downloader.dart` | Streams a server file, hands it to MediaStore, opens it |
| `android/…/MainActivity.kt` | `publishDownload` + `ensureStorage` method channel |

## Where files are stored

Device-mode downloads run entirely on the phone and are written to app-private
staging, then published to the shared Downloads collection:

- **Android 10+ (API 29+):** the finished file is inserted through MediaStore
  into `Downloads/`, so it shows in the Files app and in any other app. No
  permission is required.
- **Android 9 and below (API 23–28):** the shared `Downloads/` folder needs
  legacy `WRITE_EXTERNAL_STORAGE`, which is requested at runtime the first time
  a file is published. If the user declines, the file is kept in the app's
  external files directory instead of being lost.
- **Server-mode retrieval** uses the same publish path, so a file pulled from
  the server lands in the same place.

`lib/downloader.dart` sends the raw byte stream from yt-dlp that the server hands
back, which is what fixes media files previously being saved as HTML error
pages.

## Verifying

```bash
flutter test                                   # logic + on-device engine (real HTTP)
flutter analyze
# end-to-end against a running server:
dart run tool/integration_check.dart http://localhost:3001
```

`test/redesign_test.dart` covers the media-host detector and renders each
redesigned screen plus the home shell. `test/local_downloader_test.dart` spins up
a real `HttpServer` and exercises the device engine against it: multi-segment
transfer with exact-byte verification, single-connection fallback for servers
without range support, a server that advertises ranges then ignores them, an
unknown-length body, resume without duplicating bytes, queue persistence, and
unreachable hosts. The `publish` step (MediaStore) is the only part faked, so
nothing misses the Android channel.

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
