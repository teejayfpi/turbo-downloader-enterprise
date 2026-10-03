import { useEffect, useState } from 'react';
import { Download, X, Smartphone } from 'lucide-react';
import { usePWA, isIOS } from '../hooks/usePWA';

function isMobileDevice() {
  if (typeof navigator === 'undefined') return false;
  return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
}

/**
 * Mobile-only nudge that surfaces the native install prompt. Hidden once the
 * app is installed, on desktop, or after the user dismisses it.
 */
export default function InstallBanner() {
  const pwa = usePWA();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const eligible = !pwa.installed && !pwa.dismissed && isMobileDevice() && (pwa.canPrompt || isIOS());
    setVisible(eligible);
  }, [pwa.installed, pwa.dismissed, pwa.canPrompt]);

  if (!visible) return null;

  return (
    <div className="fixed bottom-4 inset-x-4 sm:inset-x-auto sm:right-4 sm:w-96 z-[90] animate-slide-up">
      <div className="rounded-sm border border-accent/30 bg-bg-secondary/95 backdrop-blur-xl shadow-2xl p-4 flex items-start gap-3">
        <div className="w-10 h-10 rounded-sm bg-gradient-to-br from-accent to-success flex items-center justify-center shrink-0">
          <Smartphone className="w-5 h-5 text-bg-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-sm text-text-primary">Install Turbo</p>
          <p className="text-xs text-text-secondary mt-0.5">
            Add it to your home screen for full-screen, app-like access.
          </p>
          {pwa.canPrompt ? (
            <button
              onClick={pwa.promptInstall}
              className="mt-3 inline-flex items-center gap-2 px-3.5 py-2 rounded-sm bg-accent text-bg-primary font-semibold text-xs hover:bg-accent/90 transition-colors focus-ring"
            >
              <Download className="w-3.5 h-3.5" />
              Install
            </button>
          ) : (
            <p className="mt-2 text-xs text-text-secondary">
              Tap <span className="text-accent font-medium">Share</span> then{' '}
              <span className="text-accent font-medium">Add to Home Screen</span>.
            </p>
          )}
        </div>
        <button
          onClick={pwa.dismiss}
          className="p-1.5 rounded-sm hover:bg-white/10 transition-colors shrink-0"
          aria-label="Dismiss install prompt"
        >
          <X className="w-4 h-4 text-text-muted" />
        </button>
      </div>
    </div>
  );
}
