import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import { pinnedLookup } from '../utils.js';

// Regression guard: Node enables autoSelectFamily (Happy Eyeballs) by default
// and calls a custom `lookup` with `{ all: true }`, expecting an array. The
// single-address form makes net fail the connect with ERR_INVALID_IP_ADDRESS,
// which broke every direct download. The loopback engine test cannot catch this
// because TURBO_ALLOW_PRIVATE_HOSTS=1 disables pinning entirely.

test('pinnedLookup answers the { all: true } form with an array', (_, done) => {
  pinnedLookup('203.0.113.10')('example.com', { all: true }, (err, addresses) => {
    assert.ifError(err);
    assert.ok(Array.isArray(addresses), 'must be an array when all:true');
    assert.deepEqual(addresses, [{ address: '203.0.113.10', family: 4 }]);
    done();
  });
});

test('pinnedLookup keeps the single-answer form', (_, done) => {
  pinnedLookup('203.0.113.10')('example.com', {}, (err, address, family) => {
    assert.ifError(err);
    assert.equal(address, '203.0.113.10');
    assert.equal(family, 4);
    done();
  });
});

test('pinnedLookup reports the IPv6 family', (_, done) => {
  pinnedLookup('2001:db8::1')('example.com', { all: true }, (err, addresses) => {
    assert.ifError(err);
    assert.equal(addresses[0].family, 6);
    done();
  });
});

test('a pinned connection actually completes', async () => {
  const server = http.createServer((req, res) => res.end('pinned-ok'));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    const body = await new Promise((resolve, reject) => {
      const req = http.get(
        `http://127.0.0.1:${port}/`,
        { lookup: pinnedLookup('127.0.0.1') },
        (res) => {
          let data = '';
          res.on('data', (c) => { data += c; });
          res.on('end', () => resolve(data));
        },
      );
      req.on('error', reject);
    });
    assert.equal(body, 'pinned-ok');
  } finally {
    server.close();
  }
});
