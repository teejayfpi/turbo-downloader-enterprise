import { v4 as uuidv4 } from 'uuid';
import Aria2 from 'aria2';
import path from 'path';
import fs from 'fs';
import os from 'os';

export class DownloadManager {
  constructor(io) {
    this.io = io;
    this.downloads = new Map();
    this.aria2 = null;
    this.stats = {
      totalDownloaded: 0,
      totalSpeed: 0,
      peakSpeed: 0,
      activeCount: 0,
      completedCount: 0,
      failedCount: 0
    };
    this.speedHistory = [];
    this.downloadDir = path.join(os.homedir(), 'TurboDownloads');
    
    this.initAria2();
  }

  async initAria2() {
    try {
      this.aria2 = new Aria2({
        host: 'localhost',
        port: 6800,
        secure: false,
        path: '/jsonrpc'
      });

      await this.aria2.open();
      console.log('✓ aria2 connected');
      
      // Ensure download directory exists
      if (!fs.existsSync(this.downloadDir)) {
        fs.mkdirSync(this.downloadDir, { recursive: true });
      }
      
      this.startProgressMonitor();
    } catch (error) {
      console.error('aria2 connection failed:', error.message);
      console.log('⚠ aria2 not running. Starting downloads in simulation mode.');
      this.aria2 = null;
    }
  }

  startProgressMonitor() {
    setInterval(async () => {
      if (!this.aria2) return;
      
      let totalSpeed = 0;
      let activeCount = 0;

      for (const [id, download] of this.downloads) {
        if (download.status === 'active' && download.gid) {
          try {
            const status = await this.aria2.call('tellStatus', download.gid);
            const speed = parseInt(status.downloadSpeed) || 0;
            const downloaded = parseInt(status.completedLength) || 0;
            const total = parseInt(status.totalLength) || 0;

            download.speed = speed;
            download.downloaded = downloaded;
            download.total = total;
            download.progress = total > 0 ? Math.round((downloaded / total) * 100) : 0;
            
            if (status.seeds) download.seeds = status.seighbors || 0;
            if (status.connections) download.connections = status.connections || 0;
            
            if (status.completedLength === status.totalLength && status.totalLength !== '0') {
              download.status = 'completed';
              download.completedAt = new Date();
              this.stats.completedCount++;
              this.emitNotification(download, 'completed');
            }

            if (speed > 0) activeCount++;
            totalSpeed += speed;
          } catch (error) {
            if (error.message.includes('Not Found') || error.message.includes('GID not found')) {
              if (download.status === 'active') {
                download.status = 'completed';
                download.completedAt = new Date();
                this.stats.completedCount++;
                this.emitNotification(download, 'completed');
              }
            }
          }
        }
      }

      this.stats.totalSpeed = totalSpeed;
      this.stats.activeCount = activeCount;
      if (totalSpeed > this.stats.peakSpeed) {
        this.stats.peakSpeed = totalSpeed;
      }

      // Track speed history for graph
      this.speedHistory.push(totalSpeed);
      if (this.speedHistory.length > 60) {
        this.speedHistory.shift();
      }

      // Emit updates
      this.io.emit('downloads:update', { 
        downloads: this.getDownloads(),
        stats: this.stats,
        speedHistory: this.speedHistory
      });
    }, 500);
  }

  emitNotification(download, type) {
    this.io.emit('notification', {
      type,
      title: type === 'completed' ? 'Download Complete' : 'Download Error',
      message: `${download.filename} has ${type}`,
      download
    });
  }

  async addDownloads(urls, options = {}) {
    const results = [];
    const connections = options.connections || 16;
    const split = options.split || connections;
    const maxConcurrent = options.concurrentDownloads || 3;

    for (const url of urls) {
      const download = {
        id: uuidv4(),
        url,
        filename: this.extractFilename(url),
        total: 0,
        downloaded: 0,
        speed: 0,
        progress: 0,
        status: 'queued',
        seeds: 0,
        connections: 0,
        createdAt: new Date(),
        options
      };

      this.downloads.set(download.id, download);
      results.push(download);
    }

    // Start downloads up to max concurrent
    let activeCount = 0;
    for (const download of results) {
      if (activeCount < maxConcurrent) {
        this.startDownload(download);
        activeCount++;
      }
    }

    this.io.emit('downloads:update', { 
      downloads: this.getDownloads(),
      stats: this.stats
    });

    return results;
  }

