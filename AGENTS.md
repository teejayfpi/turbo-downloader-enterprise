# AGENTS.md

Repository knowledge for agents working on Turbo Downloader.

## Architecture

- `server/` — Express API + download engine. `index.js` boots the app,
  `downloadEngine.js` handles HTTP downloads (segmented/resumable) and delegates
  media URLs to `mediaService.js`, which shells out to `yt-dlp`.
- `client/` — Vite + React SPA, built to `client/dist` and served by the server.
- `mobile/` — Flutter app for **Android and desktop** (Windows/Linux/macOS).
  It is a self-contained, offline-first downloader: no server, account, or key.
  Every transfer runs on the device that opened the app and is written to that
  device's own storage (`lib/local_downloader.dart`, `lib/file_store.dart`), and
  media pages are resolved on-device by `lib/media_extractor.dart`. YouTube is
  handled by the built-in extractor; other platforms (and HD merged downloads)
  go through an optional on-device `yt-dlp` binary driven by `lib/ytdlp.dart`.
  In-app YouTube browsing (search, channels, playlists) lives in
  `lib/services/youtube_browser.dart` and `lib/screens/browse_screen.dart`; a
  tapped result opens `lib/widgets/media_download_sheet.dart`, which resolves
  the watch URL through the same `TurboState.addLink` path as a pasted link.
  Batch downloads (a whole channel, a whole playlist, or a multi-selection) go
  through `TurboState.addBatch`, driven by `lib/widgets/batch_download_sheet.dart`;
  the first few links are probed for a concrete format and the rest are queued
  as media pages for the per-task resolver, so a large listing fills the queue
  without a long up-front wait.
  See `mobile/README.md`. The `server/` and `client/` trees below are the legacy
  web deployment and are no longer used by the mobile app.
- Deployed on Render from `main` via `Dockerfile`. `main` is the production branch.
  `mobile/` is excluded in `.dockerignore` so it never enters the server image.

## Verifying a change

Server: no test suite; exercise the real path end to end:

```bash
# run the server locally against a throwaway data dir
YT_DLP_JS_RUNTIME=node FFMPEG_PATH="$(which ffmpeg)" \
  PORT=12000 TURBO_DATA_DIR=/tmp/td DOWNLOAD_DIR=/tmp/tddl node server/index.js

curl -X POST localhost:12000/api/downloads -H 'Content-Type: application/json' \
  -d '{"url":"<url>","formatId":"best"}'
curl localhost:12000/api/downloads/<id>           # poll status
curl -OJ localhost:12000/api/downloads/<id>/file  # fetch the artifact
```

Mobile: `cd mobile && flutter analyze && flutter test`. The device engine has
real tests in `mobile/test/local_downloader_test.dart`; they bind a loopback
`HttpServer` and check exact bytes for segmented, non-range, lying-server,
unknown-length, and resume cases. Run them before touching `local_downloader.dart`.

`npm run build` builds the client. After pushing to `main`, confirm the Render
deploy reaches `live` and re-check `GET /health`.

## Hard-won gotchas

These caused real, user-visible bugs. Do not regress them.

- **yt-dlp exits 0 even when it fails to merge.** A bad `--ffmpeg-location` or
  missing ffmpeg leaves `foo.f398.mp4` + `foo.f258.m4a` on disk while printing
  the path it *meant* to create. Never trust `--print after_move:filepath`
  without checking the file exists.
- **`FFMPEG_PATH` must be forwarded to yt-dlp** as `--ffmpeg-location`. yt-dlp
  only searches `PATH`; a configured path is invisible to it.
- **YouTube withholds separate video/audio streams from datacenter IPs.** Render
  often exposes only format 18 (360p). Flexible format selectors therefore need
  a `/best[ext=mp4]/best` fallback or they hard-fail with "Requested format is
  not available". A high-resolution request cannot be honoured on such hosts.
- **YouTube blocks datacenter IPs.** Two independent requirements: cookies
  (`YT_DLP_COOKIES_DATA`) *and* an external JS runtime (`YT_DLP_JS_RUNTIME=node`)
  for `yt-dlp-ejs` to solve signature challenges. Extraction is also
  probabilistic — occasional "Failed to extract any player response" is normal
  and a retry usually succeeds.
