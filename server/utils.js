import dns from 'dns/promises';
import net from 'net';
import path from 'path';

const PLATFORMS = {
  'youtube.com': 'YouTube',
  'youtu.be': 'YouTube',
  'music.youtube.com': 'YouTube',
  'vimeo.com': 'Vimeo',
  'dailymotion.com': 'Dailymotion',
  'twitter.com': 'Twitter/X',
  'x.com': 'Twitter/X',
  'instagram.com': 'Instagram',
  'tiktok.com': 'TikTok',
  'facebook.com': 'Facebook',
  'fb.watch': 'Facebook',
  'twitch.tv': 'Twitch',
  'soundcloud.com': 'SoundCloud',
  'bandcamp.com': 'Bandcamp',
  'mixcloud.com': 'Mixcloud',
  'reddit.com': 'Reddit',
  'redd.it': 'Reddit',
  'bilibili.com': 'Bilibili',
  'vk.com': 'VK',
  'netflix.com': 'Netflix',
  'primevideo.com': 'Prime Video',
  'disneyplus.com': 'Disney+',
  'max.com': 'HBO Max',
  'hulu.com': 'Hulu',
  'peacocktv.com': 'Peacock',
  'paramountplus.com': 'Paramount+',
  'crunchyroll.com': 'Crunchyroll',
  'spotify.com': 'Spotify',
  'podcasts.apple.com': 'Apple Podcasts',
};

export function detectPlatform(url) {
  try {
    const hostname = new URL(url).hostname.toLowerCase().replace(/^www\./, '');
    for (const [pattern, platform] of Object.entries(PLATFORMS)) {
      if (hostname === pattern || hostname.endsWith(`.${pattern}`)) return platform;
    }
    return 'Direct';
  } catch {
    return 'Unknown';
  }
}

export function isMediaPlatform(platform) {
  return platform !== 'Direct' && platform !== 'Unknown';
}

export function isPrivateIp(ip) {
  if (net.isIPv4(ip)) {
    const parts = ip.split('.').map(Number);
    const [a, b] = parts;
    if (a === 10) return true;
    if (a === 127) return true;
    if (a === 0) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a >= 224) return true;
    return false;
  }
  if (net.isIPv6(ip)) {
    const lower = ip.toLowerCase();
    if (lower === '::1' || lower === '::') return true;
    if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // unique local
    if (lower.startsWith('fe80')) return true; // link local
    if (lower.startsWith('::ffff:')) return isPrivateIp(lower.slice(7));
    return false;
  }
  return false;
}

/**
 * Basic SSRF protection: the target host must resolve to a public IP address.
 * This blocks loopback, link-local, and RFC1918 ranges by default.
 */
export async function assertPublicHost(hostname) {
  if (process.env.TURBO_ALLOW_PRIVATE_HOSTS === '1') return;

  if (net.isIP(hostname)) {
    if (isPrivateIp(hostname)) {
      throw new Error('Downloads from private or local network addresses are not allowed');
    }
    return;
  }

  let records;
  try {
    records = await dns.lookup(hostname, { all: true });
  } catch {
    throw new Error(`Could not resolve host: ${hostname}`);
  }

  if (!records.length || records.some((r) => isPrivateIp(r.address))) {
    throw new Error('Downloads from private or local network addresses are not allowed');
  }
}

export function validateHttpUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error(`Invalid URL: ${rawUrl}`);
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Only http and https URLs are supported');
  }
  return parsed;
}

/** Strips path separators and control characters from a user/URL supplied name. */
export function safeFilename(name, fallback = 'download') {
  const base = path.basename(String(name || '').trim()) || fallback;
  const cleaned = base
    .replace(/[\u0000-\u001f<>:"/\\|?*]/g, '_')
    .replace(/^\.+/, '')
    .trim();
  return cleaned.slice(0, 200) || fallback;
}

export function extractFilename(url, contentDisposition = '') {
  const fromHeader = parseContentDisposition(contentDisposition);
  if (fromHeader) return safeFilename(decodeURIComponent(fromHeader));

  try {
    const { pathname } = new URL(url);
    const name = decodeURIComponent(path.basename(pathname));
    if (name && name !== '/') return safeFilename(name);
  } catch {
    /* ignore */
  }
  return safeFilename(`download_${Date.now()}`);
}

function parseContentDisposition(header) {
  if (!header) return null;
  const utf8 = header.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8) return utf8[1];
  const basic = header.match(/filename="?([^";]+)"?/i);
  return basic ? basic[1] : null;
}

export function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((bytes / k ** i).toFixed(2))} ${sizes[i]}`;
}
