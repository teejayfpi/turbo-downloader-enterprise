const API_BASE = '/api';

async function handleResponse(response) {
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || 'Request failed');
  }
  return data;
}

export const api = {
  async getDownloads() {
    const response = await fetch(`${API_BASE}/downloads`);
    return handleResponse(response);
  },

  async getDownload(id) {
    const response = await fetch(`${API_BASE}/downloads/${id}`);
    return handleResponse(response);
  },

  async addDownload(url) {
    const response = await fetch(`${API_BASE}/downloads`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
    });
    return handleResponse(response);
  },

  async addDownloads(urls) {
    // Add multiple downloads
    const results = [];
    for (const url of urls) {
      try {
        const result = await this.addDownload(url);
        results.push(result);
      } catch (e) {
        console.error('Failed to add download:', url, e);
      }
    }
    return { downloads: results.map(r => r.download) };
  },

  async pauseDownload(id) {
    const response = await fetch(`${API_BASE}/downloads/${id}/pause`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async resumeDownload(id) {
    const response = await fetch(`${API_BASE}/downloads/${id}/resume`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async retryDownload(id) {
    const response = await fetch(`${API_BASE}/downloads/${id}/retry`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async removeDownload(id) {
    const response = await fetch(`${API_BASE}/downloads/${id}`, {
      method: 'DELETE'
    });
    return handleResponse(response);
  },

  async pauseAll() {
    const response = await fetch(`${API_BASE}/downloads/pause-all`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async resumeAll() {
    const response = await fetch(`${API_BASE}/downloads/resume-all`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async clearCompleted() {
    const response = await fetch(`${API_BASE}/downloads/clear-completed`, {
      method: 'POST'
    });
    return handleResponse(response);
  },

  async getSettings() {
    const response = await fetch(`${API_BASE}/settings`);
    return handleResponse(response);
  },

  async updateSettings(settings) {
    const response = await fetch(`${API_BASE}/settings`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settings)
    });
    return handleResponse(response);
  },

  async getStats() {
    const response = await fetch(`${API_BASE}/stats`);
    return handleResponse(response);
  }
};
