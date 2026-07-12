import fs from 'fs';
import path from 'path';
import os from 'os';

const SETTINGS_FILE = path.join(os.homedir(), '.turbo-downloader-settings.json');

const DEFAULT_SETTINGS = {
  connections: 16,
  concurrentDownloads: 3,
  split: 16,
  defaultDir: path.join(os.homedir(), 'TurboDownloads'),
  duplicateHandling: 'rename',
  notifications: true,
  bandwidthLimit: 0,
  autoStart: true,
  maxRetries: 5,
  retryWait: 30,
  theme: 'dark'
};

export class SettingsManager {
  constructor() {
    this.settings = { ...DEFAULT_SETTINGS };
    this.loadSettings();
  }

  loadSettings() {
    try {
      if (fs.existsSync(SETTINGS_FILE)) {
        const data = fs.readFileSync(SETTINGS_FILE, 'utf-8');
        this.settings = { ...DEFAULT_SETTINGS, ...JSON.parse(data) };
      }
    } catch (error) {
      console.error('Failed to load settings:', error.message);
    }
  }

  saveSettings() {
    try {
      const dir = path.dirname(SETTINGS_FILE);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(SETTINGS_FILE, JSON.stringify(this.settings, null, 2));
    } catch (error) {
      console.error('Failed to save settings:', error.message);
    }
  }

  getSettings() {
    return { ...this.settings };
  }

  updateSettings(newSettings) {
    this.settings = { ...this.settings, ...newSettings };
    this.saveSettings();
    return this.settings;
  }

  resetSettings() {
    this.settings = { ...DEFAULT_SETTINGS };
    this.saveSettings();
    return this.settings;
  }
}
