import { Settings, Zap, Activity, ListOrdered } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';

export default function Header() {
  const stats = useDownloadStore((state) => state.stats);
  const downloads = useDownloadStore((state) => state.downloads);
  const toggleSettingsModal = useDownloadStore((state) => state.toggleSettingsModal);

  const formatSpeed = (bytes) => {
    if (bytes === 0) return '0 B/s';
    const k = 1024;
    const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  return (
    <header className="sticky top-0 z-50 bg-bg-primary/80 backdrop-blur-xl border-b border-border-subtle">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center gap-3">
            <div className="relative">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-accent to-success flex items-center justify-center glow-cyan">
                <Zap className="w-6 h-6 text-bg-primary" />
              </div>
              <div className="absolute -top-1 -right-1 w-3 h-3 bg-success rounded-full pulse-dot" />
            </div>
            <div>
              <h1 className="text-xl font-bold tracking-tight">
                <span className="text-gradient">TURBO</span>
              </h1>
              <p className="text-[10px] text-text-muted uppercase tracking-widest">Download Manager</p>
            </div>
          </div>

          {/* Stats Bar */}
          <div className="hidden sm:flex items-center gap-6">
            <div className="flex items-center gap-2 px-4 py-2 bg-bg-secondary rounded-lg border border-border-subtle">
              <Activity className="w-4 h-4 text-accent" />
              <span className="text-sm text-text-secondary">Speed:</span>
              <span className="font-mono font-semibold text-accent">
                {formatSpeed(stats.totalSpeed)}
              </span>
            </div>

            <div className="flex items-center gap-2 px-4 py-2 bg-bg-secondary rounded-lg border border-border-subtle">
              <Zap className="w-4 h-4 text-success" />
              <span className="text-sm text-text-secondary">Peak:</span>
              <span className="font-mono font-semibold text-success">
                {formatSpeed(stats.peakSpeed)}
              </span>
            </div>

            <div className="flex items-center gap-2 px-4 py-2 bg-bg-secondary rounded-lg border border-border-subtle">
              <ListOrdered className="w-4 h-4 text-warning" />
              <span className="text-sm text-text-secondary">Queue:</span>
              <span className="font-mono font-semibold text-warning">
                {downloads.filter(d => d.status === 'queued').length}
              </span>
            </div>
          </div>

          {/* Settings Button */}
          <button
            onClick={toggleSettingsModal}
            className="p-2 rounded-lg bg-bg-secondary border border-border-subtle hover:border-accent/50 transition-all duration-200 group"
            aria-label="Settings"
          >
            <Settings className="w-5 h-5 text-text-secondary group-hover:text-accent transition-colors" />
          </button>
        </div>
      </div>
    </header>
  );
}
