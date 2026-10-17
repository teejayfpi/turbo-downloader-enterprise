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

Session headers (`Cookie`/`Authorization`/`Referer`) for gated links travel on
the **task** and are cleaned by `sanitizeHeaders()` in `local_downloader.dart`
before any request — the mobile twin of the server's allow-list. Add new
per-request behaviour in `_open()`, not at the call sites, so the HEAD probe,
segments and muxed tracks stay consistent. yt-dlp page/media downloads use their
own cookie jar in Settings, not these headers.

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
- **Leaving the first-run tour must not wait on storage.** `onboarding_screen.dart`
  fires `completeOnboarding()` without awaiting it, and `TurboState` flips the
  in-memory `onboardingDone` flag (and notifies) *before* the `SharedPreferences`
  write. Awaiting the write before `Navigator.pushReplacement` left SKIP and
  Start unresponsive when the platform channel was slow, and dropped the write
  when the widget had already been disposed — so the tour reappeared every
  launch. The write is best-effort: worst case, the tour shows once more.
  On desktop the same bug can be worse: the platform write *throws* (rather
  than returning a bool), and awaiting it aborted `_finish()` before it
  navigated, so the tap did nothing at all.
- **A fix on `main` is not shipped until it is released.** Users get desktop
  and Android builds from GitHub releases (the in-app updater compares the
  release tag against `credits.dart`'s `appVersion` and only offers a strictly
  newer version), so a same-version rebuild never reaches them. Ship a user-facing
  fix by bumping `pubspec.yaml`'s `version` and `credits.dart`'s `appVersion`,
  then tagging `v<version>`; the tag triggers `desktop.yml`/`android.yml` to
  rebuild and attach the installers.
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
- **The browser extension is a separate MV3 extension, API-first.** It is plain
  JS (no build step) with two manifests: `manifest.json` (Chrome/Edge/Brave) and
  `manifest.firefox.json` (Firefox; needs an add-on id and `background.scripts`).
  Hand-off order is `POST http://127.0.0.1:3001/api/downloads` first, then the
  `turbo://` deep link as fallback, so the popup can say whether the app actually
  took the link. Permissions are least-privilege on purpose (`activeTab`,
  `contextMenus`, `storage`, loopback hosts only) — do not add `scripting`,
  `tabs`, `cookies`, or `<all_urls>`. Detection lives in
  `browser-extension/lib/detector.js` and is DOM-optional so it unit-tests under
  `node --test`. `.github/workflows/extension.yml` validates, lints the Firefox
  manifest with `web-ext`, and packages both zips.
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

## yt-dlp selector gotcha

`format_id` is a string. An unquoted numeric value in a filter is parsed as a
number, so `-f 'bv*[format_id=313]+ba'` matches nothing and yt-dlp aborts with
"Requested format is not available" — even though format 313 exists. Always
quote the id: `bv*[format_id="313"]`. The plain form (`-f 313`) is fine because
it is not a filter.

## Security review notes (mobile)

- yt-dlp runs with TLS verification on. Do not add `--no-check-certificates`:
  it lets a network attacker swap the media bytes or read the cookie jar in
  transit, and none of the download hosts require it.
- The cookie jar is written to `~/.turbo/secure.json` with `0600` on desktop
  and the Android Keystore on Android. Desktop has no OS keychain: a local
  user with read access to the file can recover cookies. Treat that as
  accepted, not as safe.
- `AppDirs.data()` owns the location of every state file (session, history,
  desktop credentials). Never build it as `HOME ?? '.'` + `/.turbo`: with no
  `HOME`/`USERPROFILE` that is a working-directory-relative path, and a
  read-only cwd fails the session read with `OS Error: Read-only file system`,
  which surfaces to the user as "Could not read the session" and blocks
  sign-in. `AppDirs` tries `~/.turbo`, then `getApplicationSupportDirectory()`
  (the only sensible Android location), then the temp directory, and only
  returns a candidate it confirmed it could create.
