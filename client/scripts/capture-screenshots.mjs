// Captures PWA store screenshots (wide + narrow) from a running Turbo server.
// Usage: node scripts/capture-screenshots.mjs [baseUrl]
import { spawnSync } from 'node:child_process';
import { mkdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const clientDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(clientDir, 'public', 'screenshots');
const baseUrl = process.argv[2] || 'http://localhost:12000';

const CHROME =
  process.env.CHROME_PATH ||
  ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'].find((p) => {
    try { return statSync(p).isFile(); } catch { return false; }
  });

if (!CHROME) {
  console.error('No Chromium binary found. Set CHROME_PATH.');
  process.exit(1);
}

// [width, height, output] — matches the manifest's declared screenshot sizes.
const targets = [
  [1280, 720, 'app-wide.png'],
  [720, 1280, 'app-narrow.png'],
];

mkdirSync(outDir, { recursive: true });

for (const [w, h, out] of targets) {
  const res = spawnSync(
    CHROME,
    [
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--virtual-time-budget=6000',
      `--window-size=${w},${h}`,
      `--screenshot=${path.join(outDir, out)}`,
      `${baseUrl}/?splash=0`,
    ],
    { stdio: 'inherit' }
  );
  if (res.status !== 0) {
    console.error(`Failed capturing ${out}`);
    process.exit(res.status ?? 1);
  }
  console.log(`✓ screenshots/${out}  (${w}x${h})`);
}

console.log('\nScreenshots written to public/screenshots/.');
