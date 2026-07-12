import { CheckCircle, XCircle, Info, X } from 'lucide-react';
import { useDownloadStore } from '../stores/downloadStore';

export default function ToastContainer() {
  const notifications = useDownloadStore((state) => state.notifications);
  const removeNotification = useDownloadStore((state) => state.removeNotification);

  if (notifications.length === 0) return null;

  return (
    <div className="fixed top-4 right-4 z-[100] space-y-3 max-w-sm">
      {notifications.map((notification) => (
        <Toast
          key={notification.id}
          notification={notification}
          onDismiss={() => removeNotification(notification.id)}
        />
      ))}
    </div>
  );
}

function Toast({ notification, onDismiss }) {
  const config = {
    success: {
      icon: CheckCircle,
      bg: 'bg-success/10',
      border: 'border-success/30',
      iconColor: 'text-success',
      titleColor: 'text-success'
    },
    error: {
      icon: XCircle,
      bg: 'bg-error/10',
      border: 'border-error/30',
      iconColor: 'text-error',
      titleColor: 'text-error'
    },
    info: {
      icon: Info,
      bg: 'bg-accent/10',
      border: 'border-accent/30',
      iconColor: 'text-accent',
      titleColor: 'text-accent'
    },
    warning: {
      icon: Info,
      bg: 'bg-warning/10',
      border: 'border-warning/30',
      iconColor: 'text-warning',
      titleColor: 'text-warning'
    }
  };

  const type = notification.type || 'info';
  const { icon: Icon, bg, border, iconColor, titleColor } = config[type] || config.info;

  return (
    <div 
      className={`
        ${bg} ${border} border rounded-xl p-4 shadow-lg backdrop-blur-sm
        toast-enter flex items-start gap-3
      `}
    >
      <Icon className={`w-5 h-5 ${iconColor} shrink-0 mt-0.5`} />
      
      <div className="flex-1 min-w-0">
        <p className={`font-semibold text-sm ${titleColor}`}>
          {notification.title}
        </p>
        <p className="text-sm text-text-secondary mt-0.5">
          {notification.message}
        </p>
      </div>

      <button
        onClick={onDismiss}
        className="p-1 rounded-lg hover:bg-white/10 transition-colors shrink-0"
      >
        <X className="w-4 h-4 text-text-muted" />
      </button>
    </div>
  );
}
