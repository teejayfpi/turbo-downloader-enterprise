import express from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import db from '../database.js';
import { generateToken, generateRefreshToken, authenticate } from '../middleware/auth.js';
import { authLimiter } from '../middleware/rateLimiter.js';
import { auditLog } from '../middleware/rateLimiter.js';
import { body, validationResult } from 'express-validator';

const router = express.Router();

// Validation middleware
const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

// Register
router.post('/register', 
  authLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }),
    body('name').trim().isLength({ min: 2 }),
  ],
  validateRequest,
  async (req, res) => {
    try {
      const { email, password, name, organizationName } = req.body;

      // Check if user exists
      const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
      if (existing) {
        return res.status(400).json({ error: 'Email already registered' });
      }

      // Get or create organization
      let orgId = null;
      if (organizationName) {
        const existingOrg = db.prepare('SELECT id FROM organizations WHERE name = ?').get(organizationName);
        if (existingOrg) {
          orgId = existingOrg.id;
        } else {
          orgId = uuidv4();
          db.prepare('INSERT INTO organizations (id, name, plan) VALUES (?, ?, ?)').run(
            orgId, organizationName, 'starter'
          );
        }
      } else {
        // Use default organization
        const defaultOrg = db.prepare('SELECT id FROM organizations LIMIT 1').get();
        orgId = defaultOrg?.id;
      }

      // Check org user limit
      if (orgId) {
        const org = db.prepare('SELECT max_users FROM organizations WHERE id = ?').get(orgId);
        const userCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE organization_id = ?').get(orgId);
        if (org && userCount.count >= org.max_users) {
          return res.status(400).json({ error: 'Organization user limit reached' });
        }
      }

      // Hash password
      const passwordHash = await bcrypt.hash(password, 12);
      const userId = uuidv4();

      // Create user
      db.prepare(`
        INSERT INTO users (id, email, password_hash, name, organization_id, role)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(userId, email, passwordHash, name, orgId, orgId ? 'org_admin' : 'user');

      // Get user data
      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);

      // Generate tokens
      const token = generateToken(user);
      const refreshToken = generateRefreshToken(user);

      res.status(201).json({
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          organizationId: user.organization_id,
        },
        token,
        refreshToken,
      });
    } catch (error) {
      console.error('Registration error:', error);
      res.status(500).json({ error: 'Registration failed' });
    }
  }
);

// Login
router.post('/login',
  authLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').exists(),
  ],
  validateRequest,
  async (req, res) => {
    try {
      const { email, password } = req.body;

      // Get user
      const user = db.prepare('SELECT * FROM users WHERE email = ? AND is_active = 1').get(email);
      if (!user) {
        return res.status(401).json({ error: 'Invalid credentials' });
      }

      // Verify password
      const validPassword = await bcrypt.compare(password, user.password_hash);
      if (!validPassword) {
        return res.status(401).json({ error: 'Invalid credentials' });
      }

      // Update last login
      db.prepare('UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(user.id);

      // Generate tokens
      const token = generateToken(user);
      const refreshToken = generateRefreshToken(user);

      res.json({
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          organizationId: user.organization_id,
        },
        token,
        refreshToken,
      });
    } catch (error) {
      console.error('Login error:', error);
      res.status(500).json({ error: 'Login failed' });
    }
  }
);

// Refresh token
router.post('/refresh', async (req, res) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token required' });
    }

    const jwt = await import('jsonwebtoken');
    const JWT_SECRET = process.env.JWT_SECRET || 'turbo-enterprise-secret-key-change-in-production';
    
    const decoded = jwt.default.verify(refreshToken, JWT_SECRET);
    if (decoded.type !== 'refresh') {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ? AND is_active = 1').get(decoded.userId);
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    const newToken = generateToken(user);
    const newRefreshToken = generateRefreshToken(user);

    res.json({
      token: newToken,
      refreshToken: newRefreshToken,
    });
  } catch (error) {
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});

// Get current user
router.get('/me', authenticate, (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  const org = user.organization_id 
    ? db.prepare('SELECT * FROM organizations WHERE id = ?').get(user.organization_id)
    : null;

  res.json({
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      quotaUsedMb: user.quota_used_mb,
      downloadsToday: user.downloads_today,
    },
    organization: org ? {
      id: org.id,
      name: org.name,
      plan: org.plan,
      maxUsers: org.max_users,
      maxStorageGb: org.max_storage_gb,
    } : null,
  });
});

// Update profile
router.put('/profile', authenticate, async (req, res) => {
  try {
    const { name, currentPassword, newPassword } = req.body;
    const userId = req.user.id;

    if (name) {
      db.prepare('UPDATE users SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
        .run(name, userId);
    }

    if (newPassword) {
      if (!currentPassword) {
        return res.status(400).json({ error: 'Current password required' });
      }

      const user = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(userId);
      const validPassword = await bcrypt.compare(currentPassword, user.password_hash);
      if (!validPassword) {
        return res.status(400).json({ error: 'Current password incorrect' });
      }

      const newHash = await bcrypt.hash(newPassword, 12);
      db.prepare('UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
        .run(newHash, userId);
    }

    const updatedUser = db.prepare('SELECT id, email, name, role FROM users WHERE id = ?').get(userId);
    res.json({ user: updatedUser });
  } catch (error) {
    res.status(500).json({ error: 'Update failed' });
  }
});

export default router;
