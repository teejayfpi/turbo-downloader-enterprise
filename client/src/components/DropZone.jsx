import { useState, useRef, useCallback } from 'react';
import {
  Upload, Link as LinkIcon, Loader2, X, Plus, Zap, Clock,
  SlidersHorizontal, ShieldCheck, Film, ChevronDown,
} from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';
import { isLikelyUrl, parseUrlList, formatDuration } from '../lib/format';

export default function DropZone({ onAdded }) {
  const [text, setText] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [showOptions, setShowOptions] = useState(false);
  const [options, setOptions] = useState({ connections: '', scheduledAt: '', checksum: '', checksumAlgo: 'sha256' });
  const [mediaInfo, setMediaInfo] = useState(null);
  const [mediaLoading, setMediaLoading] = useState(false);
  const [selectedFormat, setSelectedFormat] = useState('best');
  const inputRef = useRef(null);

  const addNotification = useDownloadStore((s) => s.addNotification);
  const settings = useDownloadStore((s) => s.settings);
  const system = useDownloadStore((s) => s.system);

  const urls = parseUrlList(text);
  const validUrls = urls.filter(isLikelyUrl);

  const buildOptions = () => {
    const opts = {};
    if (options.connections) opts.connections = parseInt(options.connections, 10);
    if (options.scheduledAt) opts.scheduledAt = new Date(options.scheduledAt).toISOString();
    if (options.checksum) {
      opts.checksum = options.checksum.trim();
      opts.checksumAlgo = options.checksumAlgo;
    }
    return opts;
  };

  const submit = useCallback(async () => {
    if (validUrls.length === 0) return;
    setIsLoading(true);
    setError(null);
    try {
      const opts = buildOptions();
      if (mediaInfo && selectedFormat !== 'best') opts.format = selectedFormat;
      await api.addDownloads(validUrls, opts);
      setText('');
      setMediaInfo(null);
      setSelectedFormat('best');
      addNotification({
        type: 'info',
        title: 'Downloads queued',
        message: `${validUrls.length} item(s) added to the queue`,
      });
      onAdded?.();
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  }, [validUrls, options, mediaInfo, selectedFormat, addNotification, onAdded]);

  const inspectMedia = async () => {
    if (validUrls.length !== 1) {
      setError('Media inspection works with a single URL at a time');
      return;
    }
    setMediaLoading(true);
    setError(null);
    try {
      const info = await api.getMediaInfo(validUrls[0]);
      setMediaInfo(info);
      setSelectedFormat('best');
    } catch (err) {
      setError(err.message);
    } finally {
      setMediaLoading(false);
    }
  };

  const onDrop = async (e) => {
    e.preventDefault();
    setIsDragging(false);
    const files = Array.from(e.dataTransfer.files).filter(
      (f) => f.type === 'text/plain' || f.name.endsWith('.txt') || f.name.endsWith('.json')
    );
    if (!files.length) return;
    const contents = await Promise.all(files.map((f) => f.text()));
    const found = contents
      .flatMap((c) => parseUrlList(c))
      .filter(isLikelyUrl);
    if (found.length) {
      setText(found.join('\n'));
      addNotification({
        type: 'info',
        title: 'URLs imported',
        message: `${found.length} URL(s) loaded from file`,
      });
    } else {
      setError('No valid URLs found in the dropped file');
    }
  };

  const isMediaUrl =
    validUrls.length === 1 &&
    system?.media?.available &&
    /youtube\.com|youtu\.be|vimeo\.com|soundcloud\.com|tiktok\.com|twitch\.tv|instagram\.com|facebook\.com|twitter\.com|x\.com|dailymotion\.com|bandcamp\.com|reddit\.com|bilibili\.com/i.test(
      validUrls[0]
    );

  return (
    <div
      className={`relative rounded-2xl border-2 border-dashed transition-all duration-300 ${
        isDragging
          ? 'border-accent bg-accent/5 drop-zone-active'
          : error
            ? 'border-error bg-error/5'
            : 'border-border-subtle bg-bg-secondary/50 hover:border-accent/50 hover:bg-bg-secondary'
      }`}
      onDragOver={(e) => {
        e.preventDefault();
        setIsDragging(true);
      }}
      onDragLeave={(e) => {
        e.preventDefault();
        setIsDragging(false);
      }}
      onDrop={onDrop}
    >
      <div className="p-6 sm:p-8">
        <div className="flex justify-center mb-4">
          <div
            className={`w-14 h-14 rounded-2xl flex items-center justify-center transition-all duration-300 ${
              isDragging ? 'bg-accent/20 scale-110' : error ? 'bg-error/20' : 'bg-bg-tertiary'
            }`}
          >
            {isLoading ? (
              <Loader2 className="w-7 h-7 text-accent animate-spin" />
            ) : error ? (
              <X className="w-7 h-7 text-error" />
            ) : isDragging ? (
              <Plus className="w-7 h-7 text-accent" />
            ) : (
              <Upload className="w-7 h-7 text-text-secondary" />
            )}
          </div>
        </div>

        <div className="text-center mb-4">
          <h2 className={`text-lg font-semibold mb-1 ${error ? 'text-error' : 'text-text-primary'}`}>
            {isDragging ? 'Drop to add downloads' : error ? 'Error' : 'Add Downloads'}
          </h2>
          <p className="text-sm text-text-secondary">
            {isDragging
              ? 'Release to queue these files'
              : error
                ? error
                : 'Paste URLs (one per line) or drop a .txt / .json list'}
          </p>
        </div>

        <div className="relative max-w-3xl mx-auto">
          <div className="absolute left-4 top-4">
            <LinkIcon className="w-5 h-5 text-text-muted" />
          </div>
          <textarea
            ref={inputRef}
            value={text}
            onChange={(e) => {
              setText(e.target.value);
              setError(null);
            }}
            placeholder={'https://example.com/file.zip\nhttps://example.com/video.mp4'}
            className={`w-full pl-12 pr-12 py-4 bg-bg-primary rounded-xl border transition-all duration-200 resize-none h-24 placeholder:text-text-muted text-sm font-mono focus:ring-2 focus:ring-accent/20 ${
              error ? 'border-error' : 'border-border-subtle focus:border-accent'
            }`}
            disabled={isLoading}
            aria-label="Download URLs"
          />
          {text && (
            <button
              type="button"
              onClick={() => {
                setText('');
                setError(null);
                setMediaInfo(null);
                inputRef.current?.focus();
              }}
              className="absolute right-4 top-4 p-1 rounded-lg hover:bg-bg-tertiary transition-colors"
              aria-label="Clear"
            >
              <X className="w-4 h-4 text-text-muted" />
            </button>
          )}
        </div>

        {validUrls.length > 0 && (
          <p className="text-center text-xs text-text-muted mt-2">
            {validUrls.length} valid URL{validUrls.length > 1 ? 's' : ''} detected
            {urls.length !== validUrls.length && ` · ${urls.length - validUrls.length} ignored`}
          </p>
        )}

        <div className="flex flex-wrap items-center justify-center gap-3 mt-4">
          <button
            type="button"
            onClick={submit}
            disabled={validUrls.length === 0 || isLoading}
            className={`px-8 py-3 rounded-xl font-semibold transition-all duration-200 flex items-center gap-2 focus-ring ${
              validUrls.length > 0 && !isLoading
                ? 'bg-gradient-to-r from-accent to-success text-bg-primary hover:shadow-lg hover:shadow-accent/30 hover:scale-[1.03]'
                : 'bg-bg-tertiary text-text-muted cursor-not-allowed'
            }`}
          >
            {isLoading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" /> Adding...
              </>
            ) : (
              <>
                <Zap className="w-5 h-5" /> Start Download
              </>
            )}
          </button>

          {isMediaUrl && (
            <button
              type="button"
              onClick={inspectMedia}
              disabled={mediaLoading}
              className="px-5 py-3 rounded-xl font-medium border border-border-subtle text-text-secondary hover:text-accent hover:border-accent/50 transition-colors flex items-center gap-2 focus-ring"
            >
              {mediaLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Film className="w-4 h-4" />}
              Fetch media info
            </button>
          )}

          <button
            type="button"
            onClick={() => setShowOptions((v) => !v)}
            className="px-5 py-3 rounded-xl font-medium border border-border-subtle text-text-secondary hover:text-accent hover:border-accent/50 transition-colors flex items-center gap-2 focus-ring"
          >
            <SlidersHorizontal className="w-4 h-4" />
            Options
            <ChevronDown className={`w-4 h-4 transition-transform ${showOptions ? 'rotate-180' : ''}`} />
          </button>
        </div>

        {mediaInfo && (
          <div className="max-w-3xl mx-auto mt-5 bg-bg-primary border border-border-subtle rounded-xl p-4 flex gap-4 animate-slide-down">
            {mediaInfo.thumbnail && (
              <img
                src={mediaInfo.thumbnail}
                alt=""
                className="w-28 h-20 object-cover rounded-lg shrink-0"
                referrerPolicy="no-referrer"
              />
            )}
            <div className="min-w-0 flex-1">
              <p className="font-semibold text-text-primary truncate">{mediaInfo.title}</p>
              <p className="text-xs text-text-muted mb-2">
                {mediaInfo.uploader} · {formatDuration(mediaInfo.duration)}
                {mediaInfo.isLive && ' · LIVE'}
              </p>
              <select
                value={selectedFormat}
                onChange={(e) => setSelectedFormat(e.target.value)}
                className="w-full px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle text-sm text-text-primary focus:border-accent"
              >
                <option value="best">Best quality (auto)</option>
                {mediaInfo.formats?.slice(0, 60).map((f) => (
                  <option key={`${f.formatId}-${f.ext}`} value={f.formatId}>
                    {f.type === 'audio' ? '♪ ' : '▶ '}
                    {f.label} · {f.ext}
                    {f.filesize ? ` · ${(f.filesize / 1048576).toFixed(1)} MB` : ''}
                  </option>
                ))}
              </select>
            </div>
            <button
              onClick={() => setMediaInfo(null)}
              className="p-1 h-fit rounded-lg hover:bg-bg-tertiary"
              aria-label="Close media info"
            >
              <X className="w-4 h-4 text-text-muted" />
            </button>
          </div>
        )}

        {showOptions && (
          <div className="max-w-3xl mx-auto mt-5 bg-bg-primary border border-border-subtle rounded-xl p-4 grid grid-cols-1 sm:grid-cols-2 gap-4 animate-slide-down">
            <label className="text-sm">
              <span className="flex items-center gap-2 text-text-secondary mb-1.5">
                <Zap className="w-4 h-4 text-accent" /> Connections per file
              </span>
              <input
                type="number"
                min="1"
                max="32"
                value={options.connections}
                onChange={(e) => setOptions({ ...options, connections: e.target.value })}
                placeholder={`Default: ${settings.connections}`}
                className="w-full px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle text-text-primary focus:border-accent"
              />
            </label>

            <label className="text-sm">
              <span className="flex items-center gap-2 text-text-secondary mb-1.5">
                <Clock className="w-4 h-4 text-accent" /> Schedule for
              </span>
              <input
                type="datetime-local"
                value={options.scheduledAt}
                onChange={(e) => setOptions({ ...options, scheduledAt: e.target.value })}
                className="w-full px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle text-text-primary focus:border-accent"
              />
            </label>

            <label className="text-sm">
              <span className="flex items-center gap-2 text-text-secondary mb-1.5">
                <ShieldCheck className="w-4 h-4 text-accent" /> Verify checksum
              </span>
              <input
                type="text"
                value={options.checksum}
                onChange={(e) => setOptions({ ...options, checksum: e.target.value })}
                placeholder="Expected hash (optional)"
                className="w-full px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle text-text-primary focus:border-accent font-mono text-xs"
              />
            </label>

            <label className="text-sm">
              <span className="text-text-secondary mb-1.5 block">Checksum algorithm</span>
              <select
                value={options.checksumAlgo}
                onChange={(e) => setOptions({ ...options, checksumAlgo: e.target.value })}
                className="w-full px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle text-text-primary focus:border-accent"
              >
                <option value="sha256">SHA-256</option>
                <option value="sha1">SHA-1</option>
                <option value="md5">MD5</option>
              </select>
            </label>
          </div>
        )}
      </div>

      {isDragging && (
        <div className="absolute inset-0 flex items-center justify-center rounded-2xl bg-accent/10 pointer-events-none">
          <div className="text-center">
            <Plus className="w-14 h-14 text-accent mx-auto mb-2" />
            <p className="text-accent font-semibold">Drop to add</p>
          </div>
        </div>
      )}
    </div>
  );
}
