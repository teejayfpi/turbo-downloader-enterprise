// Turbo Downloader — content script.
//
// Scans the page for playable media and downloadable files: <video>/<audio>
// sources, HLS/DASH manifests (including blob/MSE players that expose their
// manifest via a JS property), and links that point at a file extension.
// The result is reported to the background worker, which the popup and the
// context menu use. Nothing is downloaded here — Turbo does that on the user's
// device.

const MEDIA_EXTENSIONS = [
  'mp4', 'm4v', 'mov', 'm3u8', 'mpd', 'webm', 'mkv', 'avi', 'flv', 'ts',
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus',
  'pdf', 'zip', 'rar', '7z', 'tar', 'gz', 'iso',
];

const EXT_RE = new RegExp(
  '\\.(' + MEDIA_EXTENSIONS.join('|') + ')([?#].*)?$',
  'i',
);

function fileNameFromUrl(url) {
  try {
    const u = new URL(url, location.href);
    const last = u.pathname.split('/').filter(Boolean).pop() || u.hostname;
    return decodeURIComponent(last);
  } catch (_) {
    return url;
  }
}

function kindFor(url, mime = '') {
  const lower = (url.split('?')[0] || '').toLowerCase();
  const ext = (lower.match(/\.([a-z0-9]+)$/) || [])[1] || '';
  if (mime.startsWith('video') || ['mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi', 'flv', 'ts'].includes(ext)) {
    return 'video';
  }
  if (mime.startsWith('audio') || ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'].includes(ext)) {
    return 'audio';
  }
  if (['m3u8', 'mpd'].includes(ext) || mime.includes('dash') || mime.includes('mpegurl')) {
    return 'stream';
  }
  return 'file';
}

function push(list, seen, url, kind, label) {
  if (!url || url.startsWith('data:') || url.startsWith('blob:')) return;
  if (seen.has(url)) return;
  seen.add(url);
  list.push({ url, kind: kind || kindFor(url), label: label || fileNameFromUrl(url) });
}

function detect() {
  const items = [];
  const seen = new Set();

  // 1. <video> / <audio> elements and their <source> children.
  document.querySelectorAll('video, audio').forEach((el) => {
    const mime = el.getAttribute('type') || '';
    if (el.currentSrc) push(items, seen, el.currentSrc, kindFor(el.currentSrc, mime), el.title || null);
    if (el.src) push(items, seen, el.src, kindFor(el.src, mime), el.title || null);
    el.querySelectorAll('source').forEach((s) => {
      push(items, seen, s.src, kindFor(s.src, s.getAttribute('type') || ''), el.title || null);
    });
    // MSE players (YouTube-style) keep the manifest on the element.
    ['hls', 'dash'].forEach((key) => {
      const ref = el[key];
      if (ref && ref.url) push(items, seen, ref.url, 'stream', el.title || 'stream');
    });
  });

  // 2. Links that clearly point at a downloadable file.
  document.querySelectorAll('a[href]').forEach((a) => {
    const href = a.href;
    if (!href || !EXT_RE.test(href)) return;
    push(items, seen, href, kindFor(href), a.textContent.trim() || null);
  });

  // 3. Explicit download links.
  document.querySelectorAll('a[download][href]').forEach((a) => {
    push(items, seen, a.href, kindFor(a.href), a.getAttribute('download') || null);
  });

  return items;
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'turbo:detect') {
    let items = [];
    try {
      items = detect();
    } catch (_) {
      items = [];
    }
    sendResponse({ pageUrl: location.href, title: document.title, items });
  }
  return true;
});

// Report a lightweight count so the badge can hint that media is present.
try {
  const items = detect();
  chrome.runtime.sendMessage({ type: 'turbo:found', count: items.length });
} catch (_) {
  // ignore
}
