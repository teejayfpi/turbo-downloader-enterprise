// Turbo Downloader — media request capture core.
//
// Framework-free and chrome-free so it runs both inside the background service
// worker and under `node --test`. This is the IDM-style half of the extension:
// instead of reading the DOM (which YouTube hides behind `blob:`), it inspects
// the actual network requests the page makes and keeps the ones that point at a
// downloadable stream — the signed `googlevideo.com/videoplayback` URL, an HLS
// manifest, a progressive MP4.
//
// A captured URL is only useful together with the request headers that signed
// it: YouTube binds the media URL to the requesting IP and the `Cookie`/`Range`
// headers. Turbo's server sends those headers per download, so the capture
// carries a whitelisted subset (see [pickSessionHeaders]) to the local API.

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TurboMediaWatch = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Hosts whose requests are stream media. Matched on the registrable suffix so
  // `rr3---sn-abc.googlevideo.com` and `manifest.googlevideo.com` both hit.
  var MEDIA_HOST_SUFFIXES = [
    'googlevideo.com',   // YouTube / Google video CDN (signed videoplayback)
    'ytimg.com',         // thumbnails and some media
  ];

  // Path fragments that mark a request as a downloadable stream even when the
  // host is not on the list above.
  var STREAM_PATH_HINTS = ['/videoplayback', '/manifest', '/master.m3u8', '/playlist.m3u8'];

  // A request is only captured when it looks like media bytes rather than a
  // page, a stats beacon, or an ad. `videoplayback` is the canonical one.
  var MEDIA_PATH_RE = /(videoplayback|\.m3u8(\?|$)|\.mpd(\?|$)|\.mp4(\?|$)|\.webm(\?|$)|\.m4a(\?|$)|\.mp3(\?|$)|\.ts(\?|$))/i;

  // Headers worth forwarding to the server. Everything else is dropped: the
  // session is defined by Cookie/Referer/Origin/Authorization plus the client
  // identity, and a wide copy would leak unrelated request state. `Range` is
  // deliberately absent — the engine owns byte math and rejects a caller Range.
  var SESSION_HEADERS = ['cookie', 'referer', 'origin', 'authorization'];

  // YouTube serves HD as separate picture and sound streams (DASH), so one
  // video yields two requests. These tables tell them apart. A muxed itag is a
  // single file that already carries both, so it needs no pairing.
  var MUXED_ITAGS = { 17: 1, 18: 1, 22: 1, 36: 1, 59: 1, 78: 1 };
  var AUDIO_ITAGS = { 139: 1, 140: 1, 141: 1, 249: 1, 250: 1, 251: 1, 256: 1, 258: 1, 325: 1, 328: 1 };
  // Height per video itag, so the best picture can be chosen without probing.
  // Muxed itags are included so their label can still name the resolution.
  var VIDEO_HEIGHTS = {
    17: 144, 18: 360, 22: 720, 36: 240, 59: 480, 78: 480,
    160: 144, 278: 144, 133: 240, 242: 240, 134: 360, 243: 360,
    135: 480, 244: 480, 136: 720, 247: 720, 298: 720,
    137: 1080, 248: 1080, 299: 1080, 271: 1440, 308: 1440, 313: 2160, 315: 2160,
  };
  // Rough audio quality order for picking a soundtrack; higher is better.
  var AUDIO_RANK = { 139: 1, 140: 2, 141: 3, 249: 4, 250: 5, 251: 6, 256: 7, 258: 8, 325: 9, 328: 10 };

  function parseParams(url) {
    var out = {};
    try {
      var u = new URL(url);
      u.searchParams.forEach(function (value, key) { out[key.toLowerCase()] = value; });
    } catch (_) {
      /* leave empty */
    }
    return out;
  }

  /**
   * Classifies a media URL as `muxed` (video+sound in one file), `video`,
   * `audio`, or `stream` (an HLS/DASH manifest, which the server handles).
   *
   * The `itag` and `mime` params YouTube puts on a `videoplayback` URL are the
   * signal. A missing itag (a plain `.mp4`, a manifest) falls back to the mime
   * or to `stream`.
   */
  function classifyStream(url) {
    var params = parseParams(url);
    var itag = parseInt(params.itag, 10);
    var mime = (params.mime || '').toLowerCase();
    if (MUXED_ITAGS[itag]) return 'muxed';
    if (AUDIO_ITAGS[itag] || mime.indexOf('audio') === 0) return 'audio';
    if (mime.indexOf('video') === 0) return 'video';
    if (!isNaN(itag)) return 'video';
    return 'stream';
  }

  function hostOf(url) {
    try {
      return new URL(url).hostname.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  function pathOf(url) {
    try {
      return new URL(url).pathname + new URL(url).search;
    } catch (_) {
      return String(url || '');
    }
  }

  /** True when [host] is a known media CDN (matched on registrable suffix). */
  function isMediaHost(host) {
    host = String(host || '').toLowerCase();
    return MEDIA_HOST_SUFFIXES.some(function (suffix) {
      return host === suffix || host.endsWith('.' + suffix);
    });
  }

  /**
   * True when a request should be captured as a downloadable stream.
   *
   * The host check is the strong signal; the path hints catch self-hosted
   * players and HLS manifests served from an ordinary domain.
   */
  function isMediaRequest(url, method) {
    if (!url) return false;
    if (method && method.toUpperCase() !== 'GET') return false;
    var lower = String(url).toLowerCase();
    if (lower.indexOf('http') !== 0) return false;
    var host = hostOf(url);
    var path = pathOf(url);
    if (isMediaHost(host)) return MEDIA_PATH_RE.test(path) || path.indexOf('/videoplayback') !== -1;
    return STREAM_PATH_HINTS.some(function (hint) {
      return path.toLowerCase().indexOf(hint) !== -1;
    });
  }

  /**
   * Extracts the whitelisted session headers from a request's header list.
   * Chrome's `onBeforeSendHeaders` supplies `[{name, value}]`; this returns a
   * plain map the server's `sanitizeHeaders()` accepts. Values are never logged.
   */
  function pickSessionHeaders(headerList) {
    var out = {};
    if (!Array.isArray(headerList)) return out;
    headerList.forEach(function (h) {
      if (!h || !h.name) return;
      var name = String(h.name).toLowerCase();
      if (SESSION_HEADERS.indexOf(name) === -1) return;
      if (h.value == null) return;
      // Keep the original casing for a readable request; the server matches on
      // a lowercased name anyway.
      var display = name === 'cookie' ? 'Cookie'
        : name === 'referer' ? 'Referer'
        : name === 'origin' ? 'Origin'
        : 'Authorization';
      out[display] = String(h.value);
    });
    return out;
  }

  /**
   * Collapses a captured request into a stable, deduplicated record. Signed
   * `googlevideo` URLs carry a short-lived `expire`/`mn`/`mt` signature, so the
   * same stream yields a new URL each play; dedup is therefore keyed on the
   * stream identity (`id` + `itag`) rather than the full URL. The `itag` is
   * essential: a video's picture and sound tracks share the same `id` and
   * differ only in `itag`, so keying on `id` alone would collapse the pair into
   * one entry and lose the audio.
   */
  function toRecord(details, headers) {
    var url = normalizeMediaUrl(details && details.url);
    var params = parseParams(url);
    var kind = classifyStream(url);
    var itag = parseInt(params.itag, 10);
    return {
      key: dedupeKey(url),
      url: url,
      kind: kind,
      itag: isNaN(itag) ? null : itag,
      height: VIDEO_HEIGHTS[itag] || 0,
      audioRank: AUDIO_RANK[itag] || 0,
      videoId: params.id || null,
      headers: headers || {},
      tabId: details && details.tabId != null ? details.tabId : -1,
      at: Date.now(),
    };
  }

  // The player requests the stream in byte slices, so a captured URL often
  // carries a `range=` query param. The engine sets its own `Range` header for
  // multi-connection transfers, and a stale query param would pin the server to
  // that one slice, so it is removed. `rn`/`rbuf` are the player's buffer hints
  // and are meaningless to a fresh fetch.
  var DROP_QUERY_PARAMS = ['range', 'rn', 'rbuf'];

  /** Removes player-only query params so the URL describes the whole stream. */
  function normalizeMediaUrl(url) {
    if (!url) return url;
    try {
      var u = new URL(url);
      DROP_QUERY_PARAMS.forEach(function (p) { u.searchParams.delete(p); });
      return u.toString();
    } catch (_) {
      return url;
    }
  }

  /** The identity used to dedupe captures of the same stream (id + itag). */
  function dedupeKey(url) {
    try {
      var u = new URL(url);
      var id = u.searchParams.get('id');
      var itag = u.searchParams.get('itag');
      if (id) return u.hostname + ':' + id + ':' + (itag || '');
      return u.origin + u.pathname;
    } catch (_) {
      return String(url || '');
    }
  }

  /**
   * Chooses the streams needed to produce one playable file, given what the
   * user picked and everything captured for the tab.
   *
   * A `muxed` capture is already a complete file. A `video` capture is only the
   * picture, so its matching `audio` track (same `id`) is added — highest
   * quality first — and vice versa. The result tells the caller whether the
   * server must merge the two.
   */
  function planPair(items, chosen) {
    if (!chosen) return { streams: [], needsMerge: false };
    if (chosen.kind === 'muxed' || chosen.kind === 'stream') {
      return { streams: [chosen], needsMerge: false };
    }

    var wantAudio = chosen.kind === 'video';
    var candidates = (items || []).filter(function (item) {
      if (item === chosen || !chosen.videoId) return false;
      if (item.videoId !== chosen.videoId) return false;
      return wantAudio ? item.kind === 'audio' : item.kind === 'video';
    });

    if (!candidates.length) return { streams: [chosen], needsMerge: false };

    candidates.sort(function (a, b) {
      return wantAudio ? b.audioRank - a.audioRank : b.height - a.height;
    });
    var companion = candidates[0];

    // Video first: the server treats the first stream as the picture.
    var streams = wantAudio ? [chosen, companion] : [companion, chosen];
    return { streams: streams, needsMerge: true };
  }

  /**
   * A per-tab bounded store. Newest first, capped so a long session cannot grow
   * without limit. A repeated key refreshes the record (and its URL, since the
   * signature rotates) instead of adding a duplicate.
   */
  function createStore(limit) {
    var max = limit || 25;
    var byTab = new Map();

    return {
      add: function (record) {
        var list = byTab.get(record.tabId) || [];
        var index = -1;
        for (var i = 0; i < list.length; i++) {
          if (list[i].key === record.key) { index = i; break; }
        }
        if (index !== -1) list.splice(index, 1);
        list.unshift(record);
        if (list.length > max) list.length = max;
        byTab.set(record.tabId, list);
        return record;
      },
      list: function (tabId) {
        return (byTab.get(tabId) || []).slice();
      },
      clear: function (tabId) {
        byTab.delete(tabId);
      },
    };
  }

  /** A short human label for a capture, e.g. "1080p video" or "audio". */
  function labelFor(record) {
    if (record.kind === 'audio') return record.audioRank >= 4 ? 'high-quality audio' : 'audio';
    if (record.kind === 'video') return record.height ? record.height + 'p video' : 'video';
    if (record.kind === 'muxed') return record.height ? record.height + 'p (with sound)' : 'video (with sound)';
    return 'stream';
  }

  return {
    isMediaHost: isMediaHost,
    isMediaRequest: isMediaRequest,
    pickSessionHeaders: pickSessionHeaders,
    classifyStream: classifyStream,
    labelFor: labelFor,
    planPair: planPair,
    toRecord: toRecord,
    normalizeMediaUrl: normalizeMediaUrl,
    dedupeKey: dedupeKey,
    createStore: createStore,
    MEDIA_HOST_SUFFIXES: MEDIA_HOST_SUFFIXES,
    SESSION_HEADERS: SESSION_HEADERS,
  };
});
