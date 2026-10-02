export function formatBytes(bytes, digits = 2) {
  const n = Number(bytes);
  if (!n || n <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(n) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((n / k ** i).toFixed(digits))} ${sizes[i]}`;
}

export function formatSpeed(bytes) {
  if (!bytes || bytes <= 0) return '0 B/s';
  return `${formatBytes(bytes, 1)}/s`;
}

export function formatDuration(seconds) {
  if (seconds == null || !Number.isFinite(seconds)) return '—';
  if (seconds < 1) return '<1s';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) {
    const m = Math.floor(seconds / 60);
    const s = Math.round(seconds % 60);
    return `${m}m ${s}s`;
  }
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m}m`;
}

export function formatRelativeTime(value) {
  if (!value) return '—';
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return '—';
  const diff = Date.now() - then;
  const abs = Math.abs(diff);
  const units = [
    ['year', 31536000000],
    ['month', 2592000000],
    ['day', 86400000],
    ['hour', 3600000],
    ['minute', 60000],
    ['second', 1000],
  ];
  for (const [unit, ms] of units) {
    if (abs >= ms || unit === 'second') {
      const value2 = Math.round(diff / ms);
      return new Intl.RelativeTimeFormat('en', { numeric: 'auto' }).format(-value2, unit);
    }
  }
  return '—';
}

const EXTENSION_GROUPS = {
  archive: ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'],
  video: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'ts'],
  audio: ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma'],
  image: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'tiff'],
  document: ['pdf', 'doc', 'docx', 'txt', 'epub', 'mobi', 'csv', 'xls', 'xlsx', 'ppt', 'pptx'],
  code: ['js', 'ts', 'py', 'java', 'go', 'rs', 'c', 'cpp', 'json', 'xml', 'html', 'css'],
  app: ['exe', 'msi', 'dmg', 'apk', 'deb', 'rpm', 'appimage'],
};

export function fileKind(filename = '') {
  const ext = filename.split('.').pop()?.toLowerCase();
  if (!ext) return 'file';
  for (const [group, list] of Object.entries(EXTENSION_GROUPS)) {
    if (list.includes(ext)) return group;
  }
  return 'file';
}

export function isLikelyUrl(value) {
  const trimmed = String(value || '').trim();
  if (!trimmed) return false;
  try {
    const url = new URL(trimmed);
    return ['http:', 'https:'].includes(url.protocol);
  } catch {
    return false;
  }
}

export function parseUrlList(text) {
  return String(text || '')
    .split(/[\n\r\s]+/)
    .map((u) => u.trim())
    .filter((u) => u.length > 0);
}
