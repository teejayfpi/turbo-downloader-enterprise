import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import crypto from 'crypto';
import http from 'http';
import https from 'https';
import { pipeline } from 'stream/promises';
import { v4 as uuidv4 } from 'uuid';
import db from './database.js';
import mediaService from './mediaService.js';
import {
  extractFilename,
  detectPlatform,
  isMediaPlatform,
  safeFilename,
  validateHttpUrl,
  assertPublicHost,
  pinnedLookup,
} from './utils.js';

// The pool must be at least as large as the worst case the settings allow
// (max concurrent downloads x max segments), or node silently queues the
// surplus requests on a free socket and a raised concurrency setting delivers
// no extra throughput. `maxSockets` is a cap, not an allocation, so a large
// value costs nothing when the client stays at its defaults.
const MAX_INFLIGHT_STREAMS = 20 * 32;
const HTTP_AGENT = new http.Agent({ keepAlive: true, maxSockets: MAX_INFLIGHT_STREAMS });
const HTTPS_AGENT = new https.Agent({ keepAlive: true, maxSockets: MAX_INFLIGHT_STREAMS });
const TICK_MS = 500;
const SPEED_WINDOW_MS = 3000;
const SEGMENT_THRESHOLD = 4 * 1024 * 1024; // multi-connection above 4 MB
const MIN_SEGMENT_BYTES = 1 * 1024 * 1024; // never split a chunk below 1 MB
const CHUNK_TARGET_BYTES = 3 * 1024 * 1024; // aim for chunks this size
const MAX_CHUNKS = 256; // cap part files and plan rows for one download
const MAX_SEGMENT_STREAMS = 24; // in-flight segment sockets for a single file
const WRITE_HIGH_WATER_MARK = 1 * 1024 * 1024; // buffered bytes per part file
const USER_AGENT = 'Mozilla/5.0 (compatible; TurboDownloader/2.0)';

/**
 * Runs `worker` over `items` with at most `limit` in flight. Used so a raised
 * segment count cannot open an unbounded number of sockets at once, which on a
 * large file would exhaust file descriptors and collapse throughput.
 */
async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  const runners = Array.from(
    { length: Math.max(1, Math.min(limit, items.length)) },
    async () => {
      for (let i = next++; i < items.length; i = next++) {
        results[i] = await worker(items[i], i);
      }
    },
  );
  await Promise.all(runners);
  return results;
}

const COLUMNS = [
  'id', 'url', 'filename', 'filepath', 'total', 'downloaded', 'status',
  'progress', 'speed', 'error', 'platform', 'kind', 'format', 'connections',
  'priority', 'resume_supported', 'checksum', 'checksum_algo', 'scheduled_at',
  'started_at', 'completed_at', 'created_at',
];

function rowToTask(row) {
  if (!row) return null;
  return {
    id: row.id,
    url: row.url,
    filename: row.filename,
    filepath: row.filepath,
    total: row.total || 0,
    downloaded: row.downloaded || 0,
    status: row.status,
    progress: row.progress || 0,
    speed: row.speed || 0,
    error: row.error,
    platform: row.platform,
    kind: row.kind || 'http',
    format: row.format || 'best',
    connections: row.connections || 8,
    priority: row.priority || 0,
    resumeSupported: !!row.resume_supported,
    checksum: row.checksum || null,
    checksumAlgo: row.checksum_algo || null,
    scheduledAt: row.scheduled_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
    _lastBytes: row.downloaded || 0,
    _lastTick: Date.now(),
    _samples: [],
    _requests: new Set(),
    _segments: null,
    _cancel: false,
    _paused: false,
    retryAt: null,
    retryCount: 0,
  };
}

export class DownloadEngine {
  constructor(io, settingsManager) {
    this.io = io;
    this.settings = settingsManager;
    this.tasks = new Map();
    this.peakSpeed = 0;
    this.speedHistory = [];
    this.dirty = true;
    this.timer = null;
    this.stopping = false;
  }

  init() {
    const rows = db.prepare('SELECT * FROM downloads ORDER BY created_at ASC').all();
    for (const row of rows) {
      const task = rowToTask(row);
      if (['active', 'downloading'].includes(task.status)) {
        task.status = 'queued';
        task.speed = 0;
        this.persist(task);
      }
      this.tasks.set(task.id, task);
    }
    this.timer = setInterval(() => this.tick(), TICK_MS);
    this.timer.unref?.();
    this.pump();
  }

  // ---------------------------------------------------------------- persistence

