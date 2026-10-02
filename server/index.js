import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

import { engine, settingsManager, attachSocket } from './context.js';
import mediaService from './mediaService.js';
import downloadRoutes from './routes/downloads.js';
import { validateHttpUrl, assertPublicHost } from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: process.env.CORS_ORIGIN || '*', methods: ['GET', 'POST', 'PUT', 'DELETE'] },
});

app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
app.use(cors({ origin: process.env.CORS_ORIGIN || '*', credentials: true }));
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true, limit: '5mb' }));

const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', apiLimiter);

// ------------------------------------------------------------------ API routes

app.use('/api/downloads', downloadRoutes);

app.get('/api/settings', (req, res) => {
  res.json(settingsManager.getSettings());
});

app.put('/api/settings', (req, res) => {
  try {
    res.json(settingsManager.updateSettings(req.body || {}));
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
    version: '2.0.0',
    media: mediaService.info(),
    downloadDir: settingsManager.getSettings().defaultDir,
    uptime: process.uptime(),
    node: process.version,
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
      'Bilibili', 'VK', 'Netflix', 'Prime Video', 'Disney+', 'HBO Max',
      'Hulu', 'Peacock', 'Paramount+', 'Crunchyroll', 'Spotify',
    ],
  });
});

// Export / import of the download list
app.get('/api/export', (req, res) => {
  const payload = {
    exportedAt: new Date().toISOString(),
    version: '2.0.0',
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
    version: '2.0.0',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    media: mediaService.info(),
  });
});

app.get('/api/docs', (req, res) => {
  res.json({
    name: 'Turbo Downloader API',
    version: '2.0.0',
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
httpServer.listen(PORT, () => {
  console.log(`🚀 Turbo Downloader API on port ${PORT}`);
  console.log(`   Download dir: ${settingsManager.getSettings().defaultDir}`);
  console.log(`   yt-dlp: ${mediaService.isAvailable() ? `available (${mediaService.version})` : 'not installed (media downloads disabled)'}`);
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
