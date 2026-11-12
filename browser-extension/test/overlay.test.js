// Unit tests for the floating download button, run with `node --test`.
//
// The decision logic (which videos qualify, where the button sits, what a click
// does) is pure, so it is tested directly. `mountOverlay` is exercised with a
// small DOM stub that records the buttons it creates, rather than a browser.

const test = require('node:test');
const assert = require('node:assert/strict');

const overlay = require('../lib/overlay.js');

/** Minimal element stub that records styles and children. */
function makeElement(tag) {
  return {
    tagName: tag,
    style: {},
    children: [],
    listeners: {},
    textContent: '',
    disabled: false,
    className: '',
    id: '',
    type: '',
    attrs: {},
    setAttribute(name, value) { this.attrs[name] = value; },
    addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); },
    appendChild(child) { this.children.push(child); return child; },
    remove() { this.removed = true; },
    click() { (this.listeners.click || []).forEach((fn) => fn({ preventDefault() {}, stopPropagation() {} })); },
  };
}

/** A document stub with a body, head, a set of videos and getElementById. */
function makeDoc(videos) {
  const head = makeElement('head');
  const body = makeElement('body');
  const byId = new Map();
  return {
    head,
    body,
    videos,
    defaultView: {
      addEventListener() {},
      removeEventListener() {},
    },
    createElement: makeElement,
    getElementById: (id) => byId.get(id) || null,
    querySelectorAll: (sel) => (sel === 'video' ? videos : []),
    _register: (el) => byId.set(el.id, el),
  };
}

/** A video stub whose on-screen box is [rect]. */
function makeVideo(rect) {
  return {
    getBoundingClientRect: () => rect,
  };
}

test('isDownloadableRect accepts a real video and rejects tiny or empty ones', () => {
  assert.equal(overlay.isDownloadableRect({ width: 640, height: 360, left: 0, top: 0 }), true);
  assert.equal(overlay.isDownloadableRect({ width: 100, height: 360, left: 0, top: 0 }), false);
  assert.equal(overlay.isDownloadableRect({ width: 640, height: 40, left: 0, top: 0 }), false);
  assert.equal(overlay.isDownloadableRect(null), false);
});

test('buttonPosition insets the button into the video top-left', () => {
  const pos = overlay.buttonPosition({ left: 100, top: 50, width: 640, height: 360 });
  assert.equal(pos.left, 110);
  assert.equal(pos.top, 60);
});

test('decideAction sends the best stream when captures exist', () => {
  const options = [{ label: '1080p', streams: [] }, { label: 'Audio only', streams: [] }];
  const action = overlay.decideAction(options, 'https://example.com/watch');
  assert.equal(action.type, 'stream');
  assert.equal(action.option.label, '1080p');
});

test('decideAction falls back to the page when nothing was captured', () => {
  const action = overlay.decideAction([], 'https://example.com/watch');
  assert.equal(action.type, 'page');
  assert.equal(action.url, 'https://example.com/watch');
});

test('decideAction reports nothing to do with neither streams nor a page', () => {
  assert.equal(overlay.decideAction([], '').type, 'none');
});

test('isEnabled defaults on and only an explicit false turns it off', () => {
  assert.equal(overlay.isEnabled(undefined), true);
  assert.equal(overlay.isEnabled(true), true);
  assert.equal(overlay.isEnabled(false), false);
});

test('mountOverlay paints a button over an eligible video', () => {
  const doc = makeDoc([makeVideo({ width: 640, height: 360, left: 20, top: 30 })]);
  const handle = overlay.mountOverlay(doc, {
    enabled: () => true,
    listOptions: async () => [],
    pageUrl: () => 'https://example.com',
    send: async () => {},
    toast: () => {},
  });

  const button = doc.body.children[0];
  assert.ok(button, 'a button was appended to the body');
  assert.equal(button.className, 'turbo-overlay-btn');
  assert.equal(button.style.display, 'block');
  assert.equal(button.style.left, '30px');
  assert.equal(button.style.top, '40px');
  handle.destroy();
});

test('mountOverlay skips a video too small to be real', () => {
  const doc = makeDoc([makeVideo({ width: 40, height: 20, left: 0, top: 0 })]);
  overlay.mountOverlay(doc, {
    enabled: () => true,
    listOptions: async () => [],
    pageUrl: () => 'https://example.com',
    send: async () => {},
    toast: () => {},
  });
  assert.equal(doc.body.children.length, 0, 'no button for a tiny video');
});

test('mountOverlay sends the best option when the button is clicked', async () => {
  const doc = makeDoc([makeVideo({ width: 640, height: 360, left: 0, top: 0 })]);
  const sent = [];
  const option = { label: '1080p', streams: [{ url: 'https://h/v?id=a&itag=137' }] };
  const handle = overlay.mountOverlay(doc, {
    enabled: () => true,
    listOptions: async () => [option],
    optionToPayload: (o) => ({ url: o.streams[0].url, meta: { kind: 'video' } }),
    pageUrl: () => 'https://example.com',
    send: async (url, meta) => sent.push({ url, meta }),
    toast: () => {},
  });

  await doc.body.children[0].click();
  // The click handler is async; let its microtasks settle.
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, 'https://h/v?id=a&itag=137');
  assert.equal(sent[0].meta.kind, 'video');
  handle.destroy();
});

test('mountOverlay falls back to the page when no stream was captured', async () => {
  const doc = makeDoc([makeVideo({ width: 640, height: 360, left: 0, top: 0 })]);
  const sent = [];
  const handle = overlay.mountOverlay(doc, {
    enabled: () => true,
    listOptions: async () => [],
    pageUrl: () => 'https://example.com/watch',
    send: async (url, meta) => sent.push({ url, meta }),
    toast: () => {},
  });

  await doc.body.children[0].click();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, 'https://example.com/watch');
  assert.equal(sent[0].meta.kind, 'page');
  handle.destroy();
});

test('mountOverlay hides painted buttons when the setting turns off', () => {
  const doc = makeDoc([makeVideo({ width: 640, height: 360, left: 0, top: 0 })]);
  let enabled = true;
  const handle = overlay.mountOverlay(doc, {
    enabled: () => enabled,
    listOptions: async () => [],
    pageUrl: () => 'https://example.com',
    send: async () => {},
    toast: () => {},
  });
  const button = doc.body.children[0];
  assert.equal(button.style.display, 'block');

  enabled = false;
  handle.refresh();
  assert.equal(button.style.display, 'none', 'turning it off hides the button');
  handle.destroy();
});

test('mountOverlay does nothing without a body', () => {
  assert.equal(overlay.mountOverlay({ head: makeElement('head') }, { enabled: () => true }), null);
});
