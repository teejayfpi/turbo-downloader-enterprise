// Shared-secret handling for servers configured with TURBO_API_TOKEN. The token
// is kept in localStorage and attached to every API call and Socket.IO
// handshake. Direct file/export links cannot carry headers, so they append it
// as a query parameter instead.
const STORAGE_KEY = 'turbo.apiToken';

export function getToken() {
  try {
    return localStorage.getItem(STORAGE_KEY) || '';
  } catch {
    return '';
  }
}

export function setToken(value) {
  try {
    const token = (value || '').trim();
    if (token) localStorage.setItem(STORAGE_KEY, token);
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* storage unavailable */
  }
}

export function authHeaders() {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export function withToken(url) {
  const token = getToken();
  if (!token) return url;
  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}token=${encodeURIComponent(token)}`;
}
