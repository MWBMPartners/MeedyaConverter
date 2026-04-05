<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter -- Changelog

> All notable changes to this project will be documented in this file.
>
> Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
> This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## [Unreleased]

### Added -- 2026-04-05

- **Comprehensive documentation update** -- Rewrote and updated all 10 wiki pages, OpenAPI spec, CHANGELOG, and PROJECT_STATUS to reflect current application state (#186)
- **OpenAPI CLI specification** -- Complete rewrite of `docs/api/meedya-convert-api.yaml` with accurate schemas for all 6 CLI subcommands (encode, probe, profiles, batch, manifest, validate), all options, all flags, JSON output schemas, exit codes, and streaming variant ladder format
- **CLI Reference accuracy** -- Updated `docs/CLI-Reference.md` to match actual source code: correct flag names (`--video-passthrough` not `--passthrough-video`, `--tonemap` not `--hdr-mode`), correct option types, removed non-existent options (`--two-pass`, `--crop`, `--crop-detect`, `--parallel`, `--dry-run` on batch, `--metadata`, `--chapters`)
- **User Guide expansion** -- Added sections for encoding pipelines, scheduled encoding, conditional rules, post-encode actions, watch folders, scene detection, bitrate heatmap, audio waveform, quality metrics (VMAF/SSIM), content-aware encoding, AI upscaling, FFmpeg command preview, A/B quality preview, file size estimation, filename templates, smart profile suggestions, audio normalization presets, profile sharing
- **Architecture update** -- Added Licensing module (FeatureGate, ProductCatalog, StoreManager, RevenueCat, LicenseKeyValidator, EntitlementGating), Metadata module (MetadataLookup, MetadataProviders, AutoTagger), Reports module, Native module, encoding pipeline architecture, licensing architecture
- **Building from Source update** -- Added Sparkle conditional build documentation, StoreKit integration details, project structure with 35+ views
- **Troubleshooting expansion** -- Added sections for encoding pipeline failures, scheduled encoding issues, watch folder issues, subscription/licensing issues, media server notification failures
- **FAQ expansion** -- Added subscription/licensing FAQ section, pipelines/scheduling/automation FAQ, file size estimation FAQ, updated feature tier table
- **Contributing update** -- Added SwiftLint configuration details, integration test gating, copyright year policy
- **Home page update** -- Added Feature Highlights sections covering all implemented features across 8 categories

### Added -- 2026-04-05 (earlier)

- **Wiki documentation** -- 10 wiki pages in `docs/`: Home, Getting Started, User Guide, CLI Reference, Architecture, Building from Source, Contributing, Codec Reference, Troubleshooting, FAQ (#184)
- **Final documentation pass** -- Updated CHANGELOG and PROJECT_STATUS with full phase history and current status (#185)

### Added -- 2026-04-04

- **AccurateRip verification engine** -- Checksum calculation and database parsing for audio disc ripping
- **Audio disc fidelity module** -- CDTOC, cuesheet, chapters, and whole-disc ripping support
- **AccurateRip database submission** -- Submit verified checksums to the AccurateRip database

### Fixed -- 2026-04-04

- **CropRect Codable conformance** -- Fixed compilation error in SmartCropConfig
- **Swift extension recommendation** -- Updated to current `swiftlang.swift-lang` (was deprecated `sswg.swift-lang`)

### Added -- 2026-04-03

- **Project Plan** -- Comprehensive 19-phase project plan with 215+ tasks, release gates, feature gating ([Project_Plan.md](Project_Plan.md))
- **README** -- Complete project overview with architecture, supported formats, and roadmap ([README.md](README.md))
- **Project Status** -- Development progress tracker ([PROJECT_STATUS.md](PROJECT_STATUS.md))
- **Changelog** -- This changelog file ([CHANGELOG.md](CHANGELOG.md))
- **Claude Context** -- AI development context and project brief saved to `.claude/`
- **Help Documentation** -- Initial help documentation structure in `help/`
- **.gitignore** -- Updated for macOS, Windows, Linux, Xcode, VSCode, and all target platforms
- **MV-HEVC / MV-H264** -- 3D/stereoscopic video support added to Phase 3
- **Optical Disc Ripping** -- New Phase 8 with 22 disc types: Audio CD, SACD, Hybrid SACD, SHM-SACD, DVD, DVD Audio, DTS CD, Mixed Mode CD, HDCD, Blu-spec CD, SHM-CD, CD+G, DualDisc, CDV, Blu-ray, Blu-ray 3D, UHD Blu-ray, and more (disc, image, folder)
- **Disc Image Creation and Burning** -- New Phase 9 for authoring disc images and burning to physical media for all 22 supported disc types
- **Matrix encoding preservation** -- Preserve matrix metadata (Pro Logic II, Dolby Surround, etc.) when transcoding between compatible formats (Phase 5.14)
- **MP3surround, mp3PRO/mp3HD** -- Fraunhofer MP3 extensions (Phase 3.21)
- **IMAX Enhanced (DTS:X IMAX)** -- IMAX metadata profile support (Phase 3.22)
- **Additional video codecs** -- FFV1, CineForm, VC-1/WMV, JPEG 2000 (Phase 3.23)
- **Additional containers** -- MXF, AVI, FLV, MPEG-TS, MPEG-PS, 3GP, OGG, DCP (Phase 3.24)
- **Additional subtitle formats** -- EBU STL, SCC, MCC (Phase 3.25)
- **Color space conversion** -- BT.601/709/2020, DCI-P3, HDR tone mapping (Phase 3.26)
- **ASAF, Ambisonics, Auro-3D, NHK 22.2** -- Additional spatial audio formats (Phase 3.14e-h)
- **Advanced features** -- Watch folders, A/B comparison, VMAF/SSIM, scene detection, AI upscaling, content-aware encoding, DCP creation, audio fingerprinting, media server notifications, preset sharing (Phase 7.10-7.20)
- **Media Metadata Lookup** -- New Phase 14: MusicBrainz, TMDB, TVDB, IMDB, MeedyaDB, Discogs, FanArt.tv, OpenSubtitles integration
- **Image Conversion** -- New Phase 15 (future version): Bulk image format conversion (JPEG, PNG, WebP, AVIF, HEIC, RAW, JPEG XL, etc.)
- **Audio format compatibility guide** -- Comprehensive conversion matrix documentation ([help/audio-format-compatibility.md](help/audio-format-compatibility.md))
- **Platform-specific format policy** -- Support formats on platforms where libraries exist; regularly check for new availability (Phase 3.27)
- **Feature gating system** -- Lightweight capability/tier architecture (free/pro/studio) in ConverterEngine (Phase 1.11)
- **AI-Powered Features (wishlist)** -- Phase 18: AI captioning (with music/singing), AI audio translation, AI video upscaling, AI HDR enhancement. Aspirational -- may never be implemented
- **Physical disc to image copy** -- Bit-for-bit disc cloning via optical drive (Phase 11.26)
- **Teletext subtitle support** -- EBU/DVB Teletext extraction and conversion (Phase 5.5a)
- **GitHub project setup** -- 19 milestones, 26+ labels, 246 issues, project board, 9 wiki pages, 3 CI/CD workflows, issue templates, security policy
- **Phase reorganisation** -- 18 phases reorganised into 19 with explicit release gates (Alpha 0.1 to v3.0+). CLI moved earlier, settings/code signing moved to MVP, Phase 3 split into core + extended
- **Three-tier file access** -- Sandbox strategy for App Store: user-selected, bookmarks, Full Disk Access

### Changed -- 2026-04-03

- **Architecture** -- Redesigned from prior implementation to modular ConverterEngine + meedya-convert + MeedyaConverter structure
- **Technology** -- Confirmed Swift 6.3, SwiftUI, SPM
- **Encoding engine** -- Hybrid architecture: FFmpeg subprocess (direct distribution) + AVFoundation/FFmpegKit (App Store)
- **Auto-update** -- Dual strategy: Sparkle 2 (direct distribution) + Apple-managed (App Store)
- **Architecture names** -- Renamed internal targets to avoid confusion with Meedya product family (MeedyaDL, MeedyaManager, MeedyaDB)
- **Git remote** -- Updated from `MWBMPartners/Adaptix` to `MWBMPartners/MeedyaConverter`

### Removed -- 2026-04-03

- **Legacy code** -- All prior iteration Swift files (core/, modules/, ui/, viewmodels/, views/, apple/)
- **Old branding** -- Adaptix logos and placeholder assets (branding/)
- **Old docs** -- PROJECT_PROGRESS.md, docs/formats.md replaced by new documentation

---

## [0.1.0-alpha] -- Unreleased

> Alpha milestone targeting Phases 0-4 completion.

### Added

- SPM package with three targets: ConverterEngine (library), meedya-convert (CLI), MeedyaConverter (SwiftUI app)
- FFmpeg bundle manager with binary discovery, version detection, and validation
- FFmpeg process controller with start/pause/resume/stop and progress monitoring
- Media file probing via FFprobe -- streams, HDR detection, chapters, metadata
- Complete data models -- MediaFile, MediaStream, 16 video codecs, 30+ audio codecs, 25+ containers, 14+ subtitle formats
- FFmpeg argument builder translating encoding settings to CLI arguments
- Encoding profile system with 7+ built-in presets and JSON persistence
- Encoding job queue with priority ordering, state tracking, batch management
- Temp file management with per-job directories and disk space monitoring
- Encoding engine orchestrating full video/audio conversion pipeline
- 30 unit tests covering all Phase 1 components
- Feature gating system (free/pro/studio tiers)
- Full macOS SwiftUI app: sidebar navigation, source import, stream inspector, output settings, queue, log
- Passthrough (video/audio/subtitle), stream selection, metadata editor, HDR warnings
- HDR-to-SDR tone mapping (hable/reinhard/mobius/bt2390/clip), auto-trigger for incompatible settings
- PQ-to-HLG conversion via hlg-tools (preferred) or FFmpeg zscale fallback
- PQ-to-DV Profile 8.4 + HLG combined conversion: three-tier DV-to-HLG-to-SDR fallback
- Dolby Vision preservation pipeline: RPU extract, encode, inject via dovi_tool
- HLG-to-DV auto-conversion via dovi_tool generate (Profile 8.4)
- Container-codec compatibility matrix with validation and UI warnings
- Automatic black bar crop detection via FFmpeg cropdetect
- Hardware encoder detection (VideoToolbox/NVENC/QSV/AMF/VA-API)
- In-app help system, settings view, profile management
- AccurateRip verification engine for audio disc ripping
- Audio disc fidelity module (CDTOC, cuesheet, chapters, whole-disc ripping)
- CLI tool with 6 subcommands: encode, probe, profiles, batch, manifest, validate
- Licensing module: EntitlementGating, ProductCatalog, StoreManager, RevenueCat, LicenseKeyValidator
- Encoding pipelines, conditional rules, post-encode actions, encoding checkpoints
- Watch folder monitoring, scene detection, content analysis
- Audio normalization presets, surround upmixer, audio fingerprinting
- Metadata lookup and auto-tagging (MusicBrainz, TMDB, TVDB, Discogs)
- Cloud upload providers (12+), media server notifications, API key management
- Quality metrics (VMAF/SSIM), encoding reports, frame comparison
- AI upscaler, forensic watermark, DCP generator
- 35+ SwiftUI views including pipeline editor, schedule, conditional rules, bitrate heatmap, audio waveform, quality preview, paywall, analytics settings

---

## Version History

> **Version format:** `MAJOR.MINOR.PATCH`
>
> - **MAJOR** -- Breaking changes or significant milestones
> - **MINOR** -- New features or capabilities
> - **PATCH** -- Bug fixes and minor improvements

| Version | Date | Highlights |
| ------- | ---- | ---------- |
| 0.1.0-alpha | TBD | Core engine, SwiftUI app, CLI tool, HDR workflows, encoding profiles, licensing, pipelines |

---

*This changelog is updated with every code change during development.*
