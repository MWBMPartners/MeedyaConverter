# MeedyaConverter — Project Brief

> Saved for Claude AI context continuity across sessions.
> Last updated: 2026-04-04

## Project Summary

MeedyaConverter is a cross-platform media conversion application (modern HandBrake alternative)
built by MWBM Partners Ltd. It converts audio/video files between formats/containers with
advanced features including passthrough, adaptive streaming (HLS/MPEG-DASH), HDR preservation,
spatial audio, optical disc ripping/authoring, cloud upload, and image conversion (future).

## Current Status

- **Phase 0**: Complete (project setup, architecture)
- **Phase 1**: Complete (core engine: FFmpeg bundle manager, process controller, probe, argument builder, encoding profiles, temp files, feature gating, 30 unit tests)
- **Phase 2**: Complete (macOS SwiftUI app: NavigationSplitView, source import with drag-drop, stream inspector with HDR/DV badges, output settings, profile management, encoding queue with controls, unified activity log, settings, notifications, help, about)
- **Phase 3**: ~90% complete (passthrough toggles, stream selection, metadata editor, HDR warnings, hardware encoder detection, crop detection, Dolby Vision dovi_tool wrapper, container-codec compatibility matrix, 23 built-in profiles, tone mapping, auto-trigger, container validation, disposition enforcement)
- **Overall**: ~28% of 19 phases

## Key Requirements

### Core Differentiators vs HandBrake

- Video/audio/subtitle passthrough (copy without re-encoding)
- CC608/CC708 closed caption support
- Multiple video stream handling with per-stream settings
- Detailed stream metadata editing (BCP 47 language, forced/default flags)
- Audio normalization (EBU R128, ReplayGain)
- Audio channel content analysis (detect actual vs declared channels)
- Virtual surround upmixing with matrix-guided expansion
- Matrix encoding preservation on transcode
- HLS/MPEG-DASH adaptive streaming preparation
- Spatial/immersive audio (Atmos, IAMF, MPEG-H, Ambisonics, ASAF)
- 3D/stereoscopic video (MV-HEVC, MV-H264)
- IMAX Enhanced (DTS:X IMAX)
- Optical disc ripping (22 types) and authoring/burning
- Cloud upload to 12+ providers
- MediaInfo integration for detailed analysis
- Image conversion (future version)
- Media metadata lookup (MusicBrainz, TMDB, TVDB, etc.)

### Architecture (Internal Target Names)

- **ConverterEngine** — Cross-platform core library (not public-facing)
- **meedya-convert** — CLI tool (public binary name)
- **MeedyaConverter** — macOS SwiftUI app (product name)

### Technology Stack

- Language: Swift 6.3 with strict concurrency
- macOS UI: SwiftUI (native, macOS 15.0+ Sequoia)
- Core: ConverterEngine Swift Package (cross-platform)
- MVVM: @Observable AppViewModel with @Environment injection
- Media Engine: Hybrid encoding backend
  - Direct distribution: FFmpeg as subprocess (full GPL, libx264/libx265)
  - App Store: AVFoundation/VideoToolbox + FFmpegKit (LGPL linked)
- Media Analysis: ffprobe + libmediainfo (BSD-2-Clause)
- HDR: dovi_tool (DoviToolWrapper), DDVT (bundled)
- Package Manager: Swift Package Manager
- CI/CD: GitHub Actions (build, release, beta/alpha)
- Auto-Update: Sparkle 2 (direct distribution); Apple-managed (App Store)

### Key Architectural Patterns

- `@Observable` macro with `@Environment` injection for AppViewModel
- `@Bindable var vm = viewModel` pattern for SwiftUI bindings
- `NavigationSplitView` with sidebar/detail layout
- `EncodingEngine` orchestration with `EncodingQueue` (ObservableObject with @Published)
- `EncodingJobState` as ObservableObject for per-job SwiftUI binding
- `EncodingProfile` (Codable, Hashable) with JSON persistence via EncodingProfileStore
- `FFmpegArgumentBuilder` for translating settings to CLI args
- `HardwareEncoderDetector` for runtime VideoToolbox/NVENC/QSV discovery
- `CropDetector` for automatic black bar detection via cropdetect filter
- `DoviToolWrapper` for Dolby Vision RPU extraction/injection/conversion
- `ContainerFormat.supportedVideoCodecs/supportedAudioCodecs` for codec-container validation
- Feature gating: ProductTier (free/pro/studio) with FeatureGateProtocol

### Important Policies

- **Metadata passthrough by default**: `-map_metadata 0` and `-map_chapters 0` always emitted
- **TrueHD in MP4**: Allowed but MUST NOT be default audio stream (MP4-family only). All other containers: no restriction. See issue #253.
- **HDR auto-trigger**: When HDR source + incompatible output settings, tone mapping auto-enabled with notification

