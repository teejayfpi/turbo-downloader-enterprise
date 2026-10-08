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
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT 100.64.0.0/10
    if (a >= 224) return true;
    return false;
  }
  if (net.isIPv6(ip)) {
    const lower = ip.toLowerCase();
    if (lower === '::1' || lower === '::') return true;
    if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // unique local
    if (lower.startsWith('fe80')) return true; // link local
    // Dotted IPv4-mapped form (`::ffff:127.0.0.1`). The dotted tail is a single
    // split element that stands for two 16-bit groups, so it is handled here
    // rather than through the generic expansion below.
    const dotted = lower.startsWith('::ffff:') ? lower.slice(7) : '';
    if (dotted && net.isIPv4(dotted)) return isPrivateIp(dotted);
    // Hex IPv4-mapped form (`::ffff:7f00:1`) in any spelling: expand to groups
    // and test the first 80 bits for zero and the next 16 for `ffff`.
    const groups = expandIpv6(lower);
    if (groups && groups.slice(0, 5).every((g) => g === '0000') && groups[5] === 'ffff') {
      const hi = parseInt(groups[6], 16);
      const lo = parseInt(groups[7], 16);
      return isPrivateIp(`${hi >> 8}.${hi & 0xff}.${lo >> 8}.${lo & 0xff}`);
    }
    return false;
  }
  return false;
}

/** Expands an IPv6 address to eight zero-padded groups; null when malformed. */
function expandIpv6(ip) {
  const hasElision = ip.includes('::');
  const parts = ip.split('::');
  if (parts.length > 2) return null;
  const head = parts[0] ? parts[0].split(':') : [];
  const tail = parts[1] ? parts[1].split(':') : [];
  if (!hasElision && head.length !== 8) return null;
  const missing = 8 - head.length - tail.length;
  if (missing < 0) return null;
  const groups = [...head, ...Array(missing).fill('0'), ...tail];
  if (groups.length !== 8) return null;
  return groups.map((g) => g.padStart(4, '0'));
}

/**
 * Basic SSRF protection: the target host must resolve to a public IP address.
 * This blocks loopback, link-local, CGNAT, and RFC1918 ranges by default.
 *
 * Returns the address the caller should connect to, or null when the check is
 * disabled or [hostname] is already a literal IP. Passing the result back into
 * the request pins the connection to the address that was checked, so a second
 * DNS answer (DNS rebinding) cannot swap in a private address between the check
 * and the connect.
 */
export async function assertPublicHost(hostname) {
  if (process.env.TURBO_ALLOW_PRIVATE_HOSTS === '1') return null;

  // `new URL('http://[::1]/').hostname` keeps the IPv6 brackets, which makes
  // `net.isIP` return 0 and would send the literal to DNS. Strip them so
  // literal addresses are classified directly instead of being rejected as
  // unresolvable.
  const host = hostname.startsWith('[') && hostname.endsWith(']')
    ? hostname.slice(1, -1)
    : hostname;

  if (net.isIP(host)) {
    if (isPrivateIp(host)) {
      throw new Error('Downloads from private or local network addresses are not allowed');
    }
    return null;
  }

  let records;
  try {
    records = await dns.lookup(host, { all: true, verbatim: true });
  } catch {
    throw new Error(`Could not resolve host: ${hostname}`);
  }

  if (!records.length || records.some((r) => isPrivateIp(r.address))) {
    throw new Error('Downloads from private or local network addresses are not allowed');
  }
  return records[0].address;
}

/** A `lookup` implementation that always answers with [address]. */
export function pinnedLookup(address) {
  const family = net.isIPv6(address) ? 6 : 4;
  return (_hostname, options, callback) => {
    // Node enables autoSelectFamily (Happy Eyeballs) by default, which asks for
    // every answer at once. That request is `{ all: true }`, and returning the
    // single-address form makes net reject it with ERR_INVALID_IP_ADDRESS —
    // which would break every direct download, not just dual-stack hosts.
    if (options && options.all) {
      callback(null, [{ address, family }]);
      return;
    }
    callback(null, address, family);
  };
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