- yt-dlp's error text is surfaced to the user via `DownloadError.detail`, so
  do not add flags that echo secrets into stderr.

## Security review notes (server)

- Session passthrough: `options.headers` (Cookie/Referer/Authorization) lets a
  login-gated URL download. Every caller-supplied header goes through
  `sanitizeHeaders()` before storage; it strips CR/LF injection, invalid names,
  oversized values, and the `RESERVED_HEADERS` set (notably `Range`,
  `Accept-Encoding`, `Host`, `Content-Length` — the engine owns these per
  request). Those values are secrets and must never leave the process: the API
  serializer exposes only `hasCustomHeaders`, never the values. Persisting them
  means `sqlite`'s `headers` column and any DB backup are sensitive.
- CORS is fail-safe: `CORS_ORIGIN` unset means anonymous reads only
  (`credentials: false`). Pinning an origin list is what enables credentials.
  Never pair `origin: '*'` with `credentials: true` — browsers reject it, and if
  they did not, any site could read authenticated responses.
- `assertPublicHost` returns the resolved address so the caller can pin the
  connection to it (`pinnedLookup`). Keep threading that address through
  `request`/`probe`/`downloadSingle`/`downloadSegment`, and re-check every
  redirect hop: resolving again at connect time would reopen DNS rebinding.
- A datacenter IP block is reported as a typed
  `YouTubeDatacenterBlockError` (`code: YOUTUBE_DATACENTER_BLOCK`, HTTP 451).
  It is `retryable = false` on purpose: retrying an IP block wastes bandwidth
  and worsens the IP's reputation. The client offers a `turbo://add?url=`
  handoff instead. Only the definitive `HTTP Error 403` / "unable to download
  video data" text maps here — a "Sign in to confirm you're not a bot"
  challenge is cookie-solvable and must keep routing to the sign-in flow.
- The release workflow hashes with no `|| true`: an unverifiable asset fails
  the release. Platforms that did not build are skipped so one broken platform
  cannot block the others.
- Without ffmpeg a flexible media request must not resolve to
  `best[ext=mp4]/best`: YouTube serves no progressive (video+audio in one file)
  format, so nothing matches and yt-dlp fails the whole download with
  "Requested format is not available". `resolveFormat` uses `NO_MERGE_BEST`
  (`bestaudio/best`) instead; an explicit format id still passes through.
- yt-dlp errors are classified by text into typed errors so the client can
  react: `YOUTUBE_DATACENTER_BLOCK` (HTTP 451, retryable: false) and
  `MEDIA_FORMAT_UNAVAILABLE` (retryable: false). Anything else is a plain
  Error. Do not let a new failure mode fall through to the raw yt-dlp text.
- `pinnedLookup` must honour `options.all`. Node enables autoSelectFamily
  (Happy Eyeballs) by default and asks a custom `lookup` for every answer at
  once; returning the single-address form makes net fail the connect with
  `ERR_INVALID_IP_ADDRESS` and breaks *every* direct download. The loopback
  engine e2e cannot catch this because `TURBO_ALLOW_PRIVATE_HOSTS=1` disables
  pinning, so `server/test/pinnedLookup.test.mjs` guards it (`npm test` in
  `server/`).

## Throughput invariants (server + mobile)

Turbo is positioned as the fastest downloader, so these bounds are deliberate.
Changing one without the others silently caps speed.

- `connections` is the requested parallelism per file; `split` is the ceiling.
  A download opens `parallel = min(connections, split, total / MIN_SEGMENT_BYTES)`
  sockets. `split` used to be stored, validated, and shown in the UI but never
  read by the engine, so raising it did nothing — keep it wired through `runHttp`.
