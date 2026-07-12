import { useEffect } from 'react';
import { useSocket } from './hooks/useSocket';
import { useDownloadStore } from './stores/downloadStore';
import { api } from './hooks/useApi';
import Header from './components/Header';
import DropZone from './components/DropZone';
import SpeedMonitor from './components/SpeedMonitor';
import DownloadList from './components/DownloadList';
import SettingsModal from './components/SettingsModal';
import ToastContainer from './components/ToastContainer';

function App() {
  useSocket();

  const downloads = useDownloadStore((state) => state.downloads);
  const setDownloads = useDownloadStore((state) => state.setDownloads);
  const setSettings = useDownloadStore((state) => state.setSettings);

  useEffect(() => {
    // Request notification permission
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission();
    }

    // Load initial data
    const loadData = async () => {
      try {
        const [downloadsData, settingsData] = await Promise.all([
          api.getDownloads(),
          api.getSettings()
        ]);
        setDownloads(downloadsData.downloads);
        setSettings(settingsData);
      } catch (error) {
        console.error('Failed to load data:', error);
      }
    };

    loadData();
  }, [setDownloads, setSettings]);

  return (
    <div className="min-h-screen bg-bg-primary">
      {/* Background gradient */}
      <div className="fixed inset-0 bg-gradient-to-br from-accent/5 via-transparent to-success/5 pointer-events-none" />
      
      {/* Grid pattern */}
      <div 
        className="fixed inset-0 opacity-[0.02] pointer-events-none"
        style={{
          backgroundImage: `linear-gradient(rgba(0, 212, 255, 0.1) 1px, transparent 1px),
                           linear-gradient(90deg, rgba(0, 212, 255, 0.1) 1px, transparent 1px)`,
          backgroundSize: '50px 50px'
        }}
      />

      <div className="relative z-10">
        <Header />
        
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {/* Hero Section */}
          <div className="text-center mb-12 animate-slide-down">
            <h1 className="text-5xl sm:text-6xl lg:text-7xl font-extrabold mb-4">
              <span className="text-gradient">TURBO</span>
            </h1>
            <p className="text-text-secondary text-lg sm:text-xl max-w-2xl mx-auto">
              Enterprise-grade download manager. Blazing fast. Infinite possibilities.
            </p>
          </div>

          {/* Drop Zone */}
          <div className="mb-8">
            <DropZone />
          </div>

          {/* Stats & Queue Grid */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
            {/* Speed Monitor */}
            <div className="lg:col-span-1">
              <SpeedMonitor />
            </div>

            {/* Download Queue */}
            <div className="lg:col-span-2">
              <DownloadList />
            </div>
          </div>

          {/* Quick Stats */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
            <StatCard 
              label="Active Downloads"
              value={downloads.filter(d => d.status === 'active').length}
              icon="⚡"
              color="cyan"
            />
            <StatCard 
              label="Completed"
              value={downloads.filter(d => d.status === 'completed').length}
              icon="✓"
              color="green"
            />
            <StatCard 
              label="Queued"
              value={downloads.filter(d => d.status === 'queued').length}
              icon="⏳"
              color="orange"
            />
            <StatCard 
              label="Failed"
              value={downloads.filter(d => d.status === 'failed').length}
              icon="✗"
              color="red"
            />
          </div>
        </main>

        {/* Footer */}
        <footer className="border-t border-border-subtle py-6 mt-12">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            <p className="text-text-muted text-sm">
              Turbo Downloader • Built for speed
            </p>
          </div>
        </footer>
      </div>

      {/* Modals */}
      <SettingsModal />
      <ToastContainer />
    </div>
  );
}

function StatCard({ label, value, icon, color }) {
  const colorClasses = {
    cyan: 'text-accent bg-accent/10 border-accent/20',
    green: 'text-success bg-success/10 border-success/20',
    orange: 'text-warning bg-warning/10 border-warning/20',
    red: 'text-error bg-error/10 border-error/20'
  };

  return (
    <div className={`bg-bg-secondary rounded-xl p-4 border ${colorClasses[color]} card-hover`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-text-muted text-xs uppercase tracking-wider mb-1">{label}</p>
          <p className="text-2xl font-bold font-mono">{value}</p>
        </div>
        <span className="text-2xl">{icon}</span>
      </div>
    </div>
  );
}

export default App;