- **A bare 403 is the same class of failure as the bot check.** When YouTube
  will not serve the media, every client (`default`, `android`, `ios`, `tv`,
  `web`, `web_embedded`, …), both IP families, and both DASH and HLS return
  `HTTP Error 403: Forbidden` — on a large video *and* on a 114 KB audio-only
  format, and on unrelated videos. The only on-device remedies are cookies
  (Settings → Sign-in & cookies) and a different network; a pure-Dart path can
  never sign in. Classify it with `YtdlpEngine.looksLikeAccessDenied` (403 /
  forbidden / "unable to download video data" / 429) as **non-retryable** so the
  queue does not burn retries, and surface `DownloadError.advice` (rendered via
  `Notice.subtext` and the details dialog) pointing at the cookie setup. Do not
  report it as a generic "could not read the page".
- **Cookies alone are not enough for YouTube — the engine must also pass a
  JavaScript runtime.** yt-dlp solves YouTube's `n`/signature challenge with an
  external JS runtime, and by default only `deno` is enabled. With valid
  signed-in cookies but no `--js-runtimes <runtime>`, `web` returns *only*
  mhtml storyboard images (no media formats at all), which is easy to misread
  as "no formats" or a storyboard download. `YtdlpEngine` therefore detects a
  runtime (`deno`/`node`/`bun`/`quickjs`) once and adds `--js-runtimes` to both
  `probe` and `download`; a storyboard-only probe now throws a message naming
  the runtime remedy. Verified end-to-end: cookies + `node` + `yt-dlp-ejs`
  unlock full HD (video-only 1080p) and a merged download with ffmpeg. So a
  desktop needs yt-dlp **and** `yt-dlp-ejs` **and** deno/node **and** cookies —
  a signed-in cookie with no runtime still yields storyboards.
- **`app.set('trust proxy', 1)` is required behind Render's proxy.**
  `express-rate-limit` otherwise aborts every proxied request with
  `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`, which shows up as intermittent 502s.
- **A download's stored `filepath` is untrusted.** It is confined to the
  configured download directory before any read (`resolveStoredFile`), because a
  naive `startsWith` also matches sibling dirs like `<root>-evil/`.
- **`defaultDir` is environment-only.** `PUT /api/settings` rejects it (403)
  unless it equals `DOWNLOAD_DIR`; otherwise an unauthenticated caller could
  point the download root at `/root/.ssh` and write an `authorized_keys` file.
  The reported version is read from `server/package.json` at boot
  (`SERVER_VERSION`) rather than hard-coded, which had drifted before.
- **Production without `TURBO_API_TOKEN` warns, it does not refuse.** The
  Dockerfile and `render.yaml` both set `NODE_ENV=production`, so a hard exit
  would take down every existing deploy the moment this landed. The default is a
  loud startup warning; `TURBO_REQUIRE_TOKEN=true` makes an unauthenticated
  production boot fatal. `render.yaml` sets both `TURBO_API_TOKEN`
  (`generateValue`) and `TURBO_REQUIRE_TOKEN`; clients present the token as
  `Authorization: Bearer`, `X-Api-Token`, or `?token=`.

## Android & desktop client (`mobile/`)

- **The app is device-only.** It never asks for a server URL, token, or account.
  `Mobile` boots straight into a standard splash screen (mark, name, spinner,
  designer credit) and then the three tabs
  (`lib/screens/home_shell.dart`). Do not reintroduce a setup/server mode.
- **Build with JDK 17, not 21.** JDK 21 makes the Android Gradle Plugin's
  `JdkImageTransform` fail with a `jlink` error on `core-for-system-modules.jar`.
  Set `JAVA_HOME` to a JDK 17 before `flutter build`.
- **Saved files are published per platform** by `lib/file_store.dart`: Android
  goes through MediaStore (`publishDownload` in `MainActivity.kt`) so the file
  lands in the public Downloads collection; desktop copies it into the OS
  Downloads directory (derived from the documents dir, avoiding an extra
  plugin); anything else falls back to app-private storage. On **Android 9 and
  below** the Android path first calls `ensureStorage`, which requests legacy
  `WRITE_EXTERNAL_STORAGE` at runtime; if the user declines, the file stays
  app-private instead of being lost. Android 10+ needs no permission.
