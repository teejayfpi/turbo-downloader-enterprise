import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { timingSafeEqual } from 'crypto';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import fs from 'fs';

import { engine, settingsManager, attachSocket } from './context.js';
import mediaService from './mediaService.js';
import downloadRoutes from './routes/downloads.js';
import { validateHttpUrl, assertPublicHost } from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Single source of truth for the reported version: the package manifest. The
// number used to be hard-coded here as well and drifted from package.json.
const SERVER_VERSION = JSON.parse(
  fs.readFileSync(join(__dirname, 'package.json'), 'utf8'),
).version;

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: process.env.CORS_ORIGIN || '*', methods: ['GET', 'POST', 'PUT', 'DELETE'] },
});

app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
app.use(cors({ origin: process.env.CORS_ORIGIN || '*', credentials: true }));
// Hosted behind a reverse proxy (Render, Fly, Railway, nginx), the client IP
// only arrives in X-Forwarded-For. Without trusting the proxy, express-rate-limit
// rejects every request with ERR_ERL_UNEXPECTED_X_FORWARDED_FOR.
app.set('trust proxy', 1);
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true, limit: '5mb' }));

// Optional shared-secret gate. When TURBO_API_TOKEN is set, every /api request
// must present the token (Authorization: Bearer, X-Api-Token, or ?token=). The
// query form exists for direct file/export links opened by the browser, which
// cannot set headers. Left unset the server stays open, so existing local and
// private deployments keep working unchanged.
const API_TOKEN = (process.env.TURBO_API_TOKEN || '').trim();

// A production deployment must be authenticated. The README's Render/Fly/
// Docker guides produce a public URL, and an open server lets any caller
// retarget downloads and write files wherever they choose. Refuse to boot
// rather than expose that.
if (process.env.NODE_ENV === 'production' && !API_TOKEN) {
  console.error(
    'Refusing to start: NODE_ENV=production requires TURBO_API_TOKEN to be set.',
  );
  process.exit(1);
}

function tokenMatches(candidate) {
  if (!candidate) return false;
  const a = Buffer.from(String(candidate));
  const b = Buffer.from(API_TOKEN);
  return a.length === b.length && timingSafeEqual(a, b);
}

function presentedToken(req) {
  const header = req.get('authorization') || '';
  if (/^Bearer\s+/i.test(header)) return header.replace(/^Bearer\s+/i, '').trim();
  return req.get('x-api-token') || req.query.token || '';
}

function requireToken(req, res, next) {
  if (!API_TOKEN || tokenMatches(presentedToken(req))) return next();
  res.status(401).json({ error: 'Unauthorized' });
}

app.use('/api', requireToken);

const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
  // Never let a limiter validation error take down a request.
  validate: { xForwardedForHeader: false },
});
app.use('/api', apiLimiter);

// ------------------------------------------------------------------ API routes

app.use('/api/downloads', downloadRoutes);

app.get('/api/settings', (req, res) => {
  res.json(settingsManager.getSettings());
});

