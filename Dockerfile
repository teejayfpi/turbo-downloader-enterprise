# Turbo Downloader — production image.
# Includes yt-dlp + ffmpeg so media downloads work out of the box.
FROM node:22-slim

ENV NODE_ENV=production \
    TURBO_DATA_DIR=/data \
    DOWNLOAD_DIR=/downloads \
    YT_DLP_PATH=/usr/local/bin/yt-dlp

# System deps: python3/pip for yt-dlp, ffmpeg for stream merging, curl for healthchecks.
# yt-dlp is installed with its "default" extras so the yt-dlp-ejs challenge
# scripts ship with it; Node (already present in this base image) is used as
# the JS runtime to solve YouTube's signature challenges.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-pip ffmpeg curl ca-certificates \
    && pip3 install --no-cache-dir --break-system-packages -U "yt-dlp[default]" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies first for better layer caching.
COPY package.json package-lock.json ./
COPY server/package.json server/package-lock.json ./server/
COPY client/package.json client/package-lock.json ./client/
RUN npm ci --omit=dev \
    && cd server && npm ci --omit=dev \
    && cd ../client && npm ci --include=dev

# Copy source and build the client.
COPY . .
RUN npm run build

# Persistent state lives on volumes, not in the image.
RUN mkdir -p /data /downloads

EXPOSE 3001
VOLUME ["/data", "/downloads"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:${PORT:-3001}/health || exit 1

CMD ["node", "server/index.js"]
