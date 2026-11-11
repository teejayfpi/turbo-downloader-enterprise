// Unit tests for the media request capture core, run with `node --test`.
//
// The module is chrome-free by design, so everything here is a plain call. A
// real `googlevideo` request is modelled by the query shape YouTube uses.

const test = require('node:test');
const assert = require('node:assert/strict');

const watch = require('../lib/media-watch.js');

const VIDEO_URL =
  'https://rr3---sn-abc123.googlevideo.com/videoplayback' +
  '?expire=1700000000&id=o-AHxyz&itag=137&mn=sn-abc&mt=1700&range=0-1048575&rn=16';

test('isMediaHost matches the CDN and its subdomains, not a lookalike', () => {
  assert.equal(watch.isMediaHost('rr3---sn-abc.googlevideo.com'), true);
  assert.equal(watch.isMediaHost('googlevideo.com'), true);
  assert.equal(watch.isMediaHost('manifest.googlevideo.com'), true);
  // A host that merely contains the name must not match.
  assert.equal(watch.isMediaHost('googlevideo.com.evil.example'), false);
  assert.equal(watch.isMediaHost('notgooglevideo.com'), false);
  assert.equal(watch.isMediaHost('youtube.com'), false);
});

test('isMediaRequest captures a signed videoplayback GET', () => {
  assert.equal(watch.isMediaRequest(VIDEO_URL, 'GET'), true);
});

test('isMediaRequest rejects non-GET, non-http and beacon requests', () => {
  assert.equal(watch.isMediaRequest(VIDEO_URL, 'POST'), false);
  assert.equal(watch.isMediaRequest('blob:https://www.youtube.com/abc', 'GET'), false);
  assert.equal(watch.isMediaRequest('', 'GET'), false);
  // A stats beacon on the CDN is not media bytes.
  assert.equal(
    watch.isMediaRequest('https://rr3---sn-abc.googlevideo.com/api/stats/playback', 'GET'),
    false,
  );
});

test('isMediaRequest still recognises generic HLS/DASH paths', () => {
  assert.equal(watch.isMediaRequest('https://cdn.example.com/live/master.m3u8', 'GET'), true);
  assert.equal(watch.isMediaRequest('https://cdn.example.com/stream/manifest.mpd', 'GET'), true);
  assert.equal(watch.isMediaRequest('https://cdn.example.com/page.html', 'GET'), false);
});

test('pickSessionHeaders keeps only the session set, with canonical casing', () => {
  const out = watch.pickSessionHeaders([
    { name: 'Cookie', value: 'SID=abc; LOGIN_INFO=xyz' },
    { name: 'referer', value: 'https://www.youtube.com/watch?v=1' },
    { name: 'Origin', value: 'https://www.youtube.com' },
    { name: 'Authorization', value: 'Bearer t' },
    { name: 'Accept', value: '*/*' },
    { name: 'User-Agent', value: 'Mozilla/5.0' },
    { name: 'Range', value: 'bytes=0-1048575' },
  ]);
  assert.deepEqual(out, {
    Cookie: 'SID=abc; LOGIN_INFO=xyz',
    Referer: 'https://www.youtube.com/watch?v=1',
    Origin: 'https://www.youtube.com',
    Authorization: 'Bearer t',
  });
});

test('pickSessionHeaders tolerates a missing header list', () => {
  assert.deepEqual(watch.pickSessionHeaders(undefined), {});
  assert.deepEqual(watch.pickSessionHeaders(null), {});
  assert.deepEqual(watch.pickSessionHeaders([]), {});
});

test('normalizeMediaUrl drops the player byte-range and buffer hints', () => {
  const normalized = watch.normalizeMediaUrl(VIDEO_URL);
  assert.ok(!normalized.includes('range='), 'range removed');
  assert.ok(!normalized.includes('rn='), 'rn removed');
  // The signature params that make the URL valid are untouched.
  assert.ok(normalized.includes('id=o-AHxyz'));
  assert.ok(normalized.includes('itag=137'));
  assert.ok(normalized.includes('expire=1700000000'));
});

test('normalizeMediaUrl leaves a URL with no player params unchanged', () => {
  const url = 'https://cdn.example.com/video.mp4';
  assert.equal(watch.normalizeMediaUrl(url), url);
});

test('dedupeKey keys on the video id so a rotating signature is one entry', () => {
  const a = watch.dedupeKey(VIDEO_URL);
  const b = watch.dedupeKey(VIDEO_URL.replace('expire=1700000000', 'expire=1700009999'));
  assert.equal(a, b);
  // Two different videos stay distinct.
  const c = watch.dedupeKey(VIDEO_URL.replace('id=o-AHxyz', 'id=o-OTHER'));
  assert.notEqual(a, c);
});

