import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const db = new Database(path.join(__dirname, 'turbo_enterprise.db'));

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Create tables
db.exec(`
  -- Organizations table
  CREATE TABLE IF NOT EXISTS organizations (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    plan TEXT DEFAULT 'free',
    max_users INTEGER DEFAULT 5,
    max_storage_gb INTEGER DEFAULT 10,
    max_downloads_per_day INTEGER DEFAULT 100,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Users table
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    name TEXT NOT NULL,
    role TEXT DEFAULT 'user',
    organization_id TEXT,
    quota_used_mb INTEGER DEFAULT 0,
    downloads_today INTEGER DEFAULT 0,
    last_download_date TEXT,
    is_active INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (organization_id) REFERENCES organizations(id)
  );

  -- Downloads table
  CREATE TABLE IF NOT EXISTS downloads (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    url TEXT NOT NULL,
    filename TEXT,
    size_bytes INTEGER DEFAULT 0,
    status TEXT DEFAULT 'queued',
    progress REAL DEFAULT 0,
    speed_bps INTEGER DEFAULT 0,
    error TEXT,
    format TEXT,
    platform TEXT,
    scheduled_for DATETIME,
    started_at DATETIME,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- Download folders/categories
  CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    parent_id TEXT,
    color TEXT DEFAULT '#00BCD4',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (parent_id) REFERENCES folders(id)
  );

  -- Audit logs
  CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    action TEXT NOT NULL,
    resource_type TEXT,
    resource_id TEXT,
    details TEXT,
    ip_address TEXT,
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- API keys for external integrations
  CREATE TABLE IF NOT EXISTS api_keys (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    permissions TEXT,
    rate_limit INTEGER DEFAULT 100,
    last_used_at DATETIME,
    expires_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- Webhooks
  CREATE TABLE IF NOT EXISTS webhooks (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    url TEXT NOT NULL,
    events TEXT NOT NULL,
    secret TEXT,
    is_active INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (organization_id) REFERENCES organizations(id)
  );

  -- Rate limiting tracking
  CREATE TABLE IF NOT EXISTS rate_limits (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    endpoint TEXT NOT NULL,
    request_count INTEGER DEFAULT 1,
    window_start DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  -- System settings
  CREATE TABLE IF NOT EXISTS system_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Indexes for performance
  CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
  CREATE INDEX IF NOT EXISTS idx_users_org ON users(organization_id);
  CREATE INDEX IF NOT EXISTS idx_downloads_user ON downloads(user_id);
  CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status);
  CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
  CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);
`);

// Initialize default data
const initDefaultData = () => {
  const settingsCount = db.prepare('SELECT COUNT(*) as count FROM system_settings').get();
  if (settingsCount.count === 0) {
    const insertSetting = db.prepare('INSERT INTO system_settings (key, value) VALUES (?, ?)');
    insertSetting.run('app_name', 'Turbo Downloader Enterprise');
    insertSetting.run('app_version', '1.0.0');
    insertSetting.run('max_upload_size_mb', '5000');
    insertSetting.run('default_rate_limit', '100');
    insertSetting.run('maintenance_mode', 'false');
    insertSetting.run('registration_enabled', 'true');
  }

  // Create default organization
  const orgCount = db.prepare('SELECT COUNT(*) as count FROM organizations').get();
  if (orgCount.count === 0) {
    const orgId = uuidv4();
    db.prepare('INSERT INTO organizations (id, name, plan) VALUES (?, ?, ?)').run(
      orgId,
      'Default Organization',
      'enterprise'
    );
  }
};

export default db;
