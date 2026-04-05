<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Project Status

> **Last Updated:** 2026-04-05
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overall Progress

| Metric | Value |
|--------|-------|
| **Current Version** | 0.1.0-alpha |
| **Current Phase** | Phase 4 — CLI Tool (meedya-convert) |
| **Next Target** | Alpha 0.2 (Phase 4 remaining) |
| **Overall Completion** | 30% (3 of 19 phases complete) |
| **Active Work** | Phase 3 complete — ready for Phase 4 (CLI Tool) |

---

## Release Gates

| Release | Phases | Description | Status |
|---------|--------|-------------|--------|
| **Alpha 0.1** | 0, 1, 2 | Core engine + macOS app — first testable build | Complete |
| **Alpha 0.2** | 3, 4 | Essential codecs, passthrough, HDR + CLI tool | In Progress |
| **Beta 0.5** | 5, 6 | Subtitles, audio normalisation, HLS/DASH | Planned |
| **Beta 0.7** | 7, 8 | Extended formats, spatial audio, advanced audio | Planned |
| **RC 0.9** | 9 | Professional features (VMAF, watch folders, AI upscaling) | Planned |
| **Ongoing** | 16 | Polish and Distribution — runs throughout development | Ongoing |
| **v1.1+** | 10, 11 | Optical disc ripping and authoring | Planned |
| **v1.3+** | 12 | Cloud uploads | Planned |
| **v1.5+** | 15 | Media metadata lookup | Planned |
| **v2.0** | 13, 14 | Windows and Linux | Planned |
| **v3.0+** | 17 | Image conversion | Planned |

---

## Phase Status Overview

| Phase | Name | Status | Progress | Release |
|-------|------|--------|----------|---------|
| **0** | Project Setup and Architecture | Complete | 100% | -- |
| **1** | Core Engine Foundation | Complete | 100% | Alpha 0.1 |
| **2** | macOS SwiftUI Application (MVP) | Complete | 100% | Alpha 0.1 |
| **3** | Essential Encoding and Passthrough | Complete | 100% | Alpha 0.2 |
| **4** | CLI Tool (meedya-convert) | Planned | 0% | Alpha 0.2 |
| **5** | Subtitles and Core Audio Processing | Planned | 0% | Beta 0.5 |
| **6** | Adaptive Streaming (HLS/MPEG-DASH) | Planned | 0% | Beta 0.5 |
| **7** | Extended Formats and Spatial Audio | Planned | 0% | Beta 0.7 |
| **8** | Advanced Audio Processing | Planned | 0% | Beta 0.7 |
| **9** | Professional Features | Planned | 0% | RC 0.9 |
| **10** | Optical Disc Ripping (22 types) | Planned | 0% | v1.1+ |
| **11** | Disc Image Creation and Burning | Planned | 0% | v1.2+ |
| **12** | Cloud Integration and Uploads | Planned | 0% | v1.3+ |
| **13** | Platform Expansion — Windows | Planned | 0% | v2.0 |
| **14** | Platform Expansion — Linux | Planned | 0% | v2.0 |
| **15** | Media Metadata Lookup | Planned | 0% | v1.5+ |
| **16** | Polish and Distribution | Ongoing | 5% | Ongoing |
| **17** | Image Conversion (future) | Planned | 0% | v3.0+ |
| **18** | AI-Powered Features (wishlist) | Wishlist | 0% | TBD |

---

## Phase 0: Project Setup — Detail

| # | Task | Status | Notes |
|---|------|--------|-------|
| 0.1 | Project scaffolding (SPM, directories) | Complete | Package.swift, 3 targets, builds and tests pass |
| 0.2 | Documentation | Complete | README, Plan, Status, Changelog, help/, docs/ wiki |
| 0.3 | .gitignore | Complete | All platforms covered |
| 0.4 | GitHub Actions CI | Complete | build.yml, release.yml, beta-alpha.yml |
| 0.5 | GitHub Project Board | Complete | Project #13, 246 issues, 19 milestones |
| 0.6 | License file | Complete | Proprietary + third-party acknowledgments |
| 0.7 | Claude context | Complete | Project brief, standing tasks, prompt history |
| 0.8 | Clean up legacy code | Complete | All prior iteration files removed |
| 0.9 | Remote repo URL | Complete | Updated to MWBMPartners/MeedyaConverter |

---

## Phase 1: Core Engine Foundation — Detail

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | FFmpeg bundle manager | Complete | Binary discovery, version detection, validation, caching |
| 1.2 | FFmpeg process controller | Complete | Start, pause, resume, stop with progress monitoring |
| 1.3 | Media file probing (FFprobe) | Complete | Streams, HDR, chapters, metadata |
| 1.4 | Data models | Complete | MediaFile, MediaStream, VideoCodec, AudioCodec, ContainerFormat, SubtitleFormat |
| 1.5 | FFmpeg argument builder | Complete | Translates encoding settings to FFmpeg CLI arguments |
| 1.6 | Encoding profile system | Complete | Presets, CRUD, JSON persistence, 7 built-in profiles |
| 1.7 | Encoding job and queue | Complete | Job config, state tracking, priority queue management |
| 1.7a | Temp file management | Complete | Per-job directories, cleanup, disk space monitoring |
| 1.8/1.9 | Encoding engine | Complete | Video and audio encoding orchestration, multipass support |
| 1.10 | Unit tests | Complete | 30 tests covering all Phase 1 components |
| 1.11 | Feature gating system | Complete | ProductTier, Feature, FeatureGateProtocol |

