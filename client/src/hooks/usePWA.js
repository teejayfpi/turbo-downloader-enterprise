import { useEffect } from 'react';
import { useDownloadStore } from '../stores/downloadStore';

const DISMISS_KEY = 'turbo.install.dismissedAt';
const DISMISS_COOLDOWN = 1000 * 60 * 60 * 24 * 14; // 14 days

/**
 * `beforeinstallprompt` can fire before React mounts and is consumed once used,
 * so capture it at module load instead of inside a component effect.
 */
let deferredPrompt = null;

if (typeof window !== 'undefined') {
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    useDownloadStore.getState().setInstall({ canInstall: true });
  });
  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    useDownloadStore.getState().setInstall({ canInstall: false, installedApp: true });
    useDownloadStore.getState().addNotification({
      type: 'success',
      title: 'Installed',
      message: 'Turbo is now on your home screen.',
    });
  });
}

export function isStandalone() {
  if (typeof window === 'undefined') return false;
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    window.matchMedia?.('(display-mode: minimal-ui)').matches ||
    window.navigator.standalone === true
  );
}

export function isIOS() {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  const iOSDevice = /iPad|iPhone|iPod/.test(ua) || (ua.includes('Macintosh') && 'ontouchend' in document);
  return iOSDevice && !/CriOS|FxiOS|EdgiOS/.test(ua);
}

function isDismissed() {
  if (typeof localStorage === 'undefined') return false;
  const at = Number(localStorage.getItem(DISMISS_KEY) || 0);
  return at > 0 && Date.now() - at < DISMISS_COOLDOWN;
}

/**
 * Registers the service worker and exposes install state from the store.
 * Safe to call from multiple components — registration happens once.
 */
export function usePWA() {
  const canPrompt = useDownloadStore((s) => s.canInstall);
  const installed = useDownloadStore((s) => s.installedApp);
  const dismissed = useDownloadStore((s) => s.installDismissed);

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch((error) => {
        console.warn('Service worker registration failed:', error);
      });
    }

    // Reconcile state that lives outside React (localStorage, display-mode).
    const patch = {
      installDismissed: isDismissed(),
      installedApp: isStandalone() || useDownloadStore.getState().installedApp,
    };
    if (deferredPrompt) patch.canInstall = true;
    useDownloadStore.getState().setInstall(patch);

    const media = window.matchMedia?.('(display-mode: standalone)');
    const onMode = () => useDownloadStore.getState().setInstall({ installedApp: isStandalone() });
    media?.addEventListener?.('change', onMode);
    return () => media?.removeEventListener?.('change', onMode);
  }, []);

  const promptInstall = async () => {
    if (!deferredPrompt) return { outcome: 'unavailable' };
    deferredPrompt.prompt();
    const choice = await deferredPrompt.userChoice;
    deferredPrompt = null;
    useDownloadStore.getState().setInstall({
      canInstall: false,
      installedApp: choice.outcome === 'accepted',
    });
    return choice;
  };

  const dismiss = () => {
    localStorage.setItem(DISMISS_KEY, String(Date.now()));
    useDownloadStore.getState().setInstall({ installDismissed: true });
  };

  return {
    canPrompt,
    installed,
    dismissed,
    dismiss,
    promptInstall,
    isIOS: isIOS(),
    isStandalone: isStandalone(),
  };
}
