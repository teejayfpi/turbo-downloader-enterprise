import { useState, useEffect } from 'react';
import { X, Settings, Zap, Folder, Bell, Palette, Save } from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';

export default function SettingsModal() {
  const settingsModalOpen = useDownloadStore((state) => state.settingsModalOpen);
  const settings = useDownloadStore((state) => state.settings);
  const setSettings = useDownloadStore((state) => state.setSettings);
  const toggleSettingsModal = useDownloadStore((state) => state.toggleSettingsModal);
  const addNotification = useDownloadStore((state) => state.addNotification);

  const [localSettings, setLocalSettings] = useState(settings);
  const [activeTab, setActiveTab] = useState('connection');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    setLocalSettings(settings);
  }, [settings]);

  if (!settingsModalOpen) return null;

  const handleSave = async () => {
    setIsSaving(true);
    try {
      const updated = await api.updateSettings(localSettings);
      setSettings(updated);
      toggleSettingsModal();
      addNotification({
        type: 'success',
        title: 'Settings Saved',
        message: 'Your preferences have been updated'
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Save Failed',
        message: error.message
      });
    } finally {
      setIsSaving(false);
    }
  };

  const tabs = [
    { id: 'connection', label: 'Connection', icon: Zap },
    { id: 'storage', label: 'Storage', icon: Folder },
    { id: 'notifications', label: 'Notifications', icon: Bell },
    { id: 'appearance', label: 'Appearance', icon: Palette },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div 
        className="absolute inset-0 modal-backdrop"
        onClick={toggleSettingsModal}
      />
      
      {/* Modal */}
      <div className="relative w-full max-w-2xl max-h-[90vh] bg-bg-secondary rounded-2xl border border-border-subtle shadow-2xl overflow-hidden animate-slide-up">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-border-subtle">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-accent/10 flex items-center justify-center">
              <Settings className="w-5 h-5 text-accent" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-text-primary">Settings</h2>
              <p className="text-sm text-text-muted">Configure Turbo to your needs</p>
            </div>
          </div>
          <button
            onClick={toggleSettingsModal}
            className="p-2 rounded-lg bg-bg-tertiary text-text-secondary hover:text-text-primary transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="flex h-[500px]">
          {/* Sidebar */}
          <div className="w-48 border-r border-border-subtle p-4">
            <nav className="space-y-1">
              {tabs.map((tab) => {
                const Icon = tab.icon;
                return (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                    className={`
                      w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium
                      transition-all duration-200
                      ${activeTab === tab.id
                        ? 'bg-accent/10 text-accent'
                        : 'text-text-secondary hover:bg-bg-tertiary hover:text-text-primary'
                      }
                    `}
                  >
                    <Icon className="w-4 h-4" />
                    {tab.label}
                  </button>
                );
              })}
            </nav>
          </div>

          {/* Settings Content */}
          <div className="flex-1 p-6 overflow-y-auto">
            {activeTab === 'connection' && (
              <ConnectionSettings 
                settings={localSettings} 
                onChange={(key, value) => setLocalSettings({ ...localSettings, [key]: value })}
              />
            )}
            {activeTab === 'storage' && (
              <StorageSettings 
                settings={localSettings} 
                onChange={(key, value) => setLocalSettings({ ...localSettings, [key]: value })}
              />
            )}
            {activeTab === 'notifications' && (
              <NotificationSettings 
                settings={localSettings} 
                onChange={(key, value) => setLocalSettings({ ...localSettings, [key]: value })}
              />
            )}
            {activeTab === 'appearance' && (
              <AppearanceSettings 
                settings={localSettings} 
                onChange={(key, value) => setLocalSettings({ ...localSettings, [key]: value })}
              />
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 p-6 border-t border-border-subtle">
          <button
            onClick={toggleSettingsModal}
            className="px-6 py-2.5 rounded-xl text-sm font-medium text-text-secondary hover:text-text-primary transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving}
            className="px-6 py-2.5 rounded-xl text-sm font-semibold bg-gradient-to-r from-accent to-success text-bg-primary hover:shadow-lg hover:shadow-accent/30 transition-all flex items-center gap-2 disabled:opacity-50"
          >
            {isSaving ? 'Saving...' : (
              <>
                <Save className="w-4 h-4" />
                Save Changes
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

function ConnectionSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-text-primary mb-1">Connection Settings</h3>
        <p className="text-sm text-text-muted">Optimize download speed and concurrency</p>
      </div>

      <div className="space-y-4">
        {/* Connections per Download */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Connections per Download</label>
            <span className="text-sm font-mono text-accent">{settings.connections}</span>
          </div>
          <input
            type="range"
            min="1"
            max="32"
            value={settings.connections}
            onChange={(e) => onChange('connections', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">More connections = faster download (may strain servers)</p>
        </div>

        {/* Concurrent Downloads */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Concurrent Downloads</label>
            <span className="text-sm font-mono text-accent">{settings.concurrentDownloads}</span>
          </div>
          <input
            type="range"
            min="1"
            max="10"
            value={settings.concurrentDownloads}
            onChange={(e) => onChange('concurrentDownloads', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">Number of files to download simultaneously</p>
        </div>

        {/* Split Count */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Split Count</label>
            <span className="text-sm font-mono text-accent">{settings.split}</span>
          </div>
          <input
            type="range"
            min="1"
            max="32"
            value={settings.split}
            onChange={(e) => onChange('split', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">Number of segments to split each file into</p>
        </div>

        {/* Bandwidth Limit */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Bandwidth Limit (KB/s)</label>
            <span className="text-sm font-mono text-accent">
              {settings.bandwidthLimit === 0 ? 'Unlimited' : settings.bandwidthLimit + ' KB/s'}
            </span>
          </div>
          <input
            type="range"
            min="0"
            max="10000"
            step="100"
            value={settings.bandwidthLimit}
            onChange={(e) => onChange('bandwidthLimit', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">Set to 0 for unlimited bandwidth</p>
        </div>
      </div>
    </div>
  );
}

function StorageSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-text-primary mb-1">Storage Settings</h3>
        <p className="text-sm text-text-muted">Configure download location and file handling</p>
      </div>

      <div className="space-y-4">
        {/* Download Directory */}
        <div>
          <label className="text-sm font-medium text-text-primary mb-2 block">Download Directory</label>
          <input
            type="text"
            value={settings.defaultDir || 'TurboDownloads'}
            onChange={(e) => onChange('defaultDir', e.target.value)}
            className="w-full px-4 py-3 bg-bg-primary rounded-xl border border-border-subtle text-text-primary text-sm focus:border-accent focus:ring-2 focus:ring-accent/20"
            placeholder="Enter download directory path"
          />
          <p className="text-xs text-text-muted mt-1">Files will be saved to this directory</p>
        </div>

        {/* Duplicate Handling */}
        <div>
          <label className="text-sm font-medium text-text-primary mb-2 block">Duplicate File Handling</label>
          <select
            value={settings.duplicateHandling}
            onChange={(e) => onChange('duplicateHandling', e.target.value)}
            className="w-full px-4 py-3 bg-bg-primary rounded-xl border border-border-subtle text-text-primary text-sm focus:border-accent focus:ring-2 focus:ring-accent/20"
          >
            <option value="skip">Skip existing files</option>
            <option value="rename">Rename new files</option>
            <option value="overwrite">Overwrite existing files</option>
          </select>
          <p className="text-xs text-text-muted mt-1">What to do when a file already exists</p>
        </div>

        {/* Auto Start */}
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm font-medium text-text-primary">Auto-start Downloads</label>
            <p className="text-xs text-text-muted">Start downloads immediately when added</p>
          </div>
          <button
            onClick={() => onChange('autoStart', !settings.autoStart)}
            className={`
              w-12 h-6 rounded-full transition-all duration-200 relative
              ${settings.autoStart ? 'bg-accent' : 'bg-bg-tertiary'}
            `}
          >
            <span 
              className={`
                absolute top-1 w-4 h-4 rounded-full bg-white transition-all duration-200
                ${settings.autoStart ? 'left-7' : 'left-1'}
              `}
            />
          </button>
        </div>
      </div>
    </div>
  );
}

function NotificationSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-text-primary mb-1">Notification Settings</h3>
        <p className="text-sm text-text-muted">Control how Turbo notifies you</p>
      </div>

      <div className="space-y-4">
        {/* Enable Notifications */}
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm font-medium text-text-primary">Enable Notifications</label>
            <p className="text-xs text-text-muted">Show system notifications for downloads</p>
          </div>
          <button
            onClick={() => onChange('notifications', !settings.notifications)}
            className={`
              w-12 h-6 rounded-full transition-all duration-200 relative
              ${settings.notifications ? 'bg-accent' : 'bg-bg-tertiary'}
            `}
          >
            <span 
              className={`
                absolute top-1 w-4 h-4 rounded-full bg-white transition-all duration-200
                ${settings.notifications ? 'left-7' : 'left-1'}
              `}
            />
          </button>
        </div>

        {/* Max Retries */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Max Retries</label>
            <span className="text-sm font-mono text-accent">{settings.maxRetries}</span>
          </div>
          <input
            type="range"
            min="0"
            max="10"
            value={settings.maxRetries}
            onChange={(e) => onChange('maxRetries', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">Number of times to retry failed downloads</p>
        </div>

        {/* Retry Wait */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="text-sm font-medium text-text-primary">Retry Wait (seconds)</label>
            <span className="text-sm font-mono text-accent">{settings.retryWait}s</span>
          </div>
          <input
            type="range"
            min="5"
            max="120"
            step="5"
            value={settings.retryWait}
            onChange={(e) => onChange('retryWait', parseInt(e.target.value))}
            className="w-full"
          />
          <p className="text-xs text-text-muted mt-1">Time to wait between retry attempts</p>
        </div>
      </div>
    </div>
  );
}

function AppearanceSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-text-primary mb-1">Appearance Settings</h3>
        <p className="text-sm text-text-muted">Customize how Turbo looks</p>
      </div>

      <div className="space-y-4">
        {/* Theme */}
        <div>
          <label className="text-sm font-medium text-text-primary mb-3 block">Theme</label>
          <div className="grid grid-cols-2 gap-3">
            {['dark', 'light'].map((theme) => (
              <button
                key={theme}
                onClick={() => onChange('theme', theme)}
                className={`
                  p-4 rounded-xl border-2 transition-all duration-200 capitalize
                  ${settings.theme === theme
                    ? 'border-accent bg-accent/10'
                    : 'border-border-subtle hover:border-accent/50'
                  }
                `}
              >
                <div className={`
                  w-full h-16 rounded-lg mb-2
                  ${theme === 'dark' ? 'bg-bg-primary' : 'bg-gray-200'}
                `}>
                  <div className={`h-2 w-12 rounded ${theme === 'dark' ? 'bg-accent' : 'bg-blue-500'} mx-2`} />
                </div>
                <span className={`text-sm font-medium ${settings.theme === theme ? 'text-accent' : 'text-text-primary'}`}>
                  {theme} Mode
                </span>
              </button>
            ))}
          </div>
        </div>

        {/* Color Accent */}
        <div>
          <label className="text-sm font-medium text-text-primary mb-3 block">Accent Color</label>
          <div className="flex gap-3">
            {[
              { id: 'cyan', color: '#00d4ff', name: 'Cyan' },
              { id: 'green', color: '#00ff88', name: 'Green' },
              { id: 'purple', color: '#a855f7', name: 'Purple' },
              { id: 'orange', color: '#ff8800', name: 'Orange' },
            ].map((accent) => (
              <button
                key={accent.id}
                onClick={() => onChange('accentColor', accent.id)}
                className={`
                  w-10 h-10 rounded-xl border-2 transition-all duration-200
                  ${settings.accentColor === accent.id ? 'border-white scale-110' : 'border-transparent'}
                `}
                style={{ backgroundColor: accent.color }}
                title={accent.name}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
