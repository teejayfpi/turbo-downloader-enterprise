import { useState, useRef, useCallback, useEffect } from 'react';
import {
  Link as LinkIcon, Loader2, X, Plus, Zap, Clock,
  SlidersHorizontal, ShieldCheck, Film, ChevronRight, AlertTriangle,
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

  // PWA shortcut: /?action=add lands here with the URL box focused.
  useEffect(() => {
    const action = new URLSearchParams(window.location.search).get('action');
    if (action === 'add') {
      inputRef.current?.focus();
      window.history.replaceState({}, '', window.location.pathname);
    }
  }, []);

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

  const canSubmit = validUrls.length > 0 && !isLoading;

  return (
    <section
      className={`panel transition-all duration-300 ${
        isDragging ? 'drop-zone-active' : ''
      } ${error ? 'ring-1 ring-error/40' : ''}`}
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
      <div className="flex items-center gap-3 px-5 sm:px-6 pt-5">
        <span className="kicker">New Transfer</span>
        <span className="flex-1 h-px bg-border-subtle" />
        <span className="kicker" style={{ letterSpacing: '0.18em' }}>
          {isDragging ? 'Release to queue' : 'Paste · drop · enter'}
        </span>
      </div>

      <div className="p-5 sm:p-6">
        <div className="relative">
          <div className="absolute left-4 top-4 pointer-events-none">
            <LinkIcon className="w-4 h-4 text-text-muted" />
          </div>
          <textarea
            ref={inputRef}
            value={text}
            onChange={(e) => {
              setText(e.target.value);
              setError(null);
            }}
            placeholder={'https://example.com/file.zip\nhttps://example.com/video.mp4'}
            className={`w-full pl-12 pr-12 py-4 bg-bg-primary rounded-sm border transition-all duration-200 resize-none h-28 placeholder:text-text-muted text-sm font-mono leading-relaxed focus:ring-2 focus:ring-accent/20 ${
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
              className="absolute right-3 top-3 p-1.5 rounded-sm text-text-muted hover:text-error hover:bg-bg-tertiary transition-colors"
              aria-label="Clear"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 mt-3 min-h-[1.25rem]">
          {validUrls.length > 0 && (
            <p className="kicker" style={{ letterSpacing: '0.18em' }}>
              <span className="text-accent">{validUrls.length}</span> ready
              {urls.length !== validUrls.length && (
                <span className="text-text-muted"> · {urls.length - validUrls.length} ignored</span>
              )}
            </p>
          )}
          {error && (
            <p className="text-xs text-error flex items-center gap-1.5">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0" /> {error}
            </p>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-2.5 mt-4">
          <button
            type="button"
            onClick={submit}
            disabled={!canSubmit}
            className={`group flex-1 sm:flex-none inline-flex items-center justify-center gap-2 px-7 py-3 rounded-sm font-bold uppercase tracking-[0.14em] text-xs transition-all duration-200 focus-ring ${
              canSubmit
                ? 'bg-accent text-bg-primary hover:brightness-110 glow-accent'
                : 'bg-bg-tertiary text-text-muted cursor-not-allowed'
            }`}
          >
            {isLoading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" /> Queuing…
              </>
            ) : (
              <>
                <Zap className="w-4 h-4" /> Start Download
                <ChevronRight className="w-3.5 h-3.5 transition-transform group-hover:translate-x-0.5" />
              </>
            )}
          </button>

          {isMediaUrl && (
            <button
              type="button"
              onClick={inspectMedia}
              disabled={mediaLoading}
              className="inline-flex items-center gap-2 px-4 py-3 rounded-sm border border-border-subtle text-text-secondary text-xs font-semibold uppercase tracking-[0.12em] hover:text-accent hover:border-accent/50 transition-colors focus-ring"
            >
              {mediaLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Film className="w-4 h-4" />}
              Fetch media info
            </button>
          )}

          <button
            type="button"
            onClick={() => setShowOptions((v) => !v)}
            className="inline-flex items-center gap-2 px-4 py-3 rounded-sm border border-border-subtle text-text-secondary text-xs font-semibold uppercase tracking-[0.12em] hover:text-accent hover:border-accent/50 transition-colors focus-ring"
          >
            <SlidersHorizontal className="w-4 h-4" />
            Options
            <ChevronRight className={`w-3.5 h-3.5 transition-transform ${showOptions ? 'rotate-90' : ''}`} />
          </button>
        </div>

        {mediaInfo && (
          <div className="mt-5 panel p-4 flex gap-4 animate-slide-down">
            {mediaInfo.thumbnail && (
              <img
                src={mediaInfo.thumbnail}
                alt=""
                className="w-28 h-20 object-cover rounded-sm shrink-0 border border-border-subtle"
                referrerPolicy="no-referrer"
              />
            )}
            <div className="min-w-0 flex-1">
              <p className="font-semibold text-text-primary truncate">{mediaInfo.title}</p>
              <p className="kicker mb-2.5" style={{ letterSpacing: '0.16em' }}>
                {mediaInfo.uploader} · {formatDuration(mediaInfo.duration)}
                {mediaInfo.isLive && ' · LIVE'}
              </p>
              <select
                value={selectedFormat}
                onChange={(e) => setSelectedFormat(e.target.value)}
                className="w-full px-3 py-2 bg-bg-secondary rounded-sm border border-border-subtle text-sm text-text-primary focus:border-accent"
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
              className="p-1 h-fit rounded-sm text-text-muted hover:text-error transition-colors"
              aria-label="Close media info"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {showOptions && (
          <div className="mt-5 panel p-5 grid grid-cols-1 sm:grid-cols-2 gap-5 animate-slide-down">
            <label className="text-sm">
              <span className="kicker mb-2 flex items-center gap-2">
                <Zap className="w-3.5 h-3.5 text-accent" /> Connections per file
              </span>
              <input
                type="number"
                min="1"
                max="32"
                value={options.connections}
                onChange={(e) => setOptions({ ...options, connections: e.target.value })}
                placeholder={`Default: ${settings.connections}`}
                className="w-full px-3 py-2 bg-bg-secondary rounded-sm border border-border-subtle text-text-primary font-mono text-sm focus:border-accent"
              />
            </label>

            <label className="text-sm">
              <span className="kicker mb-2 flex items-center gap-2">
                <Clock className="w-3.5 h-3.5 text-accent" /> Schedule for
              </span>
              <input
                type="datetime-local"
                value={options.scheduledAt}
                onChange={(e) => setOptions({ ...options, scheduledAt: e.target.value })}
                className="w-full px-3 py-2 bg-bg-secondary rounded-sm border border-border-subtle text-text-primary text-sm focus:border-accent"
              />
            </label>

            <label className="text-sm">
              <span className="kicker mb-2 flex items-center gap-2">
                <ShieldCheck className="w-3.5 h-3.5 text-accent" /> Verify checksum
              </span>
              <input
                type="text"
                value={options.checksum}
                onChange={(e) => setOptions({ ...options, checksum: e.target.value })}
                placeholder="Expected hash (optional)"
                className="w-full px-3 py-2 bg-bg-secondary rounded-sm border border-border-subtle text-text-primary focus:border-accent font-mono text-xs"
              />
            </label>

            <label className="text-sm">
              <span className="kicker mb-2 block">Checksum algorithm</span>
              <select
                value={options.checksumAlgo}
                onChange={(e) => setOptions({ ...options, checksumAlgo: e.target.value })}
                className="w-full px-3 py-2 bg-bg-secondary rounded-sm border border-border-subtle text-text-primary text-sm focus:border-accent"
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
        <div className="absolute inset-0 flex items-center justify-center bg-accent/10 pointer-events-none">
          <div className="text-center">
            <Plus className="w-12 h-12 text-accent mx-auto mb-2" />
            <p className="kicker text-accent" style={{ letterSpacing: '0.24em' }}>Drop to add</p>
          </div>
        </div>
      )}
    </section>
  );
}
