import { useEffect, useState, useCallback } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { useSocket } from './hooks/useSocket';
import { useDownloadStore } from './stores/downloadStore';
import { api } from './hooks/useApi';
import Header from './components/Header';
import DropZone from './components/DropZone';
import SpeedMonitor from './components/SpeedMonitor';
import DownloadList from './components/DownloadList';
import SettingsModal from './components/SettingsModal';
import ToastContainer from './components/ToastContainer';
import ErrorBoundary from './components/ErrorBoundary';
import SplashScreen from './components/SplashScreen';
import InstallBanner from './components/InstallBanner';
import AuthGate from './components/AuthGate';
import { DESIGNER, APP_VERSION } from './credits';

function App() {
  useSocket();

  const downloads = useDownloadStore((s) => s.downloads);
  const stats = useDownloadStore((s) => s.stats);
  const settings = useDownloadStore((s) => s.settings);
  const setDownloads = useDownloadStore((s) => s.setDownloads);
  const setSettings = useDownloadStore((s) => s.setSettings);
  const setSystem = useDownloadStore((s) => s.setSystem);
  const addNotification = useDownloadStore((s) => s.addNotification);
  const [loading, setLoading] = useState(true);
  const [fatal, setFatal] = useState(null);
  const [locked, setLocked] = useState(false);
  const setFilter = useDownloadStore((s) => s.setFilter);

  // PWA shortcut: /?filter=completed opens the list pre-filtered.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const filter = params.get('filter');
    if (filter) {
      setFilter(filter);
      params.delete('filter');
      params.delete('source');
      const query = params.toString();
      window.history.replaceState({}, '', window.location.pathname + (query ? `?${query}` : ''));
    }
  }, [setFilter]);

  const removeBootSplash = useCallback(() => {
    document.getElementById('boot-splash')?.remove();
  }, []);

  // Apply theme + accent to the document root.
  useEffect(() => {
    document.documentElement.dataset.theme = settings.theme || 'dark';
    document.documentElement.dataset.accent = settings.accentColor || 'cyan';
  }, [settings.theme, settings.accentColor]);

  const loadData = useCallback(async () => {
    try {
      const [downloadsData, settingsData, systemData] = await Promise.all([
        api.getDownloads(),
        api.getSettings(),
        api.getSystem(),
      ]);
      setDownloads(downloadsData.downloads);
      setSettings(settingsData);
      setSystem(systemData);
      setFatal(null);
      setLocked(false);
    } catch (error) {
      if (error.status === 401) {
        setLocked(true);
        setFatal(null);
      } else {
        setFatal(error.message);
      }
    } finally {
      setLoading(false);
    }
  }, [setDownloads, setSettings, setSystem]);

  useEffect(() => {
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {});
    }
    loadData();
  }, [loadData]);

  const counts = {
    active: downloads.filter((d) => d.status === 'active').length,
    completed: downloads.filter((d) => d.status === 'completed').length,
    queued: downloads.filter((d) => d.status === 'queued' || d.status === 'scheduled').length,
    failed: downloads.filter((d) => d.status === 'failed').length,
  };

  // Background weight shifts toward the accent while transfers are running.
  const engaged = counts.active > 0;

  if (locked) {
    return <AuthGate onUnlock={() => window.location.reload()} />;
  }

  return (
    <div className="min-h-screen bg-bg-primary relative">
      <SplashScreen ready={!loading} onMounted={removeBootSplash} />

      {/* atmosphere ---------------------------------------------------- */}
      <div
        className="fixed inset-0 grid-bg opacity-[0.05] pointer-events-none"
        aria-hidden="true"
      />
      <div className={`fixed -top-1/3 left-1/2 -translate-x-1/2 w-[70rem] h-[70rem] rounded-full pointer-events-none transition-opacity duration-700 ${engaged ? 'opacity-100' : 'opacity-40'}`}
        style={{ background: 'radial-gradient(circle, rgb(var(--accent) / 0.10), transparent 62%)' }}
        aria-hidden="true"
      />
      <div className="fixed -bottom-1/3 -right-1/4 w-[52rem] h-[52rem] rounded-full pointer-events-none opacity-50"
        style={{ background: 'radial-gradient(circle, rgb(var(--success) / 0.07), transparent 62%)' }}
        aria-hidden="true"
      />

      <div className="relative z-10">
        <Header />

        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {fatal && (
            <div className="mb-6 panel flex items-center justify-between gap-4 px-4 py-3 text-sm"
              style={{ borderColor: 'rgb(var(--error) / 0.4)' }}>
              <span className="flex items-center gap-2.5 min-w-0" style={{ color: 'rgb(var(--error))' }}>
                <AlertTriangle className="w-4 h-4 shrink-0" />
                <span className="truncate">Cannot reach the Turbo server: {fatal}</span>
              </span>
              <button
                onClick={loadData}
                className="shrink-0 flex items-center gap-2 px-3 py-1.5 rounded-sm text-xs font-semibold uppercase tracking-wider transition-colors"
                style={{ background: 'rgb(var(--error) / 0.16)', color: 'rgb(var(--error))' }}
              >
                <RefreshCw className="w-3.5 h-3.5" />
                Retry
              </button>
            </div>
          )}

          <Hero counts={counts} stats={stats} engaged={engaged} />

          <div className="mb-6">
            <ErrorBoundary label="Add downloads">
              <DropZone onAdded={loadData} />
            </ErrorBoundary>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-5 mb-8">
            <div className="lg:col-span-4 xl:col-span-3">
              <ErrorBoundary label="Speed monitor">
                <SpeedMonitor />
              </ErrorBoundary>
            </div>
            <div className="lg:col-span-8 xl:col-span-9">
              <ErrorBoundary label="Download queue">
                <DownloadList loading={loading} />
              </ErrorBoundary>
            </div>
          </div>

          <Telemetry stats={stats} />
        </main>

        <footer className="border-t border-border-subtle mt-12 relative">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="text-center sm:text-left">
              <p className="font-display font-semibold tracking-wide text-text-primary">
                TURBO <span className="text-text-muted font-sans font-normal text-sm">Download Manager</span>
              </p>
              <p className="kicker mt-2" style={{ letterSpacing: '0.18em' }}>
                Designed by <span className="text-text-secondary">{DESIGNER.name}</span>
              </p>
            </div>
            <div className="flex flex-col sm:items-end gap-1.5 text-center sm:text-right">
              <p className="font-mono text-xs text-text-secondary tracking-wider">v{APP_VERSION}</p>
              <p className="text-xs flex flex-wrap items-center justify-center sm:justify-end gap-x-2 gap-y-1 text-text-muted">
                <a href={`mailto:${DESIGNER.email}`} className="hover:text-accent transition-colors">
                  {DESIGNER.email}
                </a>
                <span aria-hidden="true">·</span>
                <a href={`tel:${DESIGNER.phoneHref}`} className="hover:text-accent transition-colors">
                  {DESIGNER.phone}
                </a>
              </p>
            </div>
          </div>
        </footer>
      </div>

      <SettingsModal />
      <ToastContainer />
      <InstallBanner />
    </div>
  );
}

