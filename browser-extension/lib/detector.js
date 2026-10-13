// Turbo Downloader — media detection core.
//
// Framework-free and DOM-optional so it can run both inside the content script
// and under `node --test` with a tiny stub. `detect(doc)` takes any object that
// implements `querySelectorAll`, so tests pass a fake instead of a real page.

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TurboDetector = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var MEDIA_EXTENSIONS = [
    'mp4', 'm4v', 'mov', 'm3u8', 'mpd', 'webm', 'mkv', 'avi', 'flv', 'ts',
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus',
    'pdf', 'zip', 'rar', '7z', 'tar', 'gz', 'iso',
  ];

  var VIDEO_EXT = ['mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi', 'flv', 'ts'];
  var AUDIO_EXT = ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'];
  var STREAM_EXT = ['m3u8', 'mpd'];

  // Anchored at a path/query/fragment boundary so `…/report.zip.txt` does not
  // read as a `.zip`, and `?file=x.mp4` still does.
  var EXT_RE = new RegExp(
    '(?:^|[/?#&=\\.])(' + MEDIA_EXTENSIONS.join('|') + ')(?:[?#].*)?$',
    'i',
  );

  function extensionOf(url) {
    var lower = String(url).split('?')[0].split('#')[0].toLowerCase();
    return (lower.match(/\.([a-z0-9]+)$/) || [])[1] || '';
  }

  function fileNameFromUrl(url) {
    try {
      var u = new URL(url, 'http://localhost/');
      var last = u.pathname.split('/').filter(Boolean).pop() || u.hostname;
      return decodeURIComponent(last);
    } catch (_) {
      return url;
    }
  }

  function kindFor(url, mime) {
    mime = mime || '';
    var ext = extensionOf(url);
    if (mime.indexOf('video') === 0 || VIDEO_EXT.indexOf(ext) !== -1) return 'video';
    if (mime.indexOf('audio') === 0 || AUDIO_EXT.indexOf(ext) !== -1) return 'audio';
    if (STREAM_EXT.indexOf(ext) !== -1 || mime.indexOf('dash') !== -1 || mime.indexOf('mpegurl') !== -1) {
      return 'stream';
    }
    return 'file';
  }

  function isMediaUrl(url) {
    if (!url) return false;
    return EXT_RE.test(url);
  }

  function push(list, seen, url, kind, label) {
    if (!url) return;
    if (url.indexOf('data:') === 0 || url.indexOf('blob:') === 0) return;
    if (seen.has(url)) return;
    seen.add(url);
    list.push({
      url: url,
      kind: kind || kindFor(url),
      label: label || fileNameFromUrl(url),
    });
  }

  // A playable element can hide its source behind MSE: `currentSrc`/`src` are
  // `blob:` and the real manifest lives on a player property (`hls.url`). These
  // keys cover the common players; without one, the page has no direct URL and
  // the app must resolve the stream itself (the popup's "send page" path).
  var PLAYER_REF_KEYS = ['hls', 'dash', 'source', 'src', 'manifest', 'manifestUrl', 'streamUrl'];

  function playerRefs(el) {
    var out = [];
    if (!el) return out;
    PLAYER_REF_KEYS.forEach(function (key) {
      var ref = el[key];
      if (!ref) return;
      if (typeof ref === 'string') {
        if (ref.indexOf('http') === 0) out.push(ref);
      } else if (typeof ref.url === 'string' && ref.url.indexOf('http') === 0) {
        out.push(ref.url);
      }
    });
    return out;
  }

  function detect(doc) {
    doc = doc || (typeof document !== 'undefined' ? document : null);
    var items = [];
    var seen = new Set();
    if (!doc || typeof doc.querySelectorAll !== 'function') return items;

    doc.querySelectorAll('video, audio').forEach(function (el) {
      var mime = (el.getAttribute && el.getAttribute('type')) || '';
      var title = el.title || null;
      if (el.currentSrc) push(items, seen, el.currentSrc, kindFor(el.currentSrc, mime), title);
      if (el.src) push(items, seen, el.src, kindFor(el.src, mime), title);
      if (el.querySelectorAll) {
        el.querySelectorAll('source').forEach(function (s) {
          var type = (s.getAttribute && s.getAttribute('type')) || '';
          push(items, seen, s.src, kindFor(s.src, type), title);
        });
      }
      playerRefs(el).forEach(function (u) {
        push(items, seen, u, 'stream', title || 'stream');
      });
    });

    doc.querySelectorAll('a[href]').forEach(function (a) {
      if (!isMediaUrl(a.href)) return;
      push(items, seen, a.href, kindFor(a.href), (a.textContent || '').trim() || null);
    });

    doc.querySelectorAll('a[download][href]').forEach(function (a) {
      var name = a.getAttribute && a.getAttribute('download');
      push(items, seen, a.href, kindFor(a.href), name || null);
    });

    return items;
  }

  return {
    detect: detect,
    kindFor: kindFor,
    isMediaUrl: isMediaUrl,
    fileNameFromUrl: fileNameFromUrl,
    MEDIA_EXTENSIONS: MEDIA_EXTENSIONS,
  };
});
