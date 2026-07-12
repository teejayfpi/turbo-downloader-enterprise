import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import bcrypt from 'bcryptjs';
import db from '../database.js';
import { authenticate, requireAdmin, requireOrgAdmin } from '../middleware/auth.js';

const router = express.Router();

// System Dashboard
router.get('/dashboard', authenticate, requireOrgAdmin, (req, res) => {
  try {
    // Get system stats
    const totalUsers = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
    const activeUsers = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_active = 1').get().count;
    const totalDownloads = db.prepare('SELECT COUNT(*) as count FROM downloads').get().count;
    const completedDownloads = db.prepare("SELECT COUNT(*) as count FROM downloads WHERE status = 'completed'").get().count;
    
    // Get storage stats
    const totalSize = db.prepare('SELECT SUM(size_bytes) as total FROM downloads WHERE status = ?')
      .get('completed')?.total || 0;
    
    // Get downloads by status
    const downloadsByStatus = db.prepare(`
      SELECT status, COUNT(*) as count 
      FROM downloads 
      GROUP BY status
    `).all();

    // Get recent downloads
    const recentDownloads = db.prepare(`
      SELECT d.*, u.name as user_name, u.email as user_email
      FROM downloads d
      LEFT JOIN users u ON d.user_id = u.id
      ORDER BY d.created_at DESC
      LIMIT 10
    `).all();

    // Get top users by downloads
    const topUsers = db.prepare(`
      SELECT u.id, u.name, u.email, COUNT(d.id) as download_count, SUM(d.size_bytes) as total_size
      FROM users u
      LEFT JOIN downloads d ON u.id = d.user_id
      WHERE u.is_active = 1
      GROUP BY u.id
      ORDER BY download_count DESC
      LIMIT 10
    `).all();

    // Get bandwidth usage (last 7 days)
    const bandwidthUsage = db.prepare(`
      SELECT DATE(created_at) as date, SUM(size_bytes) as total
      FROM downloads
      WHERE status = 'completed'
        AND created_at >= DATE('now', '-7 days')
      GROUP BY DATE(created_at)
      ORDER BY date
    `).all();

    // System health
    const systemHealth = {
      database: 'healthy',
      downloads: 'healthy',
      storage: 'healthy',
      lastChecked: new Date().toISOString(),
    };

    res.json({
      stats: {
        totalUsers,
        activeUsers,
        totalDownloads,
        completedDownloads,
        totalSizeBytes: totalSize,
        totalSizeFormatted: formatBytes(totalSize),
      },
      downloadsByStatus: Object.fromEntries(downloadsByStatus.map(s => [s.status, s.count])),
      recentDownloads: recentDownloads.map(formatDownload),
      topUsers: topUsers.map(u => ({
        ...u,
        totalSizeFormatted: formatBytes(u.total_size || 0),
      })),
      bandwidthUsage,
      systemHealth,
    });
  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({ error: 'Failed to load dashboard' });
  }
});

// Get all users (admin only)
router.get('/users', authenticate, requireOrgAdmin, (req, res) => {
  try {
    const { page = 1, limit = 20, search, role } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT u.*, o.name as org_name
      FROM users u
      LEFT JOIN organizations o ON u.organization_id = o.id
      WHERE 1=1
    `;
    const params = [];

    if (search) {
      query += ' AND (u.name LIKE ? OR u.email LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    if (role) {
      query += ' AND u.role = ?';
      params.push(role);
    }

    const countQuery = query.replace('SELECT u.*, o.name as org_name', 'SELECT COUNT(*) as count');
    const total = db.prepare(countQuery).get(...params).count;

    query += ' ORDER BY u.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));

    const users = db.prepare(query).all(...params);

    res.json({
      users: users.map(u => ({
        id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        isActive: !!u.is_active,
        quotaUsedMb: u.quota_used_mb,
        downloadsToday: u.downloads_today,
        organization: u.org_name,
        createdAt: u.created_at,
      })),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get users' });
  }
});

// Create user
router.post('/users', authenticate, requireOrgAdmin, async (req, res) => {
  try {
    const { email, name, role, organizationId } = req.body;
    const userId = uuidv4();
    const tempPassword = Math.random().toString(36).slice(-8);

    const passwordHash = await bcrypt.hash(tempPassword, 12);

    db.prepare(`
      INSERT INTO users (id, email, password_hash, name, role, organization_id)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(userId, email, passwordHash, name, role || 'user', organizationId);

    res.status(201).json({
      user: { id: userId, email, name, role: role || 'user' },
      temporaryPassword: tempPassword,
    });
  } catch (error) {
    if (error.message.includes('UNIQUE constraint')) {
      return res.status(400).json({ error: 'Email already exists' });
    }
    res.status(500).json({ error: 'Failed to create user' });
  }
});

