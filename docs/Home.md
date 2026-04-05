<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter Wiki

**MeedyaConverter** is a professional-grade media transcoding application for macOS, built with Swift 6 and SwiftUI. It provides a full-featured GUI, a headless CLI (`meedya-convert`), and a shared core library (`ConverterEngine`) that powers both interfaces.

MeedyaConverter supports 16+ video codecs, 30+ audio codecs, 25+ container formats, HDR workflows (HDR10, HDR10+, HLG, Dolby Vision), adaptive streaming (HLS/DASH), optical disc ripping, and cloud delivery — all wrapped in a modern, native macOS experience.

---

## Quick Links

| Section | Description |
|---------|-------------|
| [Getting Started](Getting-Started) | Installation, first encode, basic workflow |
| [User Guide](User-Guide) | Profiles, settings, HDR, containers, streaming |
| [CLI Reference](CLI-Reference) | `meedya-convert` commands, options, batch scripting |
| [Architecture](Architecture) | System design, modules, data flow |
| [Building from Source](Building-from-Source) | Prerequisites, clone, build, test |
| [Contributing](Contributing) | Code style, PR process, branch strategy |
| [Codec Reference](Codec-Reference) | Supported video and audio codecs with settings |
| [Troubleshooting](Troubleshooting) | Common issues and solutions |
| [FAQ](FAQ) | Frequently asked questions |

---

## Project Overview

- **Developer:** MWBM Partners Ltd
- **Language:** Swift 6 / SwiftUI
- **Build System:** Swift Package Manager
- **Platforms:** macOS 15+ (Windows and Linux planned)
- **Distribution:** Direct download (with Sparkle auto-updates) and Mac App Store
- **License:** Proprietary

---

## Architecture at a Glance

```
┌─────────────────────┐    ┌─────────────────────┐
│  MeedyaConverter    │    │  meedya-convert      │
│  (SwiftUI GUI)      │    │  (CLI Tool)          │
└────────┬────────────┘    └────────┬─────────────┘
         │                          │
         └──────────┬───────────────┘
                    │
         ┌──────────▼──────────┐
         │  ConverterEngine    │
         │  (Shared Library)   │
         └──────────┬──────────┘
                    │
         ┌──────────▼──────────┐
         │  FFmpeg / FFprobe   │
         │  (Subprocess)       │
         └─────────────────────┘
```

---

## Current Status

MeedyaConverter is in active development. See the [Project Status](../PROJECT_STATUS.md) for phase completion details and the [Changelog](../CHANGELOG.md) for version history.

**Current version:** 0.1.0-alpha
