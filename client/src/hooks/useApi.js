const API_BASE = '/api';

async function handleResponse(response) {
  const contentType = response.headers.get('content-type') || '';
  const data = contentType.includes('application/json')
    ? await response.json()
    : await response.text();
  if (!response.ok) {
    throw new Error((data && data.error) || `Request failed (${response.status})`);
  }
  return data;
}

function jsonRequest(url, method, body) {
  return fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(handleResponse);
}

export const api = {
  getDownloads: () => fetch(`${API_BASE}/downloads`).then(handleResponse),
  getDownload: (id) => fetch(`${API_BASE}/downloads/${id}`).then(handleResponse),

  addDownload: (url, options = {}) =>
    jsonRequest(`${API_BASE}/downloads`, 'POST', { url, ...options }),
  addDownloads: (urls, options = {}) =>
    jsonRequest(`${API_BASE}/downloads`, 'POST', { urls, ...options }),

  pauseDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/pause`, 'POST'),
  resumeDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/resume`, 'POST'),
  retryDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/retry`, 'POST'),
  startDownload: (id) => jsonRequest(`${API_BASE}/downloads/${id}/start`, 'POST'),
  removeDownload: (id, deleteFile = false) =>
    fetch(`${API_BASE}/downloads/${id}?deleteFile=${deleteFile}`, { method: 'DELETE' }).then(handleResponse),
  updateDownload: (id, patch) => jsonRequest(`${API_BASE}/downloads/${id}`, 'PUT', patch),
  fileUrl: (id) => `${API_BASE}/downloads/${id}/file`,

  pauseAll: () => jsonRequest(`${API_BASE}/downloads/pause-all`, 'POST'),
  resumeAll: () => jsonRequest(`${API_BASE}/downloads/resume-all`, 'POST'),
  clearCompleted: () => jsonRequest(`${API_BASE}/downloads/clear-completed`, 'POST'),
  reorder: (ids) => jsonRequest(`${API_BASE}/downloads/reorder`, 'POST', { ids }),

  getSettings: () => fetch(`${API_BASE}/settings`).then(handleResponse),
  updateSettings: (settings) => jsonRequest(`${API_BASE}/settings`, 'PUT', settings),
  resetSettings: () => jsonRequest(`${API_BASE}/settings/reset`, 'POST'),

  getStats: () => fetch(`${API_BASE}/stats`).then(handleResponse),
  getSystem: () => fetch(`${API_BASE}/system`).then(handleResponse),

  getMediaInfo: (url) =>
    fetch(`${API_BASE}/media/info?url=${encodeURIComponent(url)}`).then(handleResponse),
  getSupportedPlatforms: () => fetch(`${API_BASE}/media/supported`).then(handleResponse),

  importDownloads: (payload) => jsonRequest(`${API_BASE}/import`, 'POST', payload),
  exportUrl: `${API_BASE}/export`,
};
