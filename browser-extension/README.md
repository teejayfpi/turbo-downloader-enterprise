# Turbo — browser extension (media detector)

A Manifest V3 browser extension (Chrome / Edge / Brave) that detects media on
the page and hands it to the **Turbo** app, which downloads it on your device.

## What it detects

- `<video>` / `<audio>` elements and their `<source>` children
- HLS/DASH manifests exposed by the player (`video.hls`, `video.dash`) — this
  covers blob/MSE players like YouTube
- Links that point at a media or file extension (`.mp4`, `.m3u8`, `.mp3`,
  `.pdf`, `.zip`, …)
- Explicit `download` links

It does **not** download anything itself and does not upload anything. It only
reads the current page and passes a URL to the app.

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

## Distribution note

Unpacked loading is fine for personal use. To publish on the Chrome Web Store
the extension needs store listing assets and review; the code here is already
MV3-compliant. Firefox uses the same sources but wants `background.scripts`
instead of `service_worker` — add a Firefox-specific `manifest.json` if you
target it.
