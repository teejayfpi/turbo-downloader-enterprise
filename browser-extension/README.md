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

Each item becomes a `turbo://add?url=<encoded>` link, which the Turbo app
registers as its custom protocol. Opening it launches (or focuses) the app with
that URL pre-filled. On Android you can also just use **Share → Turbo**.

The popup also has **Send this page to Turbo**, which passes the page URL so the
app's own extractor resolves the stream — useful when the page hides the real
media URL.

## Install (unpacked, for now)

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select this `browser-extension/` folder.
4. Pin the Turbo icon to the toolbar.

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

## Distribution note

Unpacked loading is fine for personal use. To publish on the Chrome Web Store
the extension needs store listing assets and review; the code here is already
MV3-compliant. Firefox uses the same sources but wants `background.scripts`
instead of `service_worker` — add a Firefox-specific `manifest.json` if you
target it.
