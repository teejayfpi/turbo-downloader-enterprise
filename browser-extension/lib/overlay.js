// Turbo Downloader — floating "Download this video" button.
//
// The defining IDM touch: a small button that appears over a video on the page,
// so a download is one click away without opening the popup. Clicking it hands
// the best captured stream for the tab to the Turbo app.
//
// The decision logic (which videos get a button, where it sits, what a click
// does) is kept pure and chrome-free so it runs under `node --test`; the DOM
// work that actually paints the button lives in [mountOverlay] and is the only
// part that needs a real page.

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TurboOverlay = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // A video smaller than this on either side is an icon, an ad pixel, or a
  // hidden element, not something a person would want to download.
  var MIN_SIZE = 120;

  /**
   * True when [rect] describes a real, visible video worth a button. A collapsed
   * or too-small element is skipped — a button floating over a 2px tracking
   * pixel would be worse than none.
   */
  function isDownloadableRect(rect) {
    if (!rect) return false;
    return rect.width >= MIN_SIZE && rect.height >= MIN_SIZE;
  }

  /**
   * Where to anchor the button for a video whose on-screen box is [rect].
   * Returns viewport coordinates for a fixed-position element: the button sits
   * in the top-left of the video, inset a little, the corner IDM uses.
   */
  function buttonPosition(rect) {
    return {
      left: Math.round(rect.left + 10),
      top: Math.round(rect.top + 10),
    };
  }

  /**
   * What a click should do, given the tab's captured streams and the page URL.
   *
   * With captures, the best quality is sent. Without any, the page is handed
   * over so the app can resolve the stream itself — the same fallback the popup
   * offers, so the button is never a dead end.
   */
  function decideAction(options, pageUrl) {
    if (options && options.length) {
      return { type: 'stream', option: options[0] };
    }
    if (pageUrl) return { type: 'page', url: pageUrl };
    return { type: 'none' };
  }

  /** True when the user has switched the floating button off. */
  function isEnabled(setting) {
    // Default on: the button is the point of the feature. An explicit `false`
    // (the user turned it off) is the only thing that hides it.
    return setting !== false;
  }

  var STYLE_ID = 'turbo-overlay-style';
  var CSS = [
    '.turbo-overlay-btn{position:fixed;z-index:2147483646;padding:6px 12px;',
    'border:0;border-radius:8px;background:#22e0ff;color:#04121a;',
    'font:700 12px/1.2 -apple-system,"Segoe UI",Roboto,sans-serif;cursor:pointer;',
    'box-shadow:0 2px 8px rgba(0,0,0,.35);opacity:.92;transition:opacity .15s,filter .15s;}',
    '.turbo-overlay-btn:hover{opacity:1;filter:brightness(1.08);}',
    '.turbo-overlay-btn:disabled{opacity:.7;cursor:default;}',
  ].join('');

  /** Injects the button stylesheet once per document. */
  function ensureStyles(doc) {
    if (!doc || !doc.head || doc.getElementById(STYLE_ID)) return;
    var style = doc.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    doc.head.appendChild(style);
  }

  /**
   * Paints a button over each eligible video and wires clicks.
   *
   * [deps] supplies the browser glue so the logic above stays testable:
   *   - listOptions(): Promise of the quality options captured for this tab
   *   - send(payload): Promise, hands {url, meta} to the app
   *   - pageUrl(): the current page URL
   *   - toast(text): brief user feedback
   *   - enabled(): whether the button should show
   */
  function mountOverlay(doc, deps) {
    if (!doc || !deps || !doc.body) return null;
    // The view is injectable so the module runs under `node --test`; in a real
    // page it is the window the document belongs to.
    var view = deps.window || (doc.defaultView || (typeof window !== 'undefined' ? window : null));
    if (!view) return null;
    ensureStyles(doc);
    var buttons = new Map();

    function place(video) {
      var rect = video.getBoundingClientRect ? video.getBoundingClientRect() : null;
      var button = buttons.get(video);
      if (!isDownloadableRect(rect)) {
        if (button) button.style.display = 'none';
        return;
      }
      if (!button) {
        button = doc.createElement('button');
        button.type = 'button';
        button.className = 'turbo-overlay-btn';
        button.textContent = 'Download';
        button.setAttribute('aria-label', 'Download this video with Turbo');
        button.addEventListener('click', function (event) {
          event.preventDefault();
          event.stopPropagation();
          onClick(button);
        });
        doc.body.appendChild(button);
        buttons.set(video, button);
      }
      // Fixed positioning in viewport coordinates, re-placed on scroll and
      // layout changes, keeps the button glued to the video however the page
      // reflows.
      var pos = buttonPosition(rect);
      button.style.display = 'block';
      button.style.left = pos.left + 'px';
      button.style.top = pos.top + 'px';
    }

    async function onClick(button) {
      button.disabled = true;
      button.textContent = 'Sending…';
      try {
        var options = await deps.listOptions();
        var action = decideAction(options, deps.pageUrl());
        if (action.type === 'stream') {
          var payload = deps.optionToPayload ? deps.optionToPayload(action.option) : null;
          if (payload) await deps.send(payload.url, payload.meta);
        } else if (action.type === 'page') {
          await deps.send(action.url, { kind: 'page' });
        } else {
          deps.toast('Play the video first, then try again');
          return;
        }
        deps.toast('Sent to Turbo');
      } catch (_) {
        deps.toast('Could not reach Turbo');
      } finally {
        button.disabled = false;
        button.textContent = 'Download';
      }
    }

    function refresh() {
      // Turning the button off must hide what is already painted, not just
      // stop painting new ones.
      if (!isEnabled(deps.enabled ? deps.enabled() : true)) {
        buttons.forEach(function (button) { button.style.display = 'none'; });
        return;
      }
      doc.querySelectorAll('video').forEach(place);
    }

    refresh();
    // Videos are added and resized as the page runs, so re-place on scroll and
    // on DOM changes. `passive` keeps scrolling smooth.
    view.addEventListener('scroll', refresh, { passive: true });
    view.addEventListener('resize', refresh, { passive: true });
    var observer = typeof MutationObserver === 'function'
      ? new MutationObserver(refresh)
      : null;
    if (observer) observer.observe(doc.body, { childList: true, subtree: true });

    return {
      refresh: refresh,
      destroy: function () {
        view.removeEventListener('scroll', refresh);
        view.removeEventListener('resize', refresh);
        if (observer) observer.disconnect();
        buttons.forEach(function (button) { button.remove(); });
        buttons.clear();
      },
    };
  }

  return {
    isDownloadableRect: isDownloadableRect,
    buttonPosition: buttonPosition,
    decideAction: decideAction,
    isEnabled: isEnabled,
    mountOverlay: mountOverlay,
    MIN_SIZE: MIN_SIZE,
  };
});
