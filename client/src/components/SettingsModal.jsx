import { useState, useEffect } from 'react';
import {
  X, Settings, Zap, Folder, Bell, Palette, Save, RotateCcw,
  Film, Server, CheckCircle2, AlertTriangle, Check, Mail, Phone, Info,
} from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';
import { DESIGNER, APP_VERSION } from '../credits';
import { usePWA } from '../hooks/usePWA';
import { InstallCard } from './InstallApp';


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
    { id: 'about', label: 'About', icon: Info },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 modal-backdrop" onClick={toggle} />
      <div className="relative w-full max-w-2xl max-h-[90vh] bg-bg-secondary rounded-sm border border-border-subtle shadow-2xl overflow-hidden animate-slide-up flex flex-col">
        <div className="flex items-center justify-between gap-3 px-6 py-5 border-b border-border-subtle">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-sm bg-accent/10 border border-accent/25 flex items-center justify-center">
              <Settings className="w-4 h-4 text-accent" />
            </div>
            <div>
              <h2 className="font-display font-semibold text-lg tracking-wide text-text-primary">Configuration</h2>
              <p className="kicker mt-0.5" style={{ letterSpacing: '0.18em' }}>Tune the engine to your workflow</p>
            </div>
          </div>
          <button
            onClick={toggle}
            className="p-2 rounded-sm text-text-secondary hover:text-text-primary hover:bg-bg-tertiary transition-colors focus-ring"
            aria-label="Close"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="flex flex-1 min-h-0 flex-col sm:flex-row">
          <div className="sm:w-44 border-b sm:border-b-0 sm:border-r border-border-subtle p-3 shrink-0 bg-bg-primary/40">
            <nav className="flex sm:flex-col gap-1 overflow-x-auto">
              {tabs.map((t) => {
                const on = tab === t.id;
                return (
                  <button
                    key={t.id}
                    onClick={() => setTab(t.id)}
                    className={`relative flex items-center gap-2.5 px-3 py-2.5 rounded-sm text-xs font-semibold uppercase tracking-wider transition-all whitespace-nowrap ${
                      on
                        ? 'bg-accent/10 text-accent'
                        : 'text-text-muted hover:bg-bg-tertiary hover:text-text-primary'
                    }`}
                  >
                    {on && <span className="absolute left-0 top-2 bottom-2 w-[2px] bg-accent" />}
                    <t.icon className="w-3.5 h-3.5" />
                    {t.label}
                  </button>
                );
              })}
            </nav>
          </div>

          <div className="flex-1 p-6 overflow-y-auto">
            {tab === 'connection' && <ConnectionSettings settings={local} onChange={change} />}
            {tab === 'storage' && <StorageSettings settings={local} onChange={change} />}
            {tab === 'notifications' && <NotificationSettings settings={local} onChange={change} />}
            {tab === 'appearance' && <AppearanceSettings settings={local} onChange={change} />}
            {tab === 'system' && <SystemInfo system={system} settings={local} />}
            {tab === 'about' && <AboutPanel system={system} />}
          </div>
        </div>

        <div className="flex items-center justify-between gap-3 px-6 py-4 border-t border-border-subtle">
          <button
            onClick={reset}
            className="px-3 py-2 rounded-sm text-xs font-semibold uppercase tracking-wider text-text-muted hover:text-error transition-colors flex items-center gap-2"
          >
            <RotateCcw className="w-3.5 h-3.5" /> Reset defaults
          </button>
          <div className="flex items-center gap-2">
            <button
              onClick={toggle}
              className="px-4 py-2.5 rounded-sm text-xs font-semibold uppercase tracking-wider text-text-secondary hover:text-text-primary transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={save}
              disabled={saving}
              className="px-5 py-2.5 rounded-sm text-xs font-bold uppercase tracking-[0.14em] bg-accent text-bg-primary hover:brightness-110 transition-all flex items-center gap-2 disabled:opacity-50 focus-ring"
            >
              {saving ? 'Saving…' : (<><Save className="w-3.5 h-3.5" /> Save changes</>)}
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
        <span className="font-mono text-sm text-accent speed-counter">
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
      {hint && <p className="text-xs text-text-muted mt-1.5">{hint}</p>}
    </div>
  );
}

function Toggle({ label, hint, checked, onChange }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <div>
        <label className="text-sm font-medium text-text-primary">{label}</label>
        {hint && <p className="text-xs text-text-muted mt-0.5">{hint}</p>}
      </div>
      <button
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`w-11 h-6 rounded-sm transition-all duration-200 relative shrink-0 border ${
          checked ? 'bg-accent border-accent' : 'bg-bg-tertiary border-border-subtle'
        }`}
      >
        <span
          className={`absolute top-0.5 w-4 h-4 rounded-sm bg-white transition-all duration-200 ${
            checked ? 'left-[1.375rem]' : 'left-0.5'
          }`}
        />
      </button>
    </div>
  );
}

function ConnectionSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <Header title="Connection" subtitle="Optimise speed and concurrency" />
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
        hint="How many files download at the same time (1–20)."
        value={settings.concurrentDownloads}
        min={1}
        max={20}
        onChange={(v) => onChange('concurrentDownloads', v)}
      />
      <Slider
        label="Split count"
        hint="Ceiling on segments per file. A download uses the smaller of this and 'Connections per download', so raising only one has no effect."
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
        suffix={settings.bandwidthLimit === 0 ? ' KB/s · unlimited' : ' KB/s'}
        onChange={(v) => onChange('bandwidthLimit', v)}
      />
    </div>
  );
}

