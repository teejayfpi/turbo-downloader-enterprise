import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const db = new Database(path.join(__dirname, 'turbo.db'));

db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS downloads (
    id TEXT PRIMARY KEY,
    device_id TEXT DEFAULT 'anonymous',
    url TEXT NOT NULL,
    filename TEXT,
    size_bytes INTEGER DEFAULT 0,
    downloaded_bytes INTEGER DEFAULT 0,
    status TEXT DEFAULT 'queued',
    progress REAL DEFAULT 0,
    speed_bps INTEGER DEFAULT 0,
    error TEXT,
    format TEXT DEFAULT 'best',
    platform TEXT DEFAULT 'Unknown',
    started_at DATETIME,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_downloads_device ON downloads(device_id);
  CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status);
`);

export default db;