  persist(task) {
    const record = {
      id: task.id,
      url: task.url,
      filename: task.filename,
      filepath: task.filepath,
      total: Math.round(task.total || 0),
      downloaded: Math.round(task.downloaded || 0),
      status: task.status,
      progress: Number((task.progress || 0).toFixed(2)),
      speed: Math.round(task.speed || 0),
      error: task.error || null,
      platform: task.platform || 'Unknown',
      kind: task.kind || 'http',
      format: task.format || 'best',
      connections: task.connections || 8,
      priority: task.priority || 0,
      resume_supported: task.resumeSupported ? 1 : 0,
      checksum: task.checksum || null,
      checksum_algo: task.checksumAlgo || null,
      scheduled_at: task.scheduledAt || null,
      started_at: task.startedAt || null,
      completed_at: task.completedAt || null,
      created_at: task.createdAt || new Date().toISOString(),
    };
    const placeholders = COLUMNS.map((c) => `@${c}`).join(', ');
    const updates = COLUMNS.filter((c) => c !== 'id').map((c) => `${c} = @${c}`).join(', ');
    db.prepare(`
      INSERT INTO downloads (${COLUMNS.join(', ')}) VALUES (${placeholders})
      ON CONFLICT(id) DO UPDATE SET ${updates}
    `).run(record);
    this.dirty = true;
  }

  // ---------------------------------------------------------------- public API

  async add({ urls, options = {} }) {
    const list = (Array.isArray(urls) ? urls : [urls]).filter(Boolean);
    const created = [];

    for (const rawUrl of list) {
      const url = String(rawUrl).trim();
      const parsed = validateHttpUrl(url);
      const platform = detectPlatform(url);
      const kind = isMediaPlatform(platform) && mediaService.isAvailable() ? 'media' : 'http';

      let scheduledAt = null;
      if (options.scheduledAt) {
        const when = new Date(options.scheduledAt);
        if (!Number.isNaN(when.getTime()) && when.getTime() > Date.now()) {
          scheduledAt = when.toISOString();
        }
      }

      const task = {
        id: uuidv4(),
        url,
        filename: safeFilename(options.filename || extractFilename(url)),
        filepath: null,
        total: 0,
        downloaded: 0,
        status: scheduledAt ? 'scheduled' : 'queued',
        progress: 0,
        speed: 0,
        error: null,
        platform,
        kind,
        format: options.format || options.formatId || 'best',
        connections: options.connections || this.settings.getSettings().connections,
        priority: options.priority || 0,
        resumeSupported: false,
        checksum: options.checksum || null,
        checksumAlgo: options.checksumAlgo || null,
        scheduledAt,
        startedAt: null,
        completedAt: null,
        createdAt: new Date().toISOString(),
        _lastBytes: 0,
        _lastTick: Date.now(),
        _samples: [],
        _requests: new Set(),
        _segments: null,
        _running: false,
        _cancel: false,
        _paused: false,
        retryAt: null,
        retryCount: 0,
      };

      await assertPublicHost(parsed.hostname);

      this.tasks.set(task.id, task);
      this.persist(task);
      created.push(task);
    }

    this.dirty = true;
    this.pump();
    this.emit();
    return created.map((t) => this.serialize(t));
  }

  start(id) {
    const task = this.tasks.get(id);
    if (!task) throw new Error('Download not found');
    if (task.status === 'completed') return this.serialize(task);
    task.status = 'queued';
    task.error = null;
    task.retryAt = null;
    task.retryCount = 0;
    this.persist(task);
    this.pump();
    this.emit();
    return this.serialize(task);
  }

  async pause(id) {
    const task = this.tasks.get(id);
    if (!task) throw new Error('Download not found');
    if (task.status === 'active') {
      task._paused = true;
      this.abort(task);
      task.status = 'paused';
      task.speed = 0;
      this.persist(task);
    } else if (task.status === 'queued' || task.status === 'scheduled') {
      task.status = 'paused';
      this.persist(task);
    }
    this.emit();
    return this.serialize(task);
  }

  async resume(id) {
    const task = this.tasks.get(id);
    if (!task) throw new Error('Download not found');
    if (!['paused', 'failed'].includes(task.status)) return this.serialize(task);
    task._paused = false;
    task._cancel = false;
    task.error = null;
    task.status = 'queued';
    task.retryAt = null;
    this.persist(task);
    this.pump();
    this.emit();
    return this.serialize(task);
  }

  async retry(id) {
    const task = this.tasks.get(id);
    if (!task) throw new Error('Download not found');
    task._paused = false;
    task._cancel = false;
    task.error = null;
    task.retryCount = 0;
    task.retryAt = null;
    task.status = 'queued';
    this.persist(task);
    this.pump();
    this.emit();
    return this.serialize(task);
  }

