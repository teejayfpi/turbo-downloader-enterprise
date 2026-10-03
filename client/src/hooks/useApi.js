import { authHeaders, withToken } from '../lib/auth';

const API_BASE = '/api';

async function handleResponse(response) {
  const contentType = response.headers.get('content-type') || '';
  const data = contentType.includes('application/json')
    ? await response.json()
    : await response.text();
  if (!response.ok) {
    const error = new Error((data && data.error) || `Request failed (${response.status})`);
    error.status = response.status;
    throw error;
  }
  return data;
}

function jsonRequest(url, method, body) {
  return fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(handleResponse);
}

export const api = {
  getDownloads: () => fetch(`${API_BASE}/downloads`, { headers: authHeaders() }).then(handleResponse),
  getDownload: (id) => fetch(`${API_BASE}/downloads/${id}`, { headers: authHeaders() }).then(handleResponse),

  addDownload: (url, options = {}) =>
    jsonRequest(`${API_BASE}/downloads`, 'POST', { url, ...options }),
  addDownloads: (urls, options = {}) =>
    jsonRequest(`${API_BASE}/downloads`, 'POST', { urls, ...options }),

  pauseDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/pause`, 'POST'),
  resumeDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/resume`, 'POST'),
  retryDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/retry`, 'POST'),
  startDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/start`, 'POST'),
  removeDownload: (id, deleteFile = false) =>
    fetch(`${API_BASE}/downloads/${id}?deleteFile=${deleteFile}`, {
      method: 'DELETE',
      headers: authHeaders(),
    }).then(handleResponse),
  updateDownload: (id, patch) => jsonRequest(`${API_BASE}/downloads/${id}`, 'PUT', patch),
  fileUrl: (id) => withToken(`${API_BASE}/downloads/${id}/file`),

  pauseAll: () => jsonRequest(`${API_BASE}/downloads/pause-all`, 'POST'),
  resumeAll: () => jsonRequest(`${API_BASE}/downloads/resume-all`, 'POST'),
  clearCompleted: () => jsonRequest(`${API_BASE}/downloads/clear-completed`, 'POST'),
  reorder: (ids) => jsonRequest(`${API_BASE}/downloads/reorder`, 'POST', { ids }),

  getSettings: () => fetch(`${API_BASE}/settings`, { headers: authHeaders() }).then(handleResponse),
  updateSettings: (settings) => jsonRequest(`${API_BASE}/settings`, 'PUT', settings),
  resetSettings: () => jsonRequest(`${API_BASE}/settings/reset`, 'POST'),

  getStats: () => fetch(`${API_BASE}/stats`, { headers: authHeaders() }).then(handleResponse),
  getSystem: () => fetch(`${API_BASE}/system`, { headers: authHeaders() }).then(handleResponse),

  getMediaInfo: (url) =>
    fetch(`${API_BASE}/media/info?url=${encodeURIComponent(url)}`, {
      headers: authHeaders(),
    }).then(handleResponse),
  getSupportedPlatforms: () =>
    fetch(`${API_BASE}/media/supported`, { headers: authHeaders() }).then(handleResponse),

  importDownloads: (payload) => jsonRequest(`${API_BASE}/import`, 'POST', payload),
  // Computed per access so a token added after login is picked up.
  get exportUrl() {
    return withToken(`${API_BASE}/export`);
  },
};
