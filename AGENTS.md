# AGENTS.md

Repository knowledge for agents working on Turbo Downloader.

## Architecture

- `server/` — Express API + download engine. `index.js` boots the app,
  `downloadEngine.js` handles HTTP downloads (segmented/resumable) and delegates
  media URLs to `mediaService.js`, which shells out to `yt-dlp`.
- `client/` — Vite + React SPA, built to `client/dist` and served by the server.
- `mobile/` — Flutter Android client packaged for the Play Store. It has two
  download modes: **device** (a real on-device segmented/resumable engine in
  `lib/local_downloader.dart`, stored via MediaStore) and **server** (a remote
  control for the REST API and `downloads:update` Socket.IO event). See
  `mobile/README.md`.
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
- **`app.set('trust proxy', 1)` is required behind Render's proxy.**
  `express-rate-limit` otherwise aborts every proxied request with
  `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`, which shows up as intermittent 502s.
- **A download's stored `filepath` is untrusted.** It is confined to the
  configured download directory before any read (`resolveStoredFile`), because a
  naive `startsWith` also matches sibling dirs like `<root>-evil/`.

## Android client (`mobile/`)

- **Build with JDK 17, not 21.** JDK 21 makes the Android Gradle Plugin's
  `JdkImageTransform` fail with a `jlink` error on `core-for-system-modules.jar`.
  Set `JAVA_HOME` to a JDK 17 before `flutter build`.
- **`socket_io_client` 2.x talks to the server's Socket.IO 4.x fine**, but the
  payload is the whole queue (`{downloads, stats, speedHistory}`) — replace the
  list wholesale rather than reconciling per task.
- **The app has no baked-in server URL.** It asks on first run and stores the
  address in `shared_preferences`; a wrong default is worse than none.
- **Saved files go through MediaStore** (`publishDownload` in `MainActivity.kt`),
  not a raw path, so they land in the public Downloads collection under scoped
  storage. On **Android 9 and below** the publish first calls `ensureStorage`,
  which requests legacy `WRITE_EXTERNAL_STORAGE` at runtime; if the user
  declines, `Downloader._appPrivate` keeps the file instead of losing it.
  Android 10+ needs no permission.
- **The UI is a "precision instrument console"** shared with the web client:
  bundled Sora / ChakraPetch / JetBrains Mono, corner-tick `TurboPanel` frames,
  uppercase mono `Kicker`s, status-railed task cards. Design primitives live in
  `lib/theme.dart`, shared widgets in `lib/widgets.dart`; keep both surfaces in
  sync rather than inventing a second visual language.
- **Play policy risk.** A YouTube/yt-dlp downloader can be pulled under IP/DMCA
  rules; see `mobile/README.md`.

## Mobile engine gotchas

- **`HttpClientResponse.contentLength` is `-1`, not null, when unknown.** Treating
  it as nullable silently produces a `-1` total and a broken progress bar.
- **A server can advertise `Accept-Ranges: bytes` and still ignore `Range`.**
  The engine re-opens the part file for writing (rather than appending) whenever
  the response is a full `200`, otherwise a resumed download grows a duplicate
  copy.
- **`autoUncompress = false` is required.** Content-encoding changes byte offsets
  and corrupts ranged/resumed transfers.
- **Plans must be reused on resume.** Rebuilding segments from zero after a pause
  appends duplicates. `_planSegments` keeps a matching plan and only rebuilds
  when the segment count or total length changed.
- **Media in device mode is resolved on the phone.** `lib/media_extractor.dart`
  uses `youtube_explode_dart` to turn a page URL into a direct stream, and the
  on-device engine downloads it. Only a combined (muxed) stream, an HLS stream,
  or audio-only is offered, because muxing separate HD tracks needs ffmpeg, which
  is not on the phone. Server mode still exists for higher-resolution media via
  yt-dlp/ffmpeg and `/api/media/*`.
- **Persist the page URL, re-resolve the stream.** Signed stream URLs expire, so
  `LocalTask.url` keeps the page and `streamUrl` is transient; a resume
  re-resolves rather than reusing a stale URL.

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