- Dynamic segmentation: the file is cut into a *chunk grid* larger than the
  worker count (`buildChunks`, sized by `CHUNK_TARGET_BYTES`, floored at
  `MIN_SEGMENT_BYTES`, capped at `MAX_CHUNKS`). `mapLimit` gives each freed
  worker the next chunk, so a slow socket cannot leave a long tail — that is the
  whole mechanism, and it needs the grid to outnumber the workers. `chunkCount`
  and `parallel` are deliberately separate arguments to `downloadSegmented`.
- `MAX_INFLIGHT_STREAMS` (20 x 32) is the socket-pool size and must be at least
  `maxConcurrentDownloads x maxSplit`, or node queues surplus requests on a free
  socket and a raised setting buys no throughput. `MAX_SEGMENT_STREAMS` (24)
  bounds in-flight segment sockets for a single file via `mapLimit`.
- Segment and merge write streams use `WRITE_HIGH_WATER_MARK` (1 MiB) rather
  than the 16 KiB default, so a fast host is not stalled by small buffered
  writes. `mergeSegments` must not use `pipeline()` on the shared output stream
  once per part: it leaks listeners up to the segment count and trips
  `MaxListenersExceededWarning`. It pipes each part and awaits that part's `end`.
- Resume is layout-aware. Part files are named by chunk index and resumed by
  size, so they only line up with the layout in `<file>.turbo.plan`. When
  `(total, chunkCount)` differs from the plan, the parts are discarded; otherwise
  a retry after a settings change (or a grid change between versions) stitches
  bytes at the wrong offsets. The plan is removed on completion and by
  `cleanupArtifacts`.
- The mobile ceiling is 32 connections everywhere: `SpeedMode.turbo` returns 32,
  `setDefaultConnections` clamps to 32, `LocalDownloader.maxConnections` is 32,
  and `LocalDownloader.add` clamps to 32. A stray `clamp(1, 16)` silently undoes
  Turbo mode.
- Mobile adaptive acceleration (`LocalDownloader.adaptiveConnections`) starts a
  ranged transfer at `initialSegments` and ramps toward `task.connections`,
  splitting the segment with the most bytes *remaining*. The ramp adds
  `rampStepConnections` per window for at most `maxRampSteps` windows, so the
  reachable width is `initialSegments + rampStepConnections * maxRampSteps`;
  `state.dart` sizes both from the speed mode (`SpeedMode.rampStep`/`rampSteps`)
  or Turbo would top out far below its own 32-connection ceiling. A split
  appends the tail index, so `segmentStart`/`segmentEnd` are **not**
  byte-ascending and
  `segmentStart[i]` is not necessarily below the segment before it in the array.
  Two rules keep that safe: the partition checker (`_planIsValidFor`) validates
  by byte order and contiguity, never by array order, and `_merge` reassembles
  through `_orderedIndices` (sorted by byte offset), not `0..n`. A split also
  shrinks the running segment's `segmentEnd`; the fetch loop re-reads `end` each
  chunk and truncates (`sublist`) to the new boundary, because the in-flight
  HTTP response still streams the original, wider range and would otherwise
  overshoot into the tail's byte range.
- Mobile per-host speed memory (`LocalDownloader.rememberHostSpeed`, opt-out):
  a host that lets the ramp grow is recorded in `host_speed.json` and seeds the
  starting width of later downloads from the same `scheme://authority`, so the
  ramp is paid once per host rather than once per download. Three invariants:
  the memory **only ever grows** (`noteHostWidth` ignores a non-larger width, so
  a `rememberHostSpeed=false` toggle cannot lower an entry), a slow host that
  never splits is never written at all, and a valid entry is always `> 1` so it
  can never shrink the [initialSegments] floor. Writes are debounced (2 s) and
  serialised behind `_hostSave`, and flushed from the app lifecycle on
  `paused`/`detached` so a backgrounded app does not drop the map. This memory
  is an optimisation, never a correctness dependency: a corrupt/unreadable file
  is ignored, and the ramp still adapts from the seeded width.
