// Turbo Downloader — content script.
//
// Scans the page for playable media and downloadable files: <video>/<audio>
// sources, HLS/DASH manifests exposed by the player, and links that point at a
// file extension. The result is reported to the popup (on demand) and to the
// background worker (as a count, for the badge). Nothing is downloaded here —
// Turbo does that on the user's device.
//
// Detection lives in lib/detector.js (loaded first, same isolated world) so the
// same code is unit-tested under `node --test`.

const detector = self.TurboDetector;

function scan() {
  const items = detector ? detector.detect(document) : [];
  // When a player exists but no direct URL was found, the stream is hidden
  // behind MSE (`blob:`); the app has to resolve it from the page URL instead.
  const hiddenPlayer =
    items.length === 0 && document.querySelectorAll('video, audio').length > 0;
  return {
    pageUrl: location.href,
    title: document.title,
    items,
    hiddenPlayer,
  };
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'turbo:detect') {
    let result;
    try {
      result = scan();
    } catch (_) {
      result = { pageUrl: location.href, title: document.title, items: [], hiddenPlayer: false };
    }
    sendResponse(result);
  }
  return true;
});

// Report a lightweight count so the badge can hint that media is present.
try {
  chrome.runtime.sendMessage({ type: 'turbo:found', count: scan().items.length });
} catch (_) {
  // ignore
}