  async remove(id, { deleteFile = false } = {}) {
    const task = this.tasks.get(id);
    if (!task) throw new Error('Download not found');
    task._cancel = true;
    this.abort(task);
    if (deleteFile) await this.cleanupArtifacts(task, true);
    this.tasks.delete(id);
    db.prepare('DELETE FROM downloads WHERE id = ?').run(id);
    this.dirty = true;
    this.pump();
    this.emit();
    return { success: true };
  }

  async pauseAll() {
    for (const task of Array.from(this.tasks.values())) {
      if (task.status === 'active') await this.pause(task.id);
    }
  }

  async resumeAll() {
    for (const task of Array.from(this.tasks.values())) {
      if (task.status === 'paused') await this.resume(task.id);
    }
    this.pump();
  }

  clearCompleted() {
    for (const [id, task] of this.tasks) {
      if (task.status === 'completed') {
        this.tasks.delete(id);
        db.prepare('DELETE FROM downloads WHERE id = ?').run(id);
      }
    }
    this.dirty = true;
    this.emit();
    return { success: true };
  }

  reorder(ids) {
    if (!Array.isArray(ids)) throw new Error('ids array required');
    ids.forEach((id, index) => {
      const task = this.tasks.get(id);
      if (task) {
        task.priority = ids.length - index;
        this.persist(task);
      }
    });
    this.dirty = true;
    this.pump();
    this.emit();
    return this.getDownloads();
  }

  getDownloads() {
    return Array.from(this.tasks.values())
      .sort((a, b) => {
        if (a.priority !== b.priority) return b.priority - a.priority;
        return new Date(b.createdAt) - new Date(a.createdAt);
      })
      .map((t) => this.serialize(t));
  }

  getDownload(id) {
    const task = this.tasks.get(id);
    return task ? this.serialize(task) : null;
  }

  getStats() {
    let totalSpeed = 0;
    let activeCount = 0;
    let completedCount = 0;
    let failedCount = 0;
    let queuedCount = 0;
    let totalDownloaded = 0;

    for (const task of this.tasks.values()) {
      if (task.status === 'active') {
        activeCount++;
        totalSpeed += task.speed || 0;
      }
      if (task.status === 'completed') completedCount++;
      if (task.status === 'failed') failedCount++;
      if (task.status === 'queued' || task.status === 'scheduled') queuedCount++;
      totalDownloaded += task.downloaded || 0;
    }

    if (totalSpeed > this.peakSpeed) this.peakSpeed = totalSpeed;

    return {
      totalDownloaded,
      totalSpeed,
      peakSpeed: this.peakSpeed,
      activeCount,
      completedCount,
      failedCount,
      queuedCount,
      totalCount: this.tasks.size,
    };
  }

  serialize(task) {
    return {
      id: task.id,
      url: task.url,
      filename: task.filename,
      filepath: task.filepath,
      total: Math.round(task.total || 0),
      downloaded: Math.round(task.downloaded || 0),
      speed: Math.round(task.speed || 0),
      progress: Number((task.progress || 0).toFixed(2)),
      status: task.status,
      error: task.error || null,
      errorCode: task.errorCode || null,
      platform: task.platform,
      kind: task.kind,
      format: task.format,
      connections: task.connections,
      priority: task.priority,
      resumeSupported: task.resumeSupported,
      segments: task._segments ? task._segments.length : 1,
      checksum: task.checksum,
      checksumAlgo: task.checksumAlgo,
      scheduledAt: task.scheduledAt,
      startedAt: task.startedAt,
      completedAt: task.completedAt,
      createdAt: task.createdAt,
      eta: this.computeEta(task),
    };
  }

  computeEta(task) {
    if (task.status !== 'active' || !task.speed || !task.total) return null;
    const remaining = task.total - task.downloaded;
    if (remaining <= 0) return 0;
    return Math.round(remaining / task.speed);
  }

  // ---------------------------------------------------------------- scheduler

  tick() {
    if (this.stopping) return;
    const now = Date.now();

    for (const task of this.tasks.values()) {
      if (task.status === 'scheduled' && task.scheduledAt && new Date(task.scheduledAt).getTime() <= now) {
        task.status = 'queued';
        this.persist(task);
      }
      if (task.status === 'active') this.updateSpeed(task, now);
    }

    this.pump();

    const stats = this.getStats();
    this.speedHistory.push(Math.round(stats.totalSpeed));
    const max = this.settings.getSettings().maxSpeedHistory || 60;
    if (this.speedHistory.length > max) this.speedHistory.shift();

    if (this.dirty || stats.activeCount > 0) {
      this.emit();
      this.dirty = false;
    }
  }