- Mobile off-peak scheduling (`LocalDownloader.setOffPeakSchedule`): a daily
  local-time window that gates *starting* work only via `_scheduleHold`; running
  transfers are never paused, so it cannot surprise a user mid-download. The
  window is half-open (`start` inclusive, `end` exclusive) and wraps past
  midnight when `start > end`; a degenerate `start == end` is treated as always
  open so a stray value cannot wedge the queue. `_pump` arms a one-shot
  `_scheduleTimer` for the soonest of the window opening and the earliest retry
  backoff, so a held queue resumes on its own. `withinWindow` is a pure static
  helper and the boundary cases (normal / wrap / empty) are unit-tested.
- Global speed cap (`LocalDownloadManager.applySpeedLimit`): one shared ceiling
  across every running transfer, not per-download. The built-in byte loops
  `await _limit(chunk.length)` before writing, against a `_SpeedGate` token
  bucket shared by all segments. The gate is created lazily and replaced
  wholesale when the cap changes (never mutated in place), so a stale wake-up
  from an old burst can never wedge a new one; `reserve` chains on a single
  future so several segments cannot race the bucket. A yt-dlp transfer receives
  the same number as `--limit-rate <n>B` so both engines honour one figure.
  Setting the cap to 0 removes the gate and releases anything waiting.
- Mobile storage-root resilience (`LocalDownloadManager._resolveRoot`): the
  scratch root (queue file, `parts/`, host memory) comes from
  `getApplicationSupportDirectory()`. That call can throw *or* hand back an
  unwritable directory on a restricted install, and if it is lost the whole
  startup is lost with it — `init()` never sets `_root`, the queue is never
  recovered, and every download fails with "Turbo could not reach its storage
  folder." `_resolveRoot` probes the support directory for writability and falls
  back, in order, to the OS data dir derived from the environment
  (`_deriveEnvRootPath`), the provider temp dir, then `Directory.systemTemp`.
  The root is scratch space only; the user's finished files go through
  `FileStore`. `TurboState.init` isolates each startup stage (preferences,
  history, diagnostics, notifications) in its own try so a failure in one cannot
  skip the queue recovery that gives the worker its root; `init()` is
  reentrant-safe via `_initFuture` because the startup timeout can abandon it.
- In-app YouTube sign-in (`services/cookie_jar.dart`, `screens/youtube_login_screen.dart`):
  YouTube 403s the media bytes ("confirm you're not a bot") even when the page
  loads, and the Android sandbox hides other apps' cookie stores, so the app
  embeds a WebView for the user to sign in. The jar is read from the *platform*
  cookie store via `CookieManager` (JavaScript cannot see the HttpOnly session
  cookies, so a JS read always comes back empty) and converted to the Netscape
  `cookies.txt` yt-dlp reads. HttpOnly entries must carry the `#HttpOnly_`
  domain prefix or yt-dlp silently drops the line. The embedded sign-in is
  offered wherever a web view exists — Android, iOS, macOS, and Windows
  (`services/sign_in_support.dart`); Linux has no supported web view and keeps
  the file/browser path, so the button is hidden there. A YouTube 403 is routed
  to this flow rather than the generic "retry in a moment" wording.
- First-run sign-in gate: after the tour, a capable platform shows
  `YouTubeLoginScreen(required: true)` as the root route (it has nothing to pop
  to, so saving replaces itself with the shell). It is "mandatory" in the sense
  that Back is intercepted (`PopScope`) and there is no skip on the page, but a
  "Not now" action confirms once and persists so a locked-out network never
  traps the user. `TurboState.needsFirstRunSignIn` is
  `platform-capable && !signInPromptDone && !sessionConfigured`; the prompt flag
  is a separate preference (`turbo.signInPromptDone`) so a declined prompt is not
  shown again while a later-cleared session does not re-trigger it. `init()`
  awaits `refreshSession()` before the splash hands off, so a returning user with
  an existing session is not gated. `signInSupported` overrides the platform
  check in tests (the harness has no web view).
