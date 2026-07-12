import { useMemo } from 'react';
import { Activity, TrendingUp, Gauge } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';

export default function SpeedMonitor() {
  const stats = useDownloadStore((state) => state.stats);
  const speedHistory = useDownloadStore((state) => state.speedHistory);

  const formatSpeed = (bytes) => {
    if (bytes === 0) return '0';
    const k = 1024;
    const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  const formatSpeedShort = (bytes) => {
    if (bytes === 0) return '0';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  // Generate SVG path for the speed graph
  const graphPath = useMemo(() => {
    if (speedHistory.length < 2) return '';
    
    const width = 100;
    const height = 100;
    const maxSpeed = Math.max(...speedHistory, 1);
    
    const points = speedHistory.map((speed, i) => {
      const x = (i / (speedHistory.length - 1)) * width;
      const y = height - (speed / maxSpeed) * height;
      return `${x},${y}`;
    });

    return `M0,${height} L${points.join(' L')} L${width},${height} Z`;
  }, [speedHistory]);

  const currentSpeedPercent = useMemo(() => {
    const maxSpeed = Math.max(...speedHistory, 1);
    return maxSpeed > 0 ? Math.min((stats.totalSpeed / maxSpeed) * 100, 100) : 0;
  }, [stats.totalSpeed, speedHistory]);

  return (
    <div className="bg-bg-secondary rounded-2xl border border-border-subtle p-6 h-full">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-accent/10 flex items-center justify-center">
            <Activity className="w-5 h-5 text-accent" />
          </div>
          <div>
            <h3 className="font-semibold text-text-primary">Speed Monitor</h3>
            <p className="text-xs text-text-muted">Real-time bandwidth</p>
          </div>
        </div>
        <div className={`w-3 h-3 rounded-full ${stats.activeCount > 0 ? 'bg-success pulse-dot' : 'bg-text-muted'}`} />
      </div>

      {/* Current Speed Display */}
      <div className="text-center mb-6">
        <div className="relative inline-block">
          <p className="text-5xl font-bold font-mono text-gradient speed-counter">
            {formatSpeedShort(stats.totalSpeed)}
          </p>
          {stats.totalSpeed > 0 && (
            <span className="absolute -top-2 -right-8 text-xs text-accent font-medium">/s</span>
          )}
        </div>
        <p className="text-sm text-text-secondary mt-1">
          {stats.activeCount > 0 
            ? `${stats.activeCount} active download${stats.activeCount > 1 ? 's' : ''}`
            : 'No active downloads'
          }
        </p>
      </div>

      {/* Speed Graph */}
      <div className="relative h-32 mb-6 bg-bg-primary rounded-xl p-3 overflow-hidden">
        {speedHistory.length > 1 ? (
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="w-full h-full">
            <defs>
              <linearGradient id="speedGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" stopColor="#00d4ff" stopOpacity="0.4" />
                <stop offset="100%" stopColor="#00d4ff" stopOpacity="0.05" />
              </linearGradient>
              <linearGradient id="lineGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stopColor="#00d4ff" />
                <stop offset="100%" stopColor="#00ffcc" />
              </linearGradient>
            </defs>
            {/* Fill area */}
            <path d={graphPath} fill="url(#speedGradient)" />
            {/* Line */}
            <path
              d={graphPath.replace(/L\d+,\d+ Z$/, '')}
              fill="none"
              stroke="url(#lineGradient)"
              strokeWidth="2"
              vectorEffect="non-scaling-stroke"
            />
            {/* Current position indicator */}
            {speedHistory.length > 0 && (
              <circle
                cx="100"
                cy={100 - (Math.min(stats.totalSpeed / Math.max(...speedHistory, 1), 1) * 100)}
                r="3"
                fill="#00d4ff"
                className="animate-pulse"
              />
            )}
          </svg>
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            <p className="text-text-muted text-sm">Start downloading to see graph</p>
          </div>
        )}
        
        {/* Grid lines */}
        <div className="absolute inset-3 pointer-events-none">
          <div className="h-full flex flex-col justify-between">
            <div className="border-b border-border-subtle/30" />
            <div className="border-b border-border-subtle/30" />
            <div className="border-b border-border-subtle/30" />
            <div className="border-b border-border-subtle/30" />
          </div>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-bg-primary rounded-xl p-3">
          <div className="flex items-center gap-2 mb-1">
            <TrendingUp className="w-4 h-4 text-success" />
            <span className="text-xs text-text-muted">Peak Speed</span>
          </div>
          <p className="font-mono font-semibold text-success">
            {formatSpeed(stats.peakSpeed)}
          </p>
        </div>
        
        <div className="bg-bg-primary rounded-xl p-3">
          <div className="flex items-center gap-2 mb-1">
            <Gauge className="w-4 h-4 text-warning" />
            <span className="text-xs text-text-muted">Utilization</span>
          </div>
          <p className="font-mono font-semibold text-warning">
            {currentSpeedPercent.toFixed(0)}%
          </p>
        </div>
      </div>

      {/* Time indicator */}
      <p className="text-xs text-text-muted text-center mt-4">
        Last 60 seconds
      </p>
    </div>
  );
}
