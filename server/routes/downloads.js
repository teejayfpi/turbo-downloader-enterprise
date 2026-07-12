import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import db from '../database.js';
import { authenticate } from '../middleware/auth.js';
import { downloadLimiter, auditLog } from '../middleware/rateLimiter.js';

const router = express.Router();

// Get user's downloads
router.get('/', authenticate, (req, res) => {
  try {
    const { page = 1, limit = 20, status, search, folderId } = req.query;
    const offset = (page - 1) * limit;
    const userId = req.user.id;

    let query = `
      SELECT * FROM downloads 
      WHERE user_id = ?
    `;
    const params = [userId];

    if (status) {
      query += ' AND status = ?';
      params.push(status);
    }

    if (search) {
      query += ' AND (url LIKE ? OR filename LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    if (folderId) {
      query += ' AND folder_id = ?';
      params.push(folderId);
    }

    const countQuery = query.replace('SELECT *', 'SELECT COUNT(*) as count');
    const total = db.prepare(countQuery).get(...params).count;

    query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));

    const downloads = db.prepare(query).all(...params);

    // Get user stats
    const stats = db.prepare(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'downloading' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) as queued,
        SUM(size_bytes) as total_size
      FROM downloads WHERE user_id = ?
    `).get(userId);

    res.json({
      downloads: downloads.map(formatDownload),
      stats: {
        ...stats,
        totalSizeFormatted: formatBytes(stats.total_size || 0),
      },
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('Get downloads error:', error);
    res.status(500).json({ error: 'Failed to get downloads' });
  }
});

// Get single download
router.get('/:id', authenticate, (req, res) => {
  try {
    const download = db.prepare(`
      SELECT * FROM downloads WHERE id = ? AND user_id = ?
    `).get(req.params.id, req.user.id);

    if (!download) {
      return res.status(404).json({ error: 'Download not found' });
    }

    res.json({ download: formatDownload(download) });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get download' });
  }
});

// Create download
router.post('/', 
  authenticate, 
  downloadLimiter,
  auditLog('create_download', 'download'),
  (req, res) => {
    try {
      const { urls, formatId, isAudioOnly, scheduledFor, folderId } = req.body;
      const userId = req.user.id;

      if (!urls || !Array.isArray(urls) || urls.length === 0) {
        return res.status(400).json({ error: 'URLs array required' });
      }

      // Check storage quota
      const user = db.prepare('SELECT quota_used_mb FROM users WHERE id = ?').get(userId);
      const org = user.organization_id 
        ? db.prepare('SELECT max_storage_gb FROM organizations WHERE id = ?').get(user.organization_id)
        : null;
      
      const maxStorageMb = (org?.max_storage_gb || 10) * 1024;
      if (user.quota_used_mb >= maxStorageMb) {
        return res.status(400).json({ error: 'Storage quota exceeded' });
      }

      const downloads = [];
      for (const url of urls) {
        const id = uuidv4();
        const platform = detectPlatform(url);

        db.prepare(`
          INSERT INTO downloads (id, user_id, url, platform, format, scheduled_for, folder_id, status)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          id,
          userId,
          url,
          platform,
          formatId || 'best',
          scheduledFor || null,
          folderId || null,
          scheduledFor ? 'scheduled' : 'queued'
        );

        downloads.push({
          id,
          url,
          platform,
          status: scheduledFor ? 'scheduled' : 'queued',
        });
      }

      res.status(201).json({ downloads });
    } catch (error) {
      console.error('Create download error:', error);
      res.status(500).json({ error: 'Failed to create download' });
    }
  }
);

// Update download (rename, move to folder)
router.put('/:id', authenticate, (req, res) => {
  try {
    const { id } = req.params;
    const { filename, folderId } = req.body;

    const download = db.prepare('SELECT * FROM downloads WHERE id = ? AND user_id = ?')
      .get(id, req.user.id);

    if (!download) {
      return res.status(404).json({ error: 'Download not found' });
    }

    if (filename !== undefined) {
      db.prepare('UPDATE downloads SET filename = ? WHERE id = ?').run(filename, id);
    }
    if (folderId !== undefined) {
      db.prepare('UPDATE downloads SET folder_id = ? WHERE id = ?').run(folderId, id);
    }

    const updated = db.prepare('SELECT * FROM downloads WHERE id = ?').get(id);
    res.json({ download: formatDownload(updated) });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update download' });
  }
});