- The signed-in session reaches **both** engines. yt-dlp gets `--cookies` /
  `--cookies-from-browser` via `SessionStore.applyTo`. The pure-Dart built-in
  extractor (`youtube_explode_dart`) reads none of that on its own — it sends
  only a hardcoded `CONSENT` cookie — so on a phone (where yt-dlp cannot run)
  the login did nothing until `services/youtube_session.dart` bridged it: it
  turns the stored Netscape jar into a `Cookie:` header
  (`SessionStore.cookieHeaderFromJar`) and hands `MediaExtractor`,
  `YoutubeBrowser`, and the resolver a `YoutubeHttpClient` subclass that adds
  it. The bridge is process-wide and revision-counted, so a `YoutubeBrowser`
  built before sign-in rebuilds its client when the session changes. Only the
  jar reaches the built-in extractor; a browser profile cannot, as it needs a
  local profile yt-dlp reads.
- `#HttpOnly_` is a cookie, not a comment. In the Netscape format it prefixes
  the domain of an HttpOnly cookie — and the signed-in session cookies (SID,
  HSID, …) are exactly those, so a parser that treats `#HttpOnly_` as a comment
  silently drops the whole login. `countCookies` and `cookieHeaderFromJar`
  both special-case it.
- YouTube fragmented (HLS/DASH) sources are fetched over many connections via
  yt-dlp `-N` (`concurrentFragments`), sized by the same `SpeedMode` width as
  the built-in engine. Without it yt-dlp pulls one fragment at a time, which
  measured 14 s versus 1 s for a 1.25 MiB clip, so it is not optional for speed.
- yt-dlp needs a solver for YouTube's signature challenge. The app prefers a
  local JavaScript runtime (`deno`/`node`, `--js-runtimes`) but does **not**
  require one: with no runtime on PATH it passes `--remote-components
  ejs:github` so yt-dlp fetches the EJS challenge solver itself. Verified: the
  same video that exposes only storyboard images with neither flag probes 22
  formats and downloads when the remote component is requested. The flag is
  gated on `--remote-components` appearing in `yt-dlp --help` (cached per
  binary), so an older yt-dlp is never handed an unrecognised argument; the
  two solvers are mutually exclusive. `jsRuntimeAvailable` still drives the
  Settings row, which now says "Auto-fetched solver" rather than warning.
- Live YouTube checks are opt-in and never run in CI. `TURBO_LIVE=1` runs
  `test/live_media_test.dart` (built-in extractor) and
  `test/live_ytdlp_test.dart` (yt-dlp engine, end-to-end download). Both skip —
  rather than fail — when YouTube blocks the network, because a datacenter IP
  gets a bare "unavailable" from the pure-Dart extractor (every player client
  fails identically) and 403s from yt-dlp; that says nothing about the app.
  `TURBO_LIVE_URL` overrides the video, as individual videos are bot-checked
  independently. A verified run downloaded real bytes through the app's own
  `YtdlpEngine.probe`/`download`; the built-in extractor could not be exercised
  from CI because the datacenter IP is blocked for it.
- Desktop CI watch-out: `flutter_inappwebview_macos` declares an OS floor of
  10.14 but uses `ASWebAuthenticationPresentationContextProviding` (10.15+), and
  `flutter_additional_macos_build_settings` lowers the pod to its declared floor,
  so `macos/Podfile`'s `post_install` re-pins every pod target to 10.15.
- Test harness: `FfmpegMuxer.isAvailable()` returns false when
  `Platform.environment['FLUTTER_TEST']` is set. Probing the plugin
  (`FFmpegKitConfig.init()`) starts its native event channel, which the
  widget-test harness has no handler for — the stray `MissingPluginException`
  fails any test that boots the app (e.g. onboarding persistence). On Windows CI
  the ffmpeg plugin does not register that channel, exposing the same throw.

