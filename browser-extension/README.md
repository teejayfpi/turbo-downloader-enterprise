# Turbo — browser extension (media detector)

A Manifest V3 browser extension (Chrome / Edge / Brave) that detects media on
the page and hands it to the **Turbo** app, which downloads it on your device.

## What it detects

- `<video>` / `<audio>` elements and their `<source>` children
- HLS/DASH manifests a player exposes on a JS property (`video.hls.url`,
  `video.dash.url`, `video.manifest`, `video.streamUrl`, …)
- Links that point at a media or file extension (`.mp4`, `.m3u8`, `.mp3`,
  `.pdf`, `.zip`, …)
- Explicit `download` links

It does **not** download anything itself and does not upload anything. It only
reads the current page and passes a URL to the app.

### When there is no direct URL

A player that streams through Media Source Extensions — YouTube and most large
sites — serves fragments to a `blob:` URL and never puts a downloadable URL on
the page, so nothing can be listed. Detection reports this as `hiddenPlayer`
and the popup says so, steering you to **Send this page to Turbo**; the app then
resolves the stream from the page URL itself. Reading the manifest property only
works for players that happen to expose it; it is not a general YouTube
solution, and no fragment-scraping is attempted here.

## How the hand-off works

The primary path is a `POST` to the Turbo app's local API
(`http://127.0.0.1:3001/api/downloads`) — the same mechanism other download
manager extensions use. It confirms the app actually received the link and
needs no custom-scheme registration. If the app is not reachable, the extension
falls back to the `turbo://add?url=<encoded>` deep link, which launches (or
focuses) the app with the URL pre-filled. On Android you can also just use
**Share → Turbo**.

The popup also has **Send this page to Turbo**, which passes the page URL so the
app's own extractor resolves the stream — useful when the page hides the real
media URL.

## Install (unpacked, for now)

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select this `browser-extension/` folder.
4. Pin the Turbo icon to the toolbar.

**Select the folder that directly contains `manifest.json`.** That folder is
`browser-extension/` — it holds `manifest.json`, `background.js`, `content.js`,
`popup.html`, `popup.js` and `lib/`. Chrome reports *"Manifest file is missing or
unreadable"* if you point it somewhere else, most often at the Flutter app
bundle (`data/flutter_assets`, `lib/`, `turbo_downloader`) from a desktop
release, which is a different thing entirely.

### Loading a build from CI

The **Browser extension** workflow attaches ready-to-load builds under the
repository's **Actions** tab (open the latest run, scroll to **Artifacts**):

- `turbo-browser-extension` — Chrome / Edge / Brave
- `turbo-browser-extension-firefox` — Firefox

Download one and **extract it once**. GitHub always delivers an artifact as a
zip, so extracting gives you a folder whose top level is `manifest.json` — that
folder is the extension. Select it in **Load unpacked**.

> Do not select the folder you unzipped *to* if it merely contains another zip.
> If you see `turbo-browser-extension.zip` (or a nested folder) instead of
> `manifest.json`, you have not extracted the inner archive yet. Chrome reports
> *"Manifest file is missing or unreadable"* when the folder it is pointed at has
> no `manifest.json` directly inside it.

Store-ready zips (`turbo-browser-extension.zip`,
`turbo-browser-extension-firefox.zip`, and a `.sha256`) are attached separately
as the `turbo-browser-extension-store-zips` artifact.

### Edge

Edge is Chromium-based and uses the same Chrome build:

1. Open `edge://extensions`.
2. Turn on **Developer mode** (left sidebar).
3. Click **Load unpacked** and select the extracted Chrome folder.

The extension was tested on Edge 131 (detection and both hand-off paths).

## Permissions

The extension asks for the minimum it needs; store review rejects unused
permissions, so nothing is declared "just in case".

| Permission | Why |
| --- | --- |
| `activeTab` | Read the current tab's URL and title when you open the popup. Granted only on click. |
| `contextMenus` | The right-click "Send … to Turbo" entries. |
| `storage` | Remember the last hand-off so the popup can offer it for copying. |
| host access to `localhost` / `127.0.0.1` | POST to the Turbo app's local API. No other host access. |

It does **not** request `tabs` (no browsing history), `scripting`, `cookies`,
`downloads`, or `<all_urls>` host access.

## Firefox

`manifest.firefox.json` is the Firefox build: same code, with an add-on ID, a
`strict_min_version`, and the MV2-style `background.scripts` key Firefox still
requires in MV3. Build it by copying that file over `manifest.json` (the CI
`package` job does this and produces the Firefox zip). It lints clean with
`web-ext lint`.

## Using it

- Click the toolbar icon → the popup lists what it found → **Send** on any item.
- Or right-click the page / a link / a video → **Send … to Turbo**.

If nothing happens after **Send**, the `turbo://` scheme likely has no registered
handler (the app is not installed). The popup keeps the last hand-off under
**Last hand-off** with a **Copy** button, so you can paste the link into
Turbo → Add by hand.

## Why not send cookies from here

The hand-off is a `turbo://add?url=…` custom-scheme link. Cookies must not ride
in it: a custom-scheme URL is visible to the OS handler, other registered
handlers, and any log that records opened URLs, so a session token in the query
string is a disclosure with no way to take it back. Reading cookies also needs
the `cookies` permission, which the store review flags and which this extension
does not request.

Session-gated URLs are therefore handled by the app instead: paste the Cookie /
Authorization / Referer into the New Transfer options in the UI, and the server
sends them per download. If automatic cookie capture is ever wanted, it must go
over a POST body to the app's HTTP API, never through the deep link.

## Store submission

The code is store-grade: MV3, least-privilege permissions, correctly sized
icons (16/48/128), no remote code, and no data collection. To publish you still
need the listing assets the store requires, which are not code:

- 128×128 store icon (use `icons/icon-128.png`), 1–5 screenshots, a promo tile
- a privacy policy URL (the extension collects nothing and sends nothing off
  device, so this is short)
- a single-purpose statement: "add links to the Turbo download manager"

Chrome Web Store and Microsoft Edge Add-ons both take the Chrome zip; Firefox
Add-ons (AMO) takes the Firefox zip. `web-ext lint` is run in CI for the Firefox
build, and both zips are produced by the `package` job.
