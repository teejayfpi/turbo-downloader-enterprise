import { spawn, spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';

const YTDLP = process.env.YT_DLP_PATH || 'yt-dlp';
const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg';
const COOKIES = process.env.YT_DLP_COOKIES || '';
const COOKIES_DATA = process.env.YT_DLP_COOKIES_DATA || '';
const COOKIES_FROM_BROWSER = process.env.YT_DLP_COOKIES_FROM_BROWSER || '';

// YouTube signature challenges are solved by yt-dlp-ejs running inside an
// external JS runtime. Without one, media URLs come back as HTTP 403.
// Override or disable with YT_DLP_JS_RUNTIME (e.g. "deno", "node:/path/to/node", "").
const JS_RUNTIME = process.env.YT_DLP_JS_RUNTIME === undefined
  ? 'node'
  : process.env.YT_DLP_JS_RUNTIME.trim();

const MEDIA_EXT = /\.(mp4|mkv|webm|mp3|m4a|opus|ogg|flac|wav)$/i;

/** Non-fragment media files in a directory. */
function listMediaFragments(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return [];
  }
  return entries
    .filter((name) => MEDIA_EXT.test(name) && !/\.f\d+\./.test(name) && !/\.part$/i.test(name))
    .map((name) => path.join(dir, name));
}

function which(bin) {
  const cmd = process.platform === 'win32' ? 'where' : 'which';
  const result = spawnSync(cmd, [bin], { encoding: 'utf8' });
  return result.status === 0;
}

class MediaService {
  constructor() {
    this.path = YTDLP;
    this._available = null;
    this._ffmpeg = null;
  }

  /**
   * Extra yt-dlp flags shared by metadata and download calls. Cookies are the
   * documented workaround for YouTube's "Sign in to confirm you're not a bot"
   * gate, which datacenter IPs hit on every request.
   *
   * YT_DLP_COOKIES_DATA holds the file contents directly, for hosts with an
   * ephemeral filesystem (Render, Fly, Railway) where a path would not survive
   * a deploy. It is written to a private temp file once per process.
   */
  authArgs() {
    const args = [];
    const cookieFile = this.cookieFile();
    if (cookieFile) args.push('--cookies', cookieFile);
    if (COOKIES_FROM_BROWSER) args.push('--cookies-from-browser', COOKIES_FROM_BROWSER);
    if (JS_RUNTIME) args.push('--js-runtimes', JS_RUNTIME);
    return args;
  }