  updateSpeed(task, now) {
    const dt = (now - task._lastTick) / 1000;
    if (dt <= 0) return;
    const instant = (task.downloaded - task._lastBytes) / dt;
    task.speed = task.speed ? task.speed * 0.6 + instant * 0.4 : instant;
    task._lastBytes = task.downloaded;
    task._lastTick = now;
    if (task.total > 0) task.progress = Math.min((task.downloaded / task.total) * 100, 100);
    task._samples.push({ t: now, bytes: task.downloaded });
    while (task._samples.length && now - task._samples[0].t > SPEED_WINDOW_MS) {
      task._samples.shift();
    }
  }

  activeCount() {
    let n = 0;
    for (const t of this.tasks.values()) if (t.status === 'active') n++;
    return n;
  }

  pump() {
    if (this.stopping) return;
    const { concurrentDownloads } = this.settings.getSettings();
    let active = this.activeCount();

    const queued = Array.from(this.tasks.values())
      .filter((t) => t.status === 'queued' && (!t.retryAt || t.retryAt <= Date.now()))
      .sort((a, b) => {
        if (a.priority !== b.priority) return b.priority - a.priority;
        return new Date(a.createdAt) - new Date(b.createdAt);
      });

    for (const task of queued) {
      if (active >= concurrentDownloads) break;
      active++;
      this.run(task);
    }
  }

  run(task) {
    if (task._running) return;
    task._running = true;
    const runner = task.kind === 'media' ? this.runMedia(task) : this.runHttp(task);
    runner
      .catch((error) => this.handleFailure(task, error))
      .finally(() => {
        task._running = false;
        if (task.status === 'queued') this.pump();
      });
  }

  // ---------------------------------------------------------------- http engine

  async runHttp(task) {
    if (task._cancel || task._paused) return;
    task.status = 'active';
    task.error = null;
    task.startedAt = task.startedAt || new Date().toISOString();
    task._lastBytes = task.downloaded;
    task._lastTick = Date.now();
    this.persist(task);
    this.emit();

    const urlObj = validateHttpUrl(task.url);
    const address = await assertPublicHost(urlObj.hostname);

    const dir = this.settings.ensureDownloadDir();
    if (!task.filepath) {
      task.filepath = await this.resolveFilepath(dir, task);
      if (!task.filepath) {
        task.status = 'completed';
        task.progress = 100;
        task.completedAt = new Date().toISOString();
        task.error = 'Skipped: file already exists';
        this.persist(task);
        this.notify('warning', 'Download Skipped', `${task.filename} already exists`);
        return;
      }
      task.filename = path.basename(task.filepath);
    }

    let finalPath = task.filepath;
    let partBase = `${finalPath}.turbo.part`;

    // If the final file is already present, there is nothing to do.
    try {
      const stat = await fsp.stat(finalPath);
      if (stat.isFile() && stat.size > 0) {
        task.total = stat.size;
        task.downloaded = stat.size;
        await this.cleanupArtifacts(task, false);
        await this.finalize(task);
        return;
      }
    } catch {
      /* not downloaded yet */
    }

    const probe = await this.probe(urlObj, task, address);
    task.resumeSupported = probe.rangeSupported;
    if (probe.total) task.total = probe.total;

    const { connections, split } = this.settings.getSettings();
    // `connections` is the requested parallelism and `split` is the ceiling.
    // Bound by both, and by the size floor so a small file is not carved into
    // segments too small to amortise a request.
    const parallel = Math.max(
      1,
      Math.min(task.connections || connections, split, Math.floor(probe.total / MIN_SEGMENT_BYTES)),
    );
    // Dynamic segmentation: slice the file into many more chunks than there are
    // workers. A worker pulls the next unclaimed chunk as soon as it frees up,
    // so one slow connection cannot leave a long tail and the others soak up
    // the slack. Chunk size targets CHUNK_TARGET_BYTES but never drops below
    // MIN_SEGMENT_BYTES, and the grid is capped so the file does not become
    // thousands of part files.
    const byTarget = Math.ceil(probe.total / CHUNK_TARGET_BYTES);
    const byFloor = Math.floor(probe.total / MIN_SEGMENT_BYTES);
    const chunkCount = Math.max(1, Math.min(Math.max(parallel, byTarget), byFloor, MAX_CHUNKS));

    if (probe.rangeSupported && probe.total >= SEGMENT_THRESHOLD && chunkCount > 1) {
      await this.downloadSegmented(task, urlObj, finalPath, probe.total, chunkCount, parallel, address);
    } else {
      await this.downloadSingle(task, urlObj, finalPath, partBase, address);
    }

    if (task._cancel || task._paused) return;
    await this.finalize(task);
  }