### Apple Dual Distribution Strategy

- App Store: Sandboxed, AVFoundation/FFmpegKit hybrid, Apple-managed updates
- Direct Download: Full-featured, FFmpeg subprocess, Sparkle 2 updates
- Three-tier file access for sandbox:
  - Tier 1: User-selected access via NSOpenPanel/NSSavePanel (default)
  - Tier 2: Security-scoped bookmarks for persistent folder access
  - Tier 3: Full Disk Access via System Settings (optional)

### Development Order & Release Gates

| Release | Phases | Description |
| ------- | ------ | ----------- |
| Alpha 0.1 | 0, 1, 2 | Core engine + macOS app |
| Alpha 0.2 | 3, 4 | Essential codecs + CLI |
| Beta 0.5 | 5, 6 | Subtitles, audio, streaming |
| Beta 0.7 | 7, 8 | Extended formats, advanced audio |
| RC 0.9 | 9 | Professional features |
| Ongoing | 16 | Polish & Distribution (runs throughout) |
| v1.1+ | 10, 11 | Disc ripping & authoring |
| v1.3+ | 12 | Cloud uploads |
| v1.5+ | 15 | Media metadata |
| v2.0 | 13, 14 | Windows & Linux |
| v3.0+ | 17 | Image conversion |

### Project Phases (19 total, 0-18)

- Phase 0: Project Setup & Architecture (COMPLETE)
- Phase 1: Core Engine Foundation (COMPLETE)
- Phase 2: macOS SwiftUI Application (MVP) (COMPLETE)
- Phase 3: Essential Encoding & Passthrough (~90%) — codecs, HDR, hardware encoding, profiles, DV, tone mapping
- Phase 4: CLI Tool — moved earlier for test automation
- Phase 5: Subtitles & Core Audio Processing
- Phase 6: Adaptive Streaming (HLS/MPEG-DASH)
- Phase 7: Extended Formats & Spatial Audio — spatial, 3D, IMAX, legacy codecs
- Phase 8: Advanced Audio Processing — upmixing, matrix expansion, channel analysis
- Phase 9: Professional Features — VMAF, watch folders, AI upscaling, DCP
- Phase 10: Optical Disc Ripping (22 types)
- Phase 11: Disc Image Creation & Burning
- Phase 12: Cloud Integration & Uploads
- Phase 13: Platform Expansion — Windows
- Phase 14: Platform Expansion — Linux
- Phase 15: Media Metadata Lookup
- Phase 16: Polish & Distribution (ongoing)
- Phase 17: Image Conversion (future version)
- Phase 18: AI-Powered Features (wishlist — may never be implemented)

### Feature Gating (Phase 1.11)

- Lightweight capability/tier system: free / pro / studio
- Protocol-based: FeatureGate.isAvailable(:), FeatureGate.requiredTier(for:)
- UI shows locked features with upgrade prompt (or hides, configurable)
- Tier definitions and pricing decided later — architecture only initially
- AI features and specialist features are candidates for paid tiers

### Meedya Product Family (GitHub: MWBMPartners)

- MeedyaConverter — this project
- MeedyaDL — media downloader
- MeedyaManager — media library management
- MeedyaDB — media database

### Licensing

- Application: Proprietary — (C) 2026-present MWBM Partners Ltd
- FFmpeg: LGPL/GPL (subprocess for direct, FFmpegKit LGPL for App Store)
- libmediainfo: BSD-2-Clause
- dovi_tool: MIT
- DDVT: MIT
- Tesseract OCR: Apache 2.0

### Branch Strategy

- main: stable production releases (vX.Y.Z)
- beta: beta testing (vX.Y.Z-beta.N)
- alpha: early development (vX.Y.Z-alpha.N)

### Code Standards

- Detailed comments/annotations on every code block
- Proprietary copyright headers with automated year range
- Modular architecture
- Accessibility compliant
- App Store guidelines where possible
- Code signing & notarization from first build

### Standing Tasks (13 mandatory, after every prompt)

1. GitHub Issues (create/update before starting, close when done)
2. **Acceptance criteria tracking** — tick each checkbox in GitHub Issues incrementally as criteria are met. Every step, every phase, consistently
3. Code quality lint loop (repeat until zero issues)
4. Security audit loop (repeat until zero issues)
5. Accessibility compliance
6. Update all .md documentation
7. Update GitHub Issues/Milestones/Project/Wiki
8. Update in-app help
9. Maintain .gitignore
10. **Stage & commit after each dev step** — incremental commits per logical unit, reference issue numbers. Do NOT push (manual only)
11. Update CLI API docs (Swagger/OpenAPI) in docs/api/
12. Cleanup temp files
13. Update .claude/ context
