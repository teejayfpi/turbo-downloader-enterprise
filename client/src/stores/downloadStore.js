import { create } from 'zustand';

export const useDownloadStore = create((set, get) => ({
  downloads: [],
  stats: {
    totalDownloaded: 0,
    totalSpeed: 0,
    peakSpeed: 0,
    activeCount: 0,
    completedCount: 0,
    failedCount: 0
  },
  speedHistory: [],
  settings: {
    connections: 16,
    concurrentDownloads: 3,
    split: 16,
    defaultDir: '',
    duplicateHandling: 'rename',
    notifications: true,
    bandwidthLimit: 0,
    autoStart: true,
    maxRetries: 5,
    retryWait: 30,
    theme: 'dark'
  },
  notifications: [],
  settingsModalOpen: false,
  
  setDownloads: (downloads) => set({ downloads }),
  
  setStats: (stats) => set({ stats }),
  
  setSpeedHistory: (speedHistory) => set({ speedHistory }),
  
  setSettings: (settings) => set({ settings }),
  
  updateFromServer: (data) => {
    if (data.downloads) set({ downloads: data.downloads });
    if (data.stats) set({ stats: data.stats });
    if (data.speedHistory) set({ speedHistory: data.speedHistory });
  },
  
  addNotification: (notification) => {
    const id = Date.now();
    set((state) => ({
      notifications: [...state.notifications, { ...notification, id }]
    }));
    setTimeout(() => {
      get().removeNotification(id);
    }, 5000);
  },
  
  removeNotification: (id) => {
    set((state) => ({
      notifications: state.notifications.filter((n) => n.id !== id)
    }));
  },
  
  toggleSettingsModal: () => {
    set((state) => ({ settingsModalOpen: !state.settingsModalOpen }));
  },
  
  getActiveDownloads: () => {
    return get().downloads.filter((d) => d.status === 'active');
  },
  
  getCompletedDownloads: () => {
    return get().downloads.filter((d) => d.status === 'completed');
  },
  
  getQueuedDownloads: () => {
    return get().downloads.filter((d) => d.status === 'queued');
  },
  
  getTotalProgress: () => {
    const downloads = get().downloads.filter((d) => d.status === 'active');
    if (downloads.length === 0) return 0;
    const total = downloads.reduce((sum, d) => sum + (d.progress || 0), 0);
    return Math.round(total / downloads.length);
  }
}));