- **Publishing must never throw.** `getApplicationDocumentsDirectory()` raises
  when no XDG `DOCUMENTS` user dir is configured, which is the norm on servers
  and minimal Linux desktops; `_downloadsDir()` and the last-resort
  `_appPrivate()` both degrade (HOME-based `Downloads`, then app support) rather
  than let a fully-downloaded file fail at the publish step. A test machine with
  no `~/Documents` will otherwise surface every completed download as an error.
- **A retry must not re-request an already-complete segment.** After a failure
  that happens *after* the bytes are on disk (e.g. publish), `segmentDone` for a
  finished segment equals its length; `_fetch`'s `fetchOne` returns early there
  instead of sending `bytes=<end+1>-<end>`, which a server answers with a full
  `200` that is then misread as the remote file changing.
- **Everything is filed under `Downloads/Turbo/<kind>`.** `FileStore.subfolderFor`
  maps a filename to a subfolder (`Videos`, `Music`, `Pictures`, `Archives`,
  `Documents`, `Apps`, `Other`) so media and documents are easy to tell apart.
  Android passes the folder as MediaStore's `RELATIVE_PATH`; desktop creates the
  real directories. Add a new kind in `folderNameFor` rather than hard-coding a
  folder name anywhere else.
- **Finished files can be shared.** `FileStore.share` opens the Android share
  sheet through the `shareFile` method channel, which exposes the file as a
  `content://` URI via the app's `FileProvider` (see `res/xml/file_paths.xml`);
  desktop platforms reveal the file in the file manager instead. The designer's
  WhatsApp link lives in `lib/credits.dart` and is opened with `url_launcher`
  through `WhatsAppTile` (`lib/contact.dart`).
- **Keep desktop green too.** `flutter create --platforms=windows,linux,macos`
  generated the runner folders; the in-app splash and the file store are
  cross-platform, and `flutter analyze && flutter test` cover them. CI runs the
  Android build (`android.yml`) and the desktop builds (`desktop.yml`).
- **The platform bridges live in `PlatformChannels.kt`.** `MainActivity.kt`
  registers the `turbo_downloader/files` channel (publish/share/background) and
  delegates the `secure`, `notify`, and `device` channels to
  `PlatformChannels.register`. Credentials are AES/GCM encrypted under an
  Android Keystore key (`SecureVault`); notifications and connectivity/battery
  state have their own objects there. The Dart side degrades gracefully when a
  channel is absent, so a desktop build or a test sees a no-op, not a crash —
  keep that property when adding a method.
- **Signed-in sessions are optional and encrypted.** `lib/services/session_store.dart`
  keeps a Netscape `cookies.txt` (or a chosen browser profile) in `SecureStore`
  and writes it to a temp file for yt-dlp via `YtdlpEngine.cookiesPath` /
  `cookiesFromBrowser` (`--cookies` / `--cookies-from-browser`). This is what
  makes bot-checked, age-restricted, private, and members-only videos work.
  Never write a cookie jar to plain preferences or a log; go through
  `SessionStore`/`SecureStore`. `TurboState.refreshSession` re-applies it to the
  engine on startup and after any change.
- **The updater installs, not just checks.** `UpdateChecker.pickAsset` chooses
  the right release asset for the platform (APK / EXE / DMG-ZIP / AppImage-deb),
  and `UpdateInstaller` downloads it and opens the platform installer
  (`TurboState.installUpdate`). Keep `pickAsset` pure and platform-parameterised
  so it stays testable; keep the installer's failure path non-throwing so a
  failed update never crashes Settings.
- **An update is verified before it is installed.** When the release publishes a
  `SHA256SUMS` asset that lists the chosen download, `UpdateChecker.pickChecksums`
  forwards it and `UpdateInstaller.download` hashes the bytes as they stream in,
  discarding the file on a mismatch. A manifest that does not list the asset is
  normal (the release cuts one per platform, e.g. desktop-only on Android) and
  the download proceeds unverified rather than failing. Keep publishing the
  manifests in the release workflows; if you ever add a signature, verify it here
  too.
