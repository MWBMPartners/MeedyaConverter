# MeedyaConverter — Claude Prompt History

> Log of significant development prompts and decisions.
> Maintained for project continuity across sessions.

## Session: 2026-04-03

### Prompt 1: Initial Project Brief

User provided comprehensive project outline for MeedyaConverter — a modern HandBrake
alternative with cross-platform support, adaptive streaming, cloud uploads, and more.
Key requirements: Swift 6.3/SwiftUI for macOS, modular architecture, detailed code annotations,
proprietary license, 12+ cloud upload providers, standing tasks after every action.

**Result:** Created Project_Plan.md (12 phases), README.md, PROJECT_STATUS.md, CHANGELOG.md,
help/ documentation, .claude/ context, .gitignore. Saved project memories.

### Prompt 2: FFmpeg App Store Licensing

User asked whether LGPL-only FFmpeg build is needed for App Store. Clarified that since FFmpeg
is a subprocess (not linked), full GPL build is fine for both App Store and direct distribution.
Corrected the Project_Plan.md.

### Prompt 3: Architecture Naming

User noted that internal names (MeedyaCore, MeedyaCLI, MeedyaApp) could be confused with
sibling products (MeedyaDL, MeedyaManager, MeedyaDB). Renamed to:

- ConverterEngine (core library)
- meedya-convert (CLI tool)
- MeedyaConverter (macOS app)

### Prompt 4: App Store Subprocess Concerns

User asked if FFmpeg subprocess meets App Store guidelines. Analysis showed risk of rejection.
Solution: hybrid encoding architecture.

- App Store: AVFoundation/VideoToolbox + FFmpegKit (LGPL linked)
- Direct: FFmpeg subprocess (full GPL)
- Three-tier file access for sandbox (user-selected, bookmarks, Full Disk Access)

### Prompt 5: Sparkle Auto-Updates

Confirmed dual update strategy:

- Direct distribution: Sparkle 2 auto-updates
- App Store: Apple-managed updates (Sparkle excluded via build config)

### Prompt 6: MV-HEVC/MV-H264 and Optical Disc Ripping

Added 3D/stereoscopic video support (MV-HEVC for Apple Vision Pro, MV-H264).
Added new Phase 8 for optical disc ripping (Audio CD through Ultra HD Blu-ray).
Added PGS/VobSub subtitle support with Tesseract OCR conversion.

### Prompt 7: Additional Disc Formats and Disc Authoring

Added 11 more disc formats to Phase 8 (DVD Audio, DTS CD, HDCD, etc. — total 22 types).
Added new Phase 9 for disc image creation and burning.
Renumbered to 14 phases (0-13).

### Prompt 8: Repo Cleanup and Remote Rename

Deleted all legacy files from prior "Adaptix" iteration.
Updated git remote from MWBMPartners/Adaptix to MWBMPartners/MeedyaConverter.
Removed old branding assets.

### Prompt 9: Full Project Setup

User requested comprehensive project setup:

