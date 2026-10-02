import { useState, useEffect } from 'react';
import {
  X, Settings, Zap, Folder, Bell, Palette, Save, RotateCcw,
  Film, Server, CheckCircle2, AlertTriangle, Check,
} from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';


export default function SettingsModal() {
  const open = useDownloadStore((s) => s.settingsModalOpen);
  const settings = useDownloadStore((s) => s.settings);
  const system = useDownloadStore((s) => s.system);
  const setSettings = useDownloadStore((s) => s.setSettings);
  const setSystem = useDownloadStore((s) => s.setSystem);
  const toggle = useDownloadStore((s) => s.toggleSettingsModal);
  const addNotification = useDownloadStore((s) => s.addNotification);

  const [local, setLocal] = useState(settings);
  const [tab, setTab] = useState('connection');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) setLocal(settings);
  }, [settings, open]);

  if (!open) return null;

  const change = (key, value) => setLocal((prev) => ({ ...prev, [key]: value }));

  const save = async () => {
    setSaving(true);
    try {
      const updated = await api.updateSettings(local);
      setSettings(updated);
      const sys = await api.getSystem();
      setSystem(sys);
      toggle();
      addNotification({ type: 'success', title: 'Settings saved', message: 'Preferences updated' });
    } catch (error) {
      addNotification({ type: 'error', title: 'Save failed', message: error.message });
    } finally {
      setSaving(false);
    }
  };

  const reset = async () => {
    try {
      const defaults = await api.resetSettings();
      setLocal(defaults);
      setSettings(defaults);
      addNotification({ type: 'info', title: 'Reset complete', message: 'Settings restored to defaults' });
    } catch (error) {
      addNotification({ type: 'error', title: 'Reset failed', message: error.message });
    }
  };

  const tabs = [
    { id: 'connection', label: 'Connection', icon: Zap },
    { id: 'storage', label: 'Storage', icon: Folder },
    { id: 'notifications', label: 'Alerts', icon: Bell },
    { id: 'appearance', label: 'Appearance', icon: Palette },
    { id: 'system', label: 'System', icon: Server },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 modal-backdrop" onClick={toggle} />
      <div className="relative w-full max-w-2xl max-h-[90vh] bg-bg-secondary rounded-2xl border border-border-subtle shadow-2xl overflow-hidden animate-slide-up flex flex-col">
        <div className="flex items-center justify-between p-6 border-b border-border-subtle">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-accent/10 flex items-center justify-center">
              <Settings className="w-5 h-5 text-accent" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-text-primary">Settings</h2>
              <p className="text-sm text-text-muted">Tune Turbo to your workflow</p>
            </div>
          </div>
          <button
            onClick={toggle}
            className="p-2 rounded-lg bg-bg-tertiary text-text-secondary hover:text-text-primary transition-colors"
            aria-label="Close"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex flex-1 min-h-0 flex-col sm:flex-row">
          <div className="sm:w-48 border-b sm:border-b-0 sm:border-r border-border-subtle p-4 shrink-0">
            <nav className="flex sm:flex-col gap-1 overflow-x-auto">
              {tabs.map((t) => (
                <button
                  key={t.id}
                  onClick={() => setTab(t.id)}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all whitespace-nowrap ${
                    tab === t.id
                      ? 'bg-accent/10 text-accent'
                      : 'text-text-secondary hover:bg-bg-tertiary hover:text-text-primary'
                  }`}
                >
                  <t.icon className="w-4 h-4" />
                  {t.label}
                </button>
              ))}
            </nav>
          </div>

          <div className="flex-1 p-6 overflow-y-auto">
            {tab === 'connection' && <ConnectionSettings settings={local} onChange={change} />}
            {tab === 'storage' && <StorageSettings settings={local} onChange={change} />}
            {tab === 'notifications' && <NotificationSettings settings={local} onChange={change} />}
            {tab === 'appearance' && <AppearanceSettings settings={local} onChange={change} />}
            {tab === 'system' && <SystemInfo system={system} settings={local} />}
          </div>
        </div>

        <div className="flex items-center justify-between gap-3 p-6 border-t border-border-subtle">
          <button
            onClick={reset}
            className="px-4 py-2.5 rounded-xl text-sm font-medium text-text-muted hover:text-error transition-colors flex items-center gap-2"
          >
            <RotateCcw className="w-4 h-4" /> Reset defaults
          </button>
          <div className="flex items-center gap-3">
            <button
              onClick={toggle}
              className="px-6 py-2.5 rounded-xl text-sm font-medium text-text-secondary hover:text-text-primary transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={save}
              disabled={saving}
              className="px-6 py-2.5 rounded-xl text-sm font-semibold bg-gradient-to-r from-accent to-success text-bg-primary hover:shadow-lg hover:shadow-accent/30 transition-all flex items-center gap-2 disabled:opacity-50 focus-ring"
            >
              {saving ? 'Saving…' : (<><Save className="w-4 h-4" /> Save changes</>)}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Slider({ label, hint, value, min, max, step = 1, suffix = '', onChange }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <label className="text-sm font-medium text-text-primary">{label}</label>
        <span className="text-sm font-mono text-accent">
          {value}
          {suffix}
        </span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseInt(e.target.value, 10))}
      />
      {hint && <p className="text-xs text-text-muted mt-1">{hint}</p>}
    </div>
  );
}

function Toggle({ label, hint, checked, onChange }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <div>
        <label className="text-sm font-medium text-text-primary">{label}</label>
        {hint && <p className="text-xs text-text-muted">{hint}</p>}
      </div>
      <button
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`w-12 h-6 rounded-full transition-all duration-200 relative shrink-0 ${
          checked ? 'bg-accent' : 'bg-bg-tertiary'
        }`}
      >
        <span
          className={`absolute top-1 w-4 h-4 rounded-full bg-white transition-all duration-200 ${
            checked ? 'left-7' : 'left-1'
          }`}
        />
      </button>
    </div>
  );
}

function ConnectionSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <Header title="Connection Settings" subtitle="Optimise speed and concurrency" />
      <Slider
        label="Connections per download"
        hint="Segments requested in parallel (1–32). Higher is faster but heavier on the server."
        value={settings.connections}
        min={1}
        max={32}
        onChange={(v) => onChange('connections', v)}
      />
      <Slider
        label="Concurrent downloads"
        hint="How many files download at the same time."
        value={settings.concurrentDownloads}
        min={1}
        max={10}
        onChange={(v) => onChange('concurrentDownloads', v)}
      />
      <Slider
        label="Split count"
        hint="Preferred number of segments when the server supports ranges."
        value={settings.split}
        min={1}
        max={32}
        onChange={(v) => onChange('split', v)}
      />
      <Slider
        label="Bandwidth limit"
        hint="0 means unlimited. Applied across active downloads."
        value={settings.bandwidthLimit}
        min={0}
        max={100000}
        step={100}
        suffix={settings.bandwidthLimit === 0 ? ' KB/s (unlimited)' : ' KB/s'}
        onChange={(v) => onChange('bandwidthLimit', v)}
      />
    </div>
  );
}

function StorageSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <Header title="Storage Settings" subtitle="Where files go and how duplicates are handled" />
      <div>
        <label className="text-sm font-medium text-text-primary mb-2 block">Download directory</label>
        <input
          type="text"
          value={settings.defaultDir}
          onChange={(e) => onChange('defaultDir', e.target.value)}
          className="w-full px-4 py-3 bg-bg-primary rounded-xl border border-border-subtle text-text-primary text-sm focus:border-accent font-mono"
          placeholder="/path/to/downloads"
        />
        <p className="text-xs text-text-muted mt-1">The directory must be writable by the server process.</p>
      </div>
      <div>
        <label className="text-sm font-medium text-text-primary mb-2 block">Duplicate files</label>
        <select
          value={settings.duplicateHandling}
          onChange={(e) => onChange('duplicateHandling', e.target.value)}
          className="w-full px-4 py-3 bg-bg-primary rounded-xl border border-border-subtle text-text-primary text-sm focus:border-accent"
        >
          <option value="skip">Skip existing files</option>
          <option value="rename">Rename new files (e.g. "file (1).zip")</option>
          <option value="overwrite">Overwrite existing files</option>
        </select>
      </div>
      <Toggle
        label="Auto-start downloads"
        hint="Begin as soon as a URL is added."
        checked={settings.autoStart}
        onChange={(v) => onChange('autoStart', v)}
      />
    </div>
  );
}

function NotificationSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <Header title="Notification Settings" subtitle="Control alerts and retry behaviour" />
      <Toggle
        label="Enable notifications"
        hint="Show in-app and desktop alerts when downloads finish."
        checked={settings.notifications}
        onChange={(v) => onChange('notifications', v)}
      />
      <Slider
        label="Max retries"
        hint="Automatic retries with exponential backoff before a download is marked failed."
        value={settings.maxRetries}
        min={0}
        max={20}
        onChange={(v) => onChange('maxRetries', v)}
      />
      <Slider
        label="Retry wait"
        hint="Base delay between retries; doubles each attempt."
        value={settings.retryWait}
        min={0}
        max={120}
        step={1}
        suffix="s"
        onChange={(v) => onChange('retryWait', v)}
      />
    </div>
  );
}

function AppearanceSettings({ settings, onChange }) {
  const accents = [
    { id: 'cyan', color: '#00d4ff', name: 'Cyan' },
    { id: 'green', color: '#00e082', name: 'Green' },
    { id: 'purple', color: '#a855f7', name: 'Purple' },
    { id: 'orange', color: '#ff8800', name: 'Orange' },
  ];
  return (
    <div className="space-y-6">
      <Header title="Appearance" subtitle="Make Turbo feel like yours" />
      <div>
        <label className="text-sm font-medium text-text-primary mb-3 block">Theme</label>
        <div className="grid grid-cols-2 gap-3">
          {['dark', 'light'].map((theme) => (
            <button
              key={theme}
              onClick={() => onChange('theme', theme)}
              className={`p-4 rounded-xl border-2 transition-all duration-200 capitalize focus-ring ${
                settings.theme === theme ? 'border-accent bg-accent/10' : 'border-border-subtle hover:border-accent/50'
              }`}
            >
              <div className={`w-full h-14 rounded-lg mb-2 ${theme === 'dark' ? 'bg-[#0a0a0f]' : 'bg-[#f4f6fa]'}`}>
                <div className="h-2 w-12 rounded bg-accent mx-2 mt-3" />
              </div>
              <span className={`text-sm font-medium ${settings.theme === theme ? 'text-accent' : 'text-text-primary'}`}>
                {theme} mode
              </span>
            </button>
          ))}
        </div>
      </div>
      <div>
        <label className="text-sm font-medium text-text-primary mb-3 block">Accent colour</label>
        <div className="flex gap-3">
          {accents.map((a) => (
            <button
              key={a.id}
              onClick={() => onChange('accentColor', a.id)}
              title={a.name}
              className={`w-11 h-11 rounded-xl border-2 transition-all duration-200 flex items-center justify-center focus-ring ${
                settings.accentColor === a.id ? 'border-white scale-110' : 'border-transparent'
              }`}
              style={{ backgroundColor: a.color }}
            >
              {settings.accentColor === a.id && <Check className="w-5 h-5 text-black/70" />}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function SystemInfo({ system, settings }) {
  const media = system?.media || {};
  return (
    <div className="space-y-6">
      <Header title="System" subtitle="Runtime capabilities reported by the server" />
      <div className="space-y-3">
        <InfoRow
          icon={Film}
          label="Media engine (yt-dlp)"
          value={media.available ? `Available · v${media.version}` : 'Not installed'}
          ok={media.available}
        />
        <InfoRow icon={Folder} label="Download directory" value={system?.downloadDir || settings.defaultDir} ok />
        <InfoRow icon={Server} label="Server version" value={`v${system?.version || '—'} · Node ${system?.node || '—'}`} ok />
      </div>
      {!media.available && (
        <div className="rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm text-warning flex gap-3">
          <AlertTriangle className="w-5 h-5 shrink-0 mt-0.5" />
          <div>
            <p className="font-medium mb-1">Media downloads are disabled</p>
            <p className="text-warning/90">
              Install <span className="font-mono">yt-dlp</span> (and <span className="font-mono">ffmpeg</span> for
              merging) on the server to download from YouTube, SoundCloud, Vimeo and more. Direct HTTP
              downloads work without it.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

function InfoRow({ icon: Icon, label, value, ok }) {
  return (
    <div className="flex items-center justify-between gap-4 bg-bg-primary rounded-xl p-3 border border-border-subtle">
      <div className="flex items-center gap-3 min-w-0">
        <Icon className="w-4 h-4 text-accent shrink-0" />
        <span className="text-sm text-text-secondary">{label}</span>
      </div>
      <div className="flex items-center gap-2 min-w-0">
        <span className="font-mono text-xs text-text-primary truncate">{value}</span>
        {ok ? (
          <CheckCircle2 className="w-4 h-4 text-success shrink-0" />
        ) : (
          <AlertTriangle className="w-4 h-4 text-warning shrink-0" />
        )}
      </div>
    </div>
  );
}

function Header({ title, subtitle }) {
  return (
    <div>
      <h3 className="text-lg font-semibold text-text-primary mb-1">{title}</h3>
      <p className="text-sm text-text-muted">{subtitle}</p>
    </div>
  );
}
