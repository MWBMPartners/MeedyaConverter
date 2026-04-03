# 📝 MeedyaConverter — Changelog

> All notable changes to this project will be documented in this file.
>
> Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
> This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## [Unreleased]

### 🏗️ Added — 2026-04-03

- **Project Plan** — Comprehensive 19-phase project plan with 215+ tasks, release gates, feature gating ([Project_Plan.md](Project_Plan.md))
- **README** — Complete project overview with architecture, supported formats, and roadmap ([README.md](README.md))
- **Project Status** — Development progress tracker ([PROJECT_STATUS.md](PROJECT_STATUS.md))
- **Changelog** — This changelog file ([CHANGELOG.md](CHANGELOG.md))
- **Claude Context** — AI development context and project brief saved to `.claude/`
- **Help Documentation** — Initial help documentation structure in `help/`
- **.gitignore** — Updated for macOS, Windows, Linux, Xcode, VSCode, and all target platforms
- **MV-HEVC / MV-H264** — 3D/stereoscopic video support added to Phase 3
- **Optical Disc Ripping** — New Phase 8 with 22 disc types: Audio CD, SACD, Hybrid SACD, SHM-SACD, DVD, DVD Audio, DTS CD, Mixed Mode CD, HDCD, Blu-spec CD, SHM-CD, CD+G, DualDisc, CDV, Blu-ray, Blu-ray 3D, UHD Blu-ray, and more (disc, image, folder)
- **Disc Image Creation & Burning** — New Phase 9 for authoring disc images and burning to physical media for all 22 supported disc types
- **Matrix encoding preservation** — Preserve matrix metadata (Pro Logic II, Dolby Surround, etc.) when transcoding between compatible formats (Phase 5.14)
- **MP3surround, mp3PRO/mp3HD** — Fraunhofer MP3 extensions (Phase 3.21)
- **IMAX Enhanced (DTS:X IMAX)** — IMAX metadata profile support (Phase 3.22)
- **Additional video codecs** — FFV1, CineForm, VC-1/WMV, JPEG 2000 (Phase 3.23)
- **Additional containers** — MXF, AVI, FLV, MPEG-TS, MPEG-PS, 3GP, OGG, DCP (Phase 3.24)
- **Additional subtitle formats** — EBU STL, SCC, MCC (Phase 3.25)
- **Color space conversion** — BT.601/709/2020, DCI-P3, HDR tone mapping (Phase 3.26)
- **ASAF, Ambisonics, Auro-3D, NHK 22.2** — Additional spatial audio formats (Phase 3.14e-h)
- **Advanced features** — Watch folders, A/B comparison, VMAF/SSIM, scene detection, AI upscaling, content-aware encoding, DCP creation, audio fingerprinting, media server notifications, preset sharing (Phase 7.10-7.20)
- **Media Metadata Lookup** — New Phase 14: MusicBrainz, TMDB, TVDB, IMDB, MeedyaDB, Discogs, FanArt.tv, OpenSubtitles integration
- **Image Conversion** — New Phase 15 (future version): Bulk image format conversion (JPEG, PNG, WebP, AVIF, HEIC, RAW, JPEG XL, etc.)
- **Audio format compatibility guide** — Comprehensive conversion matrix documentation ([help/audio-format-compatibility.md](help/audio-format-compatibility.md))
- **Platform-specific format policy** — Support formats on platforms where libraries exist; regularly check for new availability (Phase 3.27)
- **Feature gating system** — Lightweight capability/tier architecture (free/pro/studio) in ConverterEngine (Phase 1.11)
- **AI-Powered Features (wishlist)** — Phase 18: AI captioning (with music/singing), AI audio translation, AI video upscaling, AI HDR enhancement. Aspirational — may never be implemented
- **Physical disc to image copy** — Bit-for-bit disc cloning via optical drive (Phase 11.26)
- **Teletext subtitle support** — EBU/DVB Teletext extraction and conversion (Phase 5.5a)
- **GitHub project setup** — 19 milestones, 26+ labels, 246 issues, project board, 9 wiki pages, 3 CI/CD workflows, issue templates, security policy
- **Phase reorganisation** — 18 phases reorganised into 19 with explicit release gates (Alpha 0.1 → v3.0+). CLI moved earlier, settings/code signing moved to MVP, Phase 3 split into core + extended
- **Three-tier file access** — Sandbox strategy for App Store: user-selected, bookmarks, Full Disk Access

### 🔄 Changed — 2026-04-03

- **Architecture** — Redesigned from prior implementation to modular ConverterEngine + meedya-convert + MeedyaConverter structure
- **Technology** — Confirmed Swift 6.3, SwiftUI, SPM
- **Encoding engine** — Hybrid architecture: FFmpeg subprocess (direct distribution) + AVFoundation/FFmpegKit (App Store)
- **Auto-update** — Dual strategy: Sparkle 2 (direct distribution) + Apple-managed (App Store)
- **Architecture names** — Renamed internal targets to avoid confusion with Meedya product family (MeedyaDL, MeedyaManager, MeedyaDB)
- **Git remote** — Updated from `MWBMPartners/Adaptix` to `MWBMPartners/MeedyaConverter`

### 🗑️ Removed — 2026-04-03

- **Legacy code** — All prior iteration Swift files (core/, modules/, ui/, viewmodels/, views/, apple/)
- **Old branding** — Adaptix logos and placeholder assets (branding/)
- **Old docs** — PROJECT_PROGRESS.md, docs/formats.md replaced by new documentation

---

## Version History

> Releases will be documented here as development progresses.
>
> **Version format:** `MAJOR.MINOR.PATCH`
>
> - **MAJOR** — Breaking changes or significant milestones
> - **MINOR** — New features or capabilities
> - **PATCH** — Bug fixes and minor improvements

---

*This changelog is updated with every code change during development.*