// Delete download
router.delete('/:id', authenticate, auditLog('delete_download', 'download'), (req, res) => {
  try {
    const { id } = req.params;

    const download = db.prepare('SELECT * FROM downloads WHERE id = ? AND user_id = ?')
      .get(id, req.user.id);

    if (!download) {
      return res.status(404).json({ error: 'Download not found' });
    }

    db.prepare('DELETE FROM downloads WHERE id = ?').run(id);

    // Update quota if completed download
    if (download.status === 'completed' && download.size_bytes) {
      const sizeMb = Math.ceil(download.size_bytes / (1024 * 1024));
      db.prepare('UPDATE users SET quota_used_mb = quota_used_mb - ? WHERE id = ?')
        .run(sizeMb, req.user.id);
    }

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete download' });
  }
});

// Batch delete
router.post('/batch-delete', authenticate, auditLog('batch_delete', 'download'), (req, res) => {
  try {
    const { ids } = req.body;

    if (!ids || !Array.isArray(ids)) {
      return res.status(400).json({ error: 'IDs array required' });
    }

    // Get downloads to update quota
    const downloads = db.prepare(`
      SELECT * FROM downloads WHERE id IN (${ids.map(() => '?').join(',')}) AND user_id = ?
    `).all(...ids, req.user.id);

    // Update quota
    for (const d of downloads) {
      if (d.status === 'completed' && d.size_bytes) {
        const sizeMb = Math.ceil(d.size_bytes / (1024 * 1024));
        db.prepare('UPDATE users SET quota_used_mb = quota_used_mb - ? WHERE id = ?')
          .run(sizeMb, req.user.id);
      }
    }

    // Delete downloads
    db.prepare(`DELETE FROM downloads WHERE id IN (${ids.map(() => '?').join(',')}) AND user_id = ?`)
      .run(...ids, req.user.id);

    res.json({ success: true, deleted: ids.length });
  } catch (error) {
    res.status(500).json({ error: 'Failed to batch delete' });
  }
});

// Retry failed download
router.post('/:id/retry', authenticate, downloadLimiter, (req, res) => {
  try {
    const download = db.prepare('SELECT * FROM downloads WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id);

    if (!download) {
      return res.status(404).json({ error: 'Download not found' });
    }

    if (download.status !== 'failed') {
      return res.status(400).json({ error: 'Can only retry failed downloads' });
    }

    db.prepare(`
      UPDATE downloads SET status = 'queued', error = NULL WHERE id = ?
    `).run(req.params.id);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to retry download' });
  }
});

// Folders/Categories
router.get('/folders/list', authenticate, (req, res) => {
  try {
    const folders = db.prepare(`
      SELECT * FROM folders WHERE user_id = ? ORDER BY name
    `).all(req.user.id);

    res.json({ folders });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get folders' });
  }
});

router.post('/folders', authenticate, (req, res) => {
  try {
    const { name, parentId, color } = req.body;
    const id = uuidv4();

    db.prepare(`
      INSERT INTO folders (id, user_id, name, parent_id, color)
      VALUES (?, ?, ?, ?, ?)
    `).run(id, req.user.id, name, parentId || null, color || '#00BCD4');

    const folder = db.prepare('SELECT * FROM folders WHERE id = ?').get(id);
    res.status(201).json({ folder });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create folder' });
  }
});

router.delete('/folders/:id', authenticate, (req, res) => {
  try {
    db.prepare('DELETE FROM folders WHERE id = ? AND user_id = ?')
      .run(req.params.id, req.user.id);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete folder' });
  }
});

// Helper functions
function detectPlatform(url) {
  try {
    const hostname = new URL(url).hostname.toLowerCase();
    const platforms = {
      'youtube.com': 'YouTube',
      'youtu.be': 'YouTube',
      'vimeo.com': 'Vimeo',
      'twitter.com': 'Twitter',
      'x.com': 'Twitter',
      'instagram.com': 'Instagram',
      'tiktok.com': 'TikTok',
      'facebook.com': 'Facebook',
      'twitch.tv': 'Twitch',
      'soundcloud.com': 'SoundCloud',
      'netflix.com': 'Netflix',
      'spotify.com': 'Spotify',
    };

    for (const [pattern, platform] of Object.entries(platforms)) {
      if (hostname.includes(pattern)) return platform;
    }
    return 'Unknown';
  } catch {
    return 'Unknown';
  }
}

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
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
    speedBps: d.speed_bps,
    speedFormatted: formatBytes(d.speed_bps) + '/s',
    error: d.error,
    format: d.format,
    platform: d.platform,
    folderId: d.folder_id,
    scheduledFor: d.scheduled_for,
    startedAt: d.started_at,
    completedAt: d.completed_at,
    createdAt: d.created_at,
  };
}

export default router;
