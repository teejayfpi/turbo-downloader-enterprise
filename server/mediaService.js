import { spawn, spawnSync } from 'child_process';
import path from 'path';

const YTDLP = process.env.YT_DLP_PATH || 'yt-dlp';

function which(bin) {
  const cmd = process.platform === 'win32' ? 'where' : 'which';
  const result = spawnSync(cmd, [bin], { encoding: 'utf8' });
  return result.status === 0;
}

class MediaService {
  constructor() {
    this.path = YTDLP;
    this._available = null;
  }

  isAvailable() {
    if (this._available === null) {
      this._available = which(this.path);
      if (this._available) {
        const version = spawnSync(this.path, ['--version'], { encoding: 'utf8' });
        this.version = (version.stdout || '').trim() || 'unknown';
      }
    }
    return this._available;
  }

  info() {
    return {
      available: this.isAvailable(),
      version: this.version || null,
      path: this.path,
    };
  }

  async getMediaInfo(url) {
    if (!this.isAvailable()) {
      throw new Error('yt-dlp is not installed on the server');
    }
    const stdout = await this.exec(['--dump-single-json', '--no-playlist', '--no-warnings', url]);
    let info;
    try {
      info = JSON.parse(stdout.trim());
    } catch (error) {
      throw new Error(`Failed to parse media info: ${error.message}`);
    }
    return {
      id: info.id || '',
      title: info.title || 'Unknown',
      thumbnail: info.thumbnail || '',
      duration: info.duration || 0,
      uploader: info.uploader || info.channel || 'Unknown',
      description: (info.description || '').slice(0, 2000),
      webpageUrl: info.webpage_url || url,
      isLive: info.is_live || false,
      formats: this.processFormats(info.formats || []),
    };
  }

  processFormats(formats) {
    const processed = [];
    const seen = new Set();

    for (const fmt of formats) {
      const key = `${fmt.format_id}-${fmt.ext}`;
      if (seen.has(key)) continue;
      seen.add(key);

      const hasVideo = fmt.vcodec && fmt.vcodec !== 'none';
      const hasAudio = fmt.acodec && fmt.acodec !== 'none';
      if (!hasVideo && !hasAudio) continue;

      processed.push({
        formatId: fmt.format_id,
        ext: fmt.ext || 'mp4',
        type: hasVideo ? 'video' : 'audio',
        label: hasVideo
          ? `${this.getQualityLabel(fmt.height)}${hasAudio ? '' : ' (video only)'}`
          : this.getAudioLabel(fmt.ext, fmt.abr || fmt.tbr),
        width: fmt.width || 0,
        height: fmt.height || 0,
        fps: fmt.fps || 0,
        filesize: fmt.filesize || fmt.filesize_approx || 0,
        vcodec: fmt.vcodec || 'none',
        acodec: fmt.acodec || 'none',
        tbr: fmt.tbr || 0,
      });
    }

    return processed.sort((a, b) => {
      if (a.type !== b.type) return a.type === 'video' ? -1 : 1;
      return (b.height || 0) - (a.height || 0) || (b.tbr || 0) - (a.tbr || 0);
    });
  }

  getQualityLabel(height) {
    if (!height) return 'Video';
    const labels = { 4320: '8K', 2160: '4K', 1440: '2K', 1080: '1080p', 720: '720p', 480: '480p', 360: '360p', 240: '240p', 144: '144p' };
    return labels[height] || `${height}p`;
  }

  getAudioLabel(ext, bitrate) {
    const codec = ext === 'mp3' ? 'MP3' : ext === 'm4a' ? 'AAC' : (ext || 'audio').toUpperCase();
    return bitrate ? `${codec} ${Math.round(bitrate)}kbps` : codec;
  }

  exec(args) {
    return new Promise((resolve, reject) => {
      const child = spawn(this.path, args);
      let stdout = '';
      let stderr = '';
      child.stdout.on('data', (d) => { stdout += d.toString(); });
      child.stderr.on('data', (d) => { stderr += d.toString(); });
      child.on('error', (error) => reject(new Error(`Failed to run yt-dlp: ${error.message}`)));
      child.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(cleanError(stderr) || `yt-dlp exited with code ${code}`));
          return;
        }
        resolve(stdout);
      });
    });
  }

  /** Downloads media, streaming progress back via onProgress. Resolves with the filepath. */
  download(url, { formatId = 'best', outputPath = './downloads', onProgress } = {}) {
    if (!this.isAvailable()) {
      return Promise.reject(new Error('yt-dlp is not installed on the server'));
    }

    return new Promise((resolve, reject) => {
      const template = path.join(outputPath, '%(title)s.%(ext)s');
      const args = [
        '-f', formatId === 'best' ? 'bestvideo+bestaudio/best' : formatId,
        '--merge-output-format', 'mp4',
        '-o', template,
        '--no-playlist',
        '--newline',
        '--no-warnings',
        '--print', 'after_move:filepath',
        url,
      ];

      const child = spawn(this.path, args);
      let filepath = null;
      let stderr = '';
      let settled = false;

      const handleLine = (line) => {
        const text = line.toString();

        const progressMatch = text.match(/\[download\]\s+(\d+(?:\.\d+)?)%/);
        if (progressMatch && onProgress) {
          const totalMatch = text.match(/of\s+~?\s*([\d.]+)(KiB|MiB|GiB|B)/);
          const speedMatch = text.match(/at\s+([\d.]+)(KiB|MiB|GiB|B)\/s/);
          onProgress({
            progress: parseFloat(progressMatch[1]),
            total: totalMatch ? toBytes(totalMatch[1], totalMatch[2]) : null,
            speed: speedMatch ? toBytes(speedMatch[1], speedMatch[2]) : null,
          });
        }

        const destMatch = text.match(/\[download\]\s+Destination:\s+(.+)/);
        if (destMatch) filepath = destMatch[1].trim();

        // --print after_move:filepath emits the final absolute path on its own line
        const trimmed = text.trim();
        if (trimmed && path.isAbsolute(trimmed) && /\.(mp4|mkv|webm|mp3|m4a|opus|ogg|flac|wav)$/i.test(trimmed)) {
          filepath = trimmed;
        }
      };

      child.stdout.on('data', (data) => data.toString().split('\n').forEach(handleLine));
      child.stderr.on('data', (data) => { stderr += data.toString(); });

      child.on('error', (error) => {
        if (settled) return;
        settled = true;
        reject(new Error(`Failed to run yt-dlp: ${error.message}`));
      });

      child.on('close', (code) => {
        if (settled) return;
        settled = true;
        if (code !== 0) {
          reject(new Error(cleanError(stderr) || `yt-dlp exited with code ${code}`));
          return;
        }
        if (!filepath) {
          reject(new Error('Download finished but no output file was reported'));
          return;
        }
        resolve({ success: true, filepath });
      });
    });
  }
}

function toBytes(value, unit) {
  const n = parseFloat(value);
  const multipliers = { B: 1, KiB: 1024, MiB: 1024 ** 2, GiB: 1024 ** 3 };
  return Math.round(n * (multipliers[unit] || 1));
}

function cleanError(stderr) {
  const line = stderr
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('WARNING'))
    .pop();
  return line ? line.replace(/^ERROR:\s*/, '') : '';
}

export default new MediaService();
