import { Settings, Activity, Wifi, WifiOff, Sun, Moon, Download, ChevronRight } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';
import { api } from '../hooks/useApi';
import { formatSpeed } from '../lib/format';
import { usePWA } from '../hooks/usePWA';

export default function Header() {
  const stats = useDownloadStore((s) => s.stats);
  const downloads = useDownloadStore((s) => s.downloads);
  const settings = useDownloadStore((s) => s.settings);
  const setSettings = useDownloadStore((s) => s.setSettings);
  const connected = useDownloadStore((s) => s.connected);
  const toggleSettingsModal = useDownloadStore((s) => s.toggleSettingsModal);
  const pwa = usePWA();

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
    <header className="sticky top-0 z-50 border-b border-border-subtle bg-bg-primary/85 backdrop-blur-xl">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16 gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <div className="relative shrink-0">
              <div className="w-10 h-10 rounded-sm bg-gradient-to-br from-accent to-success flex items-center justify-center glow-accent">
                <svg viewBox="0 0 1024 1024" className="w-5 h-5" aria-hidden="true">
                  <path d="M462 258H562V534H688L512 736L336 534H462Z" fill="rgb(var(--bg-primary))" />
                </svg>
              </div>
              <div
                className={`absolute -bottom-1 -right-1 w-3 h-3 rounded-full border-2 border-bg-primary ${
                  stats.activeCount > 0 ? 'bg-success pulse-dot' : 'bg-text-muted'
                }`}
              />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-1.5">
                <h1 className="font-display font-bold text-lg tracking-[0.2em] text-gradient leading-none">
                  TURBO
                </h1>
              </div>
              <p className="kicker leading-none mt-1" style={{ letterSpacing: '0.24em' }}>
                Download Manager
              </p>
            </div>
          </div>

          <div className="hidden md:flex items-center gap-2">
            <Readout icon={Activity} label="Speed" value={formatSpeed(stats.totalSpeed)} tone="accent" />
            <Readout icon={Activity} label="Peak" value={formatSpeed(stats.peakSpeed)} tone="success" />
            <Readout icon={Download} label="Queue" value={String(queued)} tone="warning" />
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <span
              className={`hidden sm:inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-sm border text-[11px] font-medium uppercase tracking-wider ${
                connected
                  ? 'border-success/30 text-success bg-success/10'
                  : 'border-error/30 text-error bg-error/10'
              }`}
              title={connected ? 'Live updates connected' : 'Reconnecting...'}
            >
              {connected ? <Wifi className="w-3.5 h-3.5" /> : <WifiOff className="w-3.5 h-3.5" />}
              {connected ? 'Live' : 'Offline'}
            </span>

            {pwa.canPrompt && (
              <button
                onClick={pwa.promptInstall}
                className="hidden sm:inline-flex items-center gap-1.5 px-3 py-1.5 rounded-sm bg-accent text-bg-primary text-[11px] font-bold uppercase tracking-wider hover:brightness-110 transition focus-ring"
                aria-label="Install app"
                title="Install app"
              >
                <Download className="w-3.5 h-3.5" />
                Install
              </button>
            )}

            <button
              onClick={toggleTheme}
              className="p-2 rounded-sm border border-border-subtle text-text-secondary hover:text-accent hover:border-accent/50 transition-colors focus-ring"
              aria-label="Toggle theme"
              title="Toggle theme"
            >
              {settings.theme === 'light' ? <Moon className="w-4 h-4" /> : <Sun className="w-4 h-4" />}
            </button>

            <button
              onClick={toggleSettingsModal}
              className="group inline-flex items-center gap-2 pl-2 pr-2.5 py-2 rounded-sm border border-border-subtle text-text-secondary hover:text-accent hover:border-accent/50 transition-colors focus-ring"
              aria-label="Settings"
              title="Settings"
            >
              <Settings className="w-4 h-4" />
              <ChevronRight className="w-3 h-3 hidden sm:block opacity-50 group-hover:translate-x-0.5 transition-transform" />
            </button>
          </div>
        </div>
      </div>
    </header>
  );
}

function Readout({ icon: Icon, label, value, tone }) {
  return (
    <div className="flex items-center gap-2 px-3 py-1.5 rounded-sm border border-border-subtle bg-bg-secondary/60">
      <Icon className={`w-3.5 h-3.5 ${tone}`} />
      <span className="kicker" style={{ letterSpacing: '0.2em' }}>{label}</span>
      <span className={`font-mono font-semibold text-sm speed-counter ${tone}`}>{value}</span>
    </div>
  );
}
