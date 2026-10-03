# 🚀 Turbo Downloader

An enterprise-grade **on-device** download manager for mobile phones and
computers. It downloads files and media (YouTube and hundreds of other
platforms) straight to your device with multi-connection, resumable transfers —
**no server, no account, no API key.**

![Version](https://img.shields.io/badge/version-2.0.0-00d4ff?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-00ff88?style=for-the-badge)

---

## The app

The current product is the **Flutter app in [`mobile/`](mobile/)**. It runs on
Android phones and on desktop (Windows, Linux, macOS), and everything happens on
the device: the app opens the connections, resolves media pages, and writes the
finished file to your Downloads folder. Nothing is sent to a server and nothing
is stored anywhere but your device.

- **Detects what a link is** — a file, a YouTube video, or any other supported
  platform — and picks the right engine automatically.
- **Fast, resumable, multi-connection** downloads with a Turbo mode that splits
  range-capable transfers across up to 16 parallel segments.
- **Saves to the device** — Android's Downloads collection via MediaStore,
  or the OS Downloads folder on desktop.
- **Optional yt-dlp engine** for non-YouTube platforms and 1080p/4K merged
  downloads. It is a local program; the app just runs it on your machine.
- **Beautiful branded splash screen** on every platform.

See [`mobile/README.md`](mobile/README.md) for build instructions and details.

```bash
cd mobile
flutter pub get
flutter build apk --release       # Android
flutter build windows --release   # or linux / macos
```

---

## Legacy web deployment (not used by the app)

> The sections below describe the original Node/React server. The mobile app no
> longer uses it; it is kept for reference only.

An enterprise-grade download manager with real multi-connection, resumable
downloads, media support (yt-dlp), scheduling, checksums, and a modern
real-time UI.

## What makes it real

The download engine is a first-party implementation built on Node's `http`/`https`
modules. Nothing is simulated:

- **Multi-connection segmented downloads** — files are split into ranges and
  fetched in parallel, then merged and verified byte-for-byte.
- **True pause / resume** — active transfers are cancelled cleanly, partial
  progress is kept on disk, and resuming continues from the exact byte offset
  using HTTP `Range` requests.
- **Live progress** — byte counts, speed, ETA, and per-download state stream to
  the UI over Socket.IO in real time.
- **Persistence** — every download and setting is stored in SQLite, so the queue
  survives restarts and resumes automatically.
- **Media downloads** — optional yt-dlp integration for YouTube, SoundCloud,
  Vimeo, TikTok and hundreds more, with metadata preview and format selection.

## Features

### Speed
- Up to 32 connections per file, configurable globally or per download
- Parallel downloads with a configurable concurrency limit
- Bandwidth throttling (global token-bucket pacer)
- Automatic retry with exponential backoff
- Range support detection with graceful fallback to a single stream

### Management
- Persistent queue with drag-to-reorder priority
- Scheduling (start at a future time)
- Duplicate handling: skip / rename / overwrite
- Pause all, resume all, clear completed
- Search and filter by status
- Export / import the download list as JSON
- SHA-256 / SHA-1 / MD5 checksum verification

### Media
- Metadata preview (title, thumbnail, duration, uploader)
- Format selection before download
- Graceful degradation when yt-dlp is not installed

### UI
- Dark and light themes with four accent colours
- Live speed graph and session statistics
- Toast notifications (in-app and desktop)
- Responsive layout, keyboard-accessible controls, error boundaries

### Installable app (PWA)
- Installable on Android, iOS, Windows, macOS and Linux from the browser
- Standalone full-screen window with maskable icons and splash theming
- Offline shell: the interface loads and renders without a connection
- Home-screen shortcuts straight to *Add a download* or *Completed*
- Service worker keeps the shell cached and pushes updates on reload

### Security
- SSRF protection: private, loopback, link-local and metadata addresses are
  blocked, including across redirects
- Helmet security headers and API rate limiting
- Strict input validation and settings whitelisting

## Quick start

### Prerequisites
- Node.js 18+
- npm

### Install & run

```bash
git clone https://github.com/teejayfpi/turbo-downloader-enterprise.git
cd turbo-downloader-enterprise

npm run install:all   # root + server + client dependencies
npm run build         # build the client
npm start             # start the server (serves the built UI)
```

Open <http://localhost:3001>.

### Development

```bash
npm run dev   # server on :3001, Vite dev server on :5173 with proxy
```

### Optional: media downloads

Install `yt-dlp` (and `ffmpeg` for merging separate audio/video streams):

```bash
pipx install yt-dlp        # or: pip install -U yt-dlp
sudo apt-get install ffmpeg # Debian/Ubuntu
```

The server detects yt-dlp automatically at startup. Set `YT_DLP_PATH` to use a
specific binary. Media downloads are disabled cleanly when it is missing.

### YouTube on a hosted server

YouTube blocks video downloads from datacenter IPs — the same thing that
happens on Render, Fly, Railway and most cloud hosts. The symptoms are:

```
Sign in to confirm you're not a bot
unable to download video data: HTTP Error 403: Forbidden
```

Two independent things must both be true for a hosted YouTube download:

**1. yt-dlp needs a JavaScript runtime.** YouTube's signature challenges are
solved by the `yt-dlp-ejs` scripts running inside an external JS runtime. The
Docker image installs `yt-dlp[default]` and passes `--js-runtimes node`; set
`YT_DLP_JS_RUNTIME` to override. Without this, every media URL returns 403 no
matter what else you do. Confirm it took effect:

```bash
curl -s http://localhost:3001/health | jq .media
# { "available": true, "ffmpeg": true, "jsRuntime": "node" }
```

**2. The account must be signed in.** Even with a JS runtime, a datacenter IP
is treated as a bot until cookies prove a real session. Export them from a
browser that is **actually signed in to YouTube**:

```bash
YT_DLP_COOKIES=/path/to/cookies.txt        # or
YT_DLP_COOKIES_DATA="$(cat cookies.txt)"   # contents, for ephemeral filesystems
```

A cookie file that is missing `LOGIN_INFO` is not a signed-in YouTube session
and will not clear the gate. You can check before deploying:

```bash
grep -c LOGIN_INFO cookies.txt    # must be >= 1
```

Verify the session is live (a redirect to the sign-in page means it is not):

```bash
curl -s -b cookies.txt -o /dev/null -w '%{url_effective}\n' -L https://myaccount.google.com/
```

Use a throwaway account — cookies grant full access to that session. They also
expire, typically within weeks to months.

If both are in place and downloads still fail, the remaining causes are a
residential-connection requirement (self-host or use a residential proxy) or a
stale yt-dlp. Other platforms are not gated the same way: SoundCloud, Bandcamp,
Mixcloud, archive.org and Reddit generally work from cloud hosts without
cookies.

### Install it on your phone

Turbo is a PWA, so the hosted URL installs like a native app. The site must be
served over **HTTPS** (or `localhost`) for the browser to offer installation.

**Android (Chrome, Edge, Samsung Internet, Brave)**
1. Open the Turbo URL.
2. Tap the **Install** button in the header or the **Install Turbo** banner.
   If neither is shown, open the browser menu (⋮) and choose
   **Install app** / **Add to Home screen**.
3. Confirm — Turbo appears in the app drawer and opens full-screen.

**iPhone / iPad (Safari)**
1. Open the Turbo URL in Safari.
2. Tap **Share** → **Add to Home Screen** → **Add**.

**Desktop (Chrome / Edge)**
1. Click the install icon in the address bar, or use the header **Install**
   button.

The first load caches the app shell, so the interface opens instantly and still
renders when the phone is offline. Downloads themselves still need the server
reachable, since the files live on the server.

To verify installability locally:

```bash
cd client
npm run pwa:verify -- https://your-turbo-url   # SW state, manifest, caches
npm run mobile:check -- https://your-turbo-url # overflow at phone widths
```

### Device app (Android & desktop)

A native Flutter app lives in `mobile/`. It is a self-contained, offline-first
download manager: it downloads **on the device** (segmented, resumable, stored
in the device's Downloads folder) with no server, account, or key, and runs on
Android, Windows, Linux, and macOS. Build it with:

```bash
cd mobile && flutter pub get
flutter build apk --release        # Android APK
flutter build windows --release    # or linux / macos
```

See [`mobile/README.md`](mobile/README.md) for signing, file locations, and the
Play Store content-policy caveat for media downloaders.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Frontend — React 18 · Vite · TailwindCSS · Zustand · Socket.IO│
└──────────────────────────────────────────────────────────────┘
                             │  HTTP + WebSocket
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Backend — Node.js · Express 5 · Socket.IO · Helmet           │
│  ├─ downloadEngine.js  segmented HTTP engine + scheduler      │
│  ├─ mediaService.js    yt-dlp wrapper                         │
│  ├─ settingsManager.js validated, persisted settings          │
│  └─ database.js        SQLite (better-sqlite3, WAL)           │
└──────────────────────────────────────────────────────────────┘
                             │
                             ▼
        Real HTTP/HTTPS range requests → files on disk
```

## API reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/downloads` | List downloads |
| POST | `/api/downloads` | Add one (`url`) or many (`urls`) |
| GET | `/api/downloads/:id` | Get a single download |
| PUT | `/api/downloads/:id` | Update priority / format |
| DELETE | `/api/downloads/:id?deleteFile=true` | Remove entry (and file) |
| POST | `/api/downloads/:id/pause` | Pause |
| POST | `/api/downloads/:id/resume` | Resume |
| POST | `/api/downloads/:id/retry` | Retry a failed download |
| POST | `/api/downloads/:id/start` | Start a queued/scheduled download now |
| POST | `/api/downloads/pause-all` | Pause everything |
| POST | `/api/downloads/resume-all` | Resume everything |
| POST | `/api/downloads/clear-completed` | Remove completed entries |
| POST | `/api/downloads/reorder` | Reorder by `ids` array |
| GET | `/api/settings` | Get settings |
| PUT | `/api/settings` | Update settings (whitelisted keys) |
| POST | `/api/settings/reset` | Restore defaults |
| GET | `/api/stats` | Aggregate statistics |
| GET | `/api/system` | Runtime capabilities |
| GET | `/api/media/info?url=` | Media metadata |
| GET | `/api/media/supported` | yt-dlp availability |
| GET | `/api/export` | Export the download list |
| POST | `/api/import` | Import a download list |
| GET | `/health` | Health check |
| GET | `/api/docs` | Machine-readable endpoint list |

### Adding a download

```bash
curl -X POST http://localhost:3001/api/downloads \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "https://example.com/big.iso",
    "connections": 16,
    "checksum": "…",
    "checksumAlgo": "sha256",
    "scheduledAt": "2026-01-01T00:00:00Z"
  }'
```

## Configuration

Settings are validated and persisted in SQLite. Defaults:

| Key | Default | Range |
|-----|---------|-------|
| `connections` | 8 | 1–32 |
| `concurrentDownloads` | 3 | 1–10 |
| `split` | 8 | 1–32 |
| `defaultDir` | `~/TurboDownloads` | writable path |
| `duplicateHandling` | `rename` | skip / rename / overwrite |
| `bandwidthLimit` | 0 (unlimited) | 0–1,000,000 KB/s |
| `maxRetries` | 5 | 0–20 |
| `retryWait` | 5s | 0–600 |
| `theme` | `dark` | dark / light |
| `accentColor` | `cyan` | cyan / green / purple / orange |

Environment variables (see `server/.env.example`): `PORT`, `TURBO_DATA_DIR`,
`CORS_ORIGIN`, `YT_DLP_PATH`.

## Hosting / deployment

Turbo Downloader is a **long-running server with persistent state**, not a
static site or a serverless function. It needs two things anywhere you host it:

1. **A long-lived process** — a background download engine with timers and
   WebSockets. Serverless platforms (Vercel, Netlify, Cloudflare Workers, AWS
   Lambda) will not work: requests time out and there is no persistent disk.
2. **A persistent disk** — the SQLite database and the downloaded files must
   survive restarts and redeploys.

Anything that runs a Docker container with a mounted volume works well.

### Docker (any VPS, home server, NAS, or cloud VM)

The repo ships a `Dockerfile` and `docker-compose.yml` that bundle yt-dlp and
ffmpeg, so media downloads work with no extra setup.

```bash
docker compose up -d --build
# UI on http://localhost:3001, files in ./downloads, DB in the turbo-data volume
```

To expose it to the internet, put a reverse proxy (Caddy, Nginx, Traefik) in
front and terminate TLS there.

### Render (easiest managed option)

`render.yaml` is a ready-to-use blueprint. It provisions a Docker web service
with a persistent disk mounted at `/data`.

1. Push the repo to GitHub.
2. In Render: **New → Blueprint**, pick the repo, apply.
3. The service builds the image and deploys; health checks use `/health`.

Note: Render's free tier has no persistent disks — use the **Starter** plan (as
set in the blueprint) so the database and files persist.

### Fly.io

`fly.toml` is included.

```bash
fly launch --no-deploy
fly volumes create turbo_data --size 3
fly deploy
```

The volume is mounted at both `/data` (database) and `/downloads` (files).

### Railway / Heroku-style platforms

These build from a `Dockerfile` or `Procfile` and support volumes:

- **Railway**: New Project → Deploy from GitHub. Railway detects the
  `Dockerfile`. Add a volume mounted at `/data` and set `TURBO_DATA_DIR=/data`.
- **Heroku**: container-based dynos only; add a persistent store (e.g. a
  mounted volume is not available, so use S3-backed storage or a database
  add-on). Generally Render/Fly/Railway are a better fit.

### Environment variables for hosting

| Variable | Purpose | Example |
|----------|---------|---------|
| `PORT` | HTTP port | `3001` |
| `TURBO_DATA_DIR` | SQLite database directory | `/data` |
| `DOWNLOAD_DIR` | Default download folder | `/downloads` |
| `CORS_ORIGIN` | Allowed origin(s), or `*` | `https://app.example.com` |
| `TURBO_API_TOKEN` | Optional shared secret; locks `/api` and sockets | `a-long-random-string` |
| `YT_DLP_PATH` | Path to yt-dlp binary | `/usr/local/bin/yt-dlp` |

### Two things to plan for

- **Storage growth**: downloaded files accumulate. Mount a large enough disk and
  clean up from the UI, or point `DOWNLOAD_DIR` at a volume you manage.
- **Egress**: multi-connection downloads and media streams consume bandwidth.
  Check your provider's egress pricing before exposing it publicly.

### Security when hosting publicly

Turbo ships with an optional shared-secret gate. Set `TURBO_API_TOKEN` to a long
random string and every API call and socket connection must present it; the web
app and Android client prompt for it once and remember it. Leave it unset and
the server stays open, which is fine for a LAN or device-only setup.

For stronger protection, also put the app behind a reverse proxy with HTTP basic
auth, an SSO proxy (e.g. oauth2-proxy, Cloudflare Access), or a VPN/Tailscale,
and set `CORS_ORIGIN` to your real origin instead of `*`.

## Tech stack

- **Frontend**: React 18, Vite, TailwindCSS, Zustand, Socket.IO Client, Lucide
- **Backend**: Node.js, Express 5, Socket.IO, Helmet, express-rate-limit
- **Storage**: SQLite via better-sqlite3
- **Media**: yt-dlp + ffmpeg (optional)

## Security

See [`SECURITY.md`](SECURITY.md) for the full policy. In short: Turbo is
device-only, so nothing leaves the machine; credentials are held by the
platform's protected store; and a **Security** workflow (gitleaks secret scan,
dependency review, CodeQL) runs on every push and pull request and weekly on a
schedule.

## License

MIT — see [`LICENSE`](LICENSE).

---

<div align="center">
  <p><strong>Designed by Olatunji Ayobami Ayanlowo</strong></p>
  <p>
    <a href="mailto:ayanlowo89@gmail.com">ayanlowo89@gmail.com</a> ·
    <a href="tel:+2347038193753">+234 703 819 3753</a>
  </p>
  <p>Built for speed.</p>
</div>
