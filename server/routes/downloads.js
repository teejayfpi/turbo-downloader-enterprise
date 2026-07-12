import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import db from '../database.js';

const router = express.Router();

// Get downloads (anonymous - uses device ID)
router.get('/', (req, res) => {
  try {
    const deviceId = req.headers['x-device-id'] || 'anonymous';
    const downloads = db.prepare(`
      SELECT * FROM downloads WHERE device_id = ? ORDER BY created_at DESC
    `).all(deviceId);

    res.json({ downloads: downloads.map(formatDownload) });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get downloads' });
  }
});

// Create download (anonymous)
router.post('/', (req, res) => {
  try {
    const { url, formatId } = req.body;
    const deviceId = req.headers['x-device-id'] || 'anonymous';

    if (!url) {
      return res.status(400).json({ error: 'URL required' });
    }

    const id = uuidv4();
    const platform = detectPlatform(url);

    db.prepare(`
      INSERT INTO downloads (id, device_id, url, platform, format, status)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, deviceId, url, platform, formatId || 'best', 'queued');

    res.status(201).json({ 
      download: formatDownload({
        id, device_id: deviceId, url, platform, format: formatId || 'best', 
        status: 'queued', created_at: new Date().toISOString()
      })
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create download' });
  }
});

// Update download
router.put('/:id', (req, res) => {
  try {
    const { id } = req.params;
    const { filename, status, progress, speed, total, downloaded } = req.body;
    const deviceId = req.headers['x-device-id'] || 'anonymous';

    const updates = [];
    const values = [];

    if (filename !== undefined) {
      updates.push('filename = ?');
      values.push(filename);
    }
    if (status !== undefined) {
      updates.push('status = ?');
      values.push(status);
    }
    if (progress !== undefined) {
      updates.push('progress = ?');
      values.push(progress);
    }
    if (speed !== undefined) {
      updates.push('speed_bps = ?');
      values.push(speed);
    }
    if (total !== undefined) {
      updates.push('size_bytes = ?');
      values.push(total);
    }
    if (downloaded !== undefined) {
      updates.push('downloaded_bytes = ?');
      values.push(downloaded);
    }

    if (updates.length > 0) {
      values.push(id, deviceId);
      db.prepare(`UPDATE downloads SET ${updates.join(', ')} WHERE id = ? AND device_id = ?`)
        .run(...values);
    }

    const download = db.prepare('SELECT * FROM downloads WHERE id = ?').get(id);
    res.json({ download: formatDownload(download) });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update download' });
  }
});

// Delete download
router.delete('/:id', (req, res) => {
  try {
    const deviceId = req.headers['x-device-id'] || 'anonymous';
    db.prepare('DELETE FROM downloads WHERE id = ? AND device_id = ?')
      .run(req.params.id, deviceId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete download' });
  }
});

function detectPlatform(url) {
  try {
    const hostname = new URL(url).hostname.toLowerCase();
    const platforms = {
      'youtube.com': 'YouTube', 'youtu.be': 'YouTube',
      'vimeo.com': 'Vimeo', 'twitter.com': 'Twitter',
      'x.com': 'Twitter', 'instagram.com': 'Instagram',
      'tiktok.com': 'TikTok', 'facebook.com': 'Facebook',
      'twitch.tv': 'Twitch', 'soundcloud.com': 'SoundCloud',
      'netflix.com': 'Netflix', 'spotify.com': 'Spotify',
    };
    for (const [pattern, platform] of Object.entries(platforms)) {
      if (hostname.includes(pattern)) return platform;
    }
    return 'Unknown';
  } catch { return 'Unknown'; }
}

function formatDownload(d) {
  return {
    id: d.id,
    url: d.url,
    filename: d.filename || 'Unknown',
    total: d.size_bytes || 0,
    downloaded: d.downloaded_bytes || 0,
    speed: d.speed_bps || 0,
    progress: d.progress || 0,
    status: d.status || 'queued',
    error: d.error,
    createdAt: d.created_at,
    completedAt: d.completed_at,
  };
}

export default router;
