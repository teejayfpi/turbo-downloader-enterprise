// Turbo Downloader — background service worker.
//
// Owns the context menu, the media badge, and the hand-off. The primary path is
// a POST to the Turbo app's local HTTP API (`http://127.0.0.1:3001/api/downloads`),
// the same mechanism other download-manager extensions use: it confirms the app
// received the link and needs no custom-scheme registration. If the app is not
// reachable, it falls back to the `turbo://add?url=…` deep link (which launches
// the app on desktop/Android) and keeps the link for the popup to show as a
// copyable fallback.

const DEFAULT_API = 'http://127.0.0.1:3001';

// Chrome loads this file as a classic service worker, where a sibling script is
// pulled in with `importScripts`. Firefox lists it in `background.scripts`
// instead, so it is already defined there and this is skipped.
if (typeof importScripts === 'function' && !self.TurboMediaWatch) {
  importScripts('lib/media-watch.js');
}

const watch = self.TurboMediaWatch;
const store = watch.createStore(25);

/** Reads the user's API endpoint from storage, defaulting to loopback. */
async function apiBase() {
  const { apiBase } = await chrome.storage.local.get('apiBase');
  return (apiBase || DEFAULT_API).replace(/\/+$/, '');
}

/** True when [base] points at this machine, where a signed URL stays valid. */
function isLoopback(base) {
  try {
    const host = new URL(base).hostname;
    return host === '127.0.0.1' || host === 'localhost' || host === '::1';
  } catch (_) {
    return false;
  }
}

/**
 * POSTs one URL to the app's download queue. Resolves true only on success.
 *
 * Session headers (Cookie/Referer/Origin/Authorization) ride in the POST body
 * so the server can replay them when it fetches the media. They are only ever
 * sent to a loopback API: a signed media URL is bound to this machine's IP, and
 * shipping a session token to a remote host would both fail and disclose it.
 *
 * When the caller supplies a paired audio stream (a DASH picture capture), the
 * audio URL and its headers are sent too, and the server merges the two into a
 * single playable file.
 */
async function postToApi(url, meta) {
  const base = await apiBase();
  const loopback = isLoopback(base);
  const headers = meta && meta.headers && loopback ? meta.headers : undefined;
  const audio = meta && meta.audio && loopback ? meta.audio : undefined;
  const res = await fetch(`${base}/api/downloads`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      url,
      options: {
        ...(meta && meta.kind ? { kind: meta.kind } : {}),
        ...(headers ? { headers } : {}),
        ...(audio ? { audioUrl: audio.url, audioHeaders: audio.headers || {} } : {}),
      },
    }),
  });
  return res.ok;
}

/** Builds the deep-link hand-off that opens a link in the Turbo app. */
function handoffUrl(link) {
  return 'turbo://add?url=' + encodeURIComponent(link);
}

/** Opens the custom scheme; the transient tab is closed right after. */
function openDeepLink(link) {
  try {
    chrome.tabs.create({ url: handoffUrl(link), active: false }, (tab) => {
      if (tab && tab.id != null) {
        setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 1500);
      }
    });
  } catch (_) {
    // The popup exposes the last hand-off for manual copying.
  }
}

/**
 * Hands a link to the Turbo app: local API first, deep link as fallback.
 * The link is always stored so the popup can offer it for manual copying.
 *
 * Session headers are deliberately excluded from the stored record and from the
 * deep link: `chrome.storage.local` persists to disk and a `turbo://` URL is
 * visible to the OS handler and any URL log, so neither is a place for a
 * cookie. They only ever travel in the loopback POST body.
 */
async function sendToTurbo(link, meta) {
  if (!link) return { ok: false };
  const { headers, audio, ...safeMeta } = meta || {};
  // The paired audio carries its own session headers; strip them from the
  // stored record too, so no cookie reaches disk in either half.
  const record = {
    link,
    meta: audio ? { ...safeMeta, audio: { url: audio.url } } : safeMeta,
    at: Date.now(),
  };
  await chrome.storage.local.set({ lastHandoff: record });

  let viaApi = false;
  try {
    viaApi = await postToApi(link, meta);
  } catch (_) {
    viaApi = false;
  }
  if (!viaApi) openDeepLink(link);

  const result = { ok: true, via: viaApi ? 'api' : 'deeplink' };
  await chrome.storage.local.set({ lastHandoff: { ...record, via: result.via } });
  return result;
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'turbo-page',
    title: 'Send this page to Turbo',
    contexts: ['page'],
  });
  chrome.contextMenus.create({
    id: 'turbo-link',
    title: 'Send this link to Turbo',
    contexts: ['link'],
  });
  chrome.contextMenus.create({
    id: 'turbo-media',
    title: 'Send this media to Turbo',
    contexts: ['video', 'audio', 'image'],
  });
});

chrome.contextMenus.onClicked.addListener((info) => {
  const link = info.linkUrl || info.srcUrl || info.pageUrl;
  sendToTurbo(link, { source: info.menuItemId });
});

// ------------------------------------------------------------------ capture
//
// The IDM-style path. YouTube never puts a downloadable URL on the page (the
// player feeds fragments to a `blob:`), but it does make a real request for the
// signed `googlevideo.com/videoplayback` stream. Watching the request lets the
// extension see that URL and, with it, the `Cookie`/`Referer` that signed it.
// The pair is handed to the local Turbo server, which fetches the bytes from
// the same machine (and therefore the same IP the signature was minted for).
//
// `onBeforeSendHeaders` is used instead of `onCompleted` precisely so the
// request headers are available; only a whitelisted subset is kept.
//
// The filter is scoped to the Google video CDN so the extension needs host
// access to one family of hosts, not `<all_urls>`. `isMediaRequest` still
// understands generic HLS/DASH paths, so widening this list later is a one-line
// change if another site's host access is ever justified.
const CAPTURE_FILTER = {
  urls: ['*://*.googlevideo.com/*'],
  types: ['media', 'xmlhttprequest', 'other'],
};

chrome.webRequest.onBeforeSendHeaders.addListener(
  (details) => {
    if (!watch.isMediaRequest(details.url, details.method)) return;
    const headers = watch.pickSessionHeaders(details.requestHeaders);
    store.add(watch.toRecord(details, headers));
  },
  CAPTURE_FILTER,
  // `extraHeaders` is what makes Chrome hand over `Cookie`/`Referer`/`Origin`
  // to the listener; without it the callback sees only the safe-listed headers
  // and the capture has a URL but no session. Firefox ignores the extra flag.
  ['requestHeaders', 'extraHeaders'],
);

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg) return;
  if (msg.type === 'turbo:found') {
    const tabId = sender.tab && sender.tab.id;
    if (tabId != null) {
      chrome.action.setBadgeText({ tabId, text: msg.count ? String(msg.count) : '' });
      chrome.action.setBadgeBackgroundColor({ tabId, color: '#22E0FF' });
    }
  } else if (msg.type === 'turbo:captured') {
    // The popup asks for the streams seen on its tab; newest first.
    sendResponse({ items: store.list(msg.tabId) });
  } else if (msg.type === 'turbo:clearCaptured') {
    store.clear(msg.tabId);
    sendResponse({ ok: true });
  } else if (msg.type === 'turbo:send') {
    sendToTurbo(msg.url, msg.meta).then(sendResponse);
    return true; // keep the channel open for the async response
  }
});