test('dedupeKey falls back to origin+path without an id', () => {
  const a = watch.dedupeKey('https://cdn.example.com/a/stream.m3u8?token=1');
  const b = watch.dedupeKey('https://cdn.example.com/a/stream.m3u8?token=2');
  assert.equal(a, b);
});

test('toRecord carries the normalized URL and the session headers', () => {
  const record = watch.toRecord(
    { url: VIDEO_URL, tabId: 7 },
    { Cookie: 'SID=abc' },
  );
  assert.equal(record.tabId, 7);
  assert.equal(record.kind, 'video');
  assert.deepEqual(record.headers, { Cookie: 'SID=abc' });
  assert.ok(!record.url.includes('range='));
});

test('store dedupes a replayed video and keeps newest first', () => {
  const store = watch.createStore(3);
  store.add(watch.toRecord({ url: VIDEO_URL, tabId: 1 }, {}));
  store.add(watch.toRecord({ url: VIDEO_URL.replace('expire=1700000000', 'expire=9'), tabId: 1 }, {}));
  const list = store.list(1);
  assert.equal(list.length, 1, 'same video is one entry');
  assert.ok(list[0].url.includes('expire=9'), 'the refreshed URL wins');
});

test('store is bounded and isolated per tab', () => {
  const store = watch.createStore(2);
  store.add(watch.toRecord({ url: 'https://h/videoplayback?id=a', tabId: 1 }, {}));
  store.add(watch.toRecord({ url: 'https://h/videoplayback?id=b', tabId: 1 }, {}));
  store.add(watch.toRecord({ url: 'https://h/videoplayback?id=c', tabId: 1 }, {}));
  assert.equal(store.list(1).length, 2, 'capped at the limit');
  assert.deepEqual(store.list(2), [], 'another tab sees nothing');

  store.clear(1);
  assert.deepEqual(store.list(1), []);
});

test('classifyStream separates a DASH picture, a DASH sound and a muxed stream', () => {
  assert.equal(watch.classifyStream('https://h/videoplayback?id=x&itag=137'), 'video');
  assert.equal(watch.classifyStream('https://h/videoplayback?id=x&itag=140'), 'audio');
  assert.equal(watch.classifyStream('https://h/videoplayback?id=x&itag=18'), 'muxed');
  // A plain MP4 with a video mime is a picture stream; a manifest is neither.
  assert.equal(watch.classifyStream('https://cdn.example.com/a.mp4?mime=video/mp4'), 'video');
  assert.equal(watch.classifyStream('https://cdn.example.com/master.m3u8'), 'stream');
});

test('labelFor names the stream in human terms', () => {
  const video = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=137' }, {});
  const audio = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=140' }, {});
  const muxed = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=18' }, {});
  assert.equal(watch.labelFor(video), '1080p video');
  assert.equal(watch.labelFor(audio), 'audio');
  assert.equal(watch.labelFor(muxed), '360p (with sound)');
});

test('a picture and its sound are two records, not one', () => {
  const store = watch.createStore(10);
  store.add(watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=137', tabId: 1 }, {}));
  store.add(watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=140', tabId: 1 }, {}));
  assert.equal(store.list(1).length, 2, 'id+itag keeps the pair distinct');
});

test('planPair attaches the best sound track to a chosen picture stream', () => {
  const items = [
    watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=137' }, {}),
    watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=140' }, {}),
    watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=251' }, {}),
    watch.toRecord({ url: 'https://h/videoplayback?id=other&itag=140' }, {}),
  ];
  const plan = watch.planPair(items, items[0]);
  assert.equal(plan.needsMerge, true);
  assert.equal(plan.streams.length, 2);
  assert.equal(plan.streams[0].itag, 137, 'the picture stays first');
  assert.equal(plan.streams[1].itag, 251, 'the best audio of the same video is chosen');
});

test('planPair on an audio capture promotes a picture, and muxed needs no pair', () => {
  const video = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=136' }, {});
  const audio = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=140' }, {});
  const muxed = watch.toRecord({ url: 'https://h/videoplayback?id=y&itag=18' }, {});

  const fromAudio = watch.planPair([video, audio], audio);
  assert.equal(fromAudio.needsMerge, true);
  assert.equal(fromAudio.streams[0].itag, 136, 'the picture is placed first for the muxer');
  assert.equal(fromAudio.streams[1].itag, 140);

  const solo = watch.planPair([muxed], muxed);
  assert.equal(solo.needsMerge, false);
  assert.equal(solo.streams.length, 1);
});

test('planPair with no companion returns the chosen stream alone', () => {
  const video = watch.toRecord({ url: 'https://h/videoplayback?id=x&itag=137' }, {});
  const plan = watch.planPair([video], video);
  assert.equal(plan.needsMerge, false);
  assert.deepEqual(plan.streams, [video]);
});
