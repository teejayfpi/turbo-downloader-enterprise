import jwt from 'jsonwebtoken';
import db from '../database.js';

const JWT_SECRET = process.env.JWT_SECRET || 'turbo-enterprise-secret-key-change-in-production';

export const authenticate = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);
    
    // Get user from database
    const user = db.prepare('SELECT * FROM users WHERE id = ? AND is_active = 1').get(decoded.userId);
    if (!user) {
      return res.status(401).json({ error: 'User not found or inactive' });
    }

    req.user = {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      organizationId: user.organization_id,
    };
    
    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
};

export const requireAdmin = (req, res, next) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
};

export const requireOrgAdmin = (req, res, next) => {
  if (req.user.role !== 'admin' && req.user.role !== 'org_admin') {
    return res.status(403).json({ error: 'Organization admin access required' });
  }
  next();
};

export const generateToken = (user) => {
  return jwt.sign(
    { userId: user.id, email: user.email, role: user.role },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
};

export const generateRefreshToken = (user) => {
  return jwt.sign(
    { userId: user.id, type: 'refresh' },
    JWT_SECRET,
    { expiresIn: '7d' }
  );
};
