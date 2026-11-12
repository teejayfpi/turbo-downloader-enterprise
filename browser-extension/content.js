// Turbo Downloader — content script.
//
// Scans the page for playable media and downloadable files: <video>/<audio>
// sources, HLS/DASH manifests exposed by the player, and links that point at a
// file extension. The result is reported to the popup (on demand) and to the
// background worker (as a count, for the badge). Nothing is downloaded here —
// Turbo does that on the user's device.
//
// It also mounts the floating "Download" button over each video (IDM-style), so
// a download is one click away without opening the popup.
//
// Detection lives in lib/detector.js and the button logic in lib/overlay.js
// (both loaded first, same isolated world) so the same code is unit-tested
// under `node --test`.

const detector = self.TurboDetector;
const overlay = self.TurboOverlay;

// The mounted overlay handle, kept so the toggle can re-place the buttons.
let overlayInstance = null;

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

/**
 * Asks the background worker for this tab's captured streams and turns them
 * into selectable quality options. Returns a promise so the overlay can await
 * the list at click time — a video may have been played after the button
 * appeared, so the freshest captures are what matter.
 */
function listQualityOptions() {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendMessage({ type: 'turbo:captured' }, (resp) => {
        if (chrome.runtime.lastError || !resp) {
          resolve([]);
          return;
        }
        const items = resp.items || [];
        resolve(self.TurboMediaWatch ? self.TurboMediaWatch.groupQualities(items) : []);
      });
    } catch (_) {
      resolve([]);
    }
  });
}

function mountButton() {
  if (!overlay) return;
  const watch = self.TurboMediaWatch;
  overlayInstance = overlay.mountOverlay(document, {
    enabled: () => window.__turboOverlayEnabled !== false,
    listOptions: listQualityOptions,
    optionToPayload: watch ? watch.optionToPayload : null,
    pageUrl: () => location.href,
    toast: () => {},
    send: (url, meta) =>
      new Promise((resolve) => {
        try {
          chrome.runtime.sendMessage({ type: 'turbo:send', url, meta }, () => {
            void chrome.runtime.lastError;
            resolve();
          });
        } catch (_) {
          resolve();
        }
      }),
  });
}

// The stored preference decides the initial state. Reading it before mounting
// avoids a flash of the button on every page load for a user who turned it off.
function start() {
  try {
    chrome.storage.local.get('overlayEnabled', ({ overlayEnabled }) => {
      window.__turboOverlayEnabled = overlayEnabled !== false;
      mountButton();
    });
  } catch (_) {
    mountButton();
  }
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
  } else if (msg && msg.type === 'turbo:overlayEnabled') {
    // Re-place at once so the button hides/shows without waiting for a scroll.
    window.__turboOverlayEnabled = msg.enabled !== false;
    if (overlayInstance) overlayInstance.refresh();
  }
  return true;
});

// Report a lightweight count so the badge can hint that media is present.
try {
  chrome.runtime.sendMessage({ type: 'turbo:found', count: scan().items.length });
} catch (_) {
  // ignore
}

// Mounted after the DOM is ready so `document.body` exists.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', start, { once: true });
} else {
  start();
}
