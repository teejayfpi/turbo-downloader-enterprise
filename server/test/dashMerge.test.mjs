import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { spawnSync } from 'child_process';

// Exercises the whole DASH path against a real local range-serving server and
// real ffmpeg: two synthetic streams (a picture-only MP4 and a sound-only M4A)
// are downloaded by the engine and merged, and the merged file is inspected to
// confirm it actually carries both a video and an audio track. A stub muxer
// would not catch the mistakes this test exists to catch — a wrong `-map`, a
// container that rejects the codec, or a merge that runs before both streams
// land on disk.

process.env.TURBO_ALLOW_PRIVATE_HOSTS = '1';
process.env.TURBO_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-dash-'));
process.env.DOWNLOAD_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-dash-dl-'));

const { engine, settingsManager } = await import('../context.js');
const mediaService = (await import('../mediaService.js')).default;

const ffmpegAvailable = spawnSync('ffmpeg', ['-version'], { encoding: 'utf8' }).status === 0;
const ffprobeAvailable = spawnSync('ffprobe', ['-version'], { encoding: 'utf8' }).status === 0;

/** Renders a short picture-only or sound-only clip into [file] with ffmpeg. */
function renderClip(file, args) {
  const result = spawnSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...args, file], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, `ffmpeg failed: ${result.stderr}`);
}

/** A server that serves [body] with real Range support, recording requests. */
function serveRange(body, ranges) {
  return http.createServer((req, res) => {
    const range = req.headers.range;
    if (range) {
      ranges.push(range);
      const m = /bytes=(\d+)-(\d*)/.exec(range);
      const start = Number(m[1]);
      const end = m[2] ? Number(m[2]) : body.length - 1;
      res.writeHead(206, {
        'Content-Type': 'application/octet-stream',
        'Content-Range': `bytes ${start}-${end}/${body.length}`,
        'Content-Length': end - start + 1,
        'Accept-Ranges': 'bytes',
      });
      res.end(body.subarray(start, end + 1));
    } else {
      res.writeHead(200, {
        'Content-Type': 'application/octet-stream',
        'Content-Length': body.length,
        'Accept-Ranges': 'bytes',
      });
      res.end(body);
    }
  });
}

async function waitFor(taskId) {
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const t = engine.tasks.get(taskId);
    if (t && ['completed', 'failed'].includes(t.status)) return t;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`timeout: ${engine.tasks.get(taskId)?.status}`);
}

test('dash: a picture and a sound stream are merged into one playable file', {
  skip: !(ffmpegAvailable && ffprobeAvailable && mediaService.hasFfmpeg()),
}, async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-dash-src-'));
  const videoFile = path.join(dir, 'v.mp4');
  const audioFile = path.join(dir, 'a.m4a');
  renderClip(videoFile, ['-f', 'lavfi', '-i', 'testsrc=size=128x72:rate=10:duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p']);
  renderClip(audioFile, ['-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-c:a', 'aac']);

  const videoBody = fs.readFileSync(videoFile);
  const audioBody = fs.readFileSync(audioFile);
  const videoRanges = [];
  const audioRanges = [];
  const videoServer = serveRange(videoBody, videoRanges);
  const audioServer = serveRange(audioBody, audioRanges);

  try {
    await new Promise((r) => videoServer.listen(0, '127.0.0.1', r));
    await new Promise((r) => audioServer.listen(0, '127.0.0.1', r));
    const videoUrl = `http://127.0.0.1:${videoServer.address().port}/video`;
    const audioUrl = `http://127.0.0.1:${audioServer.address().port}/audio`;

    settingsManager.updateSettings({ connections: 4, split: 4, bandwidthLimit: 0 });
    const [task] = await engine.add({
      urls: [videoUrl],
      options: { audioUrl, filename: 'merged.mp4' },
    });
    assert.equal(task.kind, 'dash', 'a paired download becomes a dash task');

    const done = await waitFor(task.id);
    assert.equal(done.status, 'completed', done.error || '');
    assert.ok(fs.existsSync(done.filepath), 'the merged file exists');

    // The merged file must carry exactly one video and one audio stream.
    const probe = spawnSync('ffprobe', [
      '-hide_banner', '-loglevel', 'error',
      '-show_entries', 'stream=codec_type',
      '-of', 'csv=p=0',
      done.filepath,
    ], { encoding: 'utf8' });
    const types = probe.stdout.trim().split('\n').filter(Boolean).sort();
    assert.deepEqual(types, ['audio', 'video'], `merged streams: ${probe.stdout}`);

    // Both sources were actually fetched, and each with byte ranges.
    assert.ok(videoRanges.length > 0, 'the picture stream was fetched');
    assert.ok(audioRanges.length > 0, 'the sound stream was fetched');

    // The fragments are cleaned up once the merge succeeds.
    assert.ok(!fs.existsSync(`${done.filepath}.turbo.video`), 'video fragment removed');
    assert.ok(!fs.existsSync(`${done.filepath}.turbo.audio`), 'audio fragment removed');
  } finally {
    videoServer.close();
    audioServer.close();
  }
});

test('dash: session headers reach both the picture and the sound request', {
  skip: !(ffmpegAvailable && ffprobeAvailable && mediaService.hasFfmpeg()),
}, async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-dash-hdr-'));
  const videoFile = path.join(dir, 'v.mp4');
  const audioFile = path.join(dir, 'a.m4a');
  renderClip(videoFile, ['-f', 'lavfi', '-i', 'testsrc=size=64x48:rate=10:duration=1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p']);
  renderClip(audioFile, ['-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-c:a', 'aac']);

  const seen = [];
  const make = (body, name) => http.createServer((req, res) => {
    seen.push({ name, cookie: req.headers.cookie || null });
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': body.length,
    });
    res.end(body);
  });

  const videoServer = make(fs.readFileSync(videoFile), 'video');
  const audioServer = make(fs.readFileSync(audioFile), 'audio');
  try {
    await new Promise((r) => videoServer.listen(0, '127.0.0.1', r));
    await new Promise((r) => audioServer.listen(0, '127.0.0.1', r));
    const videoUrl = `http://127.0.0.1:${videoServer.address().port}/video`;
    const audioUrl = `http://127.0.0.1:${audioServer.address().port}/audio`;

    const [task] = await engine.add({
      urls: [videoUrl],
      options: {
        audioUrl,
        filename: 'gated.mp4',
        headers: { Cookie: 'SID=video' },
        audioHeaders: { Cookie: 'SID=audio' },
      },
    });
    const done = await waitFor(task.id);
    assert.equal(done.status, 'completed', done.error || '');

    const videoHit = seen.find((s) => s.name === 'video');
    const audioHit = seen.find((s) => s.name === 'audio');
    assert.equal(videoHit?.cookie, 'SID=video', 'the picture request carried its cookie');
    assert.equal(audioHit?.cookie, 'SID=audio', 'the sound request carried its own cookie');
  } finally {
    videoServer.close();
    audioServer.close();
  }
});
