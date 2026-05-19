<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter -- Project Status

> **Last Updated:** 2026-05-19
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overall Progress

| Metric | Value |
| ------ | ----- |
| **Current Version** | 0.1.0-rc.3 (signed + notarized DMG published) |
| **Last Release** | `v0.1.0-rc.3` (2026-05-18) -- direct distribution DMG + CLI tarball |
| **Current Phase** | Phase 16 -- Polish and Distribution (ongoing) |
| **Next Target** | `v0.1.0` GA tag once rc.3 DMG passes Gatekeeper smoke-test |
| **Overall Completion** | ~70% (#381 UI gap fully closed; engine + UI parity restored across the 2026-04-20 integration batch) |
| **Active Work** | Awaiting rc.3 smoke-test sign-off; App Store compliance work (#386-#391) deferred until explicit re-enable per #392 |

---

## Recent milestones (2026-05-18 / -19)

- **#382 integration batch merged** — Suite-core scaffolding (#371-#374),
  subtitle tone-mapping (#369), render farm scaffolding (#346),
  raster/vector engine (#376/#377), FFplay bundling (#378), App Store
  metadata + runbook (#178). ~3700 lines, 21 commits.
- **#380 security audit fully closed** — all four deferred items landed
  (FTP creds → 0600 config file, API keys → Keychain, TempFileManager
  orphan auto-cleanup, RenderFarmClient `.plainHTTP` → InsecureTransport-
  Override token).
- **#381 UI gap fully closed** — six new SwiftUI surfaces shipped:
  Subtitles section in OutputSettingsView, Metadata + Audio CD +
  Render Farm tabs in Settings, Vector Conversion + ProRes to Vector
  views in the Tools sidebar.
- **TestFlight workflow guardrails in place (#392/#393)** — automated
  App Store submissions cannot fire on tag pushes until explicit
  re-enable AND completion of #386-#391 ITMS findings.
- **`v0.1.0-rc.3` published** — signed (Developer ID) and notarized
  DMG + CLI tarball available at the GitHub Releases page. Smoke-test
  pending on a clean Mac.

---

## Release Gates

| Release | Phases | Description | Status |
| ------- | ------ | ----------- | ------ |
| **Alpha 0.1** | 0, 1, 2 | Core engine + macOS app -- first testable build | Complete |
| **Alpha 0.2** | 3, 4 | Essential codecs, passthrough, HDR + CLI tool | Complete |
| **Beta 0.5** | 5, 6 | Subtitles, audio normalisation, HLS/DASH | In Progress |
| **Beta 0.7** | 7, 8 | Extended formats, spatial audio, advanced audio | In Progress |
| **RC 0.9** | 9 | Professional features (VMAF, watch folders, AI upscaling) | In Progress |
| **Ongoing** | 16 | Polish and Distribution -- runs throughout development | Ongoing |
| **v1.1+** | 10, 11 | Optical disc ripping and authoring | Planned |
| **v1.3+** | 12 | Cloud uploads | In Progress |
| **v1.5+** | 15 | Media metadata lookup | In Progress |
| **v2.0** | 13, 14 | Windows and Linux | Planned |
| **v3.0+** | 17 | Image conversion | Planned |

---

## Phase Status Overview

| Phase | Name | Status | Progress | Release |
| ----- | ---- | ------ | -------- | ------- |
| **0** | Project Setup and Architecture | Complete | 100% | -- |
| **1** | Core Engine Foundation | Complete | 100% | Alpha 0.1 |
| **2** | macOS SwiftUI Application (MVP) | Complete | 100% | Alpha 0.1 |
| **3** | Essential Encoding and Passthrough | Complete | 100% | Alpha 0.2 |
| **4** | CLI Tool (meedya-convert) | Complete | 100% | Alpha 0.2 |
| **5** | Subtitles and Core Audio Processing | In Progress | 70% | Beta 0.5 |
| **6** | Adaptive Streaming (HLS/MPEG-DASH) | In Progress | 80% | Beta 0.5 |
| **7** | Extended Formats and Spatial Audio | In Progress | 60% | Beta 0.7 |
| **8** | Advanced Audio Processing | In Progress | 50% | Beta 0.7 |
| **9** | Professional Features | In Progress | 60% | RC 0.9 |
| **10** | Optical Disc Ripping (22 types) | In Progress | 30% | v1.1+ |
| **11** | Disc Image Creation and Burning | In Progress | 20% | v1.2+ |
| **12** | Cloud Integration and Uploads | In Progress | 50% | v1.3+ |
| **13** | Platform Expansion -- Windows | Planned | 0% | v2.0 |
| **14** | Platform Expansion -- Linux | Planned | 0% | v2.0 |
| **15** | Media Metadata Lookup | In Progress | 40% | v1.5+ |
| **16** | Polish and Distribution | Ongoing | 30% | Ongoing |
| **17** | Image Conversion (future) | In Progress | 10% | v3.0+ |
| **18** | AI-Powered Features (wishlist) | In Progress | 10% | TBD |

---

## Phase 0: Project Setup -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
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

## Phase 1: Core Engine Foundation -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
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

## Phase 2: macOS SwiftUI Application -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
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

## Phase 3: Essential Encoding and Passthrough -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
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

## Phase 4: CLI Tool -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 4.1 | CLI entry point and subcommand routing | Complete | MeedyaConvert.swift with ArgumentParser |
| 4.2 | encode subcommand | Complete | Full options: codec, CRF, bitrate, preset, resolution, HDR, passthrough, stream selection |
| 4.3 | probe subcommand | Complete | Text and JSON output, streams-only, HDR details |
| 4.4 | profiles subcommand | Complete | List, show, export, import, validate with platform check |
| 4.5 | batch subcommand | Complete | Directory scan and job file modes, recursive, extension filter |
| 4.6 | manifest subcommand | Complete | HLS, DASH, CMAF with variant ladders, dry-run |
| 4.7 | validate subcommand | Complete | Profile, profile-file, manifest validation with strict mode |
| 4.8 | Exit codes | Complete | POSIX-compliant exit codes (0-6, 130) |
| 4.9 | JSON progress output | Complete | Machine-readable progress and result output |
| 4.10 | OpenAPI CLI specification | Complete | Full spec in docs/api/meedya-convert-api.yaml |

---

## What's Complete

- Project plan with 19 phases (0-18), release gates, feature gating, and 215+ tasks
- Full documentation suite: README, Project Plan, Project Status, Changelog, 8 help docs, 10 wiki pages, OpenAPI spec
- Architecture: ConverterEngine (library) + meedya-convert (CLI) + MeedyaConverter (SwiftUI app)
- SPM package with 3 targets -- builds and tests pass (30/30)
- Hybrid encoding engine (FFmpeg subprocess + AVFoundation/FFmpegKit)
- Dual update strategy (Sparkle 2 direct + Apple-managed App Store)
- Three-tier file access for App Store sandbox
- GitHub: 19 milestones, 26+ labels, 246 issues, project board
- CI/CD: 3 GitHub Actions workflows (build, release, beta/alpha)
- Issue templates, security policy, CODEOWNERS, PR template, LICENSE
- FFmpeg bundle manager, process controller, argument builder
- Media probing via FFprobe -- streams, HDR detection, chapters, metadata
- Complete data models -- 16 video codecs, 30+ audio codecs, 25+ containers, 14+ subtitle formats
- Encoding profile system with 7+ built-in presets and JSON persistence
- Job queue with priority ordering, state tracking, batch management
- Temp file management with per-job directories and disk monitoring
- Encoding engine orchestrating full video/audio conversion pipeline
- 30 unit tests covering all Phase 1 components
- Feature gating system (free/pro/studio tiers)
- Full macOS SwiftUI app: 35+ views including sidebar, source import, stream inspector, output settings, queue, log, dashboard, pipeline editor, schedule, conditional rules, post-encode actions, bitrate heatmap, audio waveform, quality preview, FFmpeg preview, paywall, analytics settings, media server settings
- Passthrough (video/audio/subtitle), stream selection, metadata editor, HDR warnings
- HDR-to-SDR tone mapping with auto-trigger for incompatible settings
- PQ-to-HLG conversion, PQ-to-DV Profile 8.4, Dolby Vision RPU pipeline
- HLG-to-DV auto-conversion, three-tier DV/HLG/SDR fallback
- Container-codec compatibility matrix with validation and UI warnings
- Automatic black bar crop detection, hardware encoder detection
- In-app help system, settings view, profile management
- AccurateRip verification engine and audio disc fidelity module
- CLI tool with 6 subcommands: encode, probe, profiles, batch, manifest, validate
- Licensing module: EntitlementGating, ProductCatalog, StoreManager, RevenueCat, LicenseKeyValidator
- Encoding pipelines, conditional rules, post-encode actions, encoding checkpoints
- Watch folder monitoring, scene detection, content analysis
- Audio normalization presets, surround upmixer, audio fingerprinting
- Metadata lookup and auto-tagging
- Cloud upload providers (12+), media server notifications
- Quality metrics (VMAF/SSIM), encoding reports
- AI upscaler, forensic watermark, DCP generator, image converter
- Colour space converter, stereo 3D converter, TrueHD MP4 muxer, VVC encoder
- Speech-to-text engine, multi-stream selector, streaming enhancements
- MeedyaSuite-core integration scaffolding: Swift Package dependency
  (feature-flagged via `SUITE_CORE=1`), bridge + adapters for metadata
  and codec classification, and 12+ additional providers available
  through the unified system (#371, #372, #373, #374)
- Subtitle tone-mapping via quietvoid/subtitle_tonemap integration (#369)
- Render-farm submission subsystem: agent registry, chunked upload with
  per-chunk SHA-256, progress AsyncStream, pluggable transport (#346)
- Raster ↔ vector image conversion scaffolding with 30+ raster formats,
  SVG 1.1/2.0 output, 4 tracing modes, 6 editability presets (#376)
- ProRes alpha → animated SVG scaffolding with 4444 / 4444 XQ / 4444 HDR
  variants, rational-accurate frame rates, SMIL/CSS/hybrid assembly (#377)
- Full FFmpeg component bundling (ffmpeg + ffprobe + **ffplay**) via
  `scripts/bundle-ffmpeg.sh` for arm64 and x86_64 (#378)
- App Store Connect metadata suite under `metadata/` and submission
  runbook at `docs/distribution/app-store-submission.md` (#178)

---

## What's Next

1. **UI surfacing** (#381) -- Expose new Configuration types in SwiftUI for
   subtitle tone-mapping, render farm, metadata backend, AccurateRip
   submission, and vector conversion
2. **MeedyaSuite-core binding stabilisation** -- Once MeedyaSuite-core
   publishes a Swift Package tag, flip `SUITE_CORE` to default-on and
   execute the #374 cleanup checklist
3. **Render-farm agent binary** -- Standalone agent app that runs on
   remote Macs and services the REST protocol defined in #346
4. **App Store submission** -- Produce screenshot captures, verify the
   FFmpegKit LGPL variant, tag a `v1.0.0-beta.1`, soak in TestFlight
5. **Phase 5/6 completion** -- Finish subtitle conversion and streaming
   features; still at 70% and 80% respectively

---

## Known Issues and Blockers

| Issue | Severity | Status | Notes |
| ----- | -------- | ------ | ----- |
| FFmpeg App Store strategy | Resolved | Resolved | Hybrid engine: AVFoundation/FFmpegKit for App Store |
| App Store sandbox file access | Resolved | Resolved | Three-tier: user-selected, bookmarks, Full Disk Access |
| Optical disc DRM legality | Medium | Noted | CSS/AACS legality varies by jurisdiction |
| Swift 6.3 Windows maturity | Low | Noted | Windows UI framework TBD |

---

## Metrics

| Metric | Count |
| ------ | ----- |
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
| SwiftUI views | 35+ |
| ConverterEngine modules | 15 |
| CLI subcommands | 6 |

---

*Updated automatically during development. See [Project_Plan.md](Project_Plan.md) for full task breakdown.*
