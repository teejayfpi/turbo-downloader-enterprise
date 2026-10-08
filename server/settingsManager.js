import fs from 'fs';
import os from 'os';
import path from 'path';
import db from './database.js';

export const DEFAULT_SETTINGS = {
  connections: 8,
  concurrentDownloads: 5,
  // Segment cap. `connections` is the requested parallelism; `split` is the
  // ceiling, so raising one without the other has no effect. Previously `split`
  // was stored, validated, and shown in the UI but never read by the engine,
  // which silently capped every download at `connections`.
  split: 16,
  defaultDir: process.env.DOWNLOAD_DIR || path.join(os.homedir(), 'TurboDownloads'),
  duplicateHandling: 'rename', // skip | rename | overwrite
  notifications: true,
  bandwidthLimit: 0, // KB/s, 0 = unlimited
  autoStart: true,
  maxRetries: 5,
  retryWait: 5, // seconds
  theme: 'dark',
  accentColor: 'cyan',
  maxSpeedHistory: 60,
};

const NUMERIC_RANGES = {
  connections: [1, 32],
  concurrentDownloads: [1, 20],
  split: [1, 32],
  bandwidthLimit: [0, 1000000],
  maxRetries: [0, 20],
  retryWait: [0, 600],
};

function clamp(value, [min, max]) {
  return Math.min(Math.max(Number(value) || 0, min), max);
}

/**
 * Validates and normalizes a partial settings object. Unknown keys are dropped
 * so a client cannot persist arbitrary data into the settings store.
 */
export function sanitizeSettings(input = {}, base = DEFAULT_SETTINGS) {
  const next = { ...base };

  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    if (!(key in input)) continue;
    const value = input[key];

    if (key in NUMERIC_RANGES) {
      next[key] = clamp(value, NUMERIC_RANGES[key]);
    } else if (key === 'duplicateHandling') {
      if (['skip', 'rename', 'overwrite'].includes(value)) next[key] = value;
    } else if (key === 'theme') {
      if (['dark', 'light'].includes(value)) next[key] = value;
    } else if (key === 'accentColor') {
      if (['cyan', 'green', 'amber', 'orange', 'rose', 'purple'].includes(value)) next[key] = value;
    } else if (typeof value === 'boolean') {
      next[key] = value;
    } else if (typeof value === 'string') {
      next[key] = value.slice(0, 512);
    }
  }

  return next;
}

export class SettingsManager {
  constructor() {
    this.settings = { ...DEFAULT_SETTINGS };
    this.load();
  }

  load() {
    try {
      const rows = db.prepare('SELECT key, value FROM settings').all();
      const stored = {};
      for (const row of rows) {
        try {
          stored[row.key] = JSON.parse(row.value);
        } catch {
          stored[row.key] = row.value;
        }
      }
      this.settings = sanitizeSettings(stored, DEFAULT_SETTINGS);
    } catch (error) {
      console.error('Failed to load settings:', error.message);
    }
  }

  persist() {
    const upsert = db.prepare(`
      INSERT INTO settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `);
    const tx = db.transaction((entries) => {
      for (const [key, value] of entries) {
        upsert.run(key, JSON.stringify(value));
      }
    });
    tx(Object.entries(this.settings));
  }

  getSettings() {
    return { ...this.settings };
  }

  updateSettings(patch) {
    this.settings = sanitizeSettings(patch, this.settings);
    this.persist();
    return this.getSettings();
  }

  resetSettings() {
    this.settings = { ...DEFAULT_SETTINGS };
    this.persist();
    return this.getSettings();
  }

  /** Ensures the configured download directory exists and is writable. */
  ensureDownloadDir() {
    const dir = this.settings.defaultDir || DEFAULT_SETTINGS.defaultDir;
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.accessSync(dir, fs.constants.W_OK);
    return dir;
  }
}
