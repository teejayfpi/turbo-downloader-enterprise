// Turbo Downloader — popup UI.
//
// Asks the active tab's content script what media/files it can see, lists them,
// and hands the chosen one to the Turbo app via the background worker.

const listEl = document.getElementById('list');
const countEl = document.getElementById('count');
const titleEl = document.getElementById('pageTitle');
const urlEl = document.getElementById('pageUrl');

let pageUrl = '';

function toast(text) {
  const el = document.getElementById('toast');
  el.textContent = text;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 1400);
}

function hostOf(url) {
  try { return new URL(url).hostname; } catch (_) { return ''; }
}

function send(url, meta) {
  chrome.runtime.sendMessage({ type: 'turbo:send', url, meta });
  toast('Sent to Turbo');
}

function render(items) {
  countEl.textContent = String(items.length);
  listEl.textContent = '';
  if (!items.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent =
      'No direct media found. Use “Send this page to Turbo” — Turbo will extract the stream on your device.';
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

function scan() {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs[0];
    if (!tab) return;
    pageUrl = tab.url || '';
    titleEl.textContent = tab.title || 'Untitled';
    urlEl.textContent = pageUrl;

    document.getElementById('sendPage').addEventListener('click', () => {
      send(pageUrl, { kind: 'page' });
    });

    chrome.tabs.sendMessage(tab.id, { type: 'turbo:detect' }, (resp) => {
      if (chrome.runtime.lastError || !resp) {
        // Content script not present (e.g. chrome:// pages).
        render([]);
        return;
      }
      if (resp.title) titleEl.textContent = resp.title;
      render(resp.items || []);
    });
  });
}

document.addEventListener('DOMContentLoaded', scan);