  baseHeaders() {
    return {
      'User-Agent': USER_AGENT,
      Accept: '*/*',
      'Accept-Encoding': 'identity',
    };
  }

  async probe(urlObj, task, address = null) {
    try {
      const { res } = await this.request(urlObj, { ...this.baseHeaders(), Range: 'bytes=0-0' }, 0, address);
      const status = res.statusCode;
      const headers = res.headers;
      res.destroy();
      if (status >= 400) return { rangeSupported: false, total: 0 };
      if (status === 206 && headers['content-range']) {
        const total = parseInt(headers['content-range'].split('/')[1], 10);
        return { rangeSupported: true, total: Number.isFinite(total) ? total : 0 };
      }
      const total = parseInt(headers['content-length'], 10) || 0;
      return { rangeSupported: false, total };
    } catch {
      return { rangeSupported: false, total: 0 };
    }
  }

  async downloadSingle(task, urlObj, finalPath, partBase, address = null) {
    let startByte = 0;
    try {
      const stat = await fsp.stat(partBase);
      if (stat.isFile()) startByte = stat.size;
    } catch {
      startByte = 0;
    }

    const headers = { ...this.baseHeaders() };
    if (startByte > 0) headers.Range = `bytes=${startByte}-`;

    const { res } = await this.request(urlObj, headers, 0, address);
    this.trackRequest(task, res);

    if (res.statusCode === 416 && startByte > 0) {
      res.destroy();
      task.downloaded = startByte;
      if (task.total) task.total = Math.max(task.total, startByte);
      await fsp.rename(partBase, finalPath);
      return;
    }
    if (res.statusCode >= 400) {
      res.destroy();
      throw new Error(`Server responded with HTTP ${res.statusCode}`);
    }

    const resuming = startByte > 0 && res.statusCode === 206;
    if (!resuming) startByte = 0;

    const contentLength = parseInt(res.headers['content-length'], 10) || 0;
    task.total = resuming ? startByte + contentLength : contentLength;
    task.downloaded = startByte;

    // Adopt a server-provided filename for fresh downloads.
    if (startByte === 0 && res.headers['content-disposition']) {
      const headerName = extractFilename(task.url, res.headers['content-disposition']);
      if (headerName && headerName !== 'download') {
        const dir = path.dirname(finalPath);
        const nextPath = await this.resolveFilepath(dir, { ...task, filename: headerName, filepath: null });
        if (nextPath && nextPath !== finalPath) {
          await fsp.rm(partBase, { force: true }).catch(() => {});
          task.filepath = nextPath;
          task.filename = path.basename(nextPath);
          finalPath = nextPath;
          partBase = `${nextPath}.turbo.part`;
        }
      }
    }

    const hash = task.checksum ? crypto.createHash(task.checksumAlgo || 'sha256') : null;
    const stream = fs.createWriteStream(partBase, {
      flags: resuming ? 'a' : 'w',
      highWaterMark: WRITE_HIGH_WATER_MARK,
    });
    const budget = this.perStreamBudget(1);
    res.on('data', (chunk) => {
      task.downloaded += chunk.length;
      if (hash) hash.update(chunk);
    });
    this.pace(res, budget);

    try {
      await pipeline(res, stream);
    } catch (error) {
      if (task._cancel || task._paused) return;
      throw error;
    }
    if (task._cancel || task._paused) return;

    if (task.total > 0 && task.downloaded < task.total) {
      throw new Error(`Incomplete transfer (${task.downloaded}/${task.total} bytes)`);
    }
    if (hash && task.checksum) this.verifyChecksum(hash.digest('hex'), task.checksum);

    await fsp.rename(partBase, finalPath);
  }

