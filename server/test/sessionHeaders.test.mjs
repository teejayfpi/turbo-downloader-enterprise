import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';

process.env.TURBO_ALLOW_PRIVATE_HOSTS = '1';
process.env.TURBO_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-hdr-'));
process.env.DOWNLOAD_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-hdr-dl-'));

const { sanitizeHeaders } = await import('../utils.js');
const { engine, settingsManager } = await import('../context.js');

test('sanitizeHeaders keeps session headers and drops dangerous ones', () => {
  const out = sanitizeHeaders({
    Cookie: 'session=abc; theme=dark',
    Referer: 'https://example.com/page',
    Authorization: 'Bearer xyz',
    'X-Api-Key': 'k',
  });
  assert.deepEqual(out, {
    Cookie: 'session=abc; theme=dark',
    Referer: 'https://example.com/page',
    Authorization: 'Bearer xyz',
    'X-Api-Key': 'k',
  });
});

test('sanitizeHeaders strips injection, reserved and junk', () => {
  const out = sanitizeHeaders({
    'X-Evil': 'a\r\nHost: attacker',
    Host: 'attacker',
    Range: 'bytes=0-1',
    'Accept-Encoding': 'gzip',
    'Content-Length': '10',
    'Bad Name': 'v',
    Empty: '',
    Good: 'ok',
  });
  // Only the clean header survives; CR/LF, reserved and invalid names are gone.
  assert.deepEqual(out, { Good: 'ok' });
});

test('sanitizeHeaders tolerates non-objects and caps size', () => {
  assert.deepEqual(sanitizeHeaders(null), {});
  assert.deepEqual(sanitizeHeaders('nope'), {});
  assert.deepEqual(sanitizeHeaders([]), {});
  const big = sanitizeHeaders({ X: 'a'.repeat(9000) });
  assert.deepEqual(big, {}, 'oversized value dropped');
  const many = sanitizeHeaders(Object.fromEntries(
    Array.from({ length: 100 }, (_, i) => [`X-${i}`, 'v']),
  ));
  assert.ok(Object.keys(many).length <= 32, 'header count capped');
});

async function runWithHeaders(server, headers, options = {}) {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  const [task] = await engine.add({
    urls: [`http://127.0.0.1:${port}/secret.bin`],
    options: { connections: 4, ...options, headers },
  });
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const t = engine.tasks.get(task.id);
    if (t && ['completed', 'failed'].includes(t.status)) return t;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error('timeout');
}

test('a gated download succeeds with the cookie and every chunk carries it', async () => {
  const body = crypto.randomBytes(12 * 1024 * 1024); // 12 MB -> several chunks
  const seenCookies = [];
  const server = http.createServer((req, res) => {
    if (req.headers.cookie !== 'session=s3cr3t') {
      res.writeHead(403);
      res.end('forbidden');
      return;
    }
    seenCookies.push(req.headers.cookie);
    const range = req.headers.range;
    if (range) {
      const m = /bytes=(\d+)-(\d*)/.exec(range);
      const start = Number(m[1]);
      const end = m[2] ? Number(m[2]) : body.length - 1;
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${body.length}`,
        'Content-Length': end - start + 1,
        'Accept-Ranges': 'bytes',
      });
      res.end(body.subarray(start, end + 1));
    } else {
      res.writeHead(200, { 'Content-Length': body.length, 'Accept-Ranges': 'bytes' });
      res.end(body);
    }
  });

  try {
    const task = await runWithHeaders(server, { Cookie: 'session=s3cr3t' });
    assert.equal(task.status, 'completed', task.error || '');
    const got = fs.readFileSync(task.filepath);
    assert.equal(
      crypto.createHash('sha256').update(got).digest('hex'),
      crypto.createHash('sha256').update(body).digest('hex'),
    );
    // The probe and every chunk request must have carried the session.
    assert.ok(seenCookies.length >= task._segments.length, 'all requests authenticated');
    assert.ok(task._segments.length > 1, 'multi-chunk download');
  } finally {
    server.close();
  }
});

test('without the cookie the gated download fails', async () => {
  const body = crypto.randomBytes(5 * 1024 * 1024);
  const server = http.createServer((req, res) => {
    if (req.headers.cookie !== 'session=s3cr3t') {
      res.writeHead(403);
      res.end('forbidden');
      return;
    }
    res.writeHead(200, { 'Content-Length': body.length, 'Accept-Ranges': 'bytes' });
    res.end(body);
  });
  try {
    // No retries: a 403 is retryable, but we only assert the failure surfaces.
    settingsManager.updateSettings({ maxRetries: 0 });
    const task = await runWithHeaders(server, undefined);
    assert.equal(task.status, 'failed');
    assert.notEqual(task.error, null);
  } finally {
    settingsManager.updateSettings({ maxRetries: 5 });
    server.close();
  }
});
