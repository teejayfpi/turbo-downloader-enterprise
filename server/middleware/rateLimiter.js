import rateLimit from 'express-rate-limit';
import db from '../database.js';
import { v4 as uuidv4 } from 'uuid';

// API Rate Limiter
export const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: async (req) => {
    // Get user's rate limit from organization or default
    if (req.user) {
      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
      if (user && user.organization_id) {
        const org = db.prepare('SELECT * FROM organizations WHERE id = ?').get(user.organization_id);
        return 100; // Standard limit
      }
    }
    return 50; // Anonymous limit
  },
  message: { error: 'Too many requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Stricter limiter for auth endpoints
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: { error: 'Too many authentication attempts, please try again later' },
});

// Download rate limiter
export const downloadLimiter = async (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  const today = new Date().toISOString().split('T')[0];
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  
  if (!user) {
    return res.status(401).json({ error: 'User not found' });
  }

  // Reset daily counter if new day
  if (user.last_download_date !== today) {
    db.prepare('UPDATE users SET downloads_today = 0, last_download_date = ? WHERE id = ?')
      .run(today, req.user.id);
  }

  // Get organization limits
  let maxDownloads = 100;
  if (user.organization_id) {
    const org = db.prepare('SELECT max_downloads_per_day FROM organizations WHERE id = ?')
      .get(user.organization_id);
    if (org) {
      maxDownloads = org.max_downloads_per_day;
    }
  }

  if (user.downloads_today >= maxDownloads) {
    return res.status(429).json({ 
      error: 'Daily download limit reached',
      limit: maxDownloads,
      resetsAt: 'Tomorrow'
    });
  }

  // Increment counter
  db.prepare('UPDATE users SET downloads_today = downloads_today + 1 WHERE id = ?')
    .run(req.user.id);

  next();
};

// Audit logging middleware
export const auditLog = (action, resourceType) => {
  return (req, res, next) => {
    const originalSend = res.send;
    res.send = function(body) {
      // Log after successful response
      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          const logId = uuidv4();
          db.prepare(`
            INSERT INTO audit_logs (id, user_id, action, resource_type, details, ip_address, user_agent)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `).run(
            logId,
            req.user?.id || null,
            action,
            resourceType,
            JSON.stringify({ 
              path: req.path, 
              method: req.method,
              body: req.body 
            }),
            req.ip,
            req.get('user-agent')
          );
        } catch (err) {
          console.error('Audit log error:', err);
        }
      }
      return originalSend.call(this, body);
    };
    next();
  };
};
