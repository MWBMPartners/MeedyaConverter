<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter Wiki

**MeedyaConverter** is a professional-grade media transcoding application for macOS, built with Swift 6 and SwiftUI. It provides a full-featured GUI, a headless CLI (`meedya-convert`), and a shared core library (`ConverterEngine`) that powers both interfaces.

MeedyaConverter supports 16+ video codecs, 30+ audio codecs, 25+ container formats, HDR workflows (HDR10, HDR10+, HLG, Dolby Vision), adaptive streaming (HLS/DASH/CMAF), optical disc ripping, cloud delivery, licensing and monetisation, analytics, encoding pipelines, scheduled encoding, and more — all wrapped in a modern, native macOS experience.

---

## Quick Links

| Section | Description |
| ------- | ----------- |
| [Getting Started](Getting-Started) | Installation, first encode, basic workflow |
| [User Guide](User-Guide) | Profiles, HDR, containers, streaming, pipelines, scheduling, and all features |
| [CLI Reference](CLI-Reference) | `meedya-convert` commands, options, batch scripting |
| [Architecture](Architecture) | System design, modules, data flow |
| [Building from Source](Building-from-Source) | Prerequisites, clone, build, test, conditional builds |
| [Contributing](../CONTRIBUTING.md) | Code style, PR process, branch strategy, linting |
| [Code of Conduct](../CODE_OF_CONDUCT.md) | Contributor Covenant v2.1, community standards, enforcement |
| [Codec Reference](Codec-Reference) | Supported video and audio codecs with settings |
| [Troubleshooting](Troubleshooting) | Common issues and solutions |
| [FAQ](FAQ) | Frequently asked questions |

---

## Feature Highlights

### Core Encoding

- 16+ video codecs, 30+ audio codecs, 25+ container formats
- Per-stream encoding with independent codec/quality settings per track
- Hardware encoding (VideoToolbox, NVENC, QSV, AMF, VA-API)
- Encoding profiles with JSON import/export and profile sharing

### HDR Workflows

- HDR10, HDR10+, HLG, and Dolby Vision preservation
- HDR-to-SDR tone mapping (Hable, Reinhard, Mobius, BT.2390)
- PQ-to-HLG and PQ-to-DV Profile 8.4 conversion

### Adaptive Streaming

- HLS, MPEG-DASH, and CMAF manifest generation
- Multi-bitrate variant ladders with custom ladder files
- Dry-run mode for previewing FFmpeg commands

### Advanced Features

- Encoding pipelines — build multi-step chains in the Pipeline Editor (see note below)
- Scheduled encoding (one-time, or recurring at a fixed daily/weekly interval)
- Conditional encoding rules (if source matches criteria, apply settings)
- Post-encode actions (move, rename, upload, notify)
- Watch folder monitoring for automatic encoding
- Scene detection and chapter generation (chapters export; not yet attachable to a job — see note below)
- Audio normalization presets (EBU R128, ReplayGain)
- Smart profile suggestions based on source analysis
- FFmpeg command preview before encoding
- A/B quality comparison with frame extraction
- Bitrate heatmap and audio waveform visualisation
- File size estimation before encoding
- Filename templates for GUI encode output naming

> **Not yet reachable from the app.** Three more capabilities exist as
> backend code with no UI or CLI entry point: `ContentAnalyzer`
> (complexity/grain analysis), `AIUpscaler` (three Real-ESRGAN-based
> models), and `DCPGenerator` (Digital Cinema Package creation). None has
> a caller anywhere in `Sources/MeedyaConverter/`. VMAF/SSIM/PSNR quality
> metrics, by contrast, **are** reachable, via the Quality Metrics view.
>
> **Pipelines are a builder, not yet an automated workflow.** The
> Pipeline Editor lets you assemble and reorder steps, but nothing in the
> app executes a saved pipeline, and its own Save action has no handler
> wired up — a pipeline is discarded when you close the editor.
>
> **Scene detection's "Apply to Job" is permanently disabled** —
> `EncodingJobConfig` has no field for attaching external chapter
> metadata. Export the chapters file and inject it manually instead.

### Monetisation and Licensing

- Three-tier feature gating (Free, Pro, Studio)
- StoreKit / RevenueCat integration
- License key validation
- Entitlement-based gating with product catalogue

### Cloud and Delivery

- 12+ cloud upload providers (S3, GCS, Azure, Backblaze, etc.)
- Media server notifications (Plex, Jellyfin, Emby)
- Webhook support for CI/CD integration
- API key management

### Disc Support

- 22 optical disc types (Audio CD, DVD, Blu-ray, UHD, SACD, etc.)
- AccurateRip verification for audio disc ripping
- Disc image creation and burning
- Disc authoring

### Metadata

- Manual metadata tag editing, written through ffmpeg
- Per-stream metadata overrides (title, language, disposition)
- Kodi/Plex/Jellyfin naming templates and NFO sidecar path generation

> **Not yet available.** Online metadata *lookup* — MusicBrainz, TMDB, TVDB,
> Discogs, FanArt.tv — is **not** implemented. `MetadataLookup` and
> `MetadataProviders` build request URLs, but nothing in the app issues those
> requests or parses a response, and there is no lookup control in the UI.
> Auto-tagging (`AutoTagger`) and audio fingerprinting are likewise present as
> code but have no call site. Tracked in #205 / #467.

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

```text
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