app.put('/api/settings', (req, res) => {
  try {
    const patch = { ...(req.body || {}) };
    // `defaultDir` decides where downloads are written, so leaving it
    // client-settable turns any reachable endpoint into an arbitrary file
    // write (point it at /root/.ssh, then download a file named
    // `authorized_keys`). It is configurable from the environment only.
    if ('defaultDir' in patch) {
      const requested = String(patch.defaultDir);
      const allowed = process.env.DOWNLOAD_DIR;
      if (!allowed || resolve(requested) !== resolve(allowed)) {
        return res.status(403).json({
          error: 'defaultDir is set by the DOWNLOAD_DIR environment variable.',
        });
      }
    }
    res.json(settingsManager.updateSettings(patch));
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.post('/api/settings/reset', (req, res) => {
  res.json(settingsManager.resetSettings());
});

app.get('/api/stats', (req, res) => {
  res.json(engine.getStats());
});

app.get('/api/system', (req, res) => {
  res.json({
    version: SERVER_VERSION,
    media: mediaService.info(),
    downloadDir: settingsManager.getSettings().defaultDir,
    uptime: process.uptime(),
    node: process.version,
    authRequired: Boolean(API_TOKEN),
  });
});

// Media (yt-dlp) endpoints
app.get('/api/media/info', async (req, res) => {
  try {
    const { url } = req.query;
    if (!url) return res.status(400).json({ error: 'URL is required' });
    const parsed = validateHttpUrl(url);
    await assertPublicHost(parsed.hostname);
    const info = await mediaService.getMediaInfo(url);
    res.json(info);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get('/api/media/supported', (req, res) => {
  res.json({
    available: mediaService.isAvailable(),
    version: mediaService.version || null,
    platforms: [
      'YouTube', 'Vimeo', 'Dailymotion', 'TikTok', 'Instagram', 'Facebook',
      'Twitter/X', 'Twitch', 'SoundCloud', 'Bandcamp', 'Mixcloud', 'Reddit',
      'Bilibili', 'VK',
    ],
    // Subscription streaming services are deliberately not listed: yt-dlp
    // cannot fetch DRM-protected streams, so claiming support would mislead
    // users and invite takedown complaints.
  });
});

// Export / import of the download list
app.get('/api/export', (req, res) => {
  const payload = {
    exportedAt: new Date().toISOString(),
    version: SERVER_VERSION,
    downloads: engine.getDownloads().map((d) => ({
      url: d.url,
      filename: d.filename,
      status: d.status,
      format: d.format,
      platform: d.platform,
    })),
  };
  res.setHeader('Content-Disposition', 'attachment; filename="turbo-downloads.json"');
  res.setHeader('Content-Type', 'application/json');
  res.send(JSON.stringify(payload, null, 2));
});

app.post('/api/import', async (req, res, next) => {
  try {
    const body = req.body || {};
    const items = Array.isArray(body) ? body : body.downloads || [];
    const urls = items
      .map((item) => (typeof item === 'string' ? item : item?.url))
      .filter(Boolean);
    if (!urls.length) return res.status(400).json({ error: 'No URLs found in import' });
    const created = await engine.add({ urls, options: {} });
    res.status(201).json({ imported: created.length, downloads: created });
  } catch (error) {
    next(error);
  }
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    version: SERVER_VERSION,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    media: mediaService.info(),
  });
});

app.get('/api/docs', (req, res) => {
  res.json({
    name: 'Turbo Downloader API',
    version: SERVER_VERSION,
    endpoints: {
      'GET /api/downloads': 'List downloads + stats',
      'POST /api/downloads': 'Add one or many downloads',
      'POST /api/downloads/:id/pause': 'Pause a download',
      'POST /api/downloads/:id/resume': 'Resume a download',
      'POST /api/downloads/:id/retry': 'Retry a download',
      'DELETE /api/downloads/:id': 'Remove a download (?deleteFile=true)',
      'POST /api/downloads/pause-all': 'Pause all',
      'POST /api/downloads/resume-all': 'Resume all',
      'POST /api/downloads/clear-completed': 'Clear completed',
      'POST /api/downloads/reorder': 'Reorder by priority',
      'GET /api/settings': 'Get settings',
      'PUT /api/settings': 'Update settings',
      'GET /api/media/info': 'Media metadata via yt-dlp',
      'GET /api/media/supported': 'Supported platforms + availability',
      'GET /api/export': 'Export download list',
      'POST /api/import': 'Import download list',
      'GET /api/system': 'System + engine info',
    },
  });
});

// ------------------------------------------------------------------ static SPA

const clientDist = join(__dirname, '../client/dist');
if (fs.existsSync(clientDist)) {
  app.use(
    express.static(clientDist, {
      setHeaders(res, filePath) {
        // The worker and manifest must never be served stale, or installs and
        // updates break. Hashed /assets/* stay immutable and long-cached.
        if (filePath.endsWith('sw.js')) {
          res.setHeader('Cache-Control', 'no-cache');
          res.setHeader('Service-Worker-Allowed', '/');
        } else if (filePath.endsWith('manifest.webmanifest')) {
          res.setHeader('Cache-Control', 'no-cache');
        }
      },
    })
  );
  app.get('/{*splat}', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    res.sendFile(join(clientDist, 'index.html'));
  });
}

// ------------------------------------------------------------------ sockets

// Socket.IO cannot set an Authorization header from the browser, so the token
// is also accepted from the handshake auth payload, query string, or header.
io.use((socket, next) => {
  if (!API_TOKEN) return next();
  const handshake = socket.handshake || {};
  const candidate =
    (handshake.auth && handshake.auth.token) ||
    handshake.query?.token ||
    handshake.headers?.['x-api-token'];
  if (tokenMatches(candidate)) return next();
  next(new Error('Unauthorized'));
});

attachSocket(io);

io.on('connection', (socket) => {
  socket.emit('downloads:update', {
    downloads: engine.getDownloads(),
    stats: engine.getStats(),
    speedHistory: engine.speedHistory,
  });
});

// ------------------------------------------------------------------ errors

app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// eslint-disable-next-line no-unused-vars
app.use((error, req, res, next) => {
  console.error('API error:', error);
  const status = /not found/i.test(error.message) ? 404 : 400;
  res.status(status).json({ error: error.message || 'Internal server error' });
});

// ------------------------------------------------------------------ bootstrap

const PORT = process.env.PORT || 3001;
const HOST = process.env.HOST || '0.0.0.0';
httpServer.listen(PORT, HOST, () => {
  console.log(`🚀 Turbo Downloader API on port ${PORT}`);
  console.log(`   Download dir: ${settingsManager.getSettings().defaultDir}`);
  console.log(`   yt-dlp: ${mediaService.isAvailable() ? `available (${mediaService.version})` : 'not installed (media downloads disabled)'}`);
  // Binding to a non-loopback address without a token exposes the API to the
  // network. Production refuses to start in this state; for local/private use
  // it is allowed, but never silently.
  const publicBind = HOST !== '127.0.0.1' && HOST !== '::1' && HOST !== 'localhost';
  if (!API_TOKEN && (publicBind || process.env.NODE_ENV === 'production')) {
    console.warn(
      '⚠️  WARNING: TURBO_API_TOKEN is unset on a non-loopback bind. The API ' +
        'is open to anyone who can reach this port. Set TURBO_API_TOKEN.',
    );
  }
});

function shutdown() {
  console.log('\nShutting down Turbo Downloader...');
  engine.shutdown();
  httpServer.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

export { app, httpServer, io };
