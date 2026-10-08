import { create } from 'zustand';

export const DEFAULT_SETTINGS = {
  connections: 8,
  concurrentDownloads: 5,
  split: 16,
  defaultDir: '',
  duplicateHandling: 'rename',
  notifications: true,
  bandwidthLimit: 0,
  autoStart: true,
  maxRetries: 5,
  retryWait: 5,
  theme: 'dark',
  accentColor: 'cyan',
};

export const useDownloadStore = create((set, get) => ({
  downloads: [],
  stats: {
    totalDownloaded: 0,
    totalSpeed: 0,
    peakSpeed: 0,
    activeCount: 0,
    completedCount: 0,
    failedCount: 0,
    queuedCount: 0,
    totalCount: 0,
  },
  speedHistory: [],
  settings: DEFAULT_SETTINGS,
  system: { media: { available: false }, downloadDir: '' },
  notifications: [],
  settingsModalOpen: false,
  connected: false,
  filter: 'all',
  canInstall: false,
  installedApp: false,
  installDismissed: false,

  setDownloads: (downloads) => set({ downloads }),
  setStats: (stats) => set({ stats }),
  setSpeedHistory: (speedHistory) => set({ speedHistory }),
  setSettings: (settings) => set({ settings }),
  setSystem: (system) => set({ system }),
  setConnected: (connected) => set({ connected }),
  setFilter: (filter) => set({ filter }),
  setInstall: (patch) => set((state) => ({ ...state, ...patch })),

  updateFromServer: (data) => {
    set((state) => ({
      downloads: data.downloads ?? state.downloads,
      stats: data.stats ?? state.stats,
      speedHistory: data.speedHistory ?? state.speedHistory,
    }));
  },

  addNotification: (notification) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    set((state) => ({ notifications: [...state.notifications, { ...notification, id }] }));
    const ttl = notification.persistent ? 12000 : 5000;
    setTimeout(() => get().removeNotification(id), ttl);
  },

  removeNotification: (id) => {
    set((state) => ({ notifications: state.notifications.filter((n) => n.id !== id) }));
  },

  toggleSettingsModal: () =>
    set((state) => ({ settingsModalOpen: !state.settingsModalOpen })),
}));

export const selectors = {
  filtered: (state) => {
    const { downloads, filter } = state;
    if (filter === 'all') return downloads;
    if (filter === 'active') {
      return downloads.filter((d) => d.status === 'active' || d.status === 'paused');
    }
    if (filter === 'queued') {
      return downloads.filter((d) => d.status === 'queued' || d.status === 'scheduled');
    }
    return downloads.filter((d) => d.status === filter);
  },
  counts: (state) => {
    const downloads = state.downloads;
    return {
      all: downloads.length,
      active: downloads.filter((d) => d.status === 'active').length,
      paused: downloads.filter((d) => d.status === 'paused').length,
      queued: downloads.filter((d) => d.status === 'queued' || d.status === 'scheduled').length,
      completed: downloads.filter((d) => d.status === 'completed').length,
      failed: downloads.filter((d) => d.status === 'failed').length,
    };
  },
};
