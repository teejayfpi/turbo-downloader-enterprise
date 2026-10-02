import { SettingsManager } from './settingsManager.js';
import { DownloadEngine } from './downloadEngine.js';

/**
 * Shared singletons. Kept in a dedicated module so route modules can import the
 * engine/settings without creating a circular dependency with the server entry.
 */
export const settingsManager = new SettingsManager();
export const engine = new DownloadEngine(null, settingsManager);

export function attachSocket(io) {
  engine.io = io;
  engine.init();
}
