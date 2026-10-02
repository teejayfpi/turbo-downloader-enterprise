import { useMemo } from 'react';
import { Activity, TrendingUp, Gauge, Download } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';
import { formatSpeed, formatBytes } from '../lib/format';

export default function SpeedMonitor() {
  const stats = useDownloadStore((s) => s.stats);
  const speedHistory = useDownloadStore((s) => s.speedHistory);

  const graph = useMemo(() => {
    const points = speedHistory.slice(-60);
    if (points.length < 2) return { area: '', line: '' };
    const max = Math.max(...points, 1);
    const stepX = 100 / (points.length - 1);
    const coords = points.map((speed, i) => {
      const x = (i * stepX).toFixed(2);
      const y = (100 - (speed / max) * 100).toFixed(2);
      return `${x},${y}`;
    });
    const line = `M${coords.join(' L')}`;
    return { area: `${line} L100,100 L0,100 Z`, line };
  }, [speedHistory]);

  const utilization = useMemo(() => {
    const max = Math.max(...speedHistory, stats.totalSpeed, 1);
    return max > 0 ? Math.min((stats.totalSpeed / max) * 100, 100) : 0;
  }, [stats.totalSpeed, speedHistory]);

  return (
    <div className="bg-bg-secondary rounded-2xl border border-border-subtle p-6 h-full flex flex-col">
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-accent/10 flex items-center justify-center">
            <Activity className="w-5 h-5 text-accent" />
          </div>
          <div>
            <h3 className="font-semibold text-text-primary">Speed Monitor</h3>
            <p className="text-xs text-text-muted">Real-time bandwidth</p>
          </div>
        </div>
        <div
          className={`w-3 h-3 rounded-full ${
            stats.activeCount > 0 ? 'bg-success pulse-dot' : 'bg-text-muted'
          }`}
        />
      </div>

      <div className="text-center mb-5">
        <p className="text-4xl font-bold font-mono text-gradient speed-counter">
          {formatSpeed(stats.totalSpeed)}
        </p>
        <p className="text-sm text-text-secondary mt-1">
          {stats.activeCount > 0
            ? `${stats.activeCount} active download${stats.activeCount > 1 ? 's' : ''}`
            : 'No active downloads'}
        </p>
      </div>

      <div className="relative h-32 mb-5 bg-bg-primary rounded-xl p-3 overflow-hidden">
        {speedHistory.length > 1 ? (
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="w-full h-full">
            <defs>
              <linearGradient id="speedGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="rgb(var(--accent))" stopOpacity="0.45" />
                <stop offset="100%" stopColor="rgb(var(--accent))" stopOpacity="0.03" />
              </linearGradient>
              <linearGradient id="lineGradient" x1="0" y1="0" x2="1" y2="0">
                <stop offset="0%" stopColor="rgb(var(--accent))" />
                <stop offset="100%" stopColor="rgb(var(--speed-ultra))" />
              </linearGradient>
            </defs>
            <path d={graph.area} fill="url(#speedGradient)" />
            <path
              d={graph.line}
              fill="none"
              stroke="url(#lineGradient)"
              strokeWidth="2"
              vectorEffect="non-scaling-stroke"
            />
          </svg>
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            <p className="text-text-muted text-sm">Start downloading to see the graph</p>
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-3 mt-auto">
        <MiniStat icon={TrendingUp} label="Peak Speed" value={formatSpeed(stats.peakSpeed)} tone="text-success" />
        <MiniStat icon={Gauge} label="Utilization" value={`${utilization.toFixed(0)}%`} tone="text-warning" />
        <MiniStat icon={Download} label="Downloaded" value={formatBytes(stats.totalDownloaded)} tone="text-accent" />
        <MiniStat
          icon={Activity}
          label="Completed"
          value={String(stats.completedCount || 0)}
          tone="text-success"
        />
      </div>

      <p className="text-xs text-text-muted text-center mt-4">Last {speedHistory.length || 0}s window</p>
    </div>
  );
}

function MiniStat({ icon: Icon, label, value, tone }) {
  return (
    <div className="bg-bg-primary rounded-xl p-3">
      <div className="flex items-center gap-2 mb-1">
        <Icon className={`w-4 h-4 ${tone}`} />
        <span className="text-xs text-text-muted">{label}</span>
      </div>
      <p className={`font-mono font-semibold text-sm ${tone}`}>{value}</p>
    </div>
  );
}
