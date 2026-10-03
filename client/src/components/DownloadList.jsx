import { useState, useMemo, useRef } from 'react';
import {
  Download, Pause, Play, RotateCcw, X, CheckCircle, AlertCircle, Clock,
  Trash2, Copy, MoreVertical, ChevronDown, ChevronUp, Search,
  FileArchive, FileVideo, FileAudio, FileImage, FileText, FileCode, FileCog,
  File as FileIcon, Upload, DownloadCloud, GripVertical, CalendarClock,
} from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';
import { formatBytes, formatSpeed, formatDuration, formatRelativeTime, fileKind } from '../lib/format';

const KIND_ICONS = {
  archive: FileArchive,
  video: FileVideo,
  audio: FileAudio,
  image: FileImage,
  document: FileText,
  code: FileCode,
  app: FileCog,
  file: FileIcon,
};

const FILTERS = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'queued', label: 'Queued' },
  { key: 'completed', label: 'Completed' },
  { key: 'failed', label: 'Failed' },
];

export default function DownloadList({ loading }) {
  const downloads = useDownloadStore((s) => s.downloads);
  const filter = useDownloadStore((s) => s.filter);
  const setFilter = useDownloadStore((s) => s.setFilter);
  const addNotification = useDownloadStore((s) => s.addNotification);
  const [query, setQuery] = useState('');
  const [draggedId, setDraggedId] = useState(null);
  const fileInputRef = useRef(null);

  const counts = useMemo(() => ({
    all: downloads.length,
    active: downloads.filter((d) => d.status === 'active').length,
    queued: downloads.filter((d) => d.status === 'queued' || d.status === 'scheduled').length,
    completed: downloads.filter((d) => d.status === 'completed').length,
    failed: downloads.filter((d) => d.status === 'failed').length,
  }), [downloads]);

  const visible = useMemo(() => {
    let list = downloads;
    if (filter === 'active') list = list.filter((d) => d.status === 'active' || d.status === 'paused');
    else if (filter === 'queued') list = list.filter((d) => d.status === 'queued' || d.status === 'scheduled');
    else if (filter !== 'all') list = list.filter((d) => d.status === filter);
    if (query.trim()) {
      const q = query.toLowerCase();
      list = list.filter((d) => d.filename?.toLowerCase().includes(q) || d.url?.toLowerCase().includes(q));
    }
    return list;
  }, [downloads, filter, query]);

  const run = async (fn, successMessage) => {
    try {
      await fn();
      if (successMessage) addNotification({ type: 'success', title: 'Done', message: successMessage });
    } catch (error) {
      addNotification({ type: 'error', title: 'Action failed', message: error.message });
    }
  };

  const handleDrop = async (targetId) => {
    if (!draggedId || draggedId === targetId) return;
    const ids = downloads.map((d) => d.id);
    const from = ids.indexOf(draggedId);
    const to = ids.indexOf(targetId);
    if (from === -1 || to === -1) return;
    ids.splice(to, 0, ids.splice(from, 1)[0]);
    setDraggedId(null);
    try {
      await api.reorder(ids);
    } catch (error) {
      addNotification({ type: 'error', title: 'Reorder failed', message: error.message });
    }
  };

  const handleImport = async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    try {
      const payload = JSON.parse(await file.text());
      const result = await api.importDownloads(payload);
      addNotification({
        type: 'success',
        title: 'Import complete',
        message: `${result.imported} download(s) imported`,
      });
    } catch (error) {
      addNotification({ type: 'error', title: 'Import failed', message: error.message });
    } finally {
      event.target.value = '';
    }
  };

  return (
    <div className="panel h-full flex flex-col">
      <div className="flex flex-wrap items-center justify-between gap-3 px-5 pt-5 pb-4 border-b border-border-subtle">
        <div className="flex items-center gap-2.5">
          <Download className="w-4 h-4 text-success" />
          <span className="kicker">Queue</span>
          <span className="font-mono text-xs text-text-muted">
            {downloads.length} · drag to prioritise
          </span>
        </div>

        <div className="flex items-center gap-1.5">
          <IconAction title="Pause all" tone="warning" disabled={counts.active === 0} onClick={() => run(() => api.pauseAll(), 'All downloads paused')}>
            <Pause className="w-4 h-4" />
          </IconAction>
          <IconAction title="Resume all" tone="success" onClick={() => run(() => api.resumeAll(), 'Resuming downloads')}>
            <Play className="w-4 h-4" />
          </IconAction>
          <a
            href={api.exportUrl}
            className="p-2 rounded-sm bg-accent/10 text-accent hover:bg-accent/20 transition-colors focus-ring"
            title="Export list"
          >
            <DownloadCloud className="w-4 h-4" />
          </a>
          <IconAction title="Import list" tone="accent" onClick={() => fileInputRef.current?.click()}>
            <Upload className="w-4 h-4" />
          </IconAction>
          <input
            ref={fileInputRef}
            type="file"
            accept="application/json,.json"
            className="hidden"
            onChange={handleImport}
          />
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 px-5 py-4 border-b border-border-subtle">
        <div className="flex gap-1.5 overflow-x-auto pb-1 flex-1">
          {FILTERS.map((tab) => {
            const on = filter === tab.key;
            return (
              <button
                key={tab.key}
                onClick={() => setFilter(tab.key)}
                className={`group inline-flex items-center gap-2 px-3 py-1.5 rounded-sm border text-xs font-semibold uppercase tracking-wider transition-all whitespace-nowrap focus-ring ${
                  on
                    ? 'border-accent/50 bg-accent/12 text-accent'
                    : 'border-border-subtle text-text-muted hover:text-text-primary hover:border-border-subtle'
                }`}
              >
                {tab.label}
                <span className={`font-mono text-[10px] px-1.5 py-0.5 rounded-sm ${on ? 'bg-accent/20 text-accent' : 'bg-bg-tertiary text-text-muted'}`}>
                  {counts[tab.key] ?? 0}
                </span>
              </button>
            );
          })}
        </div>
        <div className="relative sm:w-52">
          <Search className="w-3.5 h-3.5 text-text-muted absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search downloads"
            className="w-full pl-9 pr-3 py-2 bg-bg-primary rounded-sm border border-border-subtle text-sm text-text-primary focus:border-accent"
          />
        </div>
      </div>

      <div className="space-y-2.5 overflow-y-auto p-5 flex-1 min-h-[200px] max-h-[560px]">
        {loading ? (
          [0, 1, 2].map((i) => <div key={i} className="h-24 rounded-sm skeleton" />)
        ) : visible.length === 0 ? (
          <EmptyState hasAny={downloads.length > 0} />
        ) : (
          visible.map((download) => (
            <DownloadItem
              key={download.id}
              download={download}
              onDragStart={() => setDraggedId(download.id)}
              onDropOn={() => handleDrop(download.id)}
              isDragged={draggedId === download.id}
              run={run}
            />
          ))
        )}
      </div>

      {counts.completed > 0 && (
        <div className="px-5 py-3 border-t border-border-subtle">
          <button
            onClick={() => run(() => api.clearCompleted(), 'Completed downloads cleared')}
            className="w-full py-2 rounded-sm text-xs font-semibold uppercase tracking-[0.14em] text-text-muted hover:text-error hover:bg-error/5 transition-colors flex items-center justify-center gap-2"
          >
            <Trash2 className="w-3.5 h-3.5" /> Clear completed ({counts.completed})
          </button>
        </div>
      )}
    </div>
  );
}

