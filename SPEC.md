# Turbo Downloader - Enterprise Grade Download Manager

## Concept & Vision

Turbo is a blazing-fast, enterprise-grade download manager designed for power users who demand speed and reliability. It combines the raw speed of aria2's multi-connection downloading with a sleek, modern interface that feels like a premium control center. The experience should feel like piloting a high-performance vehicle — precise, responsive, and exhilarating.

**Core Philosophy:** Speed isn't just about raw download rates — it's about intelligent bandwidth utilization, zero wasted time, and complete control over every aspect of the download process.

## Design Language

### Aesthetic Direction
**Reference:** Tesla's dashboard meets F1 telemetry — dark, focused, with electric accent colors that pulse with activity. Information-dense but never cluttered.

### Color Palette
```
--bg-primary: #0a0a0f        /* Deep space black */
--bg-secondary: #12121a      /* Card backgrounds */
--bg-tertiary: #1a1a24       /* Hover states */
--border: #2a2a3a            /* Subtle borders */
--text-primary: #ffffff      /* Primary text */
--text-secondary: #8b8b9e    /* Secondary text */
--text-muted: #5a5a6e       /* Muted text */
--accent: #00d4ff           /* Cyan - primary accent */
--accent-glow: #00d4ff33    /* Glow effect */
--success: #00ff88          /* Green - complete */
--warning: #ffaa00          /* Orange - paused/warning */
--error: #ff4466            /* Red - errors */
--speed-ultra: #00ffcc      /* Ultra fast indicator */
```

### Typography
- **Primary:** Inter (headings, UI elements) - clean, modern, highly legible
- **Monospace:** JetBrains Mono (speeds, sizes, technical data) - developer-friendly
- **Scale:** 12px base, 14px body, 18px subheadings, 24px headings, 48px hero

### Spatial System
- Base unit: 4px
- Component padding: 12px / 16px / 24px
- Section gaps: 24px / 32px
- Card border-radius: 12px
- Button border-radius: 8px

### Motion Philosophy
- **Micro-interactions:** 150ms ease-out for hovers, 200ms for state changes
- **Progress animations:** Smooth 60fps updates, pulse effects on completion
- **Speed counter:** Animated counting effect, smooth transitions
- **Card reveals:** Subtle scale (0.98 → 1) with fade, 300ms stagger

### Visual Assets
- **Icons:** Lucide React (consistent, clean line icons)
- **Progress rings:** SVG with gradient strokes
- **Speed visualization:** Real-time bandwidth graph
- **Status indicators:** Glowing dots with pulse animations

## Layout & Structure

