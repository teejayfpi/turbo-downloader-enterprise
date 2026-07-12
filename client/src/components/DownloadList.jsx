import { useState } from 'react';
import { 
  Download, Pause, Play, RotateCcw, X, CheckCircle, 
  AlertCircle, Clock, Trash2, FolderOpen, MoreVertical,
  ChevronDown, ChevronUp, PauseCircle, SkipForward
} from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';

export default function DownloadList() {
  const downloads = useDownloadStore((state) => state.downloads);
  const [filter, setFilter] = useState('all');
  const [expandedId, setExpandedId] = useState(null);
  const [menuOpenId, setMenuOpenId] = useState(null);

  const filteredDownloads = downloads.filter((d) => {
    if (filter === 'all') return true;
    if (filter === 'active') return d.status === 'active' || d.status === 'paused';
    return d.status === filter;
  });

  const activeCount = downloads.filter((d) => d.status === 'active').length;
  const completedCount = downloads.filter((d) => d.status === 'completed').length;
  const queuedCount = downloads.filter((d) => d.status === 'queued').length;
  const failedCount = downloads.filter((d) => d.status === 'failed').length;

  return (
    <div className="bg-bg-secondary rounded-2xl border border-border-subtle p-6 h-full">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-success/10 flex items-center justify-center">
            <Download className="w-5 h-5 text-success" />
          </div>
          <div>
            <h3 className="font-semibold text-text-primary">Download Queue</h3>
            <p className="text-xs text-text-muted">{downloads.length} total downloads</p>
          </div>
        </div>

        {/* Bulk Actions */}
        {activeCount > 0 && (
          <div className="flex items-center gap-2">
            <button
              onClick={() => api.pauseAll()}
              className="p-2 rounded-lg bg-warning/10 text-warning hover:bg-warning/20 transition-colors"
              title="Pause All"
            >
              <Pause className="w-4 h-4" />
            </button>
            <button
              onClick={() => api.resumeAll()}
              className="p-2 rounded-lg bg-success/10 text-success hover:bg-success/20 transition-colors"
              title="Resume All"
            >
              <Play className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* Filter Tabs */}
      <div className="flex gap-2 mb-4 overflow-x-auto pb-2">
        {[
          { key: 'all', label: 'All', count: downloads.length },
          { key: 'active', label: 'Active', count: activeCount },
          { key: 'queued', label: 'Queued', count: queuedCount },
          { key: 'completed', label: 'Completed', count: completedCount },
          { key: 'failed', label: 'Failed', count: failedCount },
        ].map((tab) => (
          <button
            key={tab.key}
            onClick={() => setFilter(tab.key)}
            className={`
              px-4 py-2 rounded-lg text-sm font-medium transition-all whitespace-nowrap
              ${filter === tab.key
                ? 'bg-accent text-bg-primary'
                : 'bg-bg-tertiary text-text-secondary hover:text-text-primary'
              }
            `}
          >
            {tab.label}
            <span className={`ml-2 px-1.5 py-0.5 rounded text-xs ${
              filter === tab.key ? 'bg-white/20' : 'bg-bg-primary'
            }`}>
              {tab.count}
            </span>
          </button>
        ))}
      </div>

      {/* Download Items */}
      <div className="space-y-3 max-h-[500px] overflow-y-auto pr-2">
        {filteredDownloads.length === 0 ? (
          <div className="text-center py-12">
            <Download className="w-12 h-12 text-text-muted mx-auto mb-3 opacity-50" />
            <p className="text-text-secondary">No downloads yet</p>
            <p className="text-text-muted text-sm">Add URLs above to start downloading</p>
          </div>
        ) : (
          filteredDownloads.map((download) => (
            <DownloadItem
              key={download.id}
              download={download}
              isExpanded={expandedId === download.id}
              onToggleExpand={() => setExpandedId(expandedId === download.id ? null : download.id)}
              menuOpen={menuOpenId === download.id}
              onToggleMenu={() => setMenuOpenId(menuOpenId === download.id ? null : download.id)}
              onCloseMenus={() => setMenuOpenId(null)}
            />
          ))
        )}
      </div>

      {/* Clear Completed Button */}
      {completedCount > 0 && (
        <div className="mt-4 pt-4 border-t border-border-subtle">
          <button
            onClick={() => api.clearCompleted()}
            className="w-full py-2 text-sm text-text-muted hover:text-error transition-colors flex items-center justify-center gap-2"
          >
            <Trash2 className="w-4 h-4" />
            Clear Completed
          </button>
        </div>
      )}
    </div>
  );
}

function DownloadItem({ download, isExpanded, onToggleExpand, menuOpen, onToggleMenu, onCloseMenus }) {
  const formatSize = (bytes) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const formatSpeed = (bytes) => {
    if (bytes === 0) return '0 B/s';
    const k = 1024;
    const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  const formatTime = (seconds) => {
    if (!seconds || seconds === Infinity) return 'Calculating...';
    if (seconds < 60) return `${Math.round(seconds)}s`;
    if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
    return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
  };

  const statusConfig = {
    active: { color: 'accent', icon: Download, glow: 'glow-cyan' },
    paused: { color: 'warning', icon: PauseCircle, glow: 'glow-orange' },
    completed: { color: 'success', icon: CheckCircle, glow: 'glow-green' },
    failed: { color: 'error', icon: AlertCircle, glow: 'glow-red' },
    queued: { color: 'text-muted', icon: Clock, glow: '' }
  };

  const config = statusConfig[download.status] || statusConfig.queued;
  const StatusIcon = config.icon;

  const handlePause = async (e) => {
    e.stopPropagation();
    await api.pauseDownload(download.id);
    onCloseMenus();
  };

  const handleResume = async (e) => {
    e.stopPropagation();
    await api.resumeDownload(download.id);
    onCloseMenus();
  };

  const handleRetry = async (e) => {
    e.stopPropagation();
    await api.retryDownload(download.id);
    onCloseMenus();
  };

  const handleRemove = async (e) => {
    e.stopPropagation();
    await api.removeDownload(download.id);
    onCloseMenus();
  };

  return (
    <div 
      className={`
        relative bg-bg-primary rounded-xl border border-border-subtle overflow-hidden
        transition-all duration-200
        ${download.status === 'active' ? 'border-accent/30' : ''}
        ${download.status === 'completed' ? 'border-success/30' : ''}
        ${download.status === 'failed' ? 'border-error/30' : ''}
        ${isExpanded ? 'ring-1 ring-accent/20' : 'hover:border-border-subtle/80'}
      `}
    >
      {/* Progress Bar Background */}
      {download.status === 'active' && (
        <div className="absolute inset-0 bg-gradient-to-r from-accent/5 to-transparent" />
      )}

      <div className="relative p-4">
        {/* Main Row */}
        <div className="flex items-start gap-4">
          {/* Status Icon */}
          <div className={`
            w-10 h-10 rounded-xl flex items-center justify-center shrink-0
            ${config.glow} bg-${config.color}/10
          `}>
            <StatusIcon className={`w-5 h-5 text-${config.color}`} />
          </div>

          {/* Content */}
          <div className="flex-1 min-w-0">
            {/* Filename */}
            <div className="flex items-center gap-2 mb-1">
              <p className="font-medium text-text-primary truncate" title={download.filename}>
                {download.filename}
              </p>
              {download.status === 'active' && (
                <span className="px-2 py-0.5 rounded text-xs bg-accent/20 text-accent font-medium">
                  {download.progress}%
                </span>
              )}
            </div>

            {/* URL */}
            <p className="text-xs text-text-muted truncate mb-2" title={download.url}>
              {download.url}
            </p>

            {/* Stats Row */}
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
              {download.status === 'active' && (
                <>
                  <span className="font-mono text-accent">{formatSpeed(download.speed)}</span>
                  <span className="text-text-muted">
                    {formatSize(download.downloaded)} / {formatSize(download.total)}
                  </span>
                  <span className="text-text-muted">
                    ETA: {formatTime(download.eta)}
                  </span>
                </>
              )}
              {download.status === 'paused' && (
                <span className="text-warning">
                  {formatSize(download.downloaded)} / {formatSize(download.total)} • Paused
                </span>
              )}
              {download.status === 'completed' && (
                <span className="text-success">
                  {formatSize(download.total)} • Completed
                </span>
              )}
              {download.status === 'failed' && (
                <span className="text-error">
                  {download.error || 'Download failed'}
                </span>
              )}
              {download.status === 'queued' && (
                <span className="text-text-muted">Waiting in queue...</span>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-2 shrink-0">
            {/* Status-specific actions */}
            {download.status === 'active' && (
              <button
                onClick={handlePause}
                className="p-2 rounded-lg bg-warning/10 text-warning hover:bg-warning/20 transition-colors"
                title="Pause"
              >
                <Pause className="w-4 h-4" />
              </button>
            )}
            
            {download.status === 'paused' && (
              <button
                onClick={handleResume}
                className="p-2 rounded-lg bg-success/10 text-success hover:bg-success/20 transition-colors"
                title="Resume"
              >
                <Play className="w-4 h-4" />
              </button>
            )}
            
            {download.status === 'failed' && (
              <button
                onClick={handleRetry}
                className="p-2 rounded-lg bg-error/10 text-error hover:bg-error/20 transition-colors"
                title="Retry"
              >
                <RotateCcw className="w-4 h-4" />
              </button>
            )}

            {/* More menu */}
            <div className="relative">
              <button
                onClick={onToggleMenu}
                className="p-2 rounded-lg bg-bg-tertiary text-text-secondary hover:text-text-primary transition-colors"
              >
                <MoreVertical className="w-4 h-4" />
              </button>

              {menuOpen && (
                <>
                  <div className="fixed inset-0 z-10" onClick={onCloseMenus} />
                  <div className="absolute right-0 top-full mt-1 z-20 bg-bg-secondary border border-border-subtle rounded-xl shadow-xl py-1 min-w-[150px] animate-slide-down">
                    {download.status !== 'completed' && download.status !== 'queued' && (
                      <button
                        onClick={handleRemove}
                        className="w-full px-4 py-2 text-left text-sm text-error hover:bg-error/10 flex items-center gap-2"
                      >
                        <X className="w-4 h-4" />
                        Cancel Download
                      </button>
                    )}
                    {download.status === 'completed' && (
                      <>
                        <button className="w-full px-4 py-2 text-left text-sm text-text-secondary hover:bg-bg-tertiary flex items-center gap-2">
                          <FolderOpen className="w-4 h-4" />
                          Open File
                        </button>
                        <button
                          onClick={handleRemove}
                          className="w-full px-4 py-2 text-left text-sm text-error hover:bg-error/10 flex items-center gap-2"
                        >
                          <Trash2 className="w-4 h-4" />
                          Remove from List
                        </button>
                      </>
                    )}
                    {download.status === 'queued' && (
                      <button
                        onClick={handleRemove}
                        className="w-full px-4 py-2 text-left text-sm text-error hover:bg-error/10 flex items-center gap-2"
                      >
                        <X className="w-4 h-4" />
                        Remove from Queue
                      </button>
                    )}
                  </div>
                </>
              )}
            </div>

            {/* Expand button */}
            <button
              onClick={onToggleExpand}
              className="p-2 rounded-lg bg-bg-tertiary text-text-secondary hover:text-text-primary transition-colors"
            >
              {isExpanded ? (
                <ChevronUp className="w-4 h-4" />
              ) : (
                <ChevronDown className="w-4 h-4" />
              )}
            </button>
          </div>
        </div>

        {/* Progress Bar */}
        {download.status === 'active' && (
          <div className="mt-4">
            <div className="h-2 bg-bg-tertiary rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-accent to-success rounded-full transition-all duration-300 relative"
                style={{ width: `${download.progress}%` }}
              >
                <div className="absolute inset-0 progress-stripes bg-white/10" />
              </div>
            </div>
          </div>
        )}

        {/* Expanded Info */}
        {isExpanded && download.status === 'active' && (
          <div className="mt-4 pt-4 border-t border-border-subtle grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div>
              <p className="text-xs text-text-muted mb-1">Connections</p>
              <p className="font-mono text-sm">{download.connections || 16}</p>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-1">Seeds</p>
              <p className="font-mono text-sm">{download.seeds || 'N/A'}</p>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-1">Downloaded</p>
              <p className="font-mono text-sm">{formatSize(download.downloaded)}</p>
            </div>
            <div>
              <p className="text-xs text-text-muted mb-1">Remaining</p>
              <p className="font-mono text-sm">{formatSize(download.total - download.downloaded)}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
