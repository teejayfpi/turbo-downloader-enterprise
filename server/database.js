import Database from 'better-sqlite3';
import os from 'os';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Keep runtime state out of the source tree by default so the database never
// lands in version control.
const DATA_DIR = process.env.TURBO_DATA_DIR || path.join(os.homedir(), '.turbo-downloader');
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

const db = new Database(path.join(DATA_DIR, 'turbo.db'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS downloads (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    filename TEXT,
    filepath TEXT,
    total INTEGER DEFAULT 0,
    downloaded INTEGER DEFAULT 0,
    status TEXT DEFAULT 'queued',
    progress REAL DEFAULT 0,
    speed INTEGER DEFAULT 0,
    error TEXT,
    platform TEXT DEFAULT 'Unknown',
    kind TEXT DEFAULT 'http',
    format TEXT DEFAULT 'best',
    connections INTEGER DEFAULT 8,
    priority INTEGER DEFAULT 0,
    resume_supported INTEGER DEFAULT 0,
    checksum TEXT,
    checksum_algo TEXT,
    scheduled_at DATETIME,
    started_at DATETIME,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status);
  CREATE INDEX IF NOT EXISTS idx_downloads_created ON downloads(created_at);

  CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
`);

// `CREATE TABLE IF NOT EXISTS` never adds a column to an existing database, so
// new columns are applied explicitly. SQLite has no `ADD COLUMN IF NOT EXISTS`,
// hence the table_info check.
const downloadColumns = db.prepare('PRAGMA table_info(downloads)').all().map((c) => c.name);
if (!downloadColumns.includes('headers')) {
  db.exec('ALTER TABLE downloads ADD COLUMN headers TEXT');
}

export default db;