- **Release builds fail without a signing keystore.** `android/app/build.gradle`
  throws rather than silently falling back to the debug key, which is public and
  would let anyone sign an APK the in-app updater accepts. `-PallowDebugSigning=true`
  (or `ALLOW_DEBUG_SIGNING=true`) is the explicit escape hatch; CI sets it only
  when no keystore secret is configured, and the workflow then skips publishing
  the APK to a release so a debug-signed build never reaches the updater.
- **A missing platform channel must never break a feature.** Every Dart bridge
  (`SecureStore`, `Notifications`, `DevicePolicy`, `FileStore`) catches
  `MissingPluginException` and falls back. Do not let a new bridge throw on
  desktop or in tests.
- **The UI is a "precision instrument console"**: bundled Sora / ChakraPetch /
  JetBrains Mono, corner-tick `TurboPanel` frames, uppercase mono `Kicker`s,
  status-railed task cards. Design primitives live in `lib/theme.dart`, shared
  widgets in `lib/widgets.dart`; keep both the app and the legacy web console in
  sync rather than inventing a second visual language.
- **Play policy risk.** A YouTube/yt-dlp-style downloader can be pulled under
  IP/DMCA rules; see `mobile/README.md`.
- **Links arrive from many places.** Incoming URLs are normalised in
  `lib/link_inbox.dart` (`LinkInbox` + `extractUrl`) and delivered to
  `TurboState.receiveLink`, which the shell and Add screen observe: Android
  share sheet and `http(s)` intents, deep links (`app_links`), desktop
  drag-and-drop (`desktop_drop`), a launch argument, and a clipboard suggestion.
  Add a new source by funnelling it through `receiveLink`; never duplicate the
  detection logic in another screen.
- **The `turbo://` scheme is a contract.** The browser extension
  (`browser-extension/`, served outside the Flutter app) hands links over as
  `turbo://add?url=<encoded>`. Both ends must agree: `extractUrl` unwraps it,
  `platform_links.dart` registers the handler at desktop startup, and the
  Android manifest and macOS `Info.plist` declare it. Change the shape in one
  place and update all four.
- **`app_links` stays under 6.4.** 6.4+ reads `flutter.compileSdkVersion` from
  its Android Gradle script, which the Flutter 3.24 template does not expose;
  the release APK fails to assemble without the pin in `pubspec.yaml`.

## Mobile engine gotchas

- **`HttpClientResponse.contentLength` is `-1`, not null, when unknown.** Treating
  it as nullable silently produces a `-1` total and a broken progress bar.
- **A server can advertise `Accept-Ranges: bytes` and still ignore `Range`.**
  The engine re-opens the part file for writing (rather than appending) whenever
  the response is a full `200`, otherwise a resumed download grows a duplicate
  copy.
- **`autoUncompress = false` is required.** Content-encoding changes byte offsets
  and corrupts ranged/resumed transfers.
- **Every engine request sends a browser `User-Agent`.** The bare dart:io default
  (`Dart/<sdk> (dart:io)`) is answered with a 403 by many CDNs, which surfaces as
  "The server refused access to this file." Route probe, segment, and muxed-track
  requests through `_open` so none of them slips through with the default agent.
  The legacy server engine already did this (`USER_AGENT` in
  `server/downloadEngine.js`).
- **Plans must be reused on resume.** Rebuilding segments from zero after a pause
  appends duplicates. `_planSegments` keeps a matching plan and only rebuilds
  when the segment count or total length changed.
- **Resume is bound to a validator.** A part file on disk only matches the
  remote resource if nothing re-uploaded it since. `_probe` records a strong
  `ETag` (falling back to `Last-Modified`; a weak `W/"…"` is not a valid
  `If-Range` value) on `LocalTask.etag`, a resumed request sends it as
  `If-Range`, and crossing sessions a changed validator resets the progress
  instead of stitching two versions together. Do not drop the `If-Range` header
  or the change check; either alone corrupts resumed files whose origin changed.
- **Media is resolved on the device.** `lib/media_extractor.dart` uses
  `youtube_explode_dart` to turn a page URL into a direct stream, and the
  on-device engine downloads it. YouTube serves resolutions above 360p as
  video-only DASH streams, so the extractor pairs each with the best audio
  track and `lib/services/ffmpeg.dart` remuxes them (`-c copy`, no re-encode)
  with the bundled FFmpeg. Combined, HLS, and audio-only streams are still
  offered directly. There is no server fallback any more.
