// Mobile layout audit: checks for horizontal overflow and that key controls
// stay reachable at common phone widths.
import { spawn } from 'node:child_process';

const BASE = process.argv[2] || 'http://localhost:12000/';
const PORT = 9223;
const DEVICES = [
  { name: 'Pixel 7', width: 412, height: 915 },
  { name: 'iPhone SE', width: 375, height: 667 },
  { name: 'Galaxy S8', width: 360, height: 740 },
];

const chrome = spawn('/usr/bin/chromium', [
  '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
  `--remote-debugging-port=${PORT}`,
  '--user-data-dir=/tmp/turbo-layout-profile',
  'about:blank',
]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page?.webSocketDebuggerUrl) return page.webSocketDebuggerUrl;
    } catch { /* retry */ }
    await sleep(250);
  }
  throw new Error('no devtools endpoint');
}

function cdp(ws) {
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  });
  return (method, params = {}) => new Promise((res) => {
    const myId = ++id;
    pending.set(myId, res);
    ws.send(JSON.stringify({ id: myId, method, params }));
  });
}

async function evaluate(send, expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  return r.result?.result?.value;
}

(async () => {
  try {
    const ws = new WebSocket(await target());
    await new Promise((r) => ws.addEventListener('open', r));
    const send = cdp(ws);
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Emulation.setUserAgentOverride', {
      userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
    });

    for (const device of DEVICES) {
      await send('Emulation.setDeviceMetricsOverride', {
        width: device.width,
        height: device.height,
        deviceScaleFactor: 2,
        mobile: true,
      });
      await send('Page.navigate', { url: `${BASE}?splash=0` });
      await sleep(2500);

      const result = await evaluate(send, `(() => {
        const vw = document.documentElement.clientWidth;
        const overflow = document.documentElement.scrollWidth - vw;
        const visible = (sel) => {
          const el = document.querySelector(sel);
          if (!el) return false;
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.height > 0 && r.top < window.innerHeight;
        };
        return {
          viewport: vw,
          horizontalOverflowPx: overflow,
          headerVisible: visible('header'),
          urlBoxVisible: visible('textarea'),
          installBanner: Boolean(document.querySelector('[aria-label="Dismiss install prompt"]')),
          installButton: [...document.querySelectorAll('button')].some(b => /install/i.test(b.textContent)),
          settingsButton: Boolean(document.querySelector('[aria-label="Settings"]')),
          themeButton: Boolean(document.querySelector('[aria-label="Toggle theme"]')),
          cardCount: document.querySelectorAll('.rounded-xl').length,
        };
      })()`);

      console.log(`${device.name} (${device.width}px):`, JSON.stringify(result));
    }

    ws.close();
  } catch (error) {
    console.error('Layout audit failed:', error.message);
    process.exitCode = 1;
  } finally {
    chrome.kill();
  }
})();