function StorageSettings({ settings, onChange }) {
  return (
    <div className="space-y-6">
      <Header title="Storage" subtitle="Where files go and how duplicates are handled" />
      <div>
        <label className="kicker mb-2 block">Download directory</label>
        <input
          type="text"
          value={settings.defaultDir}
          onChange={(e) => onChange('defaultDir', e.target.value)}
          className="w-full px-3.5 py-3 bg-bg-primary rounded-sm border border-border-subtle text-text-primary text-sm focus:border-accent font-mono"
          placeholder="/path/to/downloads"
        />
        <p className="text-xs text-text-muted mt-1.5">The directory must be writable by the server process.</p>
      </div>
      <div>
        <label className="kicker mb-2 block">Duplicate files</label>
        <select
          value={settings.duplicateHandling}
          onChange={(e) => onChange('duplicateHandling', e.target.value)}
          className="w-full px-3.5 py-3 bg-bg-primary rounded-sm border border-border-subtle text-text-primary text-sm focus:border-accent"
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
      <Header title="Alerts" subtitle="Control notifications and retry behaviour" />
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
    { id: 'cyan', color: '#22e0ff', name: 'Cyan' },
    { id: 'green', color: '#2fffc8', name: 'Mint' },
    { id: 'amber', color: '#ffc43c', name: 'Amber' },
    { id: 'orange', color: '#ff8a30', name: 'Orange' },
    { id: 'rose', color: '#ff5c8c', name: 'Rose' },
    { id: 'purple', color: '#aa7aff', name: 'Violet' },
  ];
  return (
    <div className="space-y-6">
      <Header title="Appearance" subtitle="Make Turbo feel like yours" />
      <div>
        <label className="kicker mb-3 block">Theme</label>
        <div className="grid grid-cols-2 gap-3">
          {['dark', 'light'].map((theme) => {
            const on = settings.theme === theme;
            return (
              <button
                key={theme}
                onClick={() => onChange('theme', theme)}
                className={`p-3 rounded-sm border-2 transition-all duration-200 text-left focus-ring ${
                  on ? 'border-accent bg-accent/5' : 'border-border-subtle hover:border-accent/50'
                }`}
              >
                <div className={`w-full h-14 rounded-sm mb-2.5 border border-border-subtle overflow-hidden ${theme === 'dark' ? 'bg-[#080a10]' : 'bg-[#f4f6fb]'}`}>
                  <div className="h-2 w-10 bg-accent mx-2 mt-3 rounded-sm" />
                  <div className="h-1.5 w-16 bg-text-muted/30 mx-2 mt-1.5 rounded-sm" />
                </div>
                <span className={`text-xs font-semibold uppercase tracking-wider ${on ? 'text-accent' : 'text-text-primary'}`}>
                  {theme} mode
                </span>
              </button>
            );
          })}
        </div>
      </div>
      <div>
        <label className="kicker mb-3 block">Accent signal</label>
        <div className="flex flex-wrap gap-2.5">
          {accents.map((a) => {
            const on = settings.accentColor === a.id;
            return (
              <button
                key={a.id}
                onClick={() => onChange('accentColor', a.id)}
                title={a.name}
                className={`w-10 h-10 rounded-sm border transition-all duration-200 flex items-center justify-center focus-ring ${
                  on ? 'border-white/80 scale-105' : 'border-transparent hover:scale-105'
                }`}
                style={{ backgroundColor: a.color }}
              >
                {on && <Check className="w-4 h-4 text-black/70" />}
              </button>
            );
          })}
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
      <div className="space-y-2.5">
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
        <div className="rounded-sm border border-warning/30 bg-warning/10 p-4 text-sm text-warning flex gap-3">
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

function AboutPanel({ system }) {
  const pwa = usePWA();
  return (
    <div className="space-y-6">
      <Header title="About" subtitle="Application info and credits" />

      <InstallCard pwa={pwa} />

      <div className="rounded-sm border border-border-subtle bg-bg-primary p-5 text-center">
        <p className="kicker" style={{ letterSpacing: '0.3em' }}>Designed by</p>
        <p className="mt-2 font-display text-lg font-semibold text-text-primary">{DESIGNER.name}</p>
        <div className="mt-3 flex flex-col sm:flex-row items-center justify-center gap-2 sm:gap-4 text-sm">
          <a
            href={`mailto:${DESIGNER.email}`}
            className="inline-flex items-center gap-2 text-text-secondary hover:text-accent transition-colors"
          >
            <Mail className="w-4 h-4 text-accent" />
            {DESIGNER.email}
          </a>
          <a
            href={`tel:${DESIGNER.phoneHref}`}
            className="inline-flex items-center gap-2 text-text-secondary hover:text-accent transition-colors"
          >
            <Phone className="w-4 h-4 text-accent" />
            {DESIGNER.phone}
          </a>
        </div>
      </div>

      <div className="space-y-2.5">
        <InfoRow
          icon={Info}
          label="Application"
          value={`Turbo Downloader v${APP_VERSION}`}
          ok
        />
        <InfoRow
          icon={Server}
          label="Server"
          value={`v${system?.version || APP_VERSION} · Node ${system?.node || '—'}`}
          ok
        />
      </div>
    </div>
  );
}

function InfoRow({ icon: Icon, label, value, ok }) {
  return (
    <div className="flex items-center justify-between gap-4 bg-bg-primary rounded-sm p-3 border border-border-subtle">
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
      <h3 className="font-display font-semibold text-base tracking-wide text-text-primary mb-1">{title}</h3>
      <p className="text-sm text-text-muted">{subtitle}</p>
    </div>
  );
}