### Overall Architecture
```
┌─────────────────────────────────────────────────────────────┐
│  Header: Logo + Stats Bar + Theme Toggle                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Drop Zone / URL Input (Hero Section)               │    │
│  │  [Paste URLs here or drag files...]                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────────────────┐     │
│  │  Speed Monitor   │  │  Download Queue              │     │
│  │  [Real-time      │  │  [Active downloads list]     │     │
│  │   bandwidth      │  │                              │     │
│  │   graph]         │  │                              │     │
│  └──────────────────┘  └──────────────────────────────┘     │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Completed Downloads / History                        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Responsive Strategy
- **Desktop (1200px+):** Full dashboard, side-by-side panels
- **Tablet (768px-1199px):** Stacked panels, full-width cards
- **Mobile (< 768px):** Simplified view, essential controls only

## Features & Interactions

### 1. Multi-URL Input
- **Paste detection:** Auto-detect URLs on paste, show toast notification
- **Bulk paste:** Support multiple URLs (newline separated)
- **URL validation:** Real-time validation with file type detection
- **Drag & drop:** Drop .txt files with URLs, multiple URLs

### 2. Speed Optimization
- **Multi-connection downloads:** 8-16 connections per file (configurable)
- **Segmented downloading:** Intelligent chunk sizing
- **Resume support:** Download from where it left off
- **Parallel downloads:** Up to 5 concurrent downloads (configurable)
- **Server connection reuse:** Keep connections warm

### 3. Download Queue Management
- **Add to queue:** New downloads go to queue with priority
- **Drag to reorder:** Change download priority
- **Pause/Resume:** Individual or batch control
- **Cancel with cleanup:** Remove file + metadata
- **Retry failed:** One-click retry with exponential backoff

### 4. Progress Tracking
- **Per-file progress:** Percentage, downloaded/total size, speed, ETA
- **Overall progress:** Total downloads, combined speed
- **Real-time graph:** Live bandwidth visualization (last 60 seconds)
- **Completion notification:** System notification when done

### 5. File Management
- **Custom save location:** Choose download directory
- **Auto filename detection:** Parse from URL headers
- **Duplicate handling:** Skip, rename, or overwrite
- **File type icons:** Visual identification by extension

### 6. Enterprise Features
- **Download scheduling:** Schedule downloads for later
- **Bandwidth throttling:** Set speed limits (global or per-download)
- **Download history:** Persistent log of all downloads
- **Export/Import:** Save and load download lists
- **Checksum verification:** MD5/SHA256 validation (optional)

### 7. Settings Panel
- **Connection settings:** Threads, concurrent downloads, timeout
- **Storage settings:** Default directory, duplicate handling
- **Notification settings:** Enable/disable system notifications
- **Theme settings:** Dark mode (default), light mode option

## Component Inventory

### Header Bar
- **Logo:** "TURBO" with lightning bolt icon, gradient text
- **Quick stats:** Active downloads, total speed, queued count
- **Settings gear:** Opens settings modal
- **States:** Default, settings-open

### Drop Zone
- **Default:** Dashed border, icon, instructional text
- **Drag hover:** Solid border, glow effect, scale up slightly
- **Processing:** Spinner, "Processing URLs..." text
- **Error:** Red border, error message

### URL Input Bar
- **Default:** Placeholder text, paste icon
- **Focused:** Accent border glow
- **With content:** Clear button appears
- **Validating:** Loading spinner in input

### Download Card
- **Downloading:** Progress bar, animated stripes, live stats
- **Paused:** Yellow accent, paused icon, "Resume" button prominent
- **Completed:** Green checkmark, success animation, "Open" and "Remove" buttons
- **Failed:** Red accent, error message, "Retry" button
- **Queued:** Muted appearance, waiting indicator

### Speed Monitor
- **Live graph:** Area chart, gradient fill, real-time updates
- **Current speed:** Large number display with unit (MB/s)
- **Peak speed:** Smaller, shows session peak
- **Empty state:** "No active downloads" message

### Settings Modal
- **Overlay:** Dark semi-transparent backdrop with blur
- **Card:** Slide-up animation, tabs for categories
- **Inputs:** Custom styled toggles, sliders, number inputs
- **Save/Cancel:** Bottom action buttons

### Toast Notifications
- **Success:** Green accent, checkmark icon
- **Error:** Red accent, X icon
- **Info:** Cyan accent, info icon
- **Animation:** Slide in from top-right, auto-dismiss

## Technical Approach

### Stack
- **Frontend:** React 18 + Vite + TailwindCSS
- **Backend:** Node.js + Express + aria2 (fast download engine)
- **Real-time:** Socket.IO for live progress updates
- **State:** Zustand for frontend state management

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│   Express   │────▶│   aria2c    │
│   (React)   │◀────│   Server    │◀────│   Daemon    │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                    │
      │              ┌─────┴─────┐              │
      │              │   Socket  │              │
      │              │   Server  │              │
      │              └───────────┘              │
      │                                         │
      └────────────── WebSocket ───────────────┘
                     (Real-time Updates)
```

### API Design

**POST /api/downloads**
```json
{
  "urls": ["https://example.com/file.zip", "https://example.com/file2.zip"],
  "options": {
    "connections": 16,
    "dir": "/downloads",
    "split": 16
  }
}
```

**GET /api/downloads**
```json
{
  "downloads": [
    {
      "id": "abc123",
      "url": "https://...",
      "filename": "file.zip",
      "total": 104857600,
      "downloaded": 52428800,
      "speed": 5242880,
      "status": "active",
      "progress": 50
    }
  ]
}
```

**POST /api/downloads/:id/pause**
**POST /api/downloads/:id/resume**
**DELETE /api/downloads/:id**
**GET /api/settings**
**PUT /api/settings**

### Data Model
```javascript
Download {
  id: string,
  url: string,
  filename: string,
  total: number,
  downloaded: number,
  speed: number,
  status: 'active' | 'paused' | 'completed' | 'failed' | 'queued',
  error?: string,
  createdAt: Date,
  completedAt?: Date,
  aria2Gid?: string
}

Settings {
  connections: number,        // 1-32
  concurrentDownloads: number, // 1-10
  defaultDir: string,
  duplicateHandling: 'skip' | 'rename' | 'overwrite',
  notifications: boolean,
  bandwidthLimit: number       // 0 = unlimited
}
```

### Key Implementation Details
1. **aria2 RPC:** Connect to aria2c via WebSocket RPC for efficient communication
2. **Chunked responses:** Stream progress updates, not polling
3. **File handling:** Use Node.js streams for file operations
4. **Error recovery:** Auto-retry with exponential backoff for failed downloads
5. **Cleanup:** Remove completed downloads after configurable period
