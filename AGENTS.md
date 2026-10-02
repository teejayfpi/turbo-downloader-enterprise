# AGENTS.md

Repository knowledge for agents working on Turbo Downloader.

## Architecture

- `server/` — Express API + download engine. `index.js` boots the app,
  `downloadEngine.js` handles HTTP downloads (segmented/resumable) and delegates
  media URLs to `mediaService.js`, which shells out to `yt-dlp`.
- `client/` — Vite + React SPA, built to `client/dist` and served by the server.
- Deployed on Render from `main` via `Dockerfile`. `main` is the production branch.

## Verifying a change

There is no test suite. Verify by exercising the real path end to end:

```bash
# run the server locally against a throwaway data dir
YT_DLP_JS_RUNTIME=node FFMPEG_PATH="$(which ffmpeg)" \
  PORT=12000 TURBO_DATA_DIR=/tmp/td DOWNLOAD_DIR=/tmp/tddl node server/index.js

curl -X POST localhost:12000/api/downloads -H 'Content-Type: application/json' \
  -d '{"url":"<url>","formatId":"best"}'
curl localhost:12000/api/downloads/<id>           # poll status
curl -OJ localhost:12000/api/downloads/<id>/file  # fetch the artifact
```

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