- Create folder structure (Sources/ConverterEngine, Sources/meedya-convert, Sources/MeedyaConverter)
- Package.swift with SPM targets
- GitHub Milestones (14 created, numbers 1-14)
- GitHub Project board (#13)
- GitHub labels (phase-0 through phase-13 plus component labels)
- GitHub Issues for ALL project requirements (150+)
- GitHub Wiki (comprehensive pages)
- GitHub Actions workflows (main/beta/alpha branches)
- Issue templates, security policy, LICENSE, CODEOWNERS
- Updated standing tasks (11 mandatory post-action tasks)
- Branch strategy: main (production), beta (testing), alpha (dev)

### Prompt 10: Feature Expansions (Audio, Formats, Image)

Multiple feature additions across the session:

- Matrix encoding preservation on transcode (keep PL II/Surround across format changes)
- Virtual surround upmixing (algorithmic stereo → 5.1/7.1)
- Matrix-guided surround expansion (PL II/DTS Neo:6 decode to discrete)
- Audio channel content analysis (detect actual vs declared channels, with waveform/cross-correlation)
- MP3surround, mp3PRO/mp3HD, IMAX Enhanced (DTS:X IMAX)
- Spatial audio: ASAF, Ambisonics, Auro-3D, NHK 22.2, AC-4 A-JOC
- Additional codecs: FFV1, CineForm, VC-1, JPEG 2000, DSD, WavPack, MQA, etc.
- Additional containers: MXF, AVI, FLV, MPEG-TS, DCP, etc.
- Additional subtitles: EBU STL, SCC, MCC
- MediaInfo integration (libmediainfo BSD-2-Clause)
- Dolby TrueHD encoding confirmed (FFmpeg `truehd` encoder, up to 7.1)
- Temp file management (user-configurable, per-job cleanup, OS temp default)
- Media metadata lookup phase (MusicBrainz, TMDB, TVDB, IMDB, MeedyaDB)
- Image conversion phase (future version)
- Audio format compatibility documentation created

**Result:** 232 GitHub issues, 16 milestones (later reorganised to 18).

### Prompt 11: Full Project Review & Reorganisation

User requested comprehensive review of feature list and GitHub Issues. Reorganised for
logical development order and early testability:

Key changes:

- CLI moved from Phase 6 → Phase 4 (enables test automation early)
- Settings/help/notifications moved from Phase 7 → Phase 2 (needed for usable MVP)
- Code signing/notarization moved from Phase 13 → Phase 2 (sign from first build)
- Phase 3 split: core encoding (Phase 3) + extended formats/spatial (new Phase 7)
- Phase 5 split: core audio (Phase 5) + advanced audio processing (new Phase 8)
- Old Phase 7 (Advanced Features) → Phase 9 (Professional Features)
- Disc ripping/authoring → Phases 10-11 (post v1.0)
- Windows/Linux → Phases 13-14 (v2.0)
- Polish → Phase 16 (ongoing)
- Image conversion → Phase 17 (future v3.0+)
- Added explicit release gates: Alpha 0.1 → v3.0+
- Total: 18 phases (0-17), 232 issues, release gate labels on all issues

**Result:** 18 milestones with release gates, issues reorganised and labelled.

### Prompt 12: Feature Gating, AI Wishlist, Disc-to-Image Copy

- Feature gating system added to Phase 1 (task 1.11) — lightweight free/pro/studio tier architecture
- Phase 18 created: AI-Powered Features (wishlist) — AI captioning with music/singing, AI audio translation, AI video upscaling, AI HDR enhancement. All on-device, no cloud. May never be implemented
- Physical disc to image copy (task 11.26) — bit-for-bit disc cloning via optical drive
- Teletext subtitle support (task 5.5a) — EBU/DVB Teletext
- CEA-708/EIA-708 naming clarified

**Result:** 19 phases (0-18), 240 GitHub issues (as of latest update), 19 milestones.

## Session: 2026-04-04

### Prompt 13: Review Issues & Proceed with Phase 2

User requested: "Review the GitHub issues, and proceed with the next logic step in the project main branch."

Completed Phase 2 (macOS SwiftUI Application MVP):
- NavigationSplitView with sidebar/detail layout (ContentView, SidebarView)
- Source file import with drag-and-drop (SourceFileView)
- Stream inspector with HDR/DV/3D badges (StreamInspectorView)
- Output settings with profile selection (OutputSettingsView)
- Profile management with CRUD, import/export (ProfileManagementView)
- Encoding queue with start/pause/resume/cancel (JobQueueView)
- Unified activity log with filtering and export (ActivityLogView)
- Settings with General/Encoding/Paths/Notifications/About tabs (SettingsView)
- In-app help with searchable topics (HelpView)
- Notification delivery via UNUserNotificationCenter
- AppViewModel as @Observable with @Environment injection

### Prompt 14: Proceed with Phase 3

Implemented Phase 3 (Essential Encoding & Passthrough):

**Phase 3.1–3.7** (commit 569194b):
- Video/audio/subtitle passthrough toggles in OutputSettingsView
- Stream selection pickers for multi-stream sources
- StreamMetadataEditorView for per-stream title, language (BCP 47), default/forced flags
- HDR warning system with Dolby Vision / HDR10+ badges
- Metadata passthrough: `-map_metadata 0`, `-map_chapters 0` by default
- Stream selection and metadata wired into EncodingJobConfig

**Phase 3.10, 3.14** (commit c23627c):
- HardwareEncoderDetector: queries FFmpeg for VideoToolbox/NVENC/QSV/AMF/VA-API encoders
- CropDetector: automatic black bar detection via cropdetect filter with confidence scoring

**Phase 3.8, 3.11–3.13, 3.15, 3.16** (commit d97b8cb):
- DoviToolWrapper: dovi_tool integration for RPU extract/inject/convert/generate
- Container-codec compatibility matrix (supportedVideoCodecs, supportedAudioCodecs)
- Built-in profiles expanded from 7 to 23 across 7 categories
- Codec metadata preservation (preserveCodecMetadata) and aspect ratio override
- EncodingProfile made Hashable for SwiftUI Picker

**Phase 3.9** (commit beebd58):
- HDR→SDR tone mapping via zscale/tonemap filter chain (5 algorithms)
- toneMapToSDR and toneMapAlgorithm on EncodingProfile
- Phase 3.9c auto-trigger: auto-enable tone mapping when HDR source + incompatible output
- Container validation warnings in OutputSettingsView
- Stream disposition support for TrueHD non-default enforcement (MP4-only)

**Documentation** (commit b91d2d4):
- help/container-codec-compatibility.md: full reference tables
- In-app help: "Container & Codec Compatibility" topic
- TrueHD-in-MP4 policy: allowed but non-default (MP4-family only)

**GitHub Issues:**
- #251: Metadata passthrough (updated with checkboxes)
- #252: Chapter passthrough (updated)
- #253: TrueHD in MP4 policy (created)

### Prompt 15: PQ → HLG Conversion (hlg-tools)

Implemented PQ (ST 2084) → HLG (ARIB STD-B67) conversion with dual-path approach:

- **HlgToolsWrapper**: New wrapper for external `pq2hlg` binary from hlg-tools project
  - Binary discovery across Homebrew, /usr/local/bin, /usr/bin, which(1) fallback
  - Async execution, version detection, availability check
- **FFmpeg zscale fallback**: `zscale=tin=smpte2084:t=linear` → `zscale=t=arib-std-b67` filter chain
- **EncodingProfile**: Added `convertPQToHLG`, `useHlgTools` (default: true) properties
- **OutputSettingsView**: PQ→HLG toggle, hlg-tools status indicator, "Force FFmpeg zscale" option
- **Built-in profile**: "PQ → HLG (Broadcast)" — H.265 CRF 18, 10-bit, E-AC-3 5.1, MKV
- GitHub Issue: #254

### Prompt 16: Combined PQ → DV Profile 8.4 + HLG

Combined PQ→HLG (#254) with HLG→DV (#246) for three-tier playback (DV→HLG→SDR):

- **EncodingEngine**: PQ→DV+HLG pipeline: PQ→HLG encode → dovi_tool generate (Profile 8.4 RPU) → inject → remux
- **EncodingProfile**: Added `convertPQToDVHLG` property
- **MediaFile**: Added `hasPQ` computed property
- **OutputSettingsView**: DV+HLG toggle, dovi_tool availability warning, three-tier badge
- **Built-in profile**: "PQ → DV+HLG (Max Compat)" — H.265 CRF 18, 10-bit, E-AC-3 7.1, MKV
- Total built-in profiles: 25
- GitHub Issue: #255

### Prompt 17: Tool Bundling & Auto-Updates

Strategy for bundling hlg-tools and dovi_tool:

- **Direct distribution**: Bundle binaries, check GitHub Releases API for updates
- **App Store**: Exclude tools (sandbox), graceful fallback to FFmpeg-only paths
- GitHub Issues: #256 (bundling), #257 (auto-update checks)

### Prompt 18: Context Updates & Issue Review

- Updated .claude/project_brief.md with Phase 3 completion, tool bundling policies
- Updated PROJECT_STATUS.md with all Phase 3 additions, profile count (25)
- Commented on implemented Phase 3 issues: #251, #252, #253, #247, #248, #240, #241, #244, #243

### Prompt 19: GitHub Milestones Assignment

User requested review of ALL GitHub issues and creation/assignment of milestones matching
the 19-phase project structure.

### Key Decisions Made

- **TrueHD in MP4**: Allowed but must NOT be default audio stream in MP4-family containers only. All other containers (MKV etc.) have no restriction. See issue #253.
- **Metadata passthrough by default**: All source metadata copied via `-map_metadata 0` and `-map_chapters 0`. UI overrides apply on top, not replace.
- **HDR auto-trigger**: When HDR source + incompatible output (non-HDR codec, 8-bit, non-HDR container), tone mapping auto-enabled with user notification.
- **PQ→HLG**: hlg-tools preferred when available, FFmpeg zscale fallback. `useHlgTools` defaults to true.
- **PQ→DV+HLG**: Chains PQ→HLG with DV Profile 8.4 RPU generation for three-tier playback (DV→HLG→SDR).
- **Tool bundling**: hlg-tools and dovi_tool bundled in direct distribution; excluded from App Store with graceful fallback.
- **Environment limitation**: Linux x86_64 without Swift compiler — all code verified by review only, cannot build/test.