  async downloadSegmented(task, urlObj, finalPath, total, chunkCount, workers, address = null) {
    const chunks = this.buildChunks(total, chunkCount);
    task._segments = chunks;

    // A part file only lines up with a chunk whose boundaries match the layout
    // it was written with. The layout is derived from (total, chunkCount), and
    // chunkCount changes when the user edits connections/split or a future
    // version changes the grid, so a retry after such a change would resume at
    // offsets from the old layout and stitch corrupt bytes. Record the layout
    // and discard parts that do not match it.
    const planPath = `${finalPath}.turbo.plan`;
    let previous = null;
    try {
      previous = JSON.parse(await fsp.readFile(planPath, 'utf8'));
    } catch {
      previous = null;
    }
    if (previous && (previous.total !== total || previous.chunkCount !== chunkCount)) {
      await Promise.all(chunks.map((c) =>
        fsp.rm(`${finalPath}.turbo.part${c.index}`, { force: true }).catch(() => {})));
    }
    await fsp.writeFile(planPath, JSON.stringify({ total, chunkCount })).catch(() => {});

    // Restore progress from any existing part files.
    for (const chunk of chunks) {
      chunk.part = `${finalPath}.turbo.part${chunk.index}`;
      try {
        const stat = await fsp.stat(chunk.part);
        const expected = chunk.end - chunk.start + 1;
        if (stat.size > expected) {
          await fsp.rm(chunk.part, { force: true });
          chunk.downloaded = 0;
        } else {
          chunk.downloaded = stat.size;
        }
      } catch {
        chunk.downloaded = 0;
      }
    }
    task.downloaded = chunks.reduce((sum, c) => sum + c.downloaded, 0);

    const budget = this.perStreamBudget(workers);
    // Only `workers` sockets are open at once even though the grid can hold
    // many more chunks; the rest are claimed on demand as each worker frees up.
    const streamLimit = Math.max(1, Math.min(workers, MAX_SEGMENT_STREAMS));
    await mapLimit(chunks, streamLimit, (chunk) =>
      this.downloadSegment(task, urlObj, chunk, budget, address));

    if (task._cancel || task._paused) return;

    for (const chunk of chunks) {
      const expected = chunk.end - chunk.start + 1;
      if (chunk.downloaded < expected) {
        throw new Error(`Segment ${chunk.index} incomplete (${chunk.downloaded}/${expected})`);
      }
    }

    await this.mergeSegments(chunks, finalPath);
    await fsp.rm(`${finalPath}.turbo.plan`, { force: true }).catch(() => {});
    task.downloaded = total;

    if (task.checksum) {
      const digest = await this.hashFile(finalPath, task.checksumAlgo || 'sha256');
      this.verifyChecksum(digest, task.checksum);
    }
  }

  async downloadSegment(task, urlObj, seg, budget, address = null) {
    if (task._cancel || task._paused) return;
    const expected = seg.end - seg.start + 1;
    if (seg.downloaded >= expected) return;

    const start = seg.start + seg.downloaded;
    const headers = { ...this.baseHeaders(), Range: `bytes=${start}-${seg.end}` };

    const { res } = await this.request(urlObj, headers, 0, address);
    this.trackRequest(task, res);

    if (res.statusCode === 416 && seg.downloaded > 0) {
      res.destroy();
      seg.downloaded = expected;
      this.recomputeDownloaded(task);
      return;
    }
    if (res.statusCode >= 400) {
      res.destroy();
      throw new Error(`Server responded with HTTP ${res.statusCode}`);
    }
    if (res.statusCode === 200) {
      // Server ignored the range; cannot safely stitch segments.
      res.destroy();
      throw new Error('Server does not support range requests for this file');
    }

    const stream = fs.createWriteStream(seg.part, {
      flags: seg.downloaded > 0 ? 'a' : 'w',
      highWaterMark: WRITE_HIGH_WATER_MARK,
    });
    res.on('data', (chunk) => {
      seg.downloaded += chunk.length;
      this.recomputeDownloaded(task);
    });
    this.pace(res, budget);

    try {
      await pipeline(res, stream);
    } catch (error) {
      if (task._cancel || task._paused) return;
      throw error;
    }
  }

  buildChunks(total, count) {
    const size = Math.ceil(total / count);
    const chunks = [];
    for (let i = 0; i < count; i++) {
      const start = i * size;
      if (start >= total) break;
      chunks.push({ index: i, start, end: Math.min(start + size - 1, total - 1), downloaded: 0, part: null });
    }
    return chunks;
  }

  recomputeDownloaded(task) {
    if (!task._segments) return;
    task.downloaded = task._segments.reduce((sum, s) => sum + s.downloaded, 0);
  }