function Hero({ counts, stats, engaged }) {
  return (
    <section className="relative mb-8 animate-rise">
      <div className="flex flex-col lg:flex-row lg:items-end lg:justify-between gap-6">
        <div>
          <p className="kicker mb-3 flex items-center gap-2">
            <span
              className={`inline-block w-1.5 h-1.5 rounded-full ${engaged ? 'bg-success pulse-dot' : 'bg-text-muted'}`}
            />
            {engaged ? `${counts.active} transfer${counts.active > 1 ? 's' : ''} in flight` : 'System idle'}
          </p>
          <h1 className="font-display font-bold leading-[0.92] tracking-tight text-[clamp(2.75rem,7vw,5.25rem)]">
            <span className="text-gradient">TURBO</span>
          </h1>
          <p className="mt-3 text-text-secondary text-base sm:text-lg max-w-xl">
            Enterprise-grade download engine. Multi-connection, resumable, and instrumented
            for speed.
          </p>
        </div>

        <div className="flex items-stretch gap-1 shrink-0">
          <HeroMetric label="Session" value={formatSpeed(stats.totalSpeed, true)} tone="accent" />
          <HeroMetric label="Peak" value={formatSpeed(stats.peakSpeed, true)} tone="success" />
          <HeroMetric label="Downloaded" value={formatTotal(stats.totalDownloaded)} />
        </div>
      </div>
      <div className="mt-6 h-px w-full bg-gradient-to-r from-accent/60 via-border-subtle to-transparent" />
    </section>
  );
}

function HeroMetric({ label, value, tone = 'muted' }) {
  const tones = {
    accent: 'text-accent',
    success: 'text-success',
    muted: 'text-text-primary',
  };
  return (
    <div className="px-4 sm:px-5 py-3 border-l border-border-subtle first:border-l-0">
      <p className="kicker mb-1.5" style={{ letterSpacing: '0.22em' }}>{label}</p>
      <p className={`font-mono font-semibold text-lg sm:text-xl speed-counter ${tones[tone]}`}>{value}</p>
    </div>
  );
}

function Telemetry({ stats }) {
  const cards = [
    { label: 'Session speed', value: formatSpeed(stats.totalSpeed), hint: 'aggregate throughput' },
    { label: 'Peak speed', value: formatSpeed(stats.peakSpeed), hint: 'high-water mark' },
    { label: 'Total downloaded', value: formatTotal(stats.totalDownloaded), hint: 'this session' },
    { label: 'Completed', value: String(stats.completedCount || 0), hint: 'files finished' },
  ];
  return (
    <section>
      <div className="flex items-center gap-3 mb-3">
        <span className="kicker">Telemetry</span>
        <span className="flex-1 h-px bg-border-subtle" />
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {cards.map((c) => (
          <div key={c.label} className="panel card-hover p-4 lift">
            <p className="kicker mb-2">{c.label}</p>
            <p className="font-mono font-semibold text-xl text-text-primary speed-counter">{c.value}</p>
            <p className="text-[11px] text-text-muted mt-1">{c.hint}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function formatTotal(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((bytes / k ** i).toFixed(1))} ${sizes[i]}`;
}

function formatSpeed(bytes, compact = false) {
  if (!bytes || bytes <= 0) return compact ? '0' : '0 B/s';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  const value = parseFloat((bytes / k ** i).toFixed(1));
  return compact ? `${value} ${sizes[i]}` : `${value} ${sizes[i]}/s`;
}

export default App;
