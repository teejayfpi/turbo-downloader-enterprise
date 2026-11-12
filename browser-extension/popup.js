// Turbo Downloader — popup UI.
//
// Asks the active tab's content script what media/files it can see, lists them,
// and hands the chosen one to the Turbo app via the background worker. The
// background reports whether the app's local API accepted it or whether it fell
// back to the deep link; the last hand-off is also shown here for copying.

const listEl = document.getElementById('list');
const countEl = document.getElementById('count');
const capturedListEl = document.getElementById('capturedList');
const capturedCountEl = document.getElementById('capturedCount');
const titleEl = document.getElementById('pageTitle');
const urlEl = document.getElementById('pageUrl');
const fallbackEl = document.getElementById('fallback');
const fallbackLabelEl = document.getElementById('fallbackLabel');
const fallbackUrlEl = document.getElementById('fallbackUrl');

let pageUrl = '';
let tabId = null;

function toast(text) {
  const el = document.getElementById('toast');
  el.textContent = text;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 1600);
}

function hostOf(url) {
  try { return new URL(url).hostname; } catch (_) { return ''; }
}

function send(url, meta) {
  if (!url) return;
  chrome.runtime.sendMessage({ type: 'turbo:send', url, meta }, (resp) => {
    if (chrome.runtime.lastError || !resp) {
      toast('Could not reach Turbo');
    } else if (resp.via === 'api') {
      toast('Added to Turbo');
    } else {
      toast('Opening Turbo…');
    }
    showFallback();
  });
}

function showFallback() {
  chrome.storage.local.get('lastHandoff', ({ lastHandoff }) => {
    if (!lastHandoff || !lastHandoff.link) return;
    fallbackLabelEl.textContent = lastHandoff.link;
    fallbackUrlEl.textContent = 'turbo://add?url=' + encodeURIComponent(lastHandoff.link);
    fallbackEl.hidden = false;
  });
}

function render(items, hiddenPlayer) {
  countEl.textContent = String(items.length);
  listEl.textContent = '';
  if (!items.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = hiddenPlayer
      ? 'This player streams its media in fragments, so there is no direct file link. Use “Send this page to Turbo” — Turbo resolves the stream on your device.'
      : 'No direct media found. Use “Send this page to Turbo” — Turbo will extract the stream on your device.';
    listEl.appendChild(empty);
    return;
  }
  items.forEach((item) => {
    const row = document.createElement('div');
    row.className = 'item';

    const kind = document.createElement('div');
    kind.className = 'kind';
    kind.textContent = item.kind || 'file';

    const meta = document.createElement('div');
    meta.className = 'meta';
    const label = document.createElement('div');
    label.className = 'label';
    label.textContent = item.label || item.url;
    const host = document.createElement('div');
    host.className = 'host';
    host.textContent = hostOf(item.url);
    meta.append(label, host);

    const btn = document.createElement('button');
    btn.textContent = 'Send';
    btn.addEventListener('click', () => send(item.url, item));

    row.append(kind, meta, btn);
    listEl.appendChild(row);
  });
}

/**
 * Renders the quality options for this tab — the IDM-style picker. Each option
 * is one downloadable result (e.g. "1080p" or "Audio only"); pressing Send
 * hands over the stream(s) it needs, with the session headers that sign them.
 *
 * The list is derived from the requests the player actually made, so it offers
 * the qualities that were streamed rather than every quality the site holds.
 */
function renderCaptured(items) {
  const options = TurboMediaWatch.groupQualities(items);
  capturedCountEl.textContent = String(options.length);
  capturedListEl.textContent = '';
  if (!options.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent =
      'Nothing yet — play the video for a moment, then reopen this popup.';
    capturedListEl.appendChild(empty);
    return;
  }
  options.forEach((option) => {
    const row = document.createElement('div');
    row.className = 'item';

    const kind = document.createElement('div');
    kind.className = 'kind';
    kind.textContent = option.label;

    const meta = document.createElement('div');
    meta.className = 'meta';
    const label = document.createElement('div');
    label.className = 'label';
    label.textContent = option.needsMerge
      ? 'video + audio, merged on download'
      : option.kind === 'audio'
        ? 'audio track'
        : 'single file';
    const host = document.createElement('div');
    host.className = 'host';
    host.textContent = hostOf(option.streams[0].url);
    meta.append(label, host);

    const btn = document.createElement('button');
    btn.textContent = 'Send';
    btn.addEventListener('click', () => sendOption(option));

    row.append(kind, meta, btn);
    capturedListEl.appendChild(row);
  });
}

/** Hands a chosen quality option to the app. */
function sendOption(option) {
  const payload = TurboMediaWatch.optionToPayload(option);
  if (!payload) {
    toast('Nothing to send');
    return;
  }
  if (option.needsMerge) toast('Sending video + audio…');
  send(payload.url, payload.meta);
}

function scan() {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs[0];
    if (!tab) return;
    pageUrl = tab.url || '';
    tabId = tab.id;
    titleEl.textContent = tab.title || 'Untitled';
    urlEl.textContent = pageUrl;

    document.getElementById('sendPage').addEventListener('click', () => {
      send(pageUrl, { kind: 'page' });
    });

    document.getElementById('fallbackCopy').addEventListener('click', () => {
      const text = fallbackUrlEl.textContent;
      if (text) navigator.clipboard.writeText(text).then(() => toast('Copied'), () => {});
    });

    // The floating button's on/off switch. Persisted so the choice survives
    // reopening the popup, and pushed to the tab so the button reacts at once.
    const overlayToggle = document.getElementById('overlayToggle');
    chrome.storage.local.get('overlayEnabled', ({ overlayEnabled }) => {
      overlayToggle.checked = overlayEnabled !== false;
    });
    overlayToggle.addEventListener('change', () => {
      const enabled = overlayToggle.checked;
      chrome.storage.local.set({ overlayEnabled: enabled });
      chrome.tabs.sendMessage(tab.id, { type: 'turbo:overlayEnabled', enabled }).catch(() => {});
    });

    showFallback();

    chrome.runtime.sendMessage({ type: 'turbo:captured', tabId }, (resp) => {
      if (chrome.runtime.lastError || !resp) {
        renderCaptured([]);
        return;
      }
      renderCaptured(resp.items || []);
    });

    chrome.tabs.sendMessage(tab.id, { type: 'turbo:detect' }, (resp) => {
      if (chrome.runtime.lastError || !resp) {
        render([]);
        return;
      }
      if (resp.title) titleEl.textContent = resp.title;
      render(resp.items || [], resp.hiddenPlayer);
    });
  });
}

document.addEventListener('DOMContentLoaded', scan);
