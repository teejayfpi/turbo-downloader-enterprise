import { Download, Smartphone, Check, Share, MoreVertical, Plus } from 'lucide-react';
import { isIOS, isStandalone } from '../hooks/usePWA';

/** Reusable install action — used by the About panel and the first-run banner. */
export function InstallCard({ pwa, compact = false }) {
  const installed = pwa.installed || isStandalone();

  if (installed) {
    return (
      <div className={`rounded-sm border border-success/30 bg-success/10 ${compact ? 'p-3' : 'p-4'} flex items-center gap-3`}>
        <Check className="w-5 h-5 text-success shrink-0" />
        <div className="min-w-0">
          <p className="text-sm font-semibold text-success">Installed on this device</p>
          <p className="text-xs text-text-secondary">Turbo is running as a standalone app.</p>
        </div>
      </div>
    );
  }

  return (
    <div className={`rounded-sm border border-border-subtle bg-bg-primary ${compact ? 'p-3' : 'p-4'}`}>
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-sm bg-accent/10 flex items-center justify-center shrink-0">
          <Smartphone className="w-5 h-5 text-accent" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-text-primary">Install on your phone</p>
          <p className="text-xs text-text-secondary mt-0.5">
            Add Turbo to your home screen and launch it full-screen, like a native app.
          </p>

          {pwa.canPrompt ? (
            <button
              onClick={pwa.promptInstall}
              className="mt-3 inline-flex items-center gap-2 px-4 py-2 rounded-sm bg-accent text-bg-primary font-semibold text-sm hover:bg-accent/90 transition-colors focus-ring"
            >
              <Download className="w-4 h-4" />
              Install app
            </button>
          ) : (
            <InstallInstructions ios={pwa.isIOS || isIOS()} />
          )}
        </div>
      </div>
    </div>
  );
}

function Step({ icon: Icon, children }) {
  return (
    <li className="flex items-center gap-2">
      <Icon className="w-3.5 h-3.5 text-accent shrink-0" />
      <span>{children}</span>
    </li>
  );
}

function InstallInstructions({ ios }) {
  return (
    <ol className="mt-3 space-y-1.5 text-xs text-text-secondary">
      {ios ? (
        <>
          <Step icon={Share}>Tap the Share button in Safari</Step>
          <Step icon={Plus}>Choose “Add to Home Screen”</Step>
          <Step icon={Check}>Tap Add to install Turbo</Step>
        </>
      ) : (
        <>
          <Step icon={MoreVertical}>Open the browser menu (⋮)</Step>
          <Step icon={Download}>Tap “Install app” or “Add to Home screen”</Step>
          <Step icon={Check}>Confirm to install Turbo</Step>
        </>
      )}
    </ol>
  );
}
