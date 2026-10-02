import { Settings, Zap, Activity, ListOrdered, Wifi, WifiOff, Sun, Moon } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';
import { api } from '../hooks/useApi';
import { formatSpeed } from '../lib/format';

export default function Header() {
  const stats = useDownloadStore((s) => s.stats);
  const downloads = useDownloadStore((s) => s.downloads);
  const settings = useDownloadStore((s) => s.settings);
  const setSettings = useDownloadStore((s) => s.setSettings);
  const connected = useDownloadStore((s) => s.connected);
  const toggleSettingsModal = useDownloadStore((s) => s.toggleSettingsModal);

  const queued = downloads.filter((d) => d.status === 'queued' || d.status === 'scheduled').length;

  const toggleTheme = async () => {
    const next = { ...settings, theme: settings.theme === 'light' ? 'dark' : 'light' };
    setSettings(next);
    try {
      const updated = await api.updateSettings({ theme: next.theme });
      setSettings(updated);
    } catch {
      /* keep the optimistic local change if the server is unreachable */
    }
  };

  return (
    <header className="sticky top-0 z-50 bg-bg-primary/80 backdrop-blur-xl border-b border-border-subtle">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16 gap-4">
          <div className="flex items-center gap-3">
            <div className="relative">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-accent to-success flex items-center justify-center glow-accent">
                <Zap className="w-6 h-6 text-bg-primary" />
              </div>
              <div
                className={`absolute -top-1 -right-1 w-3 h-3 rounded-full pulse-dot ${
                  stats.activeCount > 0 ? 'bg-success' : 'bg-text-muted'
                }`}
              />
            </div>
            <div>
              <h1 className="text-xl font-bold tracking-tight">
                <span className="text-gradient">TURBO</span>
              </h1>
              <p className="text-[10px] text-text-muted uppercase tracking-widest">
                Download Manager
              </p>
            </div>
          </div>

          <div className="hidden md:flex items-center gap-3">
            <Stat icon={Activity} label="Speed" value={formatSpeed(stats.totalSpeed)} tone="text-accent" />
            <Stat icon={Zap} label="Peak" value={formatSpeed(stats.peakSpeed)} tone="text-success" />
            <Stat icon={ListOrdered} label="Queue" value={String(queued)} tone="text-warning" />
          </div>

          <div className="flex items-center gap-2">
            <span
              className={`hidden sm:flex items-center gap-1.5 px-3 py-2 rounded-lg border text-xs font-medium ${
                connected
                  ? 'border-success/30 text-success bg-success/10'
                  : 'border-error/30 text-error bg-error/10'
              }`}
              title={connected ? 'Live updates connected' : 'Reconnecting...'}
            >
              {connected ? <Wifi className="w-3.5 h-3.5" /> : <WifiOff className="w-3.5 h-3.5" />}
              {connected ? 'Live' : 'Offline'}
            </span>

            <button
              onClick={toggleTheme}
              className="p-2 rounded-lg bg-bg-secondary border border-border-subtle hover:border-accent/50 transition-colors focus-ring"
              aria-label="Toggle theme"
              title="Toggle theme"
            >
              {settings.theme === 'light' ? (
                <Moon className="w-5 h-5 text-text-secondary" />
              ) : (
                <Sun className="w-5 h-5 text-text-secondary" />
              )}
            </button>

            <button
              onClick={toggleSettingsModal}
              className="p-2 rounded-lg bg-bg-secondary border border-border-subtle hover:border-accent/50 transition-colors group focus-ring"
              aria-label="Settings"
              title="Settings"
            >
              <Settings className="w-5 h-5 text-text-secondary group-hover:text-accent transition-colors" />
            </button>
          </div>
        </div>
      </div>
    </header>
  );
}

function Stat({ icon: Icon, label, value, tone }) {
  return (
    <div className="flex items-center gap-2 px-3 py-2 bg-bg-secondary rounded-lg border border-border-subtle">
      <Icon className={`w-4 h-4 ${tone}`} />
      <span className="text-xs text-text-secondary">{label}:</span>
      <span className={`font-mono font-semibold text-sm ${tone}`}>{value}</span>
    </div>
  );
}
