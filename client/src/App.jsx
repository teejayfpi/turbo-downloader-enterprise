import { useEffect, useState, useCallback } from 'react';
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
    } catch (error) {
      setFatal(error.message);
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

  return (
    <div className="min-h-screen bg-bg-primary">
      <SplashScreen ready={!loading} onMounted={removeBootSplash} />
      <div className="fixed inset-0 bg-gradient-to-br from-accent/5 via-transparent to-success/5 pointer-events-none" />
      <div
        className="fixed inset-0 opacity-[0.025] pointer-events-none"
        style={{
          backgroundImage:
            'linear-gradient(rgb(var(--grid-line) / 0.35) 1px, transparent 1px), linear-gradient(90deg, rgb(var(--grid-line) / 0.35) 1px, transparent 1px)',
          backgroundSize: '52px 52px',
        }}
      />

      <div className="relative z-10">
        <Header />

        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {fatal && (
            <div className="mb-6 rounded-xl border border-error/40 bg-error/10 px-4 py-3 text-sm text-error flex items-center justify-between">
              <span>Cannot reach the Turbo server: {fatal}</span>
              <button
                onClick={loadData}
                className="px-3 py-1.5 rounded-lg bg-error/20 hover:bg-error/30 transition-colors font-medium"
              >
                Retry
              </button>
            </div>
          )}

          <div className="text-center mb-10 animate-slide-down">
            <h1 className="text-5xl sm:text-6xl lg:text-7xl font-extrabold mb-4 tracking-tight">
              <span className="text-gradient">TURBO</span>
            </h1>
            <p className="text-text-secondary text-lg sm:text-xl max-w-2xl mx-auto">
              Enterprise-grade download manager. Multi-connection, resumable, and built for speed.
            </p>
          </div>

          <div className="mb-8">
            <ErrorBoundary label="Add downloads">
              <DropZone onAdded={loadData} />
            </ErrorBoundary>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
            <div className="lg:col-span-1">
              <ErrorBoundary label="Speed monitor">
                <SpeedMonitor />
              </ErrorBoundary>
            </div>
            <div className="lg:col-span-2">
              <ErrorBoundary label="Download queue">
                <DownloadList loading={loading} />
              </ErrorBoundary>
            </div>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
            <StatCard label="Active" value={counts.active} color="cyan" hint="downloading now" />
            <StatCard label="Completed" value={counts.completed} color="green" hint="finished" />
            <StatCard label="Queued" value={counts.queued} color="orange" hint="waiting" />
            <StatCard label="Failed" value={counts.failed} color="red" hint="need attention" />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <InfoCard label="Session speed" value={`${(stats.totalSpeed / 1048576).toFixed(2)} MB/s`} />
            <InfoCard label="Peak speed" value={`${(stats.peakSpeed / 1048576).toFixed(2)} MB/s`} />
            <InfoCard label="Total downloaded" value={formatTotal(stats.totalDownloaded)} />
          </div>
        </main>

        <footer className="border-t border-border-subtle py-8 mt-12">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-4 text-text-muted text-sm">
            <div className="text-center sm:text-left">
              <p>Turbo Downloader · Built for speed</p>
              <p className="text-xs mt-1">
                Designed by <span className="text-text-secondary font-medium">{DESIGNER.name}</span>
              </p>
            </div>
            <div className="flex flex-col sm:items-end gap-1 text-center sm:text-right">
              <p className="font-mono text-xs">v{APP_VERSION}</p>
              <p className="text-xs flex flex-wrap items-center justify-center sm:justify-end gap-x-2 gap-y-1">
                <a href={`mailto:${DESIGNER.email}`} className="hover:text-accent transition-colors">
                  {DESIGNER.email}
                </a>
                <span className="text-border-subtle" aria-hidden="true">·</span>
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
    </div>
  );
}

function formatTotal(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((bytes / k ** i).toFixed(1))} ${sizes[i]}`;
}

function StatCard({ label, value, color, hint }) {
  const colorClasses = {
    cyan: 'text-accent bg-accent/10 border-accent/20',
    green: 'text-success bg-success/10 border-success/20',
    orange: 'text-warning bg-warning/10 border-warning/20',
    red: 'text-error bg-error/10 border-error/20',
  };
  return (
    <div className={`rounded-xl p-4 border card-hover bg-bg-secondary ${colorClasses[color]}`}>
      <p className="text-text-muted text-xs uppercase tracking-wider mb-1">{label}</p>
      <p className="text-2xl font-bold font-mono">{value}</p>
      <p className="text-[11px] text-text-muted mt-0.5">{hint}</p>
    </div>
  );
}

function InfoCard({ label, value }) {
  return (
    <div className="bg-bg-secondary rounded-xl p-4 border border-border-subtle">
      <p className="text-text-muted text-xs uppercase tracking-wider mb-1">{label}</p>
      <p className="text-lg font-semibold font-mono text-text-primary">{value}</p>
    </div>
  );
}

export default App;
