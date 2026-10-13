// Unit tests for the media detection core, run with `node --test`.
//
// `detect()` takes any object exposing `querySelectorAll`, so these tests use a
// tiny DOM stub instead of a browser.

const test = require('node:test');
const assert = require('node:assert/strict');

const detector = require('../lib/detector.js');

/** Minimal element stub. */
function el(props = {}, sources = []) {
  const attrs = props.attrs || {};
  return {
    src: props.src,
    currentSrc: props.currentSrc,
    title: props.title,
    textContent: props.textContent || '',
    hls: props.hls,
    dash: props.dash,
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
    querySelectorAll: (sel) => (sel === 'source' ? sources : []),
  };
}

/** Minimal document stub: selector -> element list. */
function doc({ media = [], links = [], downloads = [] } = {}) {
  return {
    querySelectorAll(sel) {
      if (sel === 'video, audio') return media;
      if (sel === 'a[href]') return links;
      if (sel === 'a[download][href]') return downloads;
      return [];
    },
  };
}

test('reads a <video> src and labels it with the element title', () => {
  const items = detector.detect(doc({ media: [el({ src: 'https://h/movie.mp4', title: 'clip' })] }));
  assert.equal(items.length, 1);
  assert.deepEqual(items[0], { url: 'https://h/movie.mp4', kind: 'video', label: 'clip' });
});

test('reads <source> children', () => {
  const video = el({ title: 'v' }, [
    el({ src: 'https://h/a.webm', attrs: { type: 'video/webm' } }),
    el({ src: 'https://h/a.mp3' }),
  ]);
  const items = detector.detect(doc({ media: [video] }));
  assert.deepEqual(items.map((i) => i.kind), ['video', 'audio']);
});

test('an <audio> src is classified as audio', () => {
  const items = detector.detect(doc({ media: [el({ src: 'https://h/song.mp3' })] }));
  assert.equal(items[0].kind, 'audio');
});

test('a mime type wins over an extensionless URL', () => {
  const items = detector.detect(
    doc({ media: [el({ src: 'https://h/track', attrs: { type: 'audio/mpeg' } })] }),
  );
  assert.equal(items[0].kind, 'audio');
});

test('collects links by file extension and skips ordinary pages', () => {
  const items = detector.detect(
    doc({
      links: [
        { href: 'https://h/archive.zip', textContent: 'archive' },
        { href: 'https://h/stream/master.m3u8', textContent: 'hls' },
        { href: 'https://h/clip.mp4', textContent: '' },
        { href: 'https://h/readme.txt', textContent: 'plain' },
      ],
    }),
  );
  assert.deepEqual(items.map((i) => i.url), [
    'https://h/archive.zip',
    'https://h/stream/master.m3u8',
    'https://h/clip.mp4',
  ]);
  assert.deepEqual(items.map((i) => i.kind), ['file', 'stream', 'video']);
  assert.equal(items[0].label, 'archive');
  assert.equal(items[2].label, 'clip.mp4');
});

test('explicit download links are kept even without a media extension', () => {
  const items = detector.detect(
    doc({
      downloads: [
        {
          href: 'https://h/data.bin',
          getAttribute: () => 'my-file.bin',
        },
      ],
    }),
  );
  assert.equal(items.length, 1);
  assert.equal(items[0].url, 'https://h/data.bin');
  assert.equal(items[0].label, 'my-file.bin');
});

test('blob: and data: URLs are ignored', () => {
  const items = detector.detect(
    doc({
      media: [
        el({ currentSrc: 'blob:https://h/abc', src: 'blob:https://h/abc' }),
        el({ src: 'data:video/mp4;base64,AAAA' }),
      ],
    }),
  );
  assert.equal(items.length, 0);
});

test('a player manifest property (video.hls) is surfaced as a stream', () => {
  const items = detector.detect(
    doc({ media: [el({ currentSrc: 'blob:https://h/x', hls: { url: 'https://h/master.m3u8' }, title: 'live' })] }),
  );
  assert.equal(items.length, 1);
  assert.equal(items[0].kind, 'stream');
  assert.equal(items[0].url, 'https://h/master.m3u8');
});

test('duplicate URLs are reported once', () => {
  const items = detector.detect(
    doc({
      media: [el({ src: 'https://h/a.mp4' })],
      links: [{ href: 'https://h/a.mp4', textContent: 'again' }],
    }),
  );
  assert.equal(items.length, 1);
});

test('isMediaUrl anchors the extension at a URL boundary', () => {
  assert.equal(detector.isMediaUrl('https://h/report.zip.txt'), false);
  assert.equal(detector.isMediaUrl('https://h/a.mp4'), true);
  assert.equal(detector.isMediaUrl('https://h/play?file=x.mp4'), true);
  assert.equal(detector.isMediaUrl('https://h/a.mp4#t=10'), true);
  assert.equal(detector.isMediaUrl('https://h/page'), false);
});

test('detect tolerates a missing document', () => {
  assert.deepEqual(detector.detect(null), []);
});