- **yt-dlp publishes storyboards as formats; never offer them.** Each is a
  thumbnail sprite sheet: no codecs (`vcodec`/`acodec` null) and an `mhtml`
  container. `YtdlpEngine._parseProbe` must skip that container, otherwise a
  video with no combined stream (every rendition video-only) lets a storyboard
  sort to the top and become the default pick — the app downloads a `.mhtml`
  image sheet instead of the video. A codec-less `mp4`/`m4a` (the generic
  extractor's direct media link) must still be offered, so filter on the
  container, not on missing codecs.
- **Bundled FFmpeg needs an `$ORIGIN` RPATH on Linux.** FFmpegKit calls a bare
  `dlopen("libffmpegkit.so")`, and glibc resolves a dlopen'd library's own
  dependencies from the *caller's* RUNPATH — the executable's RUNPATH is not
  consulted. Without `$ORIGIN` on the plugin and every `libav*`/`libsw*` in the
  bundle, the plugin logs "libffmpegkit.so could not be loaded" and HD merging
  is dead at runtime. `linux/CMakeLists.txt` sets this after install with
  `patchelf` (present in a normal desktop dev env and in `desktop.yml`).
- **A failed engine retries on the other one.** `_runTask` catches a
  `MediaResolveException` from the built-in extractor and re-runs the task
  through yt-dlp, and catches a `YtdlpException` and re-runs it through the
  built-in extractor (`task.fellBackToBuiltin` records the switch). YouTube
  blocks the two engines differently, so this rescues links either engine
  rejects on its own.
- **The storage root is not always ready when a task starts.** `_requireTaskDir`
  throws `DownloadErrors.storageUnavailable` instead of `_taskDir(...)!`, so a
  task queued before `init()` finishes reports an actionable storage error
  rather than "The download stopped unexpectedly. / Null check operator used on
  a null value".
- **The generic yt-dlp extractor emits `vcodec: null`.** A direct `.mp4`/`.mp3`
  link has both codecs unknown; `_parseProbe` keeps it as a single combined
  format instead of dropping the only entry, which otherwise leaves the picker
  empty and crashes `formats.first`.
- **Persist the page URL, re-resolve the stream.** Signed stream URLs expire, so
  `LocalTask.url` keeps the page and `fetchUrl` is transient; a resume
  re-resolves rather than reusing a stale URL.
- **Live tests are opt-in.** `test/live_media_test.dart` and
  `test/live_manager_test.dart` are skipped unless `TURBO_LIVE=1` is set, so the
  default suite and CI never depend on YouTube or a yt-dlp install. YouTube
  also refuses media bytes to datacenter IPs ("Sign in to confirm you're not a
  bot"), so the live YouTube byte test tolerates that block.

## Environment

| Variable | Purpose |
| --- | --- |
| `YT_DLP_COOKIES_DATA` | cookies.txt contents; materialised to a `0600` temp file per process |
| `YT_DLP_JS_RUNTIME` | JS runtime for yt-dlp-ejs (default `node`) |
| `FFMPEG_PATH` | ffmpeg binary; forwarded to yt-dlp as `--ffmpeg-location` |
| `DOWNLOAD_DIR` | download root, also the file-serving confinement boundary |
| `TURBO_DATA_DIR` | SQLite state directory |

Render service: `srv-davrc8lg1s2s73bjjsb0`. Env vars can be set per key with
`PUT /v1/services/{id}/env-vars/{key}`.

## Secrets

Never commit cookies or tokens. `YT_DLP_COOKIES_DATA` holds a live signed-in
session and must be rotated after use.

## Security review notes (mobile)

- yt-dlp runs with TLS verification on. Do not add `--no-check-certificates`:
  it lets a network attacker swap the media bytes or read the cookie jar in
  transit, and none of the download hosts require it.
- The cookie jar is written to `~/.turbo/secure.json` with `0600` on desktop
  and the Android Keystore on Android. Desktop has no OS keychain: a local
  user with read access to the file can recover cookies. Treat that as
  accepted, not as safe.
- yt-dlp's error text is surfaced to the user via `DownloadError.detail`, so
  do not add flags that echo secrets into stderr.