  async startDownload(download) {
    download.status = 'active';
    
    if (!this.aria2) {
      // Simulation mode for testing
      this.simulateDownload(download);
      return;
    }

    try {
      const gid = await this.aria2.call('addUri', [download.url], {
        dir: this.downloadDir,
        split: download.options?.split || 16,
        'max-connection-per-server': download.options?.connections || 16,
        'file-allocation': 'none',
        'continue': 'true',
        'max-tries': 5,
        'retry-wait': 30
      });

      download.gid = gid;
      console.log(`Started download: ${download.filename} (GID: ${gid})`);
    } catch (error) {
      console.error(`Failed to start download: ${download.url}`, error.message);
      download.status = 'failed';
      download.error = error.message;
      this.stats.failedCount++;
    }
  }

  async simulateDownload(download) {
    const totalSize = Math.floor(Math.random() * 500000000) + 10000000; // 10MB - 500MB
    download.total = totalSize;
    
    const interval = setInterval(() => {
      if (download.status !== 'active') {
        clearInterval(interval);
        return;
      }

      const chunkSize = Math.floor(Math.random() * 10000000) + 500000; // Variable speed simulation
      download.downloaded = Math.min(download.downloaded + chunkSize, download.total);
      download.speed = chunkSize * 2; // Instantaneous speed
      download.progress = Math.round((download.downloaded / download.total) * 100);

      this.stats.totalSpeed = download.speed;
      this.stats.peakSpeed = Math.max(this.stats.peakSpeed, download.speed);

      if (download.downloaded >= download.total) {
        download.status = 'completed';
        download.completedAt = new Date();
        download.speed = 0;
        this.stats.completedCount++;
        this.stats.activeCount = 0;
        this.emitNotification(download, 'completed');
        clearInterval(interval);
        
        // Start next queued download
        this.startNextQueued();
      }

      this.io.emit('downloads:update', { 
        downloads: this.getDownloads(),
        stats: this.stats,
        speedHistory: this.speedHistory
      });
    }, 500);
  }

  async startNextQueued() {
    const maxConcurrent = this.downloads.size > 0 
      ? (this.downloads.values().next().value?.options?.concurrentDownloads || 3)
      : 3;
    
    let activeCount = 0;
    for (const download of this.downloads.values()) {
      if (download.status === 'active') activeCount++;
    }

    if (activeCount < maxConcurrent) {
      for (const download of this.downloads.values()) {
        if (download.status === 'queued') {
          this.startDownload(download);
          break;
        }
      }
    }
  }

  async pauseDownload(id) {
    const download = this.downloads.get(id);
    if (!download) throw new Error('Download not found');

    if (download.gid && this.aria2) {
      await this.aria2.call('pause', download.gid);
    }
    
    download.status = 'paused';
    this.io.emit('downloads:update', { downloads: this.getDownloads() });
  }

  async resumeDownload(id) {
    const download = this.downloads.get(id);
    if (!download) throw new Error('Download not found');

    if (download.gid && this.aria2) {
      await this.aria2.call('unpause', download.gid);
    }
    
    download.status = 'active';
    this.io.emit('downloads:update', { downloads: this.getDownloads() });
  }

  async retryDownload(id) {
    const download = this.downloads.get(id);
    if (!download) throw new Error('Download not found');

    download.status = 'queued';
    download.downloaded = 0;
    download.progress = 0;
    download.error = null;
    
    this.startDownload(download);
    this.io.emit('downloads:update', { downloads: this.getDownloads() });
  }

  async removeDownload(id) {
    const download = this.downloads.get(id);
    if (!download) throw new Error('Download not found');

    if (download.gid && this.aria2) {
      try {
        await this.aria2.call('remove', download.gid);
      } catch (e) {
        // Ignore removal errors
      }
    }

    this.downloads.delete(id);
    this.io.emit('downloads:update', { downloads: this.getDownloads() });
  }

  async pauseAll() {
    for (const download of this.downloads.values()) {
      if (download.status === 'active') {
        await this.pauseDownload(download.id);
      }
    }
  }

  async resumeAll() {
    for (const download of this.downloads.values()) {
      if (download.status === 'paused') {
        await this.resumeDownload(download.id);
      }
    }
  }

  async clearCompleted() {
    for (const [id, download] of this.downloads) {
      if (download.status === 'completed') {
        this.downloads.delete(id);
      }
    }
    this.io.emit('downloads:update', { downloads: this.getDownloads() });
  }

  getDownloads() {
    return Array.from(this.downloads.values()).sort((a, b) => 
      new Date(b.createdAt) - new Date(a.createdAt)
    );
  }

  getDownload(id) {
    return this.downloads.get(id);
  }

  getStats() {
    return this.stats;
  }

  extractFilename(url) {
    try {
      const urlObj = new URL(url);
      const pathname = urlObj.pathname;
      const filename = path.basename(pathname);
      return filename || `download_${Date.now()}`;
    } catch {
      return `download_${Date.now()}`;
    }
  }
}
