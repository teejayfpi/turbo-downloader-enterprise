// Renders the SVG brand assets to PNGs at store/app-required sizes using
// headless Chromium. Run from client/:  node scripts/render-assets.mjs
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const clientDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const publicDir = path.join(clientDir, 'public');
const tmpDir = path.join(clientDir, '.asset-tmp');

const CHROME =
  process.env.CHROME_PATH ||
  ['/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'].find((p) => {
    try { return statSync(p).isFile(); } catch { return false; }
  });

if (!CHROME) {
  console.error('No Chromium binary found. Set CHROME_PATH.');
  process.exit(1);
}

// [source svg, width, height, output file]
const targets = [
  ['icon.svg', 512, 512, 'icon-512.png'],
  ['icon.svg', 192, 192, 'icon-192.png'],
  ['icon.svg', 180, 180, 'apple-touch-icon.png'],
  ['icon.svg', 48, 48, 'favicon-48.png'],
  ['icon.svg', 32, 32, 'favicon-32.png'],
  ['icon-maskable.svg', 512, 512, 'icon-maskable-512.png'],
  ['icon-maskable.svg', 192, 192, 'icon-maskable-192.png'],
  ['splash.svg', 1290, 2796, 'splash.png'],
];

mkdirSync(tmpDir, { recursive: true });

for (const [svg, w, h, out] of targets) {
  const html = `<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
img{display:block;width:${w}px;height:${h}px}</style>
<img src="${path.join(publicDir, svg)}">`;
  const htmlPath = path.join(tmpDir, `${out}.html`);
  writeFileSync(htmlPath, html);

  const res = spawnSync(
    CHROME,
    [
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      `--window-size=${w},${h}`,
      `--screenshot=${path.join(publicDir, out)}`,
      `file://${htmlPath}`,
    ],
    { stdio: 'inherit' }
  );
  if (res.status !== 0) {
    console.error(`Failed rendering ${out}`);
    process.exit(res.status ?? 1);
  }
  console.log(`✓ ${out}  (${w}x${h})`);
}

rmSync(tmpDir, { recursive: true, force: true });
console.log('\nAll assets rendered to public/.');
