/*
 * Turbo service worker.
 *
 * Purpose: make the app installable (Chrome/Android requires a service worker
 * with a fetch handler) and keep the shell usable when the network drops.
 *
 * Caching rules:
 *   - navigations  : network-first, fall back to the cached shell when offline
 *   - /assets/*    : cache-first (Vite fingerprints these, so they never change)
 *   - icons/static : stale-while-revalidate
 *   - /api, socket : never cached — downloads are live state, not shell content
 */

const VERSION = 'v1';
const SHELL_CACHE = `turbo-shell-${VERSION}`;
const ASSET_CACHE = `turbo-assets-${VERSION}`;
const STATIC_CACHE = `turbo-static-${VERSION}`;
const KEEP = [SHELL_CACHE, ASSET_CACHE, STATIC_CACHE];

const SHELL_URLS = ['/', '/index.html', '/manifest.webmanifest'];
const STATIC_URLS = [
  '/icon.svg',
  '/icon-192.png',
  '/icon-512.png',
  '/icon-maskable-192.png',
  '/icon-maskable-512.png',
  '/apple-touch-icon.png',
  '/favicon-32.png',
  '/favicon-48.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const shell = await caches.open(SHELL_CACHE);
      // Individual adds so one bad URL cannot fail the whole install.
      await Promise.allSettled(SHELL_URLS.map((url) => shell.add(url)));
      const statics = await caches.open(STATIC_CACHE);
      await Promise.allSettled(STATIC_URLS.map((url) => statics.add(url)));
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => !KEEP.includes(k)).map((k) => caches.delete(k)));
      if (self.registration.navigationPreload) {
        await self.registration.navigationPreload.enable();
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
  if (event.data === 'CACHE_VERSION') {
    event.source?.postMessage({ type: 'CACHE_VERSION', version: VERSION });
  }
});

function isApiOrSocket(url) {
  return url.pathname.startsWith('/api') || url.pathname.startsWith('/socket.io');
}

async function networkFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  try {
    const response = await fetch(request);
    if (response && response.ok) cache.put(request, response.clone());
    return response;
  } catch {
    const cached = await cache.match(request);
    if (cached) return cached;
    const shell = await caches.open(SHELL_CACHE);
    const fallback = (await shell.match('/index.html')) || (await shell.match('/'));
    if (fallback) return fallback;
    return new Response('Offline', { status: 503, statusText: 'Offline' });
  }
}

async function cacheFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok) cache.put(request, response.clone());
  return response;
}

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const network = fetch(request)
    .then((response) => {
      if (response && response.ok) cache.put(request, response.clone());
      return response;
    })
    .catch(() => null);
  return cached || (await network) || new Response('', { status: 504 });
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin || isApiOrSocket(url)) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, SHELL_CACHE));
    return;
  }

  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(cacheFirst(request, ASSET_CACHE));
    return;
  }

  if (STATIC_URLS.includes(url.pathname) || url.pathname.endsWith('.png') || url.pathname.endsWith('.svg')) {
    event.respondWith(staleWhileRevalidate(request, STATIC_CACHE));
  }
});

/* Web push: wire-up so a future server push wakes the app. */
self.addEventListener('push', (event) => {
  let payload = { title: 'Turbo', body: 'A download finished.' };
  try {
    if (event.data) payload = { ...payload, ...event.data.json() };
  } catch {
    if (event.data) payload.body = event.data.text();
  }
  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/icon-192.png',
      badge: '/favicon-48.png',
      tag: payload.tag || 'turbo',
      data: { url: payload.url || '/' },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.url || '/';
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const existing = all.find((c) => new URL(c.url).origin === self.location.origin);
      if (existing) return existing.focus();
      return self.clients.openWindow(target);
    })()
  );
});
