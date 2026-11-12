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

## Capturing a stream the page hides (IDM-style)

A player that streams through Media Source Extensions — YouTube and most large
sites — serves fragments to a `blob:` URL and never puts a downloadable URL on
the page, so DOM detection alone finds nothing. The background worker therefore
also watches the actual network requests the page makes and keeps the ones that
point at media: the signed `googlevideo.com/videoplayback` stream, an HLS
manifest, a progressive MP4.

That captured URL is the same one the browser is playing, and it is bound to
this machine's IP address (the signature is minted for the requester) and to the
session that signed it. So the capture is handed to the app together with the
`Cookie` / `Referer` / `Origin` / `Authorization` headers from the real request,
and the app fetches the bytes **from this machine** — the same footing IDM is
on. Two consequences follow:

- It only works against a Turbo server on **this** machine (`127.0.0.1`). A
  hosted Turbo instance has a different IP, so the signed URL is rejected; the
  extension never sends session headers to a non-loopback API for that reason.
- Play the video for a moment first. The capture only exists once the browser
  has requested the stream; open the popup afterwards and the stream is listed
  under **Download this video**.

### The floating Download button

As soon as a page has a real video, a small **Download** button appears in its
top-left corner — the IDM touch — so a download is one click away without
opening the popup. Clicking it sends the **best** captured quality for that tab;
if the video has not been played yet there is nothing captured, so it falls back
to handing the page URL over, exactly like **Send this page to Turbo**. The
button can be switched off with the toggle in the popup, and the choice is
remembered.

### Choosing a quality

The popup lists one row per downloadable result, best first — "1080p",
"720p", "Audio only" — rather than the raw capture list. Each picture row is
already paired with its own soundtrack, so pressing **Send** on "1080p"
downloads the picture *and* the sound and merges them.

The list is built from the requests the player actually made, so it offers the
qualities that were streamed, not every quality the site holds. To get a
different resolution, change it in the player, let it play a moment, then reopen
the popup.

### HD arrives as two streams, and they are merged

Above 360p YouTube does not serve one file: it sends the picture and the sound
as **separate** streams (DASH). That is why IDM sometimes hands you a silent
video. The popup pairs the two automatically — the "1080p" row carries the
picture and its matching sound — and the app downloads both and muxes them with
ffmpeg into a single file with sound.

Pairing is keyed on the video id and the `itag`: a video's picture and sound
share the same id and differ only in `itag`, so both are kept and matched. On a
page with several videos, each picture is paired only with its own sound. A
`muxed` capture (the old 360p `itag=18`) already has sound and is sent alone.
Merging needs **ffmpeg** on the Turbo server; without it the picture downloads
mute and the pairing has nothing to merge with.

Detection reports a page with a player but no direct URL as `hiddenPlayer`, and
the popup says so, steering you to the captured list or to **Send this page to
Turbo**.

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
| `webRequest` | Watch media requests so a hidden stream can be captured. Read-only: it observes headers, it does not block or rewrite anything. `extraHeaders` is passed to the listener so Chrome hands over `Cookie`/`Referer`; Firefox ignores it. |
| host access to `localhost` / `127.0.0.1` | POST to the Turbo app's local API. No other host access. |
| host access to `*.googlevideo.com` | The media CDN whose requests are captured. |
| content script on `http(s)://*` | Scans the page for media and paints the floating Download button. It reads the DOM and posts findings to the background worker; it never reads page form data or sends anything to a network. |

It does **not** request `tabs` (no browsing history), `scripting`, `cookies`, or
`downloads`. The only host access declared in `host_permissions` is the loopback
API and the one media CDN — the content script runs broadly so the button and
detection work anywhere, but it talks only to the background worker, which posts
solely to `127.0.0.1`.

## Firefox

`manifest.firefox.json` is the Firefox build: same code, with an add-on ID, a
`strict_min_version`, and the MV2-style `background.scripts` key Firefox still
requires in MV3. Build it by copying that file over `manifest.json` (the CI
`package` job does this and produces the Firefox zip). It lints clean with
`web-ext lint`.

## Using it

- A **Download** button appears over each video on the page → click it to send
  the best captured quality (or the page URL if nothing was captured yet).
- Click the toolbar icon → the popup lists the qualities it captured → **Send**
  on the one you want.
- Or right-click the page / a link / a video → **Send … to Turbo**.

If nothing happens after **Send**, the `turbo://` scheme likely has no registered
handler (the app is not installed). The popup keeps the last hand-off under
**Last hand-off** with a **Copy** button, so you can paste the link into
Turbo → Add by hand.

## How session headers are sent

The hand-off to a *remote* Turbo is still a `turbo://add?url=…` custom-scheme
link, and cookies must not ride in it: a custom-scheme URL is visible to the OS
handler, other registered handlers, and any log that records opened URLs, so a
session token in the query string is a disclosure with no way to take it back.

For a **local** Turbo, session headers travel in the POST body to the app's
HTTP API instead, which is the only place they belong. The capture forwards a
whitelisted set — `Cookie`, `Referer`, `Origin`, `Authorization` — and nothing
else; the server's `sanitizeHeaders()` drops anything unsafe. The extension only
attaches them when the API endpoint is loopback, never to a remote host, and
never writes them to `storage` or the deep link.

Pasted cookies also still work: the New Transfer options in the UI accept
Cookie / Authorization / Referer for a single download.

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
