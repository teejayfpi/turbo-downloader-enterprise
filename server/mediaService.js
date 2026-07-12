import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class MediaService {
  constructor() {
    this.ytDlpPath = process.env.YT_DLP_PATH || 'yt-dlp';
    this.supportedPlatforms = [
      // Video Platforms
      'youtube.com',
      'youtu.be',
      'vimeo.com',
      'dailymotion.com',
      'twitter.com',
      'x.com',
      'instagram.com',
      'tiktok.com',
      'facebook.com',
      'twitch.tv',
      // Streaming Services
      'netflix.com',
      'amazon.com/prime',
      'primevideo.com',
      'disneyplus.com',
      'disney+',
      'hbomax.com',
      'max.com',
      'hulu.com',
      'peacocktv.com',
      'paramountplus.com',
      'appletv.com',
      'apple.com/tv',
      'espn.com',
      'watch ESPN',
      'funimation.com',
      'crunchyroll.com',
      '9anime.to',
      'kissanime',
      'soap2day',
      'putlocker',
      // Music Platforms
      'soundcloud.com',
      'spotify.com',
      'bandcamp.com',
      'mixcloud.com',
      'audiomack.com',
      // Adult Platforms
      'pornhub.com',
      'xvideos.com',
      'xvideo.com',
      'xnxx.com',
      'youporn.com',
      'redtube.com',
      'tube8.com',
      // Other Platforms
      'vk.com',
      'vkontakte',
      'reddit.com',
      'megaphone.fm',
      'anchor.fm',
      'podcast',
      'bilibili.com',
      'buzzsiler.com',
      'keek.com',
      'veoh.com',
      'liveleak.com',
      'collegehumor.com',
      'dailymotion.com',
      'meta.tv',
    ];
  }

  isMediaUrl(url) {
    try {
      const parsedUrl = new URL(url);
      const hostname = parsedUrl.hostname.toLowerCase().replace('www.', '');
      return this.supportedPlatforms.some(platform => 
        hostname.includes(platform.replace('www.', ''))
      );
    } catch {
      return false;
    }
  }

  async getMediaInfo(url) {
    return new Promise((resolve, reject) => {
      const args = [
        '--dump-json',
        '--no-download',
        '--no-playlist',
        url
      ];

      const process = spawn(this.ytDlpPath, args);
      let stdout = '';
      let stderr = '';

      process.stdout.on('data', (data) => {
        stdout += data.toString();
      });

      process.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      process.on('close', (code) => {
        if (code !== 0) {
          console.error('yt-dlp error:', stderr);
          reject(new Error(`Failed to get media info: ${stderr}`));
          return;
        }

        try {
          const info = JSON.parse(stdout.trim());
          const formats = this.processFormats(info.formats || []);
          
          resolve({
            id: info.id || '',
            title: info.title || 'Unknown',
            thumbnail: info.thumbnail || '',
            duration: info.duration || 0,
            uploader: info.uploader || info.channel || 'Unknown',
            description: info.description || '',
            webpageUrl: info.webpage_url || url,
            formats: formats,
            subtitles: info.subtitles || {},
            isLive: info.is_live || false,
            wasLive: info.was_live || false,
          });
        } catch (e) {
          reject(new Error(`Failed to parse media info: ${e.message}`));
        }
      });

      process.on('error', (err) => {
        reject(new Error(`yt-dlp process error: ${err.message}`));
      });
    });
  }

  processFormats(formats) {
    const seen = new Set();
    const processed = [];

    formats.sort((a, b) => {
      const heightA = a.height || 0;
      const heightB = b.height || 0;
      return heightB - heightA;
    });

    for (const fmt of formats) {
      const formatId = `${fmt.format_id}-${fmt.ext}`;
      if (seen.has(formatId)) continue;
      seen.add(formatId);

      const formatInfo = {
        formatId: fmt.format_id,
        ext: fmt.ext || 'mp4',
        quality: fmt.format_note || fmt.format || 'unknown',
        width: fmt.width || 0,
        height: fmt.height || 0,
        filesize: fmt.filesize || fmt.filesize_approx || 0,
        fps: fmt.fps || 0,
        vcodec: fmt.vcodec || 'none',
        acodec: fmt.acodec || 'none',
        tbr: fmt.tbr || 0,
        container: fmt.container || fmt.ext || '',
      };

      if (fmt.vcodec !== 'none' && fmt.acodec !== 'none') {
        formatInfo.type = 'video';
        formatInfo.label = this.getQualityLabel(fmt.height, true);
      } else if (fmt.vcodec !== 'none') {
        formatInfo.type = 'video';
        formatInfo.label = this.getQualityLabel(fmt.height, false);
      } else if (fmt.acodec !== 'none') {
        formatInfo.type = 'audio';
        formatInfo.label = this.getAudioLabel(fmt.ext, fmt.tbr);
      } else {
        continue;
      }

      processed.push(formatInfo);
    }

    return processed;
  }

  getQualityLabel(height, hasAudio) {
    if (!height) return hasAudio ? 'Audio+Video' : 'Video Only';
    
    const labels = {
      4320: '8K',
      2160: '4K',
      1440: '2K',
      1080: '1080p',
      720: '720p',
      480: '480p',
      360: '360p',
      240: '240p',
      144: '144p',
    };

    const label = labels[height] || `${height}p`;
    return hasAudio ? label : `${label} (no audio)`;
  }

  getAudioLabel(ext, bitrate) {
    const quality = bitrate ? `${Math.round(bitrate)}kbps` : '';
    const codec = ext === 'mp3' ? 'MP3' : ext === 'm4a' ? 'AAC' : ext.toUpperCase();
    return quality ? `${codec} ${quality}` : codec;
  }

  async downloadMedia(url, options = {}) {
    const {
      formatId = 'best',
      outputPath = './downloads',
      filename = '%(title)s.%(ext)s',
      onProgress = null,
    } = options;

    return new Promise((resolve, reject) => {
      const args = [
        '-f', formatId,
        '-o', path.join(outputPath, filename),
        '--newline',
        '--progress',
        url
      ];

      const process = spawn(this.ytDlpPath, args);
      let stdout = '';
      let stderr = '';

      process.stdout.on('data', (data) => {
        const line = data.toString();
        stdout += line;
        
        if (onProgress && line.includes('%')) {
          const progressMatch = line.match(/(\d+\.?\d*)%/);
          if (progressMatch) {
            onProgress({
              progress: parseFloat(progressMatch[1]),
            });
          }
        }
      });

      process.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      process.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(`Download failed: ${stderr}`));
          return;
        }

        const downloadMatch = stdout.match(/\[download\]\s+Destination:\s+(.+)/);
        const filepath = downloadMatch ? downloadMatch[1].trim() : null;

        resolve({
          success: true,
          filepath: filepath,
          output: stdout,
        });
      });

      process.on('error', (err) => {
        reject(new Error(`yt-dlp process error: ${err.message}`));
      });
    });
  }

  async downloadAudio(url, options = {}) {
    return this.downloadMedia(url, {
      ...options,
      formatId: 'bestaudio/best',
      filename: '%(title)s.%(ext)s',
    });
  }
}

export default new MediaService();
