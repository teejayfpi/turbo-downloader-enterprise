// Ad-hoc PWA verification over the Chrome DevTools Protocol.
// Loads the app, waits for the service worker to activate, then reports state.
import { spawn } from 'node:child_process';

const URL_TO_TEST = process.argv[2] || 'http://localhost:12000/';
const PORT = 9222;

const chrome = spawn('/usr/bin/chromium', [
  '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
  `--remote-debugging-port=${PORT}`,
  '--user-data-dir=/tmp/pwa-verify-profile',
  'about:blank',
]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getTarget() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
      const list = await res.json();
      const page = list.find((t) => t.type === 'page');
      if (page?.webSocketDebuggerUrl) return page.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(250);
  }
  throw new Error('Could not reach Chrome DevTools endpoint');
}

function cdp(ws) {
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  });
  return (method, params = {}) =>
    new Promise((resolve) => {
      const myId = ++id;
      pending.set(myId, resolve);
      ws.send(JSON.stringify({ id: myId, method, params }));
    });
}

async function evaluate(send, expression) {
  const res = await send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (res.result?.exceptionDetails) return { error: res.result.exceptionDetails.text };
  return res.result?.result?.value;
}

(async () => {
  try {
    const wsUrl = await getTarget();
    const ws = new WebSocket(wsUrl);
    await new Promise((r) => ws.addEventListener('open', r));
    const send = cdp(ws);
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Page.navigate', { url: URL_TO_TEST });
    await sleep(4000);

    const report = await evaluate(send, `(async () => {
      const reg = await navigator.serviceWorker.ready.catch(() => null);
      const manifestLink = document.querySelector('link[rel=manifest]');
      const manifest = manifestLink ? await fetch(manifestLink.href).then(r => r.json()).catch(() => null) : null;
      const swRes = await fetch('/sw.js');
      const cacheNames = await caches.keys();
      const cached = {};
      for (const name of cacheNames) {
        const keys = await (await caches.open(name)).keys();
        cached[name] = keys.map(r => new URL(r.url).pathname).sort();
      }
      return {
        controller: Boolean(navigator.serviceWorker.controller),
        activeState: reg?.active?.state || null,
        manifestOk: Boolean(manifest),
        manifestName: manifest?.name || null,
        display: manifest?.display || null,
        iconCount: manifest?.icons?.length || 0,
        hasMaskable: Boolean(manifest?.icons?.some(i => (i.purpose||'').includes('maskable'))),
        screenshots: manifest?.screenshots?.length || 0,
        shortcuts: manifest?.shortcuts?.length || 0,
        swStatus: swRes.status,
        swType: swRes.headers.get('content-type'),
        installButtonVisible: [...document.querySelectorAll('button')].some(b => /install/i.test(b.textContent)),
        cacheNames,
        cached,
      };
    })()`);

    console.log(JSON.stringify(report, null, 2));

    // Phase 2: go offline and confirm the cached shell still renders.
    await send('Network.enable');
    await send('Network.emulateNetworkConditions', {
      offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0,
    });
    await send('Page.navigate', { url: URL_TO_TEST });
    await sleep(3000);

    const offline = await evaluate(send, `({
      title: document.title,
      hasRoot: Boolean(document.getElementById('root')),
      bodyText: document.body.innerText.slice(0, 60),
      rendered: document.body.innerText.includes('TURBO'),
    })`);
    console.log('\\nOffline fallback:', JSON.stringify(offline, null, 2));

    ws.close();
  } catch (error) {
    console.error('Verification failed:', error.message);
    process.exitCode = 1;
  } finally {
    chrome.kill();
  }
})();
