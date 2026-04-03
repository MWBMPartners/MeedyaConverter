# 📡 Adaptive Streaming Guide

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter can prepare your media files for **HTTP Live Streaming (HLS)** and **MPEG-DASH** — the two dominant adaptive streaming protocols used by web and mobile video players.

Adaptive Bitrate (ABR) streaming encodes your content at multiple quality levels. Players automatically switch between qualities based on the viewer's available bandwidth, providing the best experience without buffering.

---

## How It Works

1. **Source Analysis** — MeedyaConverter probes your source file to determine resolution, codec, and stream information
2. **Bitrate Ladder** — Multiple quality variants are encoded (e.g., 1080p, 720p, 480p, 360p)
3. **Segmenting** — Each variant is split into small segments (typically 6-10 seconds)
4. **Audio Separation** — Audio tracks are encoded separately for bandwidth-efficient switching
5. **Manifest Generation** — HLS (.m3u8) and/or DASH (.mpd) manifest files are created
6. **Validation** — Manifests are validated for spec compliance

---

## Output Structure

```text
output/
├── video/
│   ├── 1080p/
│   │   ├── segment_000.m4s
│   │   ├── segment_001.m4s
│   │   └── ...
│   ├── 720p/
│   ├── 480p/
│   └── 360p/
├── audio/
│   ├── en-GB/
│   │   ├── segment_000.m4s
│   │   └── ...
│   ├── fr-FR/
│   └── es-ES/
├── subtitles/
│   ├── en-GB.vtt
│   └── fr-FR.vtt
├── master.m3u8          # HLS master playlist
├── stream.mpd           # DASH manifest
└── thumbnails/
    └── sprite.jpg       # Preview scrubbing sprites
```

---

## Streaming Presets

| Preset | Variants | Audio | Use Case |
| ------ | -------- | ----- | -------- |
| **Apple HLS** | 1080p, 720p, 480p, 360p | AAC 128k, 64k | Apple devices, Safari |
| **MPEG-DASH Standard** | 1080p, 720p, 480p | AAC 128k | Cross-platform |
| **YouTube-like ABR** | 2160p, 1440p, 1080p, 720p, 480p, 360p, 240p | AAC 128k | Full range |

---

## Encryption

MeedyaConverter supports **AES-128 encryption** for HLS content:

- Automatic key generation
- Key URL configuration for your key server
- IV (Initialization Vector) management
- Key rotation support

---

*This guide will be expanded with detailed configuration options as adaptive streaming features are implemented.*