function EmptyState({ hasAny }) {
  return (
    <div className="h-full min-h-[220px] flex flex-col items-center justify-center text-center">
      <div className="w-14 h-14 rounded-sm border border-border-subtle flex items-center justify-center mb-4">
        <Download className="w-6 h-6 text-text-muted" />
      </div>
      <p className="kicker mb-2" style={{ letterSpacing: '0.22em' }}>
        {hasAny ? 'No match' : 'Queue empty'}
      </p>
      <p className="text-sm text-text-secondary max-w-xs">
        {hasAny
          ? 'No transfers match this view. Try another filter or search term.'
          : 'Add a URL above to begin. Transfers appear here with live progress.'}
      </p>
    </div>
  );
}

function DownloadItem({ download, onDragStart, onDropOn, isDragged, run }) {
  const [expanded, setExpanded] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const addNotification = useDownloadStore((s) => s.addNotification);

  const KindIcon = KIND_ICONS[fileKind(download.filename)] || FileIcon;

  const statusMeta = {
    active: { tone: 'text-accent', bar: 'bg-accent', Icon: Download, soft: 'bg-accent/12' },
    paused: { tone: 'text-warning', bar: 'bg-warning', Icon: Pause, soft: 'bg-warning/12' },
    completed: { tone: 'text-success', bar: 'bg-success', Icon: CheckCircle, soft: 'bg-success/12' },
    failed: { tone: 'text-error', bar: 'bg-error', Icon: AlertCircle, soft: 'bg-error/12' },
    scheduled: { tone: 'text-text-secondary', bar: 'bg-text-secondary', Icon: CalendarClock, soft: 'bg-bg-tertiary' },
    queued: { tone: 'text-text-muted', bar: 'bg-text-muted', Icon: Clock, soft: 'bg-bg-tertiary' },
  };
  const meta = statusMeta[download.status] || statusMeta.queued;
  const StatusIcon = meta.Icon;

  const copyPath = async () => {
    if (!download.filepath) return;
    try {
      await navigator.clipboard.writeText(download.filepath);
      addNotification({ type: 'info', title: 'Path copied', message: download.filepath });
    } catch {
      addNotification({ type: 'error', title: 'Copy failed', message: 'Clipboard unavailable' });
    }
  };

  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={(e) => e.preventDefault()}
      onDrop={onDropOn}
      className={`group relative bg-bg-primary rounded-sm border border-border-subtle overflow-hidden transition-all duration-200 hover:border-accent/40 ${
        isDragged ? 'opacity-50' : ''
      }`}
    >
      {/* status rail */}
      <div className={`absolute left-0 top-0 bottom-0 w-[3px] ${meta.bar} ${download.status === 'active' ? 'opacity-100' : 'opacity-60'}`} />

      <div className="pl-4 pr-4 py-3.5">
        <div className="flex items-start gap-3">
          <div className="flex flex-col items-center gap-1 shrink-0 pt-1">
            <GripVertical className="w-4 h-4 text-text-muted cursor-grab opacity-0 group-hover:opacity-60 transition-opacity" />
          </div>

          <div className={`w-10 h-10 rounded-sm flex items-center justify-center shrink-0 ${meta.soft}`}>
            <KindIcon className={`w-5 h-5 ${meta.tone}`} />
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <p className="font-medium text-text-primary truncate" title={download.filename}>
                {download.filename}
              </p>
              {download.status === 'active' && (
                <span className="px-1.5 py-0.5 rounded-sm text-[10px] font-mono bg-accent/20 text-accent shrink-0">
                  {download.progress.toFixed(0)}%
                </span>
              )}
              {download.kind === 'media' && (
                <span className="px-1.5 py-0.5 rounded-sm text-[9px] bg-warning/20 text-warning font-semibold tracking-wider shrink-0 uppercase">
                  media
                </span>
              )}
              {download.status === 'scheduled' && (
                <span className="px-1.5 py-0.5 rounded-sm text-[10px] bg-accent/20 text-accent shrink-0">
                  {formatRelativeTime(download.scheduledAt)}
                </span>
              )}
            </div>

            <p className="text-[11px] text-text-muted truncate mb-2 font-mono" title={download.url}>
              {download.url}
            </p>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
              {download.status === 'active' && (
                <>
                  <span className="font-mono text-accent speed-counter">{formatSpeed(download.speed)}</span>
                  <span className="text-text-muted font-mono text-xs">
                    {formatBytes(download.downloaded)} / {formatBytes(download.total)}
                  </span>
                  <span className="text-text-muted text-xs">ETA {formatDuration(download.eta)}</span>
                </>
              )}
              {download.status === 'paused' && (
                <span className="text-warning text-xs font-mono">
                  {formatBytes(download.downloaded)} / {formatBytes(download.total)} · paused
                </span>
              )}
              {download.status === 'completed' && (
                <span className="text-success text-xs font-mono">{formatBytes(download.total)} · completed</span>
              )}
              {download.status === 'failed' && (
                <span className="text-error text-xs line-clamp-1">{download.error || 'Download failed'}</span>
              )}
              {download.status === 'queued' && <span className="text-text-muted text-xs">Waiting in queue…</span>}
              {download.status === 'scheduled' && (
                <span className="text-text-secondary text-xs">Scheduled {formatRelativeTime(download.scheduledAt)}</span>
              )}
            </div>
          </div>

          <div className="flex items-center gap-1 shrink-0">
            {download.status === 'active' && (
              <ActionButton title="Pause" tone="warning" onClick={() => run(() => api.pauseDownload(download.id))}>
                <Pause className="w-4 h-4" />
              </ActionButton>
            )}
            {download.status === 'paused' && (
              <ActionButton title="Resume" tone="success" onClick={() => run(() => api.resumeDownload(download.id))}>
                <Play className="w-4 h-4" />
              </ActionButton>
            )}
            {(download.status === 'failed' || download.status === 'scheduled') && (
              <ActionButton
                title={download.status === 'failed' ? 'Retry' : 'Start now'}
                tone={download.status === 'failed' ? 'error' : 'accent'}
                onClick={() =>
                  run(() => (download.status === 'failed' ? api.retryDownload(download.id) : api.startDownload(download.id)))
                }
              >
                <RotateCcw className="w-4 h-4" />
              </ActionButton>
            )}
            {download.status === 'queued' && (
              <ActionButton title="Start now" tone="accent" onClick={() => run(() => api.startDownload(download.id))}>
                <Play className="w-4 h-4" />
              </ActionButton>
            )}
            {download.status === 'completed' && download.filepath && (
              <a
                href={api.fileUrl(download.id)}
                download
                title="Download file"
                className="p-2 rounded-sm bg-accent/15 text-accent hover:bg-accent/25 transition-colors focus-ring"
                aria-label="Download file"
              >
                <DownloadCloud className="w-4 h-4" />
              </a>
            )}

            <div className="relative">
              <button
                onClick={() => setMenuOpen((v) => !v)}
                className="p-2 rounded-sm text-text-secondary hover:text-text-primary hover:bg-bg-tertiary transition-colors focus-ring"
                aria-label="More actions"
              >
                <MoreVertical className="w-4 h-4" />
              </button>
              {menuOpen && (
                <>
                  <div className="fixed inset-0 z-10" onClick={() => setMenuOpen(false)} />
                  <div className="absolute right-0 top-full mt-1 z-20 bg-bg-secondary border border-border-subtle rounded-sm shadow-xl py-1 min-w-[200px] animate-slide-down">
                    {download.filepath && (
                      <>
                        <MenuItem icon={Download} onClick={() => { window.location.href = api.fileUrl(download.id); setMenuOpen(false); }}>
                          Download file
                        </MenuItem>
                        <MenuItem icon={Copy} onClick={() => { copyPath(); setMenuOpen(false); }}>
                          Copy file path
                        </MenuItem>
                      </>
                    )}
                    {download.status !== 'completed' && (
                      <MenuItem
                        icon={X}
                        tone="error"
                        onClick={() => { run(() => api.removeDownload(download.id, false), 'Download removed'); setMenuOpen(false); }}
                      >
                        Cancel download
                      </MenuItem>
                    )}
                    {download.status === 'completed' && (
                      <MenuItem
                        icon={Trash2}
                        tone="error"
                        onClick={() => { run(() => api.removeDownload(download.id, true), 'File deleted'); setMenuOpen(false); }}
                      >
                        Delete file + entry
                      </MenuItem>
                    )}
                    <MenuItem
                      icon={Trash2}
                      onClick={() => { run(() => api.removeDownload(download.id, false), 'Removed from list'); setMenuOpen(false); }}
                    >
                      Remove from list
                    </MenuItem>
                  </div>
                </>
              )}
            </div>

            <button
              onClick={() => setExpanded((v) => !v)}
              className="p-2 rounded-sm text-text-secondary hover:text-text-primary hover:bg-bg-tertiary transition-colors focus-ring"
              aria-label="Toggle details"
            >
              {expanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            </button>
          </div>
        </div>

        {download.status === 'active' && (
          <div className="mt-3 ml-[3.25rem]">
            <div className="h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-accent to-success rounded-full transition-all duration-300 relative"
                style={{ width: `${download.progress}%` }}
              >
                <div className="absolute inset-0 progress-stripes" />
              </div>
            </div>
          </div>
        )}

        {expanded && (
          <div className="mt-3 ml-[3.25rem] pt-4 border-t border-border-subtle grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <Detail label="Status" value={download.status} icon={StatusIcon} />
            <Detail label="Connections" value={download.status === 'active' || download.resumeSupported ? `${download.segments || 1} seg` : '—'} />
            <Detail label="Platform" value={download.platform} />
            <Detail label="Format" value={download.format} />
            <Detail label="Downloaded" value={formatBytes(download.downloaded)} />
            <Detail label="Remaining" value={formatBytes(Math.max(download.total - download.downloaded, 0))} />
            <Detail label="Created" value={formatRelativeTime(download.createdAt)} />
            <Detail
              label="Completed"
              value={download.completedAt ? formatRelativeTime(download.completedAt) : '—'}
            />
            {download.filepath && (
              <div className="col-span-2 sm:col-span-4">
                <p className="kicker mb-1.5">Saved to</p>
                <p className="font-mono text-xs text-text-secondary break-all">{download.filepath}</p>
              </div>
            )}
            {download.checksum && (
              <div className="col-span-2 sm:col-span-4">
                <p className="kicker mb-1.5">Checksum ({download.checksumAlgo?.toUpperCase()})</p>
                <p className="font-mono text-xs text-text-secondary break-all">{download.checksum}</p>
              </div>
            )}
            {download.error && (
              <div className="col-span-2 sm:col-span-4">
                <p className="kicker mb-1.5">Last error</p>
                <p className="text-xs text-error break-words">{download.error}</p>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function ActionButton({ title, tone, onClick, children }) {
  const tones = {
    warning: 'bg-warning/10 text-warning hover:bg-warning/20',
    success: 'bg-success/10 text-success hover:bg-success/20',
    error: 'bg-error/10 text-error hover:bg-error/20',
    accent: 'bg-accent/10 text-accent hover:bg-accent/20',
  };
  return (
    <button
      onClick={onClick}
      title={title}
      aria-label={title}
      className={`p-2 rounded-sm transition-colors focus-ring ${tones[tone]}`}
    >
      {children}
    </button>
  );
}

function IconAction({ title, tone, onClick, disabled, children }) {
  const tones = {
    warning: 'bg-warning/10 text-warning hover:bg-warning/20',
    success: 'bg-success/10 text-success hover:bg-success/20',
    accent: 'bg-accent/10 text-accent hover:bg-accent/20',
  };
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      title={title}
      aria-label={title}
      className={`p-2 rounded-sm transition-colors focus-ring disabled:opacity-40 disabled:cursor-not-allowed ${tones[tone]}`}
    >
      {children}
    </button>
  );
}

function MenuItem({ icon: Icon, children, onClick, tone }) {
  return (
    <button
      onClick={onClick}
      className={`w-full px-4 py-2 text-left text-xs flex items-center gap-2.5 transition-colors ${
        tone === 'error' ? 'text-error hover:bg-error/10' : 'text-text-secondary hover:bg-bg-tertiary'
      }`}
    >
      <Icon className="w-3.5 h-3.5" />
      {children}
    </button>
  );
}

function Detail({ label, value, icon: Icon }) {
  return (
    <div className="min-w-0">
      <p className="kicker mb-1.5 flex items-center gap-1.5">
        {Icon && <Icon className="w-3 h-3" />} {label}
      </p>
      <p className="font-mono text-xs text-text-secondary capitalize truncate">{value}</p>
    </div>
  );
}
