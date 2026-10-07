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
expired stream URL. YouTube serves every resolution above 360p as separate
video and audio tracks; the app downloads both and merges them on the device
with the bundled FFmpeg, so 720p, 1080p and higher are available with no extra
setup. yt-dlp is still optional and adds non-YouTube platforms; when its own
ffmpeg is present it can merge tracks too. Everything works out of the box —
install yt-dlp only to unlock more platforms.

## Install

Grab the latest build from the
[releases page](https://github.com/teejayfpi/turbo-downloader-enterprise/releases/latest):

- **Windows:** download `TurboSetup-windows.exe` and run it. It installs for the
  current user only (no admin prompt), adds a Start Menu entry and an optional
  desktop shortcut, registers the `turbo://` link handler, and can be removed
  from *Apps & features*.
- **macOS:** download `Turbo-macos.zip`, unzip, and drag `Turbo.app` into
  *Applications*. The first launch needs *System Settings → Privacy & Security →
  Open Anyway* because the build is not notarised.
- **Linux:** download `Turbo-linux.tar.gz`, unpack it, and run
  `./turbo_downloader`.

To build from source instead, see *Verifying* below (you need the Flutter SDK
and, on Windows, Visual Studio 2022 with the C++ desktop workload).

## Getting links in from anywhere

Turbo does not care where a link comes from. It accepts a URL from whichever
route is closest to hand:

- **Share to Turbo** — in any browser or app, tap *Share* and choose Turbo
  (Android share sheet).
- **Open with Turbo** — tap a link and pick Turbo; the app registers for
  `http`/`https` links (Android intent filter), so a browser's *Open in app*
  works.
- **Drag and drop** — on Windows/Linux/macOS, drag a link straight from the
  browser onto the window; a drop overlay appears and the Add screen opens.
- **Launch argument / deep link** — the desktop build also reads a URL passed on
  the command line, so a `.desktop`/protocol handler or a shell command
  (`turbo_downloader "https://…"`) works.
- **Clipboard** — opening the Add screen checks the clipboard once and offers
  a one-tap *Use* if it finds a link. Pasting text with a link buried inside it
  also extracts just the URL.
- **Browser extension** — a companion Manifest V3 extension (`browser-extension/`)
  scans the current page for `<video>`/`<audio>`, HLS/DASH manifests, and file
  links, and hands the chosen one to the app through `turbo://add?url=…`. See
  `browser-extension/README.md`.

Every source funnels into the same Add screen, which auto-detects whether the
link is a plain file or a media page and inspects it immediately.

## Speed

Turbo mode (the default) raises the parallel-segment ceiling to 16 for
range-capable hosts and lets several downloads run at once. The Add screen and
Settings expose the connection count, and Settings has a Balanced/Turbo switch.

## Bandwidth limit

Settings → Device engine → Bandwidth limit caps the total download rate for the
whole device, so downloads do not saturate a connection you are still using.
Choose Unlimited (default), 5 MB/s, 1 MB/s, or 500 KB/s. The cap is enforced by a
shared token bucket in `lib/services/bandwidth.dart` that every HTTP transfer
draws from, and passed to yt-dlp as `--limit-rate`, so it applies to both engines
and to concurrent downloads together.

## Scheduled downloads

Any link can be queued for a later time instead of starting immediately. On the
Add screen, tap Schedule to pick a preset (in 15 minutes, tonight at 22:00,
tomorrow at 08:00) or an exact date and time; the task waits in the queue and
starts on its own, so the app does not need to stay open. A scheduled task is
labelled in the list and can be started early or rescheduled from its menu.

## Trial and Pro access

Every install starts a 7-day trial with a live countdown shown in the app bar
and in Settings → Access. When the trial ends the app keeps working at the free
tier (one download at a time, no batch or scheduling); a signed Pro key lifts
those limits for as long as the key allows.

There is no server, account, or API key. A key is verified on-device with an
Ed25519 public key baked into the build. The app only ever holds the public
half, so it can check a key but never mint one. The countdown also remembers the
latest time it has seen, so winding the system clock back does not extend access.

The operator commands to generate a keypair, issue keys, and ship a build that
accepts them are in [`../docs/LICENSING.md`](../docs/LICENSING.md). In short:

```bash
cd mobile
dart run tools/license_tool.dart keygen          # create a keypair
dart run tools/license_tool.dart issue --seed <seed> --days 365 --holder "Ada"
flutter build apk --release \
  --dart-define=TURBO_LICENCE_PUBLIC_KEY=<public key>
```

In CI, set the `TURBO_LICENCE_PUBLIC_KEY` repository secret; the Android and
desktop workflows pass it through. Without it the app runs on the trial alone
and hides the key-entry controls.

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
| `lib/credits.dart` | Designer attribution, WhatsApp link + app version |
| `lib/contact.dart` | WhatsApp contact tile (opens a chat via `url_launcher`) |
| `lib/state.dart` | `ChangeNotifier` holding settings, engines, and the device queue |
| `lib/services/access.dart` | Trial clock, licence activation, and the time-limited access status |
| `lib/services/licence.dart` | Ed25519 licence format: sign and verify |
| `lib/widgets/access_widgets.dart` | Countdown banner, app-bar chip, and licence-key dialog |
| `tools/license_tool.dart` | Operator CLI: `keygen`, `issue`, `inspect` |
| `lib/media_url.dart` | Detects media pages vs files and classifies file kinds |
| `lib/local_downloader.dart` | On-device engine: ranged/segmented fetch, resume, persistence, yt-dlp routing |
| `lib/media_extractor.dart` | Resolves a YouTube page to a direct stream on-device |
| `lib/ytdlp.dart` | Finds and drives the yt-dlp binary for other platforms and HD merge |
| `lib/file_store.dart` | Publishes a finished file per platform and opens it |
| `lib/screens/splash_screen.dart` | Standard splash: mark, name, spinner, designer credit |
| `lib/screens/home_shell.dart` | Bottom-nav shell: Downloads / Add / Settings |
| `lib/screens/` | Downloads, Add, Settings |
| `android/…/MainActivity.kt` | `publishDownload` + `ensureStorage` method channel |

## Where files are stored

Downloads run entirely on the device and are written to app-private staging,
then published to the user-visible Downloads location by `lib/file_store.dart`:

- **Android 10+ (API 29+):** the finished file is inserted through MediaStore
  into `Downloads/Turbo/<kind>/`, so it shows in the Files app and in any other
  app. No permission is required.
- **Android 9 and below (API 23–28):** the shared `Downloads/` folder needs
  legacy `WRITE_EXTERNAL_STORAGE`, requested at runtime the first time a file is
  published. If the user declines, the file is kept in the app's external files
  directory instead of being lost.
- **Desktop:** the finished file is moved into `Downloads/Turbo/<kind>/`. Name
  collisions get a ` (n)` suffix, so an existing file is never clobbered.

The `<kind>` subfolder separates media from documents:

| Kind | Folder | Examples |
| --- | --- | --- |
| Video | `Turbo/Videos` | `.mp4`, `.mkv`, `.webm` |
| Audio | `Turbo/Music` | `.mp3`, `.m4a`, `.flac` |
| Image | `Turbo/Pictures` | `.jpg`, `.png`, `.gif` |
| Archive | `Turbo/Archives` | `.zip`, `.rar`, `.7z` |
| Document | `Turbo/Documents` | `.pdf`, `.docx`, `.csv` |
| App | `Turbo/Apps` | `.apk`, `.exe`, `.dmg` |
| Other | `Turbo/Other` | anything unrecognised |

## Sharing a downloaded file

Completed downloads can be handed to another app:

- **Android:** the card's share button (or the ⋮ menu → *Share*) opens the system
  share sheet — WhatsApp, Bluetooth, Drive, and so on. The file is exposed as a
  `content://` URI through the app's `FileProvider`, so the receiving app never
  gets broad storage access.
- **Desktop:** there is no share sheet, so *Share* reveals the file in the file
  manager (`explorer /select,`, `open -R`, `xdg-open`), ready to attach.

The designer credit (settings *About* and the Add screen footer) is a tappable
tile that opens a WhatsApp chat with the designer via `url_launcher`.

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