  cookieFile() {
    if (COOKIES) return COOKIES;
    if (!COOKIES_DATA) return '';

    if (!this._cookieFilePath) {
      const target = path.join(os.tmpdir(), `turbo-cookies-${process.pid}.txt`);
      fs.writeFileSync(target, COOKIES_DATA, { mode: 0o600 });
      this._cookieFilePath = target;
    }
    return this._cookieFilePath;
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

  /**
   * ffmpeg is required to merge separate video and audio streams. Without it we
   * must fall back to progressive formats, since YouTube no longer serves
   * combined streams above 360p.
   */
  hasFfmpeg() {
    if (this._ffmpeg === null) {
      this._ffmpeg = which(FFMPEG);
    }
    return this._ffmpeg;
  }

  info() {
    return {
      available: this.isAvailable(),
      version: this.version || null,
      path: this.path,
      ffmpeg: this.hasFfmpeg(),
      jsRuntime: JS_RUNTIME || null,
    };
  }

  async getMediaInfo(url) {
    if (!this.isAvailable()) {
      throw new Error('yt-dlp is not installed on the server');
    }
    const stdout = await this.exec(['--dump-single-json', '--no-playlist', '--no-warnings', ...this.authArgs(), url]);
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

  /**
   * Turns a stored format choice into a yt-dlp format selector.
   *
   * An explicit single format id ("18", "251", "139-drc") is an exact request
   * and passes through untouched. Everything else is flexible, and gets a
   * combined-stream fallback: YouTube withholds the separate video and audio
   * streams from datacenter IPs, and a hard "Requested format is not available"
   * is worse for the user than a lower-resolution file that actually plays.
   * Without ffmpeg there is no merging at all, so flexible requests collapse to
   * a progressive stream (YouTube serves no combined stream above 360p).
   */
  resolveFormat(formatId) {
    const requested = (formatId || 'best').trim();

    if (/^\d+[\w-]*$/.test(requested)) return requested;

    if (!this.hasFfmpeg()) return 'best[ext=mp4]/best';

    const flexible = requested === 'best' || /bestvideo|bestaudio|\+/.test(requested);
    if (!flexible) return requested;

    const base = requested === 'best' ? 'bestvideo+bestaudio' : requested;
    return `${base}/best[ext=mp4]/best`;
  }

  /** Downloads media, streaming progress back via onProgress. Resolves with the filepath. */
  download(url, { formatId = 'best', outputPath = './downloads', onProgress } = {}) {
    if (!this.isAvailable()) {
      return Promise.reject(new Error('yt-dlp is not installed on the server'));
    }

    return new Promise((resolve, reject) => {
      const template = path.join(outputPath, '%(title)s.%(ext)s');
      const args = [
        '-f', this.resolveFormat(formatId),
        '--merge-output-format', 'mp4',
        '-o', template,
        '--no-playlist',
        '--newline',
        '--no-warnings',
      ];
      // yt-dlp looks ffmpeg up on PATH; a configured FFMPEG_PATH is only
      // visible to us, so it must be handed over explicitly or merging fails.
      if (this.hasFfmpeg()) args.push('--ffmpeg-location', FFMPEG);
      args.push(
        ...this.authArgs(),
        '--print', 'after_move:filepath',
        url,
      );

      const child = spawn(this.path, args);
      let filepath = null;
      let stderr = '';
      let settled = false;
      // Snapshot before yt-dlp writes anything, so recovery only ever considers
      // files this download produced rather than an unrelated older file.
      const preexisting = new Set(listMediaFragments(outputPath));

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

        // --print after_move:filepath emits the final path on its own line, but
        // only when ffmpeg actually merged. Without a merger yt-dlp prints
        // nothing and the separate streams stay on disk, so the path alone is
        // not trusted — existence is checked before reporting success.
        const trimmed = text.trim();
        if (trimmed && path.isAbsolute(trimmed)) filepath = trimmed;
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

        // yt-dlp can exit 0 while leaving a video and an audio fragment behind.
        // Reporting that as a completed download hands the user a broken file,
        // so fall back to recovering the merged output and fail loudly if the
        // media never came together.
        let finalPath = filepath && fs.existsSync(filepath) ? filepath : null;

        if (!finalPath) {
          const produced = listMediaFragments(outputPath).filter((f) => !preexisting.has(f));
          finalPath = produced.length === 1 ? produced[0] : null;
        }

        if (!finalPath) {
          const produced = listMediaFragments(outputPath).filter((f) => !preexisting.has(f));
          if (produced.length > 1) {
            reject(new Error(
              `Downloaded ${produced.length} separate streams but they could not be merged `
              + '(ffmpeg is unavailable or failed). Install ffmpeg, or choose a single-format option.',
            ));
            return;
          }
          reject(new Error('Download finished but no output file was produced'));
          return;
        }

        resolve({ success: true, filepath: finalPath });
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
  if (!line) return '';
  const message = line.replace(/^ERROR:\s*/, '');

  // YouTube rejects datacenter IPs with a 403 or a bot check. The raw text is
  // meaningless to a user, so it is replaced with the one thing that fixes it.
  if (
    /HTTP Error 403|unable to download video data|Sign in to confirm|not a bot/i.test(
      message,
    )
  ) {
    return (
      'YouTube refused this download from the server\'s IP address. ' +
      'Configure YT_DLP_COOKIES_DATA on the server (export cookies from a ' +
      'signed-in browser) to allow it. Other sites are unaffected.'
    );
  }
  return message;
}

export default new MediaService();