// Update user
router.put('/users/:id', authenticate, requireOrgAdmin, (req, res) => {
  try {
    const { id } = req.params;
    const { name, role, isActive } = req.body;

    const updates = [];
    const params = [];

    if (name !== undefined) {
      updates.push('name = ?');
      params.push(name);
    }
    if (role !== undefined) {
      updates.push('role = ?');
      params.push(role);
    }
    if (isActive !== undefined) {
      updates.push('is_active = ?');
      params.push(isActive ? 1 : 0);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No updates provided' });
    }

    updates.push('updated_at = CURRENT_TIMESTAMP');
    params.push(id);

    db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...params);

    const user = db.prepare('SELECT id, email, name, role, is_active FROM users WHERE id = ?').get(id);
    res.json({ user });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update user' });
  }
});

// Delete user
router.delete('/users/:id', authenticate, requireAdmin, (req, res) => {
  try {
    const { id } = req.params;

    // Don't allow self-deletion
    if (id === req.user.id) {
      return res.status(400).json({ error: 'Cannot delete yourself' });
    }

    // Delete user's downloads first
    db.prepare('DELETE FROM downloads WHERE user_id = ?').run(id);
    
    // Delete user
    db.prepare('DELETE FROM users WHERE id = ?').run(id);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// Get organizations
router.get('/organizations', authenticate, requireAdmin, (req, res) => {
  try {
    const orgs = db.prepare('SELECT * FROM organizations ORDER BY created_at DESC').all();
    const users = db.prepare(`
      SELECT organization_id, COUNT(*) as user_count 
      FROM users 
      WHERE organization_id IS NOT NULL 
      GROUP BY organization_id
    `).all();

    const userCountMap = Object.fromEntries(users.map(u => [u.organization_id, u.user_count]));

    res.json({
      organizations: orgs.map(o => ({
        ...o,
        userCount: userCountMap[o.id] || 0,
      })),
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get organizations' });
  }
});

// Update organization
router.put('/organizations/:id', authenticate, requireAdmin, (req, res) => {
  try {
    const { id } = req.params;
    const { name, plan, maxUsers, maxStorageGb, maxDownloadsPerDay } = req.body;

    db.prepare(`
      UPDATE organizations 
      SET name = COALESCE(?, name),
          plan = COALESCE(?, plan),
          max_users = COALESCE(?, max_users),
          max_storage_gb = COALESCE(?, max_storage_gb),
          max_downloads_per_day = COALESCE(?, max_downloads_per_day),
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(name, plan, maxUsers, maxStorageGb, maxDownloadsPerDay, id);

    const org = db.prepare('SELECT * FROM organizations WHERE id = ?').get(id);
    res.json({ organization: org });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update organization' });
  }
});

// Get audit logs
router.get('/audit-logs', authenticate, requireOrgAdmin, (req, res) => {
  try {
    const { page = 1, limit = 50, userId, action } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT a.*, u.name as user_name, u.email as user_email
      FROM audit_logs a
      LEFT JOIN users u ON a.user_id = u.id
      WHERE 1=1
    `;
    const params = [];

    if (userId) {
      query += ' AND a.user_id = ?';
      params.push(userId);
    }
    if (action) {
      query += ' AND a.action = ?';
      params.push(action);
    }

    const countQuery = query.replace(/SELECT a\.\*, u\.name.*FROM/, 'SELECT COUNT(*) as count FROM');
    const total = db.prepare(countQuery).get(...params).count;

    query += ' ORDER BY a.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));

    const logs = db.prepare(query).all(...params);

    res.json({
      logs: logs.map(l => ({
        ...l,
        details: l.details ? JSON.parse(l.details) : null,
      })),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get audit logs' });
  }
});

// System settings
router.get('/settings', authenticate, requireAdmin, (req, res) => {
  try {
    const settings = db.prepare('SELECT * FROM system_settings').all();
    const settingsMap = Object.fromEntries(settings.map(s => [s.key, s.value]));
    res.json({ settings: settingsMap });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get settings' });
  }
});

router.put('/settings', authenticate, requireAdmin, (req, res) => {
  try {
    const { key, value } = req.body;
    
    db.prepare(`
      INSERT INTO system_settings (key, value, updated_at)
      VALUES (?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = CURRENT_TIMESTAMP
    `).run(key, value, value);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update setting' });
  }
});

// Helper functions
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatDownload(d) {
  return {
    id: d.id,
    url: d.url,
    filename: d.filename,
    sizeBytes: d.size_bytes,
    sizeFormatted: formatBytes(d.size_bytes),
    status: d.status,
    progress: d.progress,
    platform: d.platform,
    userName: d.user_name,
    userEmail: d.user_email,
    createdAt: d.created_at,
    completedAt: d.completed_at,
  };
}

export default router;
