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

/** Reads the user's API endpoint from storage, defaulting to loopback. */
async function apiBase() {
  const { apiBase } = await chrome.storage.local.get('apiBase');
  return (apiBase || DEFAULT_API).replace(/\/+$/, '');
}

/** POSTs one URL to the app's download queue. Resolves true only on success. */
async function postToApi(url, meta) {
  const res = await fetch(`${await apiBase()}/api/downloads`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ url, options: meta && meta.kind ? { kind: meta.kind } : {} }),
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
 */
async function sendToTurbo(link, meta) {
  if (!link) return { ok: false };
  const record = { link, meta, at: Date.now() };
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

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg) return;
  if (msg.type === 'turbo:found') {
    const tabId = sender.tab && sender.tab.id;
    if (tabId != null) {
      chrome.action.setBadgeText({ tabId, text: msg.count ? String(msg.count) : '' });
      chrome.action.setBadgeBackgroundColor({ tabId, color: '#22E0FF' });
    }
  } else if (msg.type === 'turbo:send') {
    sendToTurbo(msg.url, msg.meta).then(sendResponse);
    return true; // keep the channel open for the async response
  }
});
