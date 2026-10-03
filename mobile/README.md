# Turbo — device download manager

Turbo is an offline-first download manager for **Android phones and desktop
computers** (Windows, Linux, macOS). Everything happens on the device you run it
on: the app opens the connections, writes the bytes to its own storage, and
needs no server, account, key, or approval. Open it and download.

Turbo detects what a link is and picks the right engine for it, entirely on the
device:

- **Plain file links** (`.zip`, `.mp4`, `.pdf`, …) go straight through the
  built-in multi-connection engine, which splits range-capable downloads into up
  to 16 parallel segments, resumes from the exact byte offset, and merges the
  parts byte-for-byte.
- **YouTube pages** are resolved on-device by `youtube_explode_dart`
  (`lib/media_extractor.dart`) into a direct stream URL. The page is inspected
  first so the UI can show the title, uploader, duration, thumbnail, and a
  quality picker.
- **Every other platform** (Vimeo, TikTok, SoundCloud, Twitch, Instagram,
  archive.org, and hundreds more) is handled by [yt-dlp](https://github.com/yt-dlp/yt-dlp)
  when it is installed. yt-dlp is an ordinary program that runs on your machine:
  it opens the connections and writes to this device's disk, so there is still
  no server, account, or key. The app finds it on `PATH` or in the usual install
  locations.
- **Unlisted sites keep working**: a link that has no file extension is treated
  as a page and offered to an extractor too, so a brand-new platform is not
  stuck behind a hard-coded list.

The page URL is what is stored, so a resume re-resolves rather than reusing an
expired stream URL. When ffmpeg is present, yt-dlp can merge separate HD video
and audio tracks and offer 1080p/4K; without it, the app offers combined streams
(and the built-in engine tops out around 360p/720p). Everything is optional —
install yt-dlp to unlock more platforms and higher quality, or use the app
as-is.

## Speed

Turbo mode (the default) raises the parallel-segment ceiling to 16 for
range-capable hosts and lets several downloads run at once. The Add screen and
Settings expose the connection count, and Settings has a Balanced/Turbo switch.

## Requirements

- Flutter 3.24.x (Dart 3.5.4)
- Android: JDK 17 (JDK 21 breaks the Android Gradle Plugin's `jlink` step) and
  Android SDK 35 with build-tools 35.0.0
- Desktop: the usual platform toolchain — Visual Studio (Windows), GTK 3 +
  clang/cmake/ninja (Linux), Xcode (macOS)

No server is required for any feature.

## Build

### In CI (GitHub Actions)

- `.github/workflows/android.yml` runs on every push or PR that touches
  `mobile/`. It runs `flutter analyze` and `flutter test`, then builds the
  release APK and AAB and uploads them as the `turbo-apk` and `turbo-aab`
  artifacts. Download them from the run summary — the easiest way to get an
  installable APK without a local Android toolchain.
- `.github/workflows/desktop.yml` builds the Windows, Linux, and macOS release
  bundles and uploads them as `turbo-windows`, `turbo-linux`, and `turbo-macos`.

The Android build is signed with the debug key unless you add these repository
secrets (Settings → Secrets and variables → Actions):

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

# Android
flutter build apk --release        # APK -> build/app/outputs/flutter-apk/
flutter build appbundle --release  # AAB -> build/app/outputs/bundle/release/

# Desktop (pick your platform)
flutter build windows --release
flutter build linux   --release
flutter build macos   --release
```

Run it during development with `flutter run -d windows` (or `-d linux`,
`-d macos`, or an attached Android device).

## Layout

The app uses a "precision instrument console" language: a dark, panel-based
shell with corner-tick frames, uppercase mono kickers, a left status rail on
every task card, and a user-selectable accent. Type is bundled (Sora for UI,
ChakraPetch for the display face, JetBrains Mono for numbers and identifiers).

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App entry: state provider + `MaterialApp` |
| `lib/theme.dart` | Palette, type families, `TurboPanel`/`TurboButton`/`Kicker` primitives |
| `lib/widgets.dart` | Shared UI: stat tiles, status pills, section labels, notices, progress bar |
| `lib/credits.dart` | Designer attribution + app version |
| `lib/state.dart` | `ChangeNotifier` holding settings, engines, and the device queue |
| `lib/media_url.dart` | Detects media pages vs files and classifies file kinds |
| `lib/local_downloader.dart` | On-device engine: ranged/segmented fetch, resume, persistence, yt-dlp routing |
| `lib/media_extractor.dart` | Resolves a YouTube page to a direct stream on-device |
| `lib/ytdlp.dart` | Finds and drives the yt-dlp binary for other platforms and HD merge |
| `lib/file_store.dart` | Publishes a finished file per platform and opens it |
| `lib/screens/splash_screen.dart` | Animated branded splash shown on launch |
| `lib/screens/home_shell.dart` | Bottom-nav shell: Downloads / Add / Settings |
| `lib/screens/` | Downloads, Add, Settings |
| `android/…/MainActivity.kt` | `publishDownload` + `ensureStorage` method channel |

## Where files are stored

Downloads run entirely on the device and are written to app-private staging,
then published to the user-visible Downloads location by `lib/file_store.dart`:

- **Android 10+ (API 29+):** the finished file is inserted through MediaStore
  into `Downloads/`, so it shows in the Files app and in any other app. No
  permission is required.
- **Android 9 and below (API 23–28):** the shared `Downloads/` folder needs
  legacy `WRITE_EXTERNAL_STORAGE`, requested at runtime the first time a file is
  published. If the user declines, the file is kept in the app's external files
  directory instead of being lost.
- **Desktop:** the finished file is moved into the OS Downloads directory. Name
  collisions get a ` (n)` suffix, so an existing file is never clobbered.

## Verifying

```bash
cd mobile
flutter analyze
flutter test
```

`test/local_downloader_test.dart` spins up a real `HttpServer` and exercises the
device engine against it: multi-segment transfer with exact-byte verification,
single-connection fallback for servers without range support, a server that
advertises ranges then ignores them, an unknown-length body, resume without
duplicating bytes, queue persistence, and unreachable hosts. The `publish` step
is the only part faked, so nothing misses the platform channel.

`test/redesign_test.dart` checks the splash hand-off and renders each screen and
the home shell. `test/core_test.dart` covers URL detection, formatting, and
filename sanitising. `test/state_test.dart` asserts the app starts with no
server, token, or account.

## Play Store notes

- `applicationId` is `com.turbodl.turbo_downloader`.
- `minSdk` 23, `targetSdk` 35.
- Release builds run R8 (`minifyEnabled` + `shrinkResources`); keep rules live in
  `android/app/proguard-rules.pro`.
- The launcher icon and splash come from `assets/icon/`, applied with
  `dart run flutter_launcher_icons`.
- Cleartext HTTP is permitted only for loopback/emulator addresses
  (`res/xml/network_security_config.xml`); public hosts must use TLS.

**Content policy risk:** apps whose primary purpose is downloading media from
platforms such as YouTube can be removed under Play's IP/DMCA and device-abuse
policies. Position the listing around general file downloads and expect review
scrutiny.
