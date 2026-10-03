// Turbo Downloader — background service worker.
//
// Owns the context menu, the media badge, and the actual hand-off: it opens the
// detected link in the Turbo app via the `turbo://add?url=…` custom scheme. The
// app receives it through its deep-link inbox and downloads on the device.

const MENU_ID = 'turbo-send';

/** Builds the hand-off URL that opens a link in the Turbo app. */
function handoffUrl(link) {
  return 'turbo://add?url=' + encodeURIComponent(link);
}

/**
 * Hands a link to the Turbo app. Opening the custom scheme is what launches
 * (or focuses) the desktop/Android app; the transient tab is closed right after.
 * If no handler is registered the open silently fails, so the link is also
 * kept in storage for the popup to show as a copyable fallback.
 */
function sendToTurbo(link, meta) {
  if (!link) return;
  chrome.storage.local.set({ lastHandoff: { link, meta, at: Date.now() } });
  const url = handoffUrl(link);
  try {
    chrome.tabs.create({ url, active: false }, (tab) => {
      if (tab && tab.id != null) {
        setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 1500);
      }
    });
  } catch (_) {
    // Fall through: the popup exposes the last hand-off for manual copying.
  }
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
    sendToTurbo(msg.url, msg.meta);
    sendResponse({ ok: true });
  }
});
