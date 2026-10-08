import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';

// Exercises the real engine against a real (local) range-serving server that
// records every Range header. This is the only way to observe the dynamic
// scheduler: the loopback SSRF pin is disabled here via the allow flag, which
// is also why the separate pinnedLookup test exists.

process.env.TURBO_ALLOW_PRIVATE_HOSTS = '1';
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-chunk-'));
process.env.TURBO_DATA_DIR = dataDir;
process.env.DOWNLOAD_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-dl-'));

const { engine } = await import('../context.js');
const settingsManager = (await import('../context.js')).settingsManager;

function makeServer() {
  const body = crypto.randomBytes(20 * 1024 * 1024); // 20 MB, incompressible
  const ranges = [];
  const server = http.createServer((req, res) => {
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
  return { server, body, ranges };
}

async function runTask(server, options = {}) {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/big.bin`;
  const [task] = await engine.add({ urls: [url], options });
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const t = engine.tasks.get(task.id);
    if (t && ['completed', 'failed'].includes(t.status)) return t;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`timeout: ${engine.tasks.get(task.id)?.status}`);
}

test('dynamic scheduler: byte-exact output, more chunks than workers', async () => {
  const { server, body, ranges } = makeServer();
  try {
    settingsManager.updateSettings({ connections: 4, split: 4, bandwidthLimit: 0 });
    const task = await runTask(server, { connections: 4 });
    assert.equal(task.status, 'completed', task.error || '');
    assert.equal(task.downloaded, body.length);

    const got = fs.readFileSync(task.filepath);
    assert.equal(got.length, body.length);
    assert.equal(
      crypto.createHash('sha256').update(got).digest('hex'),
      crypto.createHash('sha256').update(body).digest('hex'),
      'downloaded bytes must match the source exactly',
    );

    // Proof of work-stealing: a 20 MB file at 4 workers must issue far more
    // range requests than there are workers (one per chunk, many chunks).
    assert.ok(task._segments.length > 4, `chunk grid should exceed workers, got ${task._segments.length}`);
    assert.ok(
      ranges.length >= task._segments.length,
      `expected a range request per chunk, got ${ranges.length} for ${task._segments.length} chunks`,
    );

    // Part files and the plan must be cleaned up.
    const leftovers = fs.readdirSync(path.dirname(task.filepath))
      .filter((f) => f.includes('.turbo.part') || f.endsWith('.turbo.plan'));
    assert.deepEqual(leftovers, [], 'no part files or plan should remain');
  } finally {
    server.close();
  }
});

test('single worker still completes correctly', async () => {
  const { server, body } = makeServer();
  try {
    settingsManager.updateSettings({ connections: 1, split: 1 });
    const task = await runTask(server, { connections: 1 });
    assert.equal(task.status, 'completed', task.error || '');
    const got = fs.readFileSync(task.filepath);
    assert.equal(
      crypto.createHash('sha256').update(got).digest('hex'),
      crypto.createHash('sha256').update(body).digest('hex'),
    );
  } finally {
    server.close();
  }
});
