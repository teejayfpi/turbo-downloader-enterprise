# 🚀 Turbo Downloader

Enterprise-grade download manager with blazing-fast multi-threaded downloads.

![Turbo Downloader](https://img.shields.io/badge/Version-1.0.0-00d4ff?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-00ff88?style=for-the-badge)

## Features

### ⚡ Speed Optimization
- **Multi-threaded downloading** - Up to 32 connections per file
- **Segmented downloading** - Split files into multiple chunks
- **Parallel downloads** - Download multiple files simultaneously
- **Resume support** - Continue interrupted downloads

### 🎛️ Enterprise Features
- **Download queue management** - Priority ordering, drag to reorder
- **Bandwidth throttling** - Control download speeds
- **Download scheduling** - Schedule downloads for later
- **Real-time monitoring** - Live speed graphs and statistics

### 🎨 Beautiful UI
- **Dark theme** - Easy on the eyes
- **Responsive design** - Works on all devices
- **Smooth animations** - 60fps transitions
- **Progress tracking** - Per-file and overall progress

### 🛠️ Advanced
- **URL validation** - Automatic file type detection
- **Duplicate handling** - Skip, rename, or overwrite
- **System notifications** - Get notified when downloads complete
- **Export/Import** - Save and load download lists

## Quick Start

### Prerequisites
- Node.js 18+
- npm or yarn
- aria2 (optional, for production use)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/turbo-downloader.git
cd turbo-downloader

# Install all dependencies
npm run install:all

# Start the application
npm run dev
```

### Manual Installation

```bash
# Install root dependencies
npm install

# Install server dependencies
cd server
npm install

# Install client dependencies
cd ../client
npm install
```

### Running

```bash
# Development mode (runs both server and client)
npm run dev

# Or run separately:
# Terminal 1 - Server
cd server && npm start

# Terminal 2 - Client
cd client && npm run dev
```

### Optional: Install aria2

For production use, install aria2 for maximum speed:

```bash
# macOS
brew install aria2

# Ubuntu/Debian
sudo apt-get install aria2

# Windows
# Download from https://github.com/aria2/aria2/releases
```

Start aria2 daemon:
```bash
aria2c --enable-rpc --rpc-listen-all=true --rpc-allow-origin-all
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                              │
│  React + Vite + TailwindCSS + Zustand + Socket.IO Client    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP + WebSocket
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Backend                              │
│  Node.js + Express + Socket.IO + aria2                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Download Engine                           │
│  aria2 (multi-threaded, resumable downloads)                  │
└─────────────────────────────────────────────────────────────┘
```

## API Reference

### Downloads

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/downloads` | List all downloads |
| POST | `/api/downloads` | Add new downloads |
| POST | `/api/downloads/:id/pause` | Pause a download |
| POST | `/api/downloads/:id/resume` | Resume a download |
| POST | `/api/downloads/:id/retry` | Retry failed download |
| DELETE | `/api/downloads/:id` | Remove download |

### Settings

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/settings` | Get current settings |
| PUT | `/api/settings` | Update settings |

## Configuration

Settings are stored in `~/.turbo-downloader-settings.json`:

```json
{
  "connections": 16,
  "concurrentDownloads": 3,
  "split": 16,
  "defaultDir": "~/TurboDownloads",
  "duplicateHandling": "rename",
  "notifications": true,
  "bandwidthLimit": 0,
  "autoStart": true,
  "maxRetries": 5,
  "retryWait": 30,
  "theme": "dark"
}
```

## Tech Stack

- **Frontend**: React 18, Vite, TailwindCSS, Zustand, Socket.IO Client
- **Backend**: Node.js, Express, Socket.IO
- **Download Engine**: aria2 (optional, falls back to simulation mode)
- **Icons**: Lucide React

## Screenshots

*Coming soon*

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [aria2](https://aria2.github.io/) - Lightweight multi-protocol download utility
- [TailwindCSS](https://tailwindcss.com/) - Utility-first CSS framework
- [Lucide](https://lucide.dev/) - Beautiful open source icons

---

<div align="center">
  <p>Made with ❤️ by Turbo</p>
</div>
