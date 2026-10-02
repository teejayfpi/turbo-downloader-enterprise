import { CheckCircle, XCircle, Info, AlertTriangle, X } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';

const CONFIG = {
  success: { icon: CheckCircle, tone: 'text-success', bg: 'bg-success/10', border: 'border-success/30' },
  error: { icon: XCircle, tone: 'text-error', bg: 'bg-error/10', border: 'border-error/30' },
  info: { icon: Info, tone: 'text-accent', bg: 'bg-accent/10', border: 'border-accent/30' },
  warning: { icon: AlertTriangle, tone: 'text-warning', bg: 'bg-warning/10', border: 'border-warning/30' },
};

export default function ToastContainer() {
  const notifications = useDownloadStore((s) => s.notifications);
  const removeNotification = useDownloadStore((s) => s.removeNotification);

  if (notifications.length === 0) return null;

  return (
    <div className="fixed top-20 right-4 z-[100] space-y-3 max-w-sm w-[calc(100%-2rem)] sm:w-auto">
      {notifications.map((n) => {
        const { icon: Icon, tone, bg, border } = CONFIG[n.type] || CONFIG.info;
        return (
          <div
            key={n.id}
            role="status"
            className={`${bg} ${border} border rounded-xl p-4 shadow-lg backdrop-blur-sm toast-enter flex items-start gap-3`}
          >
            <Icon className={`w-5 h-5 ${tone} shrink-0 mt-0.5`} />
            <div className="flex-1 min-w-0">
              <p className={`font-semibold text-sm ${tone}`}>{n.title}</p>
              <p className="text-sm text-text-secondary mt-0.5 break-words">{n.message}</p>
            </div>
            <button
              onClick={() => removeNotification(n.id)}
              className="p-1 rounded-lg hover:bg-white/10 transition-colors shrink-0"
              aria-label="Dismiss"
            >
              <X className="w-4 h-4 text-text-muted" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
