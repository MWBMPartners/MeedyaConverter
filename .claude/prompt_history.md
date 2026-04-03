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