  async mergeSegments(segments, finalPath) {
    const tmp = `${finalPath}.turbo.merge`;
    const out = fs.createWriteStream(tmp, {
      flags: 'w',
      highWaterMark: WRITE_HIGH_WATER_MARK,
    });
    // A write error must fail the merge rather than hang: the write stream
    // outlives every per-part promise, so its error is latched and re-checked.
    let writeError = null;
    out.on('error', (error) => {
      writeError = error;
    });
    try {
      // `pipeline` attaches its own error/close/finish listeners to the shared
      // output stream and only releases them when that stream ends, so calling
      // it once per part accumulated listeners up to the segment count and
      // tripped MaxListenersExceededWarning at higher split values. Piping each
      // part and awaiting its own `end` keeps the listeners on the per-part
      // read stream, which is discarded after every segment.
      for (const seg of segments) {
        await new Promise((resolve, reject) => {
          const src = fs.createReadStream(seg.part, { highWaterMark: WRITE_HIGH_WATER_MARK });
          src.on('error', reject);
          src.on('end', () => (writeError ? reject(writeError) : resolve()));
          src.pipe(out, { end: false });
        });
      }
    } finally {
      await new Promise((resolve) => out.end(resolve));
    }
    if (writeError) throw writeError;
    await fsp.rename(tmp, finalPath);
    await Promise.all(segments.map((s) => fsp.rm(s.part, { force: true }).catch(() => {})));
  }

  hashFile(file, algo) {
    return new Promise((resolve, reject) => {
      const hash = crypto.createHash(algo);
      const stream = fs.createReadStream(file);
      stream.on('data', (chunk) => hash.update(chunk));
      stream.on('error', reject);
      stream.on('end', () => resolve(hash.digest('hex')));
    });
  }

  verifyChecksum(actual, expected) {
    if (String(actual).toLowerCase() !== String(expected).toLowerCase()) {
      throw new Error(`Checksum mismatch: expected ${expected}, got ${actual}`);
    }
  }

  perStreamBudget(streamCount) {
    const limitKbps = this.settings.getSettings().bandwidthLimit;
    if (!limitKbps || limitKbps <= 0) return 0;
    return Math.max(1, Math.floor((limitKbps * 1024) / Math.max(1, streamCount)));
  }

  pace(res, bytesPerSecond) {
    if (!bytesPerSecond) return;
    const windowMs = 50;
    const budget = Math.max(1, Math.floor((bytesPerSecond * windowMs) / 1000));
    let emitted = 0;
    let paused = false;
    const timer = setInterval(() => {
      emitted = 0;
      if (paused) {
        paused = false;
        res.resume();
      }
    }, windowMs);
    timer.unref?.();
    res.on('data', (chunk) => {
      emitted += chunk.length;
      if (!paused && emitted >= budget) {
        paused = true;
        res.pause();
      }
    });
    res.on('close', () => clearInterval(timer));
  }