---

## Phase 2: macOS SwiftUI Application — Detail

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2.1 | App shell and navigation | Complete | Sidebar, main content, inspector |
| 2.2 | Source file import | Complete | Drag-and-drop, file picker, recent files |
| 2.3 | Stream inspector | Complete | Video, audio, subtitle track details |
| 2.4 | Output settings | Complete | Codec, quality, container, per-stream config |
| 2.5 | Encoding queue | Complete | Queue management, progress, pause/resume/cancel |
| 2.6 | Log viewer | Complete | Real-time FFmpeg output |
| 2.7 | Settings/preferences | Complete | General, encoding, paths, updates |
| 2.8 | Help system | Complete | In-app help, help/ documentation |
| 2.9 | Profile management | Complete | Create, edit, delete, import, export profiles |

---

## Phase 3: Essential Encoding and Passthrough — Detail

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3.1 | Video passthrough | Complete | Copy video without re-encoding |
| 3.2 | Audio passthrough | Complete | Copy audio without re-encoding |
| 3.3 | Subtitle passthrough | Complete | Copy subtitles without conversion |
| 3.4 | HDR-to-SDR tone mapping | Complete | Hable, Reinhard, Mobius, BT.2390, Clip |
| 3.5 | PQ-to-HLG conversion | Complete | hlg-tools preferred, FFmpeg zscale fallback |
| 3.6 | PQ-to-DV conversion | Complete | Profile 8.4 + HLG combined, three-tier fallback |
| 3.7 | Dolby Vision preservation | Complete | RPU extract/encode/inject via dovi_tool |
| 3.8 | HLG-to-DV conversion | Complete | Auto-generate via dovi_tool |
| 3.9 | Container-codec validation | Complete | Compatibility matrix with UI warnings |
| 3.10 | Crop detection | Complete | FFmpeg cropdetect |
| 3.11 | Hardware encoder detection | Complete | VideoToolbox, NVENC, QSV, AMF, VA-API |
| 3.12 | Stream metadata editor | Complete | Edit title, language, disposition |

---

## What's Complete

- Project plan with 19 phases (0-18), release gates, feature gating, and 215+ tasks
- Full documentation suite: README, Project Plan, Project Status, Changelog, 8 help docs, 10 wiki pages
- Architecture: ConverterEngine (library) + meedya-convert (CLI) + MeedyaConverter (SwiftUI app)
- SPM package with 3 targets — builds and tests pass (30/30)
- Hybrid encoding engine (FFmpeg subprocess + AVFoundation/FFmpegKit)
- Dual update strategy (Sparkle 2 direct + Apple-managed App Store)
- Three-tier file access for App Store sandbox
- GitHub: 19 milestones, 26+ labels, 246 issues, project board
- CI/CD: 3 GitHub Actions workflows (build, release, beta/alpha)
- Issue templates, security policy, CODEOWNERS, PR template, LICENSE
- FFmpeg bundle manager, process controller, argument builder
- Media probing via FFprobe — streams, HDR detection, chapters, metadata
- Complete data models — 16 video codecs, 30+ audio codecs, 25+ containers, 14+ subtitle formats
- Encoding profile system with 7+ built-in presets and JSON persistence
- Job queue with priority ordering, state tracking, batch management
- Temp file management with per-job directories and disk monitoring
- Encoding engine orchestrating full video/audio conversion pipeline
- 30 unit tests covering all Phase 1 components
- Feature gating system (free/pro/studio tiers)
- Full macOS SwiftUI app: sidebar navigation, source import, stream inspector, output settings, queue, log
- Passthrough (video/audio/subtitle), stream selection, metadata editor, HDR warnings
- HDR-to-SDR tone mapping with auto-trigger for incompatible settings
- PQ-to-HLG conversion, PQ-to-DV Profile 8.4, Dolby Vision RPU pipeline
- HLG-to-DV auto-conversion, three-tier DV/HLG/SDR fallback
- Container-codec compatibility matrix with validation and UI warnings
- Automatic black bar crop detection, hardware encoder detection
- In-app help system, settings view, profile management
- AccurateRip verification engine and audio disc fidelity module

---

## What's Next (Alpha 0.2 Path)

1. **Phase 4** — CLI tool (meedya-convert): encode, probe, batch, profiles, manifest, validate commands
2. Alpha 0.2 release targeting full CLI support alongside the GUI app

---

## Known Issues and Blockers

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| FFmpeg App Store strategy | Resolved | Resolved | Hybrid engine: AVFoundation/FFmpegKit for App Store |
| App Store sandbox file access | Resolved | Resolved | Three-tier: user-selected, bookmarks, Full Disk Access |
| Optical disc DRM legality | Medium | Noted | CSS/AACS legality varies by jurisdiction |
| Swift 6.3 Windows maturity | Low | Noted | Windows UI framework TBD |

---

## Metrics

| Metric | Count |
|--------|-------|
| Total tasks across all phases | 215+ |
| GitHub Issues | 257+ |
| Supported video codecs | 16 |
| Supported audio codecs | 30+ (including spatial) |
| Supported subtitle formats | 14+ |
| Supported containers | 25+ |
| Supported optical disc formats | 22 |
| Supported image formats | 20+ (future) |
| Cloud upload providers | 12+ |
| Target platforms | 3 (macOS, Windows, Linux) |
| Wiki documentation pages | 10 |
| Help documentation files | 8 |

---

*Updated automatically during development. See [Project_Plan.md](Project_Plan.md) for full task breakdown.*
