import { useMemo } from 'react';
import { Activity, TrendingUp, Gauge } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';
import { formatSpeed, formatBytes } from '../lib/format';

export default function SpeedMonitor() {
  const stats = useDownloadStore((s) => s.stats);
  const speedHistory = useDownloadStore((s) => s.speedHistory);

  const graph = useMemo(() => {
    const points = speedHistory.slice(-60);
    if (points.length < 2) return { area: '', line: '', peak: 0, last: 0 };
    const max = Math.max(...points, 1);
    const stepX = 100 / (points.length - 1);
    const coords = points.map((speed, i) => {
      const x = (i * stepX).toFixed(2);
      const y = (100 - (speed / max) * 100).toFixed(2);
      return `${x},${y}`;
    });
    const line = `M${coords.join(' L')}`;
    return { area: `${line} L100,100 L0,100 Z`, line, peak: max, last: points[points.length - 1] };
  }, [speedHistory]);

  const utilization = useMemo(() => {
    const max = Math.max(...speedHistory, stats.totalSpeed, 1);
    return max > 0 ? Math.min((stats.totalSpeed / max) * 100, 100) : 0;
  }, [stats.totalSpeed, speedHistory]);

  return (
    <div className="panel h-full flex flex-col">
      <div className="flex items-center justify-between gap-3 px-5 pt-5 pb-4 border-b border-border-subtle">
        <div className="flex items-center gap-2.5">
          <Activity className="w-4 h-4 text-accent" />
          <span className="kicker">Throughput</span>
        </div>
        <span className="kicker flex items-center gap-1.5" style={{ letterSpacing: '0.18em' }}>
          <span className={`inline-block w-1.5 h-1.5 rounded-full ${stats.activeCount > 0 ? 'bg-success pulse-dot' : 'bg-text-muted'}`} />
          {stats.activeCount > 0 ? 'live' : 'idle'}
        </span>
      </div>

      <div className="px-5 pt-5">
        <p className="font-mono font-bold text-4xl text-gradient speed-counter leading-none">
          {formatSpeed(stats.totalSpeed)}
        </p>
        <p className="text-xs text-text-secondary mt-2">
          {stats.activeCount > 0
            ? `${stats.activeCount} active download${stats.activeCount > 1 ? 's' : ''}`
            : 'No active downloads'}
        </p>
      </div>

      <div className="relative h-28 mx-5 my-5 bg-bg-primary rounded-sm border border-border-subtle overflow-hidden">
        {speedHistory.length > 1 ? (
          <>
            <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="w-full h-full">
              <defs>
                <linearGradient id="speedGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="rgb(var(--accent))" stopOpacity="0.4" />
                  <stop offset="100%" stopColor="rgb(var(--accent))" stopOpacity="0.02" />
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
            {/* faint horizontal graticule */}
            <div className="absolute inset-0 pointer-events-none grid-bg opacity-[0.06]" />
          </>
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            <p className="kicker">Awaiting telemetry</p>
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-px bg-border-subtle mt-auto border-t border-border-subtle">
        <MiniStat icon={TrendingUp} label="Peak" value={formatSpeed(stats.peakSpeed)} tone="text-success" />
        <MiniStat icon={Gauge} label="Utilization" value={`${utilization.toFixed(0)}%`} tone="text-warning" />
        <MiniStat icon={Activity} label="Downloaded" value={formatBytes(stats.totalDownloaded)} tone="text-accent" />
        <MiniStat icon={Activity} label="Completed" value={String(stats.completedCount || 0)} tone="text-success" />
      </div>
    </div>
  );
}

function MiniStat({ icon: Icon, label, value, tone }) {
  return (
    <div className="bg-bg-secondary p-3.5">
      <div className="flex items-center gap-1.5 mb-1.5">
        <Icon className={`w-3.5 h-3.5 ${tone}`} />
        <span className="kicker" style={{ letterSpacing: '0.2em' }}>{label}</span>
      </div>
      <p className={`font-mono font-semibold text-sm speed-counter ${tone}`}>{value}</p>
    </div>
  );
}