  request(urlObj, headers, redirects = 0, address = null) {
    return new Promise((resolve, reject) => {
      if (redirects > 5) {
        reject(new Error('Too many redirects'));
        return;
      }
      const lib = urlObj.protocol === 'https:' ? https : http;
      const options = {
        headers,
        agent: urlObj.protocol === 'https:' ? HTTPS_AGENT : HTTP_AGENT,
      };
      // Pin the connection to the address that passed the SSRF check, so a
      // second DNS answer (DNS rebinding) cannot redirect the connect to a
      // private host. Node falls back to normal resolution when unset.
      if (address) options.lookup = pinnedLookup(address);
      const req = lib.get(
        urlObj,
        options,
        (res) => {
          if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
            res.destroy();
            let next;
            try {
              next = new URL(res.headers.location, urlObj);
            } catch {
              reject(new Error('Invalid redirect location'));
              return;
            }
            assertPublicHost(next.hostname)
              .then((nextAddress) => resolve(this.request(next, headers, redirects + 1, nextAddress)))
              .catch(reject);
            return;
          }
          resolve({ req, res });
        }
      );
      req.on('error', reject);
      req.setTimeout(45000, () => req.destroy(new Error('Connection timed out')));
    });
  }

  trackRequest(task, res) {
    task._requests.add(res);
    res.on('close', () => task._requests.delete(res));
  }

  // ---------------------------------------------------------------- media engine

  async runMedia(task) {
    if (task._cancel || task._paused) return;
    if (!mediaService.isAvailable()) {
      throw new Error('yt-dlp is not installed; media downloads are unavailable');
    }
    task.status = 'active';
    task.error = null;
    task.startedAt = task.startedAt || new Date().toISOString();
    this.persist(task);
    this.emit();

    const dir = this.settings.ensureDownloadDir();
    const result = await mediaService.download(task.url, {
      formatId: task.format || 'best',
      outputPath: dir,
      onProgress: (p) => {
        if (task._cancel || task._paused) return;
        if (p.total != null) task.total = p.total;
        if (p.speed != null) task.speed = p.speed;
        if (p.progress != null && task.total > 0) {
          task.downloaded = Math.round((p.progress / 100) * task.total);
        }
      },
    });

    if (task._cancel || task._paused) return;

    if (result.filepath && fs.existsSync(result.filepath)) {
      task.filepath = result.filepath;
      task.filename = path.basename(result.filepath);
      const stat = await fsp.stat(result.filepath);
      task.total = stat.size;
      task.downloaded = stat.size;
    }
    await this.finalize(task);
  }

  // ---------------------------------------------------------------- helpers

  async resolveFilepath(dir, task) {
    const { duplicateHandling } = this.settings.getSettings();
    const name = safeFilename(task.filename || 'download');
    const candidate = path.join(dir, name);

    const exists = await fsp.access(candidate).then(() => true).catch(() => false);
    if (!exists) return candidate;
    if (task.filepath && path.resolve(task.filepath) === path.resolve(candidate)) return candidate;

    if (duplicateHandling === 'overwrite') return candidate;
    if (duplicateHandling === 'skip') return null;

    const ext = path.extname(name);
    const base = path.basename(name, ext);
    for (let i = 1; i < 10000; i++) {
      const next = path.join(dir, `${base} (${i})${ext}`);
      const taken = await fsp.access(next).then(() => true).catch(() => false);
      if (!taken) return next;
    }
    return path.join(dir, `${base} (${Date.now()})${ext}`);
  }

  async cleanupArtifacts(task, removeFinal) {
    const targets = [];
    if (task.filepath) {
      targets.push(`${task.filepath}.turbo.part`);
      targets.push(`${task.filepath}.turbo.merge`);
      targets.push(`${task.filepath}.turbo.plan`);
      for (let i = 0; i < 64; i++) targets.push(`${task.filepath}.turbo.part${i}`);
      if (removeFinal) targets.push(task.filepath);
    }
    await Promise.all(targets.map((t) => fsp.rm(t, { force: true }).catch(() => {})));
    task._segments = null;
  }

  async finalize(task) {
    task.status = 'completed';
    task.completedAt = new Date().toISOString();
    task.speed = 0;
    task.progress = 100;
    if (task.filepath) {
      try {
        const stat = await fsp.stat(task.filepath);
        if (stat.size > 0) {
          task.total = stat.size;
          task.downloaded = stat.size;
        }
      } catch {
        /* ignore */
      }
    }
    this.persist(task);
    this.dirty = true;
    this.notify('success', 'Download Complete', `${task.filename} has finished`);
    this.emit();
    this.pump();
  }

  handleFailure(task, error) {
    if (task._cancel) return;
    if (task._paused) {
      task.status = 'paused';
      task.speed = 0;
      this.persist(task);
      this.emit();
      return;
    }

    task.speed = 0;
    const { maxRetries, retryWait } = this.settings.getSettings();
    task.error = error?.message || String(error);
    // A datacenter IP block is permanent for this host: retrying only spends
    // bandwidth and worsens the IP's reputation, so fail immediately and let
    // the client hand the link off to a device on a residential connection.
    task.errorCode = error?.code || null;

    if (error?.retryable !== false && task.retryCount < maxRetries) {
      task.retryCount++;
      const backoff = Math.min(Math.max(retryWait, 1) * 2 ** (task.retryCount - 1), 300);
      task.retryAt = Date.now() + backoff * 1000;
      task.status = 'queued';
      this.notify('warning', 'Retrying Download', `${task.filename}: retry ${task.retryCount}/${maxRetries} in ${backoff}s`);
    } else {
      task.status = 'failed';
      this.notify('error', 'Download Failed', `${task.filename}: ${task.error}`);
    }
    this.persist(task);
    this.dirty = true;
    this.emit();
    this.pump();
  }

  abort(task) {
    for (const res of task._requests) {
      try { res.destroy(); } catch { /* ignore */ }
    }
    task._requests.clear();
    task._segments = null;
  }

  notify(type, title, message) {
    if (!this.settings.getSettings().notifications && type !== 'error') return;
    this.io?.emit('notification', { type, title, message, timestamp: Date.now() });
  }

  emit() {
    this.io?.emit('downloads:update', {
      downloads: this.getDownloads(),
      stats: this.getStats(),
      speedHistory: this.speedHistory,
    });
  }

  shutdown() {
    this.stopping = true;
    if (this.timer) clearInterval(this.timer);
    for (const task of this.tasks.values()) {
      if (task.status === 'active') {
        task._paused = true;
        this.abort(task);
        task.status = 'queued';
        task.speed = 0;
        this.persist(task);
      }
    }
  }
}
