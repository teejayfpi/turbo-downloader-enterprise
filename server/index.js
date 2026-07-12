import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { DownloadManager } from './downloadManager.js';
import { SettingsManager } from './settingsManager.js';
import mediaService from './mediaService.js';
import downloadRoutes from './routes/downloads.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE']
  }
});

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false,
}));
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

const downloadManager = new DownloadManager(io);
const settingsManager = new SettingsManager();

// Download routes (no auth required)
app.use('/api/downloads', downloadRoutes);

// Settings routes
app.get('/api/settings', (req, res) => {
  res.json(settingsManager.getSettings());
});

app.put('/api/settings', (req, res) => {
  try {
    settingsManager.updateSettings(req.body);
    res.json(settingsManager.getSettings());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/stats', (req, res) => {
  res.json(downloadManager.getStats());
});

// Media API Routes (YouTube, streaming platforms, etc.)
app.get('/api/media/info', async (req, res) => {
  try {
    const { url } = req.query;
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }
    
    const info = await mediaService.getMediaInfo(url);
    res.json(info);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/media/download', async (req, res) => {
  try {
    const { url, formatId, isAudioOnly } = req.body;
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }
    
    const settings = settingsManager.getSettings();
    const outputPath = settings.defaultDir || './downloads';
    
    let downloadPromise;
    if (isAudioOnly) {
      downloadPromise = mediaService.downloadAudio(url, {
        outputPath,
        onProgress: (progress) => {
          io.emit('media:progress', { url, ...progress });
        }
      });
    } else {
      downloadPromise = mediaService.downloadMedia(url, {
        formatId: formatId || 'best',
        outputPath,
        onProgress: (progress) => {
          io.emit('media:progress', { url, ...progress });
        }
      });
    }
    
    const result = await downloadPromise;
    
    // Create download entry
    const downloads = await downloadManager.addDownloads([url], {
      ...settings,
      filename: result.filepath ? result.filepath.split('/').pop() : undefined
    });
    
    res.json({
      success: true,
      filepath: result.filepath,
      download: downloads[0]
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/media/supported', (req, res) => {
  res.json({
    supported: true,
    platforms: [
      // Video Platforms
      'YouTube',
      'Vimeo',
      'Dailymotion',
      'TikTok',
      'Instagram',
      'Facebook',
      'Twitter/X',
      'Twitch',
      // Streaming Services
      'Netflix',
      'Prime Video',
      'Disney+',
      'HBO Max',
      'Hulu',
      'Peacock',
      'Paramount+',
      'Apple TV+',
      'ESPN',
      // Anime
      'Crunchyroll',
      'Funimation',
      // Music
      'SoundCloud',
      'Spotify',
      'Bandcamp',
      'Mixcloud',
      // Other
      'VK',
      'Reddit',
      'Bilibili',
    ],
    categories: {
      video: ['YouTube', 'Vimeo', 'TikTok', 'Instagram', 'Facebook', 'Twitter/X', 'Twitch', 'Bilibili'],
      streaming: ['Netflix', 'Prime Video', 'Disney+', 'HBO Max', 'Hulu', 'Peacock', 'Paramount+', 'Apple TV+'],
      anime: ['Crunchyroll', 'Funimation'],
      music: ['SoundCloud', 'Spotify', 'Bandcamp', 'Mixcloud'],
    }
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// API documentation
app.get('/api/docs', (req, res) => {
  res.json({
    name: 'Turbo Downloader API',
    version: '1.0.0',
    endpoints: {
      downloads: {
        'GET /api/downloads': 'Get downloads',
        'POST /api/downloads': 'Create download',
        'PUT /api/downloads/:id': 'Update download',
        'DELETE /api/downloads/:id': 'Delete download',
      },
      media: {
        'GET /api/media/info': 'Get media info',
        'POST /api/media/download': 'Download media',
        'GET /api/media/supported': 'Get supported platforms',
      },
    },
  });
});

// Serve static files in production (MUST be last)
app.use(express.static(join(__dirname, '../client/dist')));
app.get('/{*splat}', (req, res) => {
  res.sendFile(join(__dirname, '../client/dist/index.html'));
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
  console.log(`🚀 Turbo Downloader running on port ${PORT}`);
});
