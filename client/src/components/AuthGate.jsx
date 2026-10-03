import { useState } from 'react';
import { setToken } from '../lib/auth';

/**
 * Shown when the server answered 401 because it is configured with
 * TURBO_API_TOKEN. The token is stored locally and attached to every later
 * request; a reload restarts the socket with the new credential.
 */
export default function AuthGate({ onUnlock }) {
  const [value, setValue] = useState('');

  const submit = (event) => {
    event.preventDefault();
    if (!value.trim()) return;
    setToken(value);
    onUnlock?.();
  };

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <form
        onSubmit={submit}
        className="w-full max-w-sm rounded-2xl border border-border-subtle bg-bg-secondary/80 backdrop-blur p-6 shadow-xl"
      >
        <h1 className="text-lg font-semibold text-text-primary mb-1">Server locked</h1>
        <p className="text-sm text-text-secondary mb-5">
          This Turbo server requires an access token. Enter it to continue.
        </p>
        <input
          type="password"
          autoFocus
          value={value}
          onChange={(event) => setValue(event.target.value)}
          placeholder="Access token"
          className="w-full rounded-lg border border-border-subtle bg-bg-tertiary px-3 py-2.5 text-sm text-text-primary outline-none focus:border-accent mb-4"
        />
        <button
          type="submit"
          className="w-full rounded-lg bg-accent/90 hover:bg-accent text-bg-primary font-medium py-2.5 transition-colors"
        >
          Unlock
        </button>
      </form>
    </div>
  );
}
