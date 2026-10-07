import { useEffect, useState } from 'react';
import { DESIGNER, APP_VERSION } from '../credits';

const SPLASH_KEY = 'turbo-splash-shown';

/**
 * Animated launch splash. Shown once per session on top of the app while the
 * initial data loads, then fades away. Respects prefers-reduced-motion and
 * honours a `?splash=1` / `?splash=0` override for previewing or skipping.
 */
export default function SplashScreen({ ready, onMounted }) {
  const forced = new URLSearchParams(window.location.search).get('splash');
  const [visible, setVisible] = useState(() => {
    if (forced === '1') return true;
    if (forced === '0') return false;
    return sessionStorage.getItem(SPLASH_KEY) !== '1';
  });
  const [leaving, setLeaving] = useState(false);

  // React's splash has taken over — drop the pre-React boot splash.
  useEffect(() => {
    onMounted?.();
  }, [onMounted]);

  // Minimum display time so the animation reads even if data loads instantly.
  useEffect(() => {
    if (!visible) return undefined;
    if (forced === 'hold') return undefined; // preview / screenshot mode
    const MIN_MS = 30000;
    const start = performance.now();
    let leaveTimer;
    let removeTimer;

    const schedule = () => {
      const wait = Math.max(0, MIN_MS - (performance.now() - start));
      leaveTimer = setTimeout(() => {
        setLeaving(true);
        removeTimer = setTimeout(() => {
          setVisible(false);
          sessionStorage.setItem(SPLASH_KEY, '1');
        }, 620);
      }, wait);
    };

    if (ready) schedule();

    return () => {
      clearTimeout(leaveTimer);
      clearTimeout(removeTimer);
    };
  }, [visible, ready]);

  if (!visible) return null;

  return (
    <div
      className={`splash-overlay${leaving ? ' splash-leave' : ''}`}
      role="status"
      aria-live="polite"
      aria-label="Turbo Downloader is starting"
    >
      <div className="splash-grid" aria-hidden="true" />
      <div className="splash-glow" aria-hidden="true" />

      <div className="splash-content">
        <div className="splash-mark">
          <svg viewBox="0 0 1024 1024" className="splash-svg" aria-hidden="true">
            <defs>
              <linearGradient id="smark" x1="0.1" y1="0.05" x2="0.9" y2="1">
                <stop offset="0" stopColor="#8af8ff" />
                <stop offset="0.42" stopColor="#22e0ff" />
                <stop offset="1" stopColor="#2fffc8" />
              </linearGradient>
            </defs>
            <path d="M566 176 L334 548 H484 L430 848 L690 466 H536 Z" fill="url(#smark)" />
          </svg>
        </div>

        <h1 className="splash-wordmark">TURBO</h1>
        <p className="splash-tagline">ENTERPRISE DOWNLOAD OPERATIONS</p>
        <p className="splash-sub">Local-first · Secure · Resumable</p>

        <div className="splash-rail" aria-hidden="true">
          <span className="splash-rail-fill" />
        </div>
        <p className="splash-version">v{APP_VERSION}</p>

        <div className="splash-credit">
          <span className="splash-credit-label">designed by:</span>
          <span className="splash-credit-name">{DESIGNER.name}</span>
          <span className="splash-credit-links">
            <a href={`mailto:${DESIGNER.email}`}>{DESIGNER.email}</a>
            <span className="splash-credit-dot" aria-hidden="true">·</span>
            <a href={`tel:${DESIGNER.phoneHref}`}>{DESIGNER.phone}</a>
          </span>
        </div>
      </div>
    </div>
  );
}
