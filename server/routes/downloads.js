import express from 'express';
import { engine, settingsManager } from '../context.js';

const router = express.Router();

const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// List downloads
router.get('/', (req, res) => {
  res.json({ downloads: engine.getDownloads(), stats: engine.getStats() });
});

// Create one or more downloads
router.post('/', asyncHandler(async (req, res) => {
  const { url, urls, options = {}, format, formatId, scheduledAt, checksum, checksumAlgo, connections, filename, priority } = req.body || {};
  const list = urls || (url ? [url] : []);

  if (!Array.isArray(list) || list.length === 0) {
    return res.status(400).json({ error: 'At least one URL is required' });
  }
  if (list.length > 100) {
    return res.status(400).json({ error: 'Too many URLs in a single request (max 100)' });
  }

  const created = await engine.add({
    urls: list,
    options: {
      ...options,
      format,
      formatId: formatId || format || options.formatId,
      scheduledAt: scheduledAt || options.scheduledAt,
      checksum: checksum || options.checksum,
      checksumAlgo: checksumAlgo || options.checksumAlgo,
      connections: connections || options.connections,
      filename: filename || options.filename,
      priority: priority ?? options.priority,
    },
  });
  res.status(201).json({ downloads: created, download: created[0] });
}));

router.post('/pause-all', asyncHandler(async (req, res) => {
  await engine.pauseAll();
  res.json({ success: true, downloads: engine.getDownloads() });
}));

router.post('/resume-all', asyncHandler(async (req, res) => {
  await engine.resumeAll();
  res.json({ success: true, downloads: engine.getDownloads() });
}));

router.post('/clear-completed', (req, res) => {
  engine.clearCompleted();
  res.json({ success: true, downloads: engine.getDownloads() });
});

router.post('/reorder', (req, res) => {
  const { ids } = req.body || {};
  if (!Array.isArray(ids)) return res.status(400).json({ error: 'ids array required' });
  res.json({ downloads: engine.reorder(ids) });
});

router.get('/:id', (req, res) => {
  const download = engine.getDownload(req.params.id);
  if (!download) return res.status(404).json({ error: 'Download not found' });
  res.json({ download });
});

router.post('/:id/pause', asyncHandler(async (req, res) => {
  res.json({ download: await engine.pause(req.params.id) });
}));

router.post('/:id/resume', asyncHandler(async (req, res) => {
  res.json({ download: await engine.resume(req.params.id) });
}));

router.post('/:id/retry', asyncHandler(async (req, res) => {
  res.json({ download: await engine.retry(req.params.id) });
}));

router.post('/:id/start', asyncHandler(async (req, res) => {
  res.json({ download: engine.start(req.params.id) });
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const task = engine.tasks.get(req.params.id);
  if (!task) return res.status(404).json({ error: 'Download not found' });
  const { priority, format } = req.body || {};
  if (priority !== undefined) task.priority = Number(priority) || 0;
  if (format !== undefined) task.format = String(format);
  engine.persist(task);
  res.json({ download: engine.serialize(task) });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const deleteFile = req.query.deleteFile === 'true';
  res.json(await engine.remove(req.params.id, { deleteFile }));
}));

export default router;
