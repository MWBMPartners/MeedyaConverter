# 📋 MeedyaConverter — Project Plan

> **A modern, cross-platform media conversion toolkit with adaptive streaming support**
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## 📌 Project Overview

MeedyaConverter is a professional-grade, cross-platform media conversion application designed as a modern alternative to HandBrake — with significantly expanded capabilities including video/audio/subtitle passthrough, multi-bitrate HLS & MPEG-DASH preparation, HDR preservation, forensic watermarking, and cloud upload integration.

**Primary Target:** Website owners and media professionals who need to prepare audio/video content for on-demand streaming.

---

## 🏗️ Technical Architecture

### Platform Strategy

| Platform | UI Framework | Priority | Status |
| -------- | ----------- | -------- | ------ |
| **macOS** (Apple Silicon only) | Swift 6.3 / SwiftUI | 🔴 Primary | Phase 2 |
| **Windows** (x86, x64, ARM) | Swift + WinUI 3 / WinAppSDK | 🟡 Secondary | Phase 8 |
| **Linux** (x86, x64, ARM, ARMv7, ARM64, RPi OS) | Swift + GTK4 | 🟢 Tertiary | Phase 9 |
| **CLI** (all platforms) | Swift ArgumentParser | 🔴 Primary | Phase 6 |

### Core Technology Stack

| Component | Technology | Purpose |
| --------- | --------- | ------- |
| **Language** | Swift 6.3 (released March 2026) | Primary language across all platforms |
| **macOS UI** | SwiftUI (latest) | Native macOS interface |
| **Package Manager** | Swift Package Manager (SPM) | Dependency management & build system |
| **Media Engine** | Hybrid — see [Encoding Engine Architecture](#-encoding-engine-architecture-hybrid) | Encoding, decoding, muxing, probing |
| **HDR/DV Tools** | dovi_tool, DDVT (bundled) | Dolby Vision creation & manipulation |
| **Build System** | Xcode (macOS), SPM (cross-platform) | Compilation & packaging |
| **CI/CD** | GitHub Actions | Automated builds, tests, packaging |
| **Auto-Update** | Sparkle 2 (direct distribution); Apple-managed (App Store) | Dual update strategy per distribution channel |

### Third-Party Dependencies

#### Bundled Tools (Direct Distribution only)

| Tool | License | Purpose | App Store Build |
| ---- | ------- | ------- | --------------- |
| **FFmpeg** | LGPL 2.1 / GPL 2+ | Core media encoding/decoding (subprocess) | ❌ Excluded — FFmpegKit used instead |
| **dovi_tool** | MIT | Dolby Vision RPU manipulation | ✅ Included (MIT, no conflict) |
| **DDVT** | MIT | HDR10+ to Dolby Vision conversion | ✅ Included (MIT, no conflict) |
| **MP4Box (GPAC)** | LGPL 2.1 | MP4 muxing/demuxing, DASH segmenting | ⚠️ Evaluate — may use FFmpegKit instead |
| **Bento4** | GPL 2 | MP4/DASH/HLS tooling | ❌ Excluded — use FFmpegKit/AVFoundation |
| **Tesseract OCR** | Apache 2.0 | Bitmap subtitle → text conversion (PGS, VobSub, DVB-SUB) | ✅ Included (Apache 2.0, no conflict) |
| **libmediainfo** | BSD-2-Clause | Detailed media file analysis (HDR profiles, codec metadata, disc content) | ✅ Included (BSD, no conflict) |

#### Swift Package Dependencies

| Package | Purpose | Build Config |
| ------- | ------- | ------------ |
| **swift-argument-parser** | CLI argument parsing | All |
| **swift-log** | Structured logging | All |
| **swift-collections** | Efficient data structures | All |
| **KeychainAccess** | Secure credential storage (macOS) | All |
| **Sparkle** (SPM) | Auto-update framework (macOS) | `DIRECT` only |
| **FFmpegKit** (SPM) | FFmpeg as linked library (LGPL build) | `APP_STORE` only |
| **SwiftSoup** | HTML/XML parsing for manifest validation | All |
| **Yams** | YAML parsing for configuration files | All |
| **ZIPFoundation** | Archive handling for tool bundling | All |

#### Future Dependencies (later milestones)

| Package | Platform | Purpose |
| ------- | -------- | ------- |
| **Soto (AWS SDK)** | All | S3/CloudFront uploads |
| **AzureSDK** | All | Azure Blob uploads |
| **GoogleAPIClientForREST** | All | Google Drive uploads |
| **NIOSSH** | All | SFTP upload support |

### 🔧 Encoding Engine Architecture (Hybrid)

The encoding engine uses a **protocol-based abstraction** so the rest of the application is unaware of which backend is active. The backend is selected at build time via build configuration (`APP_STORE` vs `DIRECT`).

```text
┌─────────────────────────────────────────────────┐
│              EncodingBackend Protocol            │
│  encode() / probe() / cancel() / progress       │
├────────────────────┬────────────────────────────┤
│                    │                            │
│  ┌─────────────────▼──────────┐ ┌──────────────▼──────────────┐
│  │   FFmpegSubprocessBackend  │ │  NativeHybridBackend        │
│  │   (Direct Distribution)    │ │  (App Store Distribution)   │
│  │                            │ │                             │
│  │  • FFmpeg as subprocess    │ │  • AVFoundation primary     │
│  │  • Full GPL codec support  │ │  • VideoToolbox H/W accel   │
│  │  • libx264, libx265        │ │  • FFmpegKit (LGPL) for     │
│  │  • All filters & tools     │ │    codecs AVF doesn't cover │
│  │  • dovi_tool subprocess    │ │  • dovi_tool bundled (MIT)  │
│  │  • No sandbox restrictions │ │  • Sandbox-safe             │
│  └────────────────────────────┘ └─────────────────────────────┘
```

#### Apple App Store Build (`APP_STORE` configuration)

| Codec Need | Engine | Notes |
| ---------- | ------ | ----- |
| H.264 / HEVC encoding | **AVFoundation / VideoToolbox** | Hardware-accelerated, excellent quality on Apple Silicon |
| ProRes encoding | **AVFoundation / VideoToolbox** | Native Apple support |
| VP8, VP9, AV1, Theora | **FFmpegKit** (LGPL linked) | Codecs AVFoundation doesn't support |
| AAC, ALAC audio | **AVFoundation** | Native Apple audio codecs |
| MP3, FLAC, Opus, Vorbis | **FFmpegKit** (LGPL linked) | Non-Apple audio codecs |
| Dolby AC-3, E-AC-3, TrueHD | **FFmpegKit** (LGPL linked) | FFmpeg's built-in Dolby encoders |
| DTS family | **FFmpegKit** (LGPL linked) | FFmpeg's built-in DTS support |
| Media probing | **AVFoundation** + **FFmpegKit** | Combined for full format coverage |
| Dolby Vision RPU | **dovi_tool** (bundled, MIT) | Signed helper tool in app bundle |

#### Apple Direct Distribution Build (`DIRECT` configuration)

| Codec Need | Engine | Notes |
| ---------- | ------ | ----- |
| H.264 (software) | **FFmpeg subprocess** (libx264) | Best-in-class software encoder, full CRF tuning |
| HEVC (software) | **FFmpeg subprocess** (libx265) | Best-in-class software encoder |
| H.264 / HEVC (hardware) | **FFmpeg subprocess** + VideoToolbox | User can choose software vs hardware |
| All other codecs | **FFmpeg subprocess** | Full GPL build, all codecs & filters |
| AVFoundation | **Also available** | User preference — can use either backend |
| Dolby Vision RPU | **dovi_tool subprocess** | No sandbox restrictions |

#### Sandbox & File Access Strategy (App Store Build)

The App Store build uses a **three-tier file access model**, giving the user control over how much access they grant:

##### Tier 1 — User-Selected Access (Default, zero-config)

The user picks files/folders via standard macOS open/save panels (`NSOpenPanel` / `NSSavePanel`). The app receives access only to what the user explicitly selects. Works immediately with no setup.

##### Tier 2 — Security-Scoped Bookmarks (Persistent, recommended)

When the user selects a folder (e.g., their media library or output directory), the app stores a **security-scoped bookmark**. Access is retained across app launches — no repeated permission dialogs. Ideal for batch processing workflows.

##### Tier 3 — Full Disk Access (User-granted via System Settings, optional)

For power users who want unrestricted file access, the app can detect whether Full Disk Access has been granted and offer an in-app prompt directing the user to **System Settings → Privacy & Security → Full Disk Access**. The app cannot request this programmatically — the user must enable it manually at the OS level.

**Recommended UX Flow:**

| Scenario | Behaviour |
| -------- | --------- |
| First launch | Prompt user to select input and output folders via file pickers; store as security-scoped bookmarks |
| Settings page | Show saved folder bookmarks with "Add Folder" and "Change" options |
| Optional full access | In Settings, offer "Grant Full Disk Access" with explanation and deep-link to System Settings pane |
| Access denied fallback | If the app attempts to access a file outside bookmarked folders, show a file picker rather than failing silently |

**Required Entitlements:**

| Entitlement | Purpose |
| ----------- | ------- |
| `com.apple.security.files.user-selected.read-write` | Tier 1 — read/write files chosen via open/save panels |
| `com.apple.security.files.bookmarks.app-scope` | Tier 2 — persist folder access across app launches |
| `com.apple.security.files.bookmarks.document-scope` | Tier 2 — persist per-document file access |
| `com.apple.security.network.client` | Outgoing network for cloud uploads & update checks |

> 📌 **Batch processing:** With Tier 2 (security-scoped bookmarks), the user selects input and output folders **once**. The app retains access across sessions — no repeated permission dialogs. Tier 3 (Full Disk Access) eliminates all file restrictions entirely but requires user action in System Settings.

### Application Architecture

```text
┌──────────────────────────────────────────────────────────┐
│                    MeedyaConverter                        │
├──────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  macOS App    │  │  Windows App  │  │  Linux App    │  │
│  │  (SwiftUI)    │  │  (WinUI 3)   │  │  (GTK4)       │  │
│  └──────┬────────┘  └──────┬───────┘  └──────┬────────┘  │
│         │                  │                  │           │
│  ┌──────┴──────────────────┴──────────────────┴────────┐ │
│  │                 meedya-convert                       │ │
│  │              (CLI — ArgumentParser)                  │ │
│  └──────────────────────┬──────────────────────────────┘ │
│                         │                                │
│  ┌──────────────────────┴──────────────────────────────┐ │
│  │                ConverterEngine                       │ │
│  │                                                      │ │
│  │  ┌──────────────────────────────────────────────┐    │ │
│  │  │         EncodingBackend (Protocol)            │    │ │
│  │  │  ┌─────────────────┐ ┌─────────────────────┐ │    │ │
│  │  │  │ FFmpeg Subprocess│ │ AVFoundation/       │ │    │ │
│  │  │  │ (Direct Dist.)  │ │ FFmpegKit Hybrid    │ │    │ │
│  │  │  │                 │ │ (App Store)         │ │    │ │
│  │  │  └─────────────────┘ └─────────────────────┘ │    │ │
│  │  └──────────────────────────────────────────────┘    │ │
│  │                                                      │ │
│  │  ┌──────────┐ ┌──────────┐ ┌────────────────────┐   │ │
│  │  │ Encoding │ │ Audio    │ │ Manifest Generator │   │ │
│  │  │ Profiles │ │ Process  │ │ (HLS/DASH)         │   │ │
│  │  ├──────────┤ ├──────────┤ ├────────────────────┤   │ │
│  │  │ Media    │ │ Subtitle │ │ Cloud Upload       │   │ │
│  │  │ Analyzer │ │ Process  │ │ Manager            │   │ │
│  │  ├──────────┤ ├──────────┤ ├────────────────────┤   │ │
│  │  │ HDR /    │ │ Crypto / │ │ Reports /          │   │ │
│  │  │ DolbyVis │ │ DRM      │ │ Analytics          │   │ │
│  │  └──────────┘ └──────────┘ └────────────────────┘   │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Directory Structure (New Implementation)

```text
MeedyaConverter/
├── Package.swift                    # SPM package definition
├── Sources/
│   ├── ConverterEngine/             # Cross-platform core engine
│   │   ├── Backend/                 # Encoding backend abstraction
│   │   │   ├── EncodingBackend.swift        # Protocol definition
│   │   │   ├── FFmpegSubprocessBackend.swift # Direct distribution backend
│   │   │   ├── NativeHybridBackend.swift     # App Store backend (AVF + FFmpegKit)
│   │   │   └── BackendFactory.swift          # Build-config-aware backend selection
│   │   ├── FFmpeg/                  # FFmpeg integration (subprocess mode)
│   │   │   ├── FFmpegController.swift
│   │   │   ├── FFmpegArgumentBuilder.swift
│   │   │   ├── FFmpegProbe.swift
│   │   │   └── FFmpegBundleManager.swift
│   │   ├── Native/                  # AVFoundation/VideoToolbox integration
│   │   │   ├── AVFoundationEncoder.swift
│   │   │   ├── VideoToolboxEncoder.swift
│   │   │   └── AVFoundationProbe.swift
│   │   ├── Encoding/               # Encoding profiles & job management
│   │   │   ├── EncodingProfile.swift
│   │   │   ├── EncodingProfileStore.swift
│   │   │   ├── EncodingJob.swift
│   │   │   └── EncodingQueue.swift
│   │   ├── Manifest/               # HLS/DASH manifest generation
│   │   │   ├── ManifestGenerator.swift
│   │   │   ├── HLSManifestWriter.swift
│   │   │   ├── DASHManifestWriter.swift
│   │   │   └── ManifestValidator.swift
│   │   ├── Audio/                   # Audio processing
│   │   │   ├── AudioNormalizer.swift
│   │   │   ├── ReplayGainAnalyzer.swift
│   │   │   └── AudioMixdown.swift
│   │   ├── Subtitles/               # Subtitle/CC handling
│   │   │   ├── SubtitleProcessor.swift
│   │   │   ├── ClosedCaptionHandler.swift
│   │   │   └── SubtitleConverter.swift
│   │   ├── HDR/                     # HDR & Dolby Vision
│   │   │   ├── HDRAnalyzer.swift
│   │   │   ├── DoviToolController.swift
│   │   │   └── DDVTController.swift
│   │   ├── Crypto/                  # Encryption & DRM
│   │   │   ├── AES128Encryptor.swift
│   │   │   └── KeyManager.swift
│   │   ├── Cloud/                   # Cloud upload services
│   │   │   ├── CloudUploadProtocol.swift
│   │   │   ├── S3Uploader.swift
│   │   │   ├── AzureUploader.swift
│   │   │   └── ... (other providers)
│   │   ├── Models/                  # Shared data models
│   │   │   ├── MediaFile.swift
│   │   │   ├── MediaStream.swift
│   │   │   ├── VideoCodec.swift
│   │   │   ├── AudioCodec.swift
│   │   │   ├── ContainerFormat.swift
│   │   │   └── SubtitleFormat.swift
│   │   ├── Reports/                 # Post-encoding reports
│   │   │   ├── EncodingReport.swift
│   │   │   └── ReportGenerator.swift
│   │   └── Utilities/               # Shared utilities
│   │       ├── Logger.swift
│   │       ├── ProcessRunner.swift
│   │       └── FileManager+Extensions.swift
│   │
│   ├── meedya-convert/              # CLI executable target
│   │   ├── MeedyaConvert.swift
│   │   ├── Commands/
│   │   │   ├── EncodeCommand.swift
│   │   │   ├── ProbeCommand.swift
│   │   │   ├── ProfileCommand.swift
│   │   │   └── ManifestCommand.swift
│   │   └── CLIOutput.swift
│   │
│   └── MeedyaConverter/             # macOS SwiftUI app target
│       ├── MeedyaConverterApp.swift
│       ├── Views/
│       │   ├── ContentView.swift
│       │   ├── SourceFileView.swift
│       │   ├── EncodingProfileView.swift
│       │   ├── OutputSettingsView.swift
│       │   ├── JobQueueView.swift
│       │   ├── ManifestGeneratorView.swift
│       │   ├── SettingsView.swift
│       │   └── HelpView.swift
│       ├── ViewModels/
│       │   ├── SourceFileViewModel.swift
│       │   ├── EncodingViewModel.swift
│       │   ├── JobQueueViewModel.swift
│       │   └── SettingsViewModel.swift
│       ├── Components/
│       │   ├── StreamMetadataEditor.swift
│       │   ├── CodecPicker.swift
│       │   ├── BitrateSlider.swift
│       │   └── ProgressIndicator.swift
│       └── Resources/
│           ├── Assets.xcassets
│           └── Localizable.strings
│
├── Tests/
│   ├── ConverterEngineTests/
│   └── MeedyaConvertTests/
│
├── Resources/
│   ├── Profiles/                    # Built-in encoding presets (JSON)
│   └── Help/                        # In-app help content (Markdown)
│
├── Tools/                           # Bundled third-party executables (direct dist.)
│   └── .gitkeep
│
├── help/                            # User documentation
│   ├── getting-started.md
│   ├── encoding-guide.md
│   ├── adaptive-streaming.md
│   ├── cli-reference.md
│   ├── troubleshooting.md
│   └── faq.md
│
├── .github/
│   ├── workflows/
│   │   ├── build.yml               # CI build & test
│   │   ├── release.yml             # Automated packaging & release
│   │   └── lint.yml                # Code quality checks
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
│
├── branding/                        # Brand assets
├── docs/                            # Extended documentation
├── .claude/                         # Claude AI context & memory
│
├── README.md
├── Project_Plan.md
├── PROJECT_STATUS.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

---

## 🎯 Milestones & Phases

> **Development Order:** Phases are numbered by feature area. The development sequence follows a logical build order — some later-numbered phases start before earlier ones complete. Release gates define what's needed for each milestone.

### Release Gates

| Gate | Phases Required | Description |
| ---- | --------------- | ----------- |
| **Alpha 0.1** | 0, 1, 2 | Core engine + basic macOS app — first testable build |
| **Alpha 0.2** | 3, 4 | Essential codecs, passthrough, HDR + CLI tool — real-world usable |
| **Beta 0.5** | 5, 6 | Subtitles, audio normalization, HLS/DASH streaming |
| **Beta 0.7** | 7, 8 | Extended formats (spatial/3D/IMAX), advanced audio (upmixing/channel analysis) |
| **RC 0.9** | 9 | Professional features (VMAF, watch folders, AI upscaling) |
| **Ongoing** | 16 | Polish & Distribution — runs throughout development, not tied to a specific release |
| **v1.1+** | 10, 11 | Optical disc ripping and authoring |
| **v1.3+** | 12 | Cloud uploads |
| **v1.5+** | 15 | Media metadata lookup |
| **v2.0** | 13, 14 | Windows and Linux platform expansion |
| **v3.0+** | 17 | Image conversion (future version) |

---

### Phase 0: Project Setup & Architecture ⚙️ — COMPLETE

**Goal:** Establish project foundation, documentation, and CI/CD pipeline.

| # | Task | Details |
| - | ---- | ------- |
| 0.1 | Project scaffolding | Create SPM Package.swift, directory structure, initial targets |
| 0.2 | Documentation | README.md, Project_Plan.md, PROJECT_STATUS.md, CHANGELOG.md |
| 0.3 | .gitignore | Comprehensive ignore rules for macOS, Windows, Linux, Xcode, VSCode |
| 0.4 | GitHub Actions CI | Build workflow for macOS (Swift 6.3), linting, test runner |
| 0.5 | GitHub Project Board | Set up project tracking with milestones & labels |
| 0.6 | License file | Proprietary license with third-party acknowledgments |
| 0.7 | Claude context | Save project brief, requirements, and context to .claude/ |
| 0.8 | Clean up legacy code | Remove prior implementation files no longer needed |

---

### Phase 1: Core Engine Foundation 🔧 — Alpha 0.1

**Goal:** Build the cross-platform core library with FFmpeg integration.

| # | Task | Details |
| - | ---- | ------- |
| 1.1 | FFmpeg bundle manager | Locate/download FFmpeg binary, version detection, path management |
| 1.2 | FFmpeg process controller | Launch, monitor, pause/resume/stop FFmpeg processes |
| 1.3 | Media file probing | Use `ffprobe` AND `libmediainfo` (BSD-2-Clause) to analyze input files — streams, codecs, metadata. MediaInfo provides more detailed HDR/DV profile info, commercial codec metadata, and disc-ripped content analysis. Dual-probe approach: ffprobe for encoding decisions, MediaInfo for detailed display |
| 1.4 | Data models | MediaFile, MediaStream, codec enums, container format enums |
| 1.5 | FFmpeg argument builder | Generate FFmpeg CLI arguments from encoding profiles |
| 1.6 | Encoding profile system | Profile model, built-in presets, JSON serialization, CRUD |
| 1.7 | Encoding job & queue | Job model, queue management, progress tracking |
| 1.7a | Temporary file management | User-configurable temp directory for all intermediary files (demuxed streams, multi-pass logs, segments, etc.). Default: system temp. Per-job cleanup: auto-delete all intermediary files for a specific encode when that encode completes (success or failure). Retain only final output. Disk space monitoring with warning when temp drive is low |
| 1.8 | Basic video encoding | Single-file video encoding via FFmpeg with progress reporting |
| 1.9 | Basic audio encoding | Single-file audio encoding (audio-only files supported) |
| 1.10 | Unit tests | Tests for argument builder, profile serialization, models |
| 1.11 | Feature gating system | Lightweight capability/tier system to allow features to be gated behind product tiers (free/pro/studio). Protocol-based: `FeatureGate.isAvailable(:)` and `FeatureGate.requiredTier(for:)`. UI shows locked features with upgrade prompt or hides them (configurable). Tier definitions and pricing decided later — architecture only at this stage. No DRM, just clean capability checks |

---

### Phase 2: macOS SwiftUI Application (MVP) 🖥️ — Alpha 0.1

**Goal:** Deliver a functional macOS app for basic media conversion.

| # | Task | Details |
| - | ---- | ------- |
| 2.1 | Xcode project setup | macOS app target importing ConverterEngine as local SPM package |
| 2.2 | App shell & navigation | Main window, sidebar navigation, toolbar |
| 2.3 | Source file import | Drag-and-drop & file picker, media info display |
| 2.4 | Stream inspector | Display all video/audio/subtitle streams with metadata |
| 2.5 | Output settings UI | Container, codec, quality, output path selection |
| 2.6 | Profile management UI | Create, edit, delete, import/export profiles |
| 2.7 | Encoding workflow | Start/pause/stop encoding, progress bar, ETA |
| 2.8 | Job queue UI | Queue multiple files, batch processing |
| 2.9 | Unified activity log | Single log panel combining structured application events (encoding lifecycle, settings changes, filter operations, HDR decisions, audio analysis, warnings, errors, progress) AND raw FFmpeg/tool output. Filterable by category (app events, FFmpeg output, warnings, errors). Timestamped, searchable, colour-coded by severity, exportable (text/JSON). Persists per-job for post-encode review. Real-time updates during encoding |
| 2.10 | Dark/light mode | Full support, system-aware + manual toggle |
| 2.11 | App icon & branding | Application icon, about screen |
| 2.12 | Accessibility | VoiceOver support, keyboard navigation, Dynamic Type |
| 2.13 | Settings & preferences | Application settings with secure API key management |
| 2.14 | In-app help system | Native help viewer with searchable documentation |
| 2.15 | Job completion notifications | macOS notifications, Dynamic Island activity, menu bar status |
| 2.16 | Code signing setup | Developer ID signing with Apple Developer Program — set up from first build |
| 2.17 | Notarization setup | Apple notarization for Gatekeeper — configure for all builds from start |

---

### Phase 3: Essential Encoding & Passthrough 🎬 — Alpha 0.2

**Goal:** Implement key differentiators over HandBrake.

| # | Task | Details |
| - | ---- | ------- |
| 3.1 | Video passthrough | Copy video codec without re-encoding (`-c:v copy`) |
| 3.2 | Audio passthrough | Copy audio codec without re-encoding (`-c:a copy`) |
| 3.3 | Subtitle passthrough | Copy subtitles to output if container supports format |
| 3.4 | Multi-video stream | Handle input files with multiple video streams |
| 3.5 | Per-stream encoding settings | Different codec/quality per video stream |
| 3.6 | Stream metadata editor | Title, language (BCP 47), default/forced/enabled flags |
| 3.7 | HDR preservation | Detect & preserve HDR10, HDR10+, HLG metadata |
| 3.8 | Dolby Vision support | dovi_tool integration for DV RPU handling |
| 3.9 | HDR10+ → DV auto-conversion | DDVT integration for automatic Dolby Vision creation |
| 3.9a | HLG → DV auto-conversion | Generate Dolby Vision RPU from HLG-only content for wider device compatibility. Target DV Profile 8.4 (HLG base). Via dovi_tool content analysis. Toggle: enabled by default. If tooling not yet mature, keep for future implementation |
| 3.9b | HDR → SDR tone mapping (explicit) | Convert any HDR format (PQ/HDR10/HDR10+/Dolby Vision/HLG) to standard SDR with correct colour space conversion (BT.2020 → BT.709, 10-bit → 8-bit). Configurable tone mapping algorithm (Hable, Reinhard, Mobius, BT.2390). For DV sources, flatten via dovi_tool → PQ → tone map. Settable per-encode and per-video-track. Adjustable peak brightness, desat strength, and tone curve. Preview tone-mapped output before encoding |
| 3.9c | HDR → SDR auto-trigger | Automatically engage tone mapping and colour space conversion when user selects HDR-incompatible output settings (BT.709 colour space, 8-bit depth, H.264, or other non-HDR codec/container). Prevents producing broken files with HDR flags but SDR encoding. UI notification explains what happened with option to revert. Reverses automatically if user switches back to HDR-compatible settings. Per-video-track aware |
| 3.10 | Hardware encoding | VideoToolbox (macOS), with codec capability detection |
| 3.11 | All output containers | MP4, M4V, M4A, M4B, MKV, MKA, MOV, WebM |
| 3.12 | All video codecs | ProRes, MPEG-2/4, H.264, H.265, VP8/9, AV1, DNxHR, Theora, H.266/VVC (when encoder matures), AV2 (future — still in research) |
| 3.13 | All audio codecs | PCM, AAC family (incl. xHE-AAC/USAC), Dolby family, DTS family, MP3/2, FLAC, ALAC, Opus, Vorbis |
| 3.14 | Automatic black bar cropping | Detect and auto-crop letterboxing, pillarboxing, and postage-stamp black bars using FFmpeg `cropdetect` filter. Enabled by default at app level. Toggleable at app-wide, per-encode, and per-video-stream level. Preview crop before encoding. Support for non-standard aspect ratios and partial bars |
| 3.15 | Built-in encoding profiles | Comprehensive preset library with optimised CRF/QP/bitrate values for all resolution/codec/HDR combinations. Separate profiles for VBR (file-based) and CVBR (adaptive streaming). See Resources/Profiles/PROFILE_SPEC.md for full matrix |
| 3.16a | Same-format codec metadata preservation | When re-encoding within the same audio codec (e.g., AC-3 → AC-3 at different bitrate), preserve all codec-specific metadata from the original stream: dialog normalization, dynamic range, surround mode flags, copyright, room type, matrix encoding flags. Only applies when staying within the same codec family |
| 3.16b | Dynamic aspect ratio metadata | Preserve dynamic aspect ratio switching flags (AFD, clean aperture/clap atoms, mid-stream DAR/SAR changes) when destination format supports them. Detect and display in stream inspector. Interact with auto-crop to inform cropping decisions |

---

### Phase 4: CLI Tool 💻 — Alpha 0.2

**Goal:** Full-featured command-line interface for scripting and automation.

| # | Task | Details |
| - | ---- | ------- |
| 4.1 | CLI executable | SwiftArgumentParser-based CLI tool |
| 4.2 | `encode` command | Encode media files with profile/custom settings |
| 4.3 | `probe` command | Inspect media file streams and metadata |
| 4.4 | `profile` command | List, create, export, import encoding profiles |
| 4.5 | `manifest` command | Generate HLS/DASH manifests |
| 4.6 | `validate` command | Validate manifest files |
| 4.7 | JSON job files | Accept JSON-based job definitions for complex workflows |
| 4.8 | Progress output | Machine-readable progress (JSON) and human-readable output |
| 4.9 | Exit codes & error handling | Proper exit codes for scripting integration |
| 4.10 | CLI API documentation | Comprehensive man-page style docs + generated reference |

---

### Phase 5: Subtitles & Core Audio Processing 🔊 — Beta 0.5

**Goal:** Complete audio normalization and subtitle/CC support.

| # | Task | Details |
| - | ---- | ------- |
| 5.1 | EBU R128 normalization | Loudness normalization to target LUFS |
| 5.2 | ReplayGain analysis | Per-track and album-mode gain calculation |
| 5.3 | Peak limiting | True peak limiting to specified dBTP |
| 5.4 | Audio-only encoding | Support encoding audio files without video |
| 5.5 | CC608 / CEA-708 (EIA-708) handling | Extract, preserve, and embed closed captions. CEA-708 (formerly EIA-708) is the current standard; CC608 is legacy but still common |
| 5.5a | Teletext subtitles | Extract, convert, and passthrough EBU Teletext / DVB Teletext subtitles. Common in European broadcast recordings. FFmpeg native support |
| 5.6 | Subtitle format conversion | Convert between SRT, TTML, WebVTT, SSA/ASS, SAMI, LRC |
| 5.7 | DVB-SUB support | Bitmap subtitle handling |
| 5.8 | PGS (Blu-ray subtitles) | Extract, passthrough, and convert Presentation Graphic Stream bitmap subtitles |
| 5.9 | VobSub (DVD subtitles) | Extract, passthrough, and convert DVD bitmap subtitles (.sub/.idx) |
| 5.10 | Bitmap → text OCR conversion | Convert PGS, VobSub, DVB-SUB bitmap subtitles to SRT, TTML, WebVTT, ASS via Tesseract OCR; preserve formatting, colours, and positioning where target format supports it |
| 5.11 | Rich SRT formatting | Preserve formatting tags in SRT files |
| 5.12 | Enhanced LRC & Walaoke | Lyrics file format support |

---

### Phase 6: Adaptive Streaming (HLS / MPEG-DASH) 📡 — Beta 0.5

**Goal:** Enable multi-bitrate streaming content preparation.

| # | Task | Details |
| - | ---- | ------- |
| 6.1 | ABR encoding ladder | Encode source into multiple bitrate variants |
| 6.2 | Separate audio/video output | Split streams into individual segment files |
| 6.3 | HLS manifest generation | Master .m3u8 and variant playlists |
| 6.4 | MPEG-DASH manifest generation | MPD file with adaptation sets |
| 6.5 | Multi-language audio tracks | Encode all audio tracks with BCP 47 language codes in filenames |
| 6.6 | AES-128 encryption (HLS) | Key generation, encryption, key delivery URL configuration |
| 6.7 | Manifest validation | Validate generated manifests for spec compliance |
| 6.8 | Keyframe alignment | Ensure consistent keyframe intervals across variants |
| 6.9 | Streaming presets | Apple HLS, MPEG-DASH common, YouTube-like ABR ladder profiles |
| 6.10 | Thumbnail sprite sheets | Generate preview sprites for video scrubbing (VideoJS, Shaka) |

---

### Phase 7: Extended Formats & Spatial Audio 🌐 — Beta 0.7

**Goal:** Support spatial/immersive audio, 3D video, and extended codec/container coverage.

| # | Task | Details |
| - | ---- | ------- |
| 7.1 | Dolby MAT support | Dolby Metadata-enhanced Audio Transmission — lossless TrueHD/Atmos passthrough wrapper for HDMI; decode/re-wrap MAT containers |
| 7.2 | Eclipsa Audio (IAMF) | Google's Immersive Audio Model and Formats — decode, encode, and convert via open-source libiamf (BSD license) |
| 7.3 | MPEG-H 3D Audio | Decode and convert MPEG-H Audio (ATSC 3.0, DVB, Korean broadcast). Open-source library availability limited — implement when tooling matures |
| 7.4 | 360 Reality Audio | Sony's object-based spatial audio (built on MPEG-H). Proprietary SDK — implement when open tooling available or via MPEG-H support |
| 7.5 | ASAF (Apple Spatial Audio Format) | Apple's spatial audio format for Apple Music. Proprietary — monitor for public API availability; may be accessible via AVFoundation on macOS |
| 7.6 | Ambisonics (FOA/HOA) | First and Higher Order Ambisonics encoding/decoding — FFmpeg supports ambisonics channel layouts. Convert to/from channel-based and binaural |
| 7.7 | Auro-3D | Auro Technologies immersive audio (height channels). Limited open tooling — future implementation when available |
| 7.8 | NHK 22.2 | Japanese broadcast 22.2 channel layout (Super Hi-Vision). FFmpeg supports channel layout; encode as multichannel PCM/FLAC |
| 7.9 | AC-4 with A-JOC | Dolby AC-4 immersive variant with Audio Joint Object Coding. FFmpeg AC-4 decoder (limited); full support needs Dolby tools |
| 7.10 | Additional audio codecs | DSD (DFF/DSF), AIFF/AIFF-C, CAF, W64/RF64, WavPack, MQA (decode), Musepack, APE, TTA, WMA/WMA Pro (decode), ATRAC family (decode), Speex |
| 7.11 | Additional audio containers | Support AIFF, CAF (Core Audio Format), W64 (Sony Wave64), RF64 (EBU, for files > 4GB) as input/output containers |
| 7.12 | MV-HEVC (Multiview HEVC) | 3D/stereoscopic video encoding & passthrough — Apple Vision Pro spatial video, Meta Quest VR, Google VR. VideoToolbox native on Apple Silicon |
| 7.13 | MV-H264 (Stereo High Profile) | H.264 multiview extension for stereoscopic 3D — left/right eye encoding with inter-view prediction |
| 7.14 | 3D format conversion | Convert between 3D formats: MVC (Blu-ray 3D) → MV-HEVC, side-by-side ↔ top-bottom ↔ multiview, frame packing |
| 7.15 | 3D metadata handling | Frame packing arrangement, stereo mode flags, view identification for VR/3D players |
| 7.16 | MP3surround & mp3PRO/mp3HD | Fraunhofer MPEG Surround extension (backward-compatible surround in MP3) and mp3PRO (SBR-enhanced) / mp3HD (lossless extension) |
| 7.17 | IMAX Enhanced (DTS:X IMAX) | DTS:X with IMAX-specific metadata and mastering profile; IMAX-tuned Dolby Vision/HDR10+ video mastering detection and preservation |
| 7.18 | Additional video codecs | FFV1 (lossless archival), CineForm (GoPro intermediate), VC-1/WMV (Microsoft, found on Blu-ray), JPEG 2000 (DCP/cinema) |
| 7.19 | Additional containers | MXF (broadcast/cinema), AVI (legacy), FLV (Flash), MPEG-TS (.ts, broadcast/IPTV), MPEG-PS (.mpg, DVD), 3GP/3G2 (mobile), OGG/OGM (Xiph), DCP (Digital Cinema Package) |
| 7.20 | Additional subtitle formats | EBU STL (European broadcast), SCC (Scenarist Closed Caption), MCC (MacCaption) |
| 7.21 | Color space conversion | BT.601 ↔ BT.709 ↔ BT.2020 ↔ DCI-P3; HDR tone mapping; wide color gamut handling |
| 7.22 | Platform-specific format support | Include format support on platforms where libraries are available; regularly check for new library availability on other platforms. Document platform-specific limitations |

---

### Phase 8: Advanced Audio Processing 🎧 — Beta 0.7

**Goal:** Advanced surround upmixing, matrix encoding, and channel content analysis.

| # | Task | Details |
| - | ---- | ------- |
| 8.1 | Matrix encoding on downmix | When downmixing surround to stereo (user-selected or analysis-suggested), offer option to embed matrix encoding metadata (Dolby Surround, Pro Logic II, DTS Neo:6 flags) so AVR systems can unfold surround from the stereo signal. Support matrix metadata in all applicable output formats (AC-3, AAC, PCM, FLAC, ALAC, MP3). Default: embed Pro Logic II metadata when downmixing 5.1+ to stereo |
| 8.2 | Matrix encoding preservation on transcode | When converting between formats that both support matrix encoding, preserve matrix metadata in the output. E.g., AC-3 with Pro Logic II → AAC should carry matrix_mixdown_idx. App-wide setting (default: enabled), configurable per audio track and per-encode. Document which matrix methods are supported in which output formats |
| 8.3 | Virtual surround upmixing | Algorithmically upmix stereo audio to discrete 5.1/7.1 multichannel PCM, then encode to native Dolby (AC-3/E-AC-3) or DTS formats. Methods: FFmpeg `surround` filter (frequency-domain, recommended), pan matrix, ambisonic encode/decode, Haas effect, sofalizer (binaural). NOT available for mono sources (disable/hide in UI). Never auto-enabled — opt-in per audio track only. Smart defaults per method + target layout based on sound engineering best practices. Audio preview before encoding |
| 8.4 | Matrix-guided surround expansion | When source has matrix encoding metadata (Pro Logic II, DTS Neo:6, Dolby Surround, PL IIx, Dolby EX, DTS ES Matrix), use that information for high-quality decode to discrete 5.1/6.1/7.1 — significantly better than blind algorithmic upmix. This option ONLY appears in UI when matrix metadata is detected. When user enables upmix and matrix metadata is present, matrix decode is **pre-selected as default method** with note explaining it reconstructs the intended mix. User can switch to algorithmic methods. Output can be encoded to native Dolby (AC-3 5.1, E-AC-3 up to 7.1), DTS, or AAC multichannel formats |
| 8.5 | Audio channel content analysis | Multi-method analysis (per-channel levels, cross-correlation, spectral analysis, phase detection, energy distribution) to detect when declared channel config doesn't match actual content — applies to any channel count (7.1.4, 7.1, 5.1, stereo, etc.). Detect all matrix encoding metadata (Dolby Surround/Pro Logic/Pro Logic II/Digital EX, DTS ES Matrix/Neo:6/Neural:X, Dolby Atmos JOC, Auro-3D, MPEG Surround) to avoid false positives. Auto-suggest optimal output channel config. Toggle: enabled by default (app-wide + per-encode override). UI info banner when config is adjusted with explanation and revert option |

---

### Phase 9: Professional Features ✨ — RC 0.9

**Goal:** Premium features for professional workflows.

| # | Task | Details |
| - | ---- | ------- |
| 9.1 | Multipass encoding | Two-pass and multi-pass encoding with toggle |
| 9.2 | Forensic watermarking | Invisible watermark embedding (toggle) |
| 9.3 | Encoding reports | Post-encode report: bitrate ladder, track summary, manifest checks |
| 9.4 | Visual encoding graphs | Real-time bitrate/quality graphs during encoding |
| 9.5 | Auto metadata tagging | Automatic language detection and metadata population |
| 9.6 | Update checker | Sparkle 2 for self-distributed builds; conditionally excluded from App Store builds (App Store uses Apple's native update mechanism) |
| 9.7 | Watch folder / batch automation | Monitor designated folders for new files, auto-encode using selected profile. Configurable rules per folder |
| 9.8 | A/B comparison viewer | Side-by-side or toggle comparison of source vs encoded output with synced playback |
| 9.9 | VMAF / SSIM / PSNR quality metrics | Objective quality measurement of encoded output vs source. Display scores and per-frame graphs |
| 9.10 | Scene detection & auto-chaptering | Detect scene boundaries in video; auto-generate chapter markers. Uses FFmpeg scene detection filter |
| 9.11 | Smart crop & letterbox detection | Auto-detect letterboxing/pillarboxing and offer to crop. Detect content aspect ratio |
| 9.12 | AI upscaling | Resolution enhancement using Real-ESRGAN or similar models. Toggle, with quality/speed presets |
| 9.13 | Content-aware encoding | Adjust bitrate/CRF dynamically based on scene complexity. Higher bitrate for complex scenes, lower for static |
| 9.14 | DCP creation | Digital Cinema Package output (JPEG 2000 video + PCM audio in MXF) for theatrical distribution |
| 9.15 | Audio fingerprinting | AcoustID / Chromaprint integration for content identification |
| 9.16 | Media server notifications | Notify Plex, Jellyfin, Emby of new content after encoding completes |
| 9.17 | Preset sharing | Export/import encoding presets as shareable files. Optional preset library/marketplace |

---

### Phase 10: Optical Disc Ripping 💿 — v1.1+

**Goal:** Read and extract content from optical disc media — physical discs, disc images, and extracted disc structures.

| # | Task | Details |
| - | ---- | ------- |
| 10.1 | Disc reading framework | Unified API for physical discs, ISO/IMG images, and local disc structures |
| 10.2 | Audio CD ripping | Lossless extraction via libcdio/cdparanoia with error correction; CDDB/MusicBrainz metadata lookup |
| 10.3 | SACD ripping | DSD audio extraction (requires compatible hardware/firmware); conversion to PCM/FLAC/DSF |
| 10.4 | CD-MIDI extraction | MIDI data extraction from Red Book extension tracks |
| 10.5 | Video CD / Super Video CD | MPEG-1/2 extraction via FFmpeg + libcdio |
| 10.6 | Enhanced CD (eCD/CD+) | Audio track ripping + data session handling |
| 10.7 | DVD-Video ripping | Title/chapter structure via libdvdread + libdvdnav; subtitle extraction; multi-angle support |
| 10.8 | HD DVD ripping | Content extraction via FFmpeg; limited format (largely defunct) |
| 10.9 | Blu-ray ripping | Title/chapter/playlist via libbluray; audio (Atmos/DTS:X), subtitle extraction |
| 10.10 | Blu-ray 3D ripping | Stereoscopic MVC stream extraction; conversion to MV-HEVC (Apple Vision Pro/Meta Quest/Google VR), side-by-side, or top-bottom |
| 10.11 | Ultra HD Blu-ray ripping | 4K HDR content with HDR10/HDR10+/Dolby Vision metadata; Dolby Atmos audio |
| 10.12 | DVD Audio ripping | DVD-Audio disc extraction; MLP (Meridian Lossless Packing) and PCM audio tracks |
| 10.13 | DTS CD ripping | Extract DTS-encoded audio from DTS CDs |
| 10.14 | Mixed Mode CD ripping | Handle CDs with both audio tracks and data sessions |
| 10.15 | HDCD ripping | High Definition Compatible Digital — extract with HDCD decoding to 20-bit via FFmpeg's hdcd filter |
| 10.16 | Blu-spec CD / SHM-CD ripping | Standard CD ripping with metadata indicating audiophile pressing format |
| 10.17 | CD+G ripping | Extract audio and CD+Graphics subchannel data (karaoke) |
| 10.18 | Hybrid SACD ripping | Extract both SACD (DSD) layer and CD (PCM) layer |
| 10.19 | SHM-SACD ripping | Super High Material SACD — DSD extraction with pressing format metadata |
| 10.20 | DualDisc ripping | Handle DVD-side and CD-side content extraction |
| 10.21 | CDV (CD Video) ripping | Extract audio tracks and video segments from CD Video discs |
| 10.22 | Multi-angle → MV-HEVC/MV-H264 | Extract multi-angle DVD/Blu-ray streams and encode as MV-HEVC or MV-H264 multiview |
| 10.23 | Chapter detection & naming | Auto-detect chapter markers; allow user naming; embed in output container |
| 10.24 | Disc image support | Read from ISO, IMG, BIN/CUE, MDF/MDS, NRG disc image formats |
| 10.25 | Disc structure on local drive | Read extracted VIDEO_TS (DVD), BDMV (Blu-ray), DVDAUDIO (DVD-A) folder structures from local storage |
| 10.26 | Ripping UI | Disc browser with title/chapter/track selection, preview, metadata editing |
| 10.27 | Batch disc ripping | Queue multiple titles/chapters for sequential ripping and encoding |

> ⚠️ **DRM/Encryption Note:** Commercial DVDs use CSS encryption; Blu-rays use AACS/BD+. Reading encrypted discs requires decryption libraries (libdvdcss for DVD, libaacs/libbdplus for Blu-ray). The legality of circumventing copy protection varies by jurisdiction. MeedyaConverter will include support for these libraries but will clearly document the legal considerations. Users are responsible for compliance with local laws.
>
> 📌 **Bundled disc tools:** libcdio, cdparanoia (GPL), libdvdread, libdvdnav, libbluray, libdvdaudio, sacd_extract, cdgtools. These are invoked as subprocesses or linked per distribution build configuration (matching the hybrid engine approach).

---

### Phase 11: Disc Image Creation & Burning 💽 — v1.2+

**Goal:** Create disc images from encoded content, and burn directly to physical media with compatible drives.

| # | Task | Details |
| - | ---- | ------- |
| 11.1 | Disc authoring framework | Unified API for disc image creation and physical disc burning |
| 11.2 | Audio CD authoring | Create Red Book audio CDs from encoded audio files; CD-TEXT metadata; pre-gap/post-gap control |
| 11.3 | SACD image creation | Create SACD ISO images with DSD audio content |
| 11.4 | CD-MIDI authoring | Create CDs with MIDI data tracks |
| 11.5 | Video CD / Super Video CD authoring | Create VCD/SVCD-compliant disc structures with MPEG-1/2 video |
| 11.6 | Enhanced CD (eCD/CD+) authoring | Create multi-session CDs with audio tracks and data content |
| 11.7 | DVD-Video authoring | Create DVD-Video structures (VIDEO_TS) with menus, chapters, subtitles, multi-audio |
| 11.8 | HD DVD authoring | Create HD DVD disc structures (limited, largely defunct format) |
| 11.9 | Blu-ray authoring | Create BDMV structures with chapter markers, multiple audio/subtitle tracks |
| 11.10 | Blu-ray 3D authoring | Create stereoscopic Blu-ray 3D disc structures from MV-HEVC/MVC/SBS/TB content |
| 11.11 | Ultra HD Blu-ray authoring | Create UHD BD structures with HDR10/HDR10+/DV metadata and Atmos audio |
| 11.12 | DVD Audio authoring | Create DVD-Audio disc structures with high-resolution PCM/MLP audio |
| 11.13 | DTS CD authoring | Create DTS-encoded audio CDs |
| 11.14 | Mixed Mode CD authoring | Create CDs with both audio tracks and data sessions |
| 11.15 | HDCD authoring | Create HDCD-compatible audio CDs with 20-bit encoding flags |
| 11.16 | Blu-spec CD / SHM-CD metadata | Tag audio CD images with audiophile pressing format metadata |
| 11.17 | CD+G authoring | Create CD+Graphics discs with synchronised graphics/lyrics subchannel data |
| 11.18 | Hybrid SACD authoring | Create hybrid SACD images with both DSD and CD-compatible PCM layers |
| 11.19 | SHM-SACD authoring | Create SHM-SACD images with DSD content and pressing format metadata |
| 11.20 | DualDisc authoring | Create DualDisc images with DVD content on one side and CD audio on the other |
| 11.21 | CDV (CD Video) authoring | Create CD Video disc structures with audio tracks and video segments |
| 11.22 | Disc image output formats | Output to ISO, BIN/CUE, MDF/MDS, NRG, IMG disc image files |
| 11.23 | Physical disc burning | Burn disc images to physical media via compatible optical drives; burn verification |
| 11.24 | Burn settings UI | Drive selection, write speed, verify after burn, number of copies, disc label |
| 11.25 | Disc authoring templates | Pre-built templates for common disc types (music album CD, concert DVD, etc.) |
| 11.26 | Physical disc to image copy | Read/copy a physical disc (via optical drive) directly to a disc image file (ISO, BIN/CUE, etc.) without re-encoding. Bit-for-bit copy of the disc structure. Supports all readable disc types from Phase 10. Drive speed selection, read error recovery options, verify after copy |

> 📌 **Burning tools:** cdrecord/wodim (GPL), growisofs (GPL), dvd+rw-tools. On macOS, DRBurn framework (native) is also available for disc burning. Drive capability detection will determine which disc types can be burned.

---

### Phase 12: Cloud Integration & Uploads ☁️ — v1.3+

**Goal:** Direct upload to cloud storage and streaming platforms.

| # | Task | Details |
| - | ---- | ------- |
| 12.1 | Cloud upload protocol | Unified upload interface with progress/retry |
| 12.2 | AWS S3 | Upload to S3 buckets |
| 12.3 | AWS CloudFront | CDN distribution integration |
| 12.4 | Azure Blob Storage | Azure upload support |
| 12.5 | Cloudflare Stream | Direct Cloudflare Stream upload |
| 12.6 | Google Drive | Google Drive upload |
| 12.7 | Dropbox | Dropbox upload |
| 12.8 | OneDrive / OneDrive for Business | Microsoft OneDrive upload |
| 12.9 | SharePoint | SharePoint document library upload |
| 12.10 | iCloud Drive | iCloud upload (macOS) |
| 12.11 | Mega.nz | Mega.nz upload |
| 12.12 | Mux | Mux.com video upload & processing |
| 12.13 | Akamai NetStorage | Akamai upload |
| 12.14 | SFTP / FTP | Direct server upload |
| 12.15 | API key management | Secure storage, user-provided vs app-provided keys, toggle for packaging |

---

### Phase 13: Platform Expansion — Windows 🪟 — v2.0

**Goal:** Bring MeedyaConverter to Windows.

| # | Task | Details |
| - | ---- | ------- |
| 13.1 | Windows build setup | Swift toolchain for Windows, CMake/SPM build |
| 13.2 | Windows UI (WinUI 3) | Native Windows interface using WinAppSDK |
| 13.3 | FFmpeg bundling (Windows) | Package FFmpeg for Windows distribution |
| 13.4 | Hardware encoding (Windows) | NVENC (NVIDIA), QSV (Intel), AMF (AMD) |
| 13.5 | Windows installer | MSI/MSIX installer with code signing |
| 13.6 | Windows CI/CD | GitHub Actions for Windows builds |
| 13.7 | Optical disc support (Windows) | Windows disc reading/burning via same libraries; drive detection |

---

### Phase 14: Platform Expansion — Linux 🐧 — v2.0

**Goal:** Bring MeedyaConverter to Linux (including Raspberry Pi).

| # | Task | Details |
| - | ---- | ------- |
| 14.1 | Linux build setup | Swift toolchain for Linux distributions |
| 14.2 | Linux UI (GTK4) | GTK4-based interface using SwiftGtk or Adwaita |
| 14.3 | FFmpeg bundling (Linux) | AppImage/Flatpak with bundled FFmpeg |
| 14.4 | Hardware encoding (Linux) | VAAPI, V4L2 (RPi) |
| 14.5 | Raspberry Pi support | ARM/ARM64 builds, optimized for RPi OS |
| 14.6 | Linux packaging | .deb, .rpm, AppImage, Flatpak, Snap |
| 14.7 | Optical disc support (Linux) | Linux disc reading/burning; udev rules for drive access |

---

### Phase 15: Media Metadata Lookup 🏷️ — v1.5+

**Goal:** Integrate with online metadata services to auto-tag converted media for rich library experiences.

| # | Task | Details |
| - | ---- | ------- |
| 15.1 | Metadata lookup framework | Unified API for querying multiple metadata services with caching and rate limiting |
| 15.2 | MusicBrainz integration | Music metadata: artist, album, track, release date, genre, cover art. Uses open MusicBrainz API |
| 15.3 | AcoustID / Chromaprint | Audio fingerprint-based identification — identify unknown music tracks. Open API |
| 15.4 | TheMovieDB (TMDB) | Movie metadata: title, year, cast, crew, synopsis, poster, backdrop. Free API key |
| 15.5 | TheTVDB | TV show metadata: series, season, episode, air date, synopsis, artwork |
| 15.6 | IMDB integration | Movie/TV metadata via IMDB datasets (non-commercial) or OMDb API |
| 15.7 | MeedyaDB integration | MWBM Partners' own media database — direct API integration |
| 15.8 | Discogs integration | Music release metadata with emphasis on physical media (vinyl, CD, SACD) |
| 15.9 | FanArt.tv | High-quality fan artwork for media libraries (clearart, logos, backgrounds) |
| 15.10 | OpenSubtitles | Search and download matching subtitles for video content |
| 15.11 | Auto-tag on encode | Option to automatically look up and embed metadata after encoding completes |
| 15.12 | Metadata editor UI | View, edit, and apply metadata to encoded files. Cover art embedding |
| 15.13 | Media server compatibility | Tag files for optimal display in Plex, Jellyfin, Emby, Kodi, Apple TV, VLC |

> 📌 This phase is planned for later development. Core encoding functionality (Phases 1-9) takes priority. Complements MeedyaManager but provides standalone metadata capability for users without MeedyaManager.

---

### Phase 16: Polish & Distribution 📦 — Ongoing

**Goal:** App Store readiness, release automation, and final polish.

> 📌 Code signing and notarization basics are set up in Phase 2. This phase covers App Store submission, DMG automation, and final polish.

| # | Task | Details |
| - | ---- | ------- |
| 16.1 | App Store submission | Prepare for Mac App Store (if guidelines permit) |
| 16.2 | GitHub Releases | Automated release creation with changelogs |
| 16.3 | DMG creation | macOS disk image with drag-to-install |
| 16.4 | Touch Bar support | Touch Bar controls for encoding (legacy Macs) |
| 16.5 | Dynamic Island / Live Activities | iOS-style activity indicators on Apple Silicon |
| 16.6 | Analytics integration | Optional usage analytics (privacy-respecting) |
| 16.7 | GitHub Wiki | Complete API & user documentation wiki |
| 16.8 | Final documentation pass | All help docs, troubleshooting, FAQ finalized |

---

### Phase 17: Image Conversion 🖼️ — v3.0+ (Future Version)

**Goal:** Add bulk image format conversion capability. Planned for a future version — audio/video functionality is prioritised.

| # | Task | Details |
| - | ---- | ------- |
| 17.1 | Image conversion engine | Core image conversion using native platform APIs (CoreImage on macOS, GDI+ on Windows) + ImageMagick/libvips for extended format support |
| 17.2 | Common formats | JPEG, PNG, GIF, BMP, TIFF, WebP, AVIF, HEIC/HEIF |
| 17.3 | Professional formats | PSD (read), EXR (OpenEXR), HDR, RAW (CR2, NEF, ARW, DNG, ORF, RW2) |
| 17.4 | Modern formats | JPEG XL (JXL), JPEG 2000 (JP2), APNG |
| 17.5 | Legacy/other formats | TGA, PCX, ICO, DDS, PBM/PGM/PPM, SVG (render to raster) |
| 17.6 | Bulk conversion | Convert selected files or all files in a directory. Preserve directory structure option |
| 17.7 | Resize & transform | Scale, crop, rotate, flip. Configurable output dimensions and DPI |
| 17.8 | Quality settings | Compression quality, lossless toggle, colour profile (sRGB, Display P3, Adobe RGB) |
| 17.9 | Metadata handling | Preserve/strip/edit EXIF, IPTC, XMP metadata. GPS privacy stripping option |
| 17.10 | Image conversion UI | File browser with thumbnails, format selector, batch progress. Preview before/after |
| 17.11 | CLI image commands | `meedya-convert image <input> --format png --quality 90 --resize 1920x1080` |

> ⚠️ **Future version:** Image conversion is planned for release AFTER all audio/video functionality is complete. It will be included in a future version of MeedyaConverter.

---

### Phase 18: AI-Powered Features 🤖 — Wishlist

**Goal:** Explore AI-powered media processing capabilities. These are aspirational features — implementation depends on available models, licensing, and feasibility. May never come to fruition.

| # | Task | Details |
| - | ---- | ------- |
| 18.1 | AI caption/subtitle generator | Automatic speech-to-text captioning using Whisper (OpenAI, MIT license) or similar models. Must support speech AND music/singing lyrics. Generate SRT, TTML, WebVTT output. Multi-language support with language auto-detection. Speaker diarisation (identify different speakers). Configurable accuracy vs speed trade-off |
| 18.2 | AI audio translation | Translate audio from one language to another using AI voice synthesis. Preserve original speaker characteristics where possible. Generate translated audio track as additional stream (not replace original). Options: text-to-speech from translated subtitles, or direct speech-to-speech translation models |
| 18.3 | AI video upscaling | Resolution enhancement beyond basic interpolation — use neural network models (Real-ESRGAN, ESPCN, or similar) for intelligent upscaling. 480p→1080p, 1080p→4K. Models bundled or downloadable. GPU-accelerated (Metal on macOS, CUDA on Windows). Quality/speed presets. Frame-by-frame or scene-aware processing |
| 18.4 | AI HDR enhancement | Add HDR-like visual enhancement to SDR video content using AI tone mapping and colour expansion. Inverse tone mapping from SDR to HDR10/HLG. AI-based colour grading to expand dynamic range. NOT the same as real HDR mastering — clearly labelled as "AI-enhanced" to set expectations. Optional, toggle-based |

> 🔮 **Wishlist:** These features are aspirational and may never be implemented. They depend on the maturity of open-source AI models, GPU acceleration availability across platforms, model licensing compatibility with proprietary software, and the quality achievable. They are listed here for long-term planning reference only.
>
> 📌 **Potential AI libraries:** OpenAI Whisper (MIT), Real-ESRGAN (BSD), ESPCN, CoreML (Apple), ONNX Runtime (cross-platform). All model inference should be LOCAL (on-device) — no cloud AI dependency.
>
> 💰 **Feature gating:** AI features are strong candidates for the "Studio" tier if product tiering is implemented (see Phase 1.11 feature gating system).

---

## 🔑 Key Differentiators vs HandBrake

| Feature | HandBrake | MeedyaConverter |
| ------- | --------- | --------------- |
| Video passthrough | ❌ Forces re-encode | ✅ Copy without re-encoding |
| Subtitle passthrough | ❌ Converts to SRT | ✅ Preserves original format |
| CC608/CC708 passthrough | ❌ Limited | ✅ Full support |
| Multiple video streams | ❌ Single stream only | ✅ Per-stream encoding settings |
| Stream metadata editing | ❌ Basic | ✅ Full BCP 47, forced/default flags |
| Audio normalization | ❌ None | ✅ EBU R128, ReplayGain |
| Audio channel analysis | ❌ None | ✅ Detect actual channel content vs declared config |
| Matrix encoding on downmix | ❌ None | ✅ Embed PL II/Surround metadata for AVR unfold |
| Immersive audio | ❌ None | ✅ Eclipsa (IAMF), MPEG-H, 360 Reality Audio, Dolby MAT |
| HLS/DASH preparation | ❌ None | ✅ Full ABR ladder + manifests |
| Cloud upload | ❌ None | ✅ 12+ cloud providers |
| Forensic watermarking | ❌ None | ✅ Invisible watermarks |
| HDR10+ → DV auto-convert | ❌ None | ✅ Automatic Dolby Vision creation |
| 3D / Stereoscopic video | ❌ None | ✅ MV-HEVC, MV-H264, frame packing |
| Optical disc ripping | ❌ DVD/Blu-ray only | ✅ 22 disc types: CD through UHD BD, plus disc images |
| Disc image creation & burning | ❌ None | ✅ Author and burn all supported disc types |
| Matrix preservation on transcode | ❌ None | ✅ Preserve Pro Logic II/Surround across format changes |
| Virtual surround upmixing | ❌ None | ✅ Algorithmic stereo → 5.1/7.1 upmix (frequency-domain) |
| MediaInfo integration | ❌ None | ✅ Detailed HDR/DV/codec metadata analysis |
| IMAX Enhanced | ❌ None | ✅ DTS:X IMAX profile support |
| Watch folder automation | ❌ None | ✅ Auto-encode from monitored folders |
| A/B comparison | ❌ None | ✅ Side-by-side source vs encoded viewer |
| Quality metrics | ❌ None | ✅ VMAF, SSIM, PSNR scoring |
| Scene detection | ❌ None | ✅ Auto-chapter generation |
| AI upscaling | ❌ None | ✅ Resolution enhancement |
| Media metadata lookup | ❌ None | ✅ MusicBrainz, TMDB, TVDB, MeedyaDB auto-tagging |
| Image conversion | ❌ None | ✅ Bulk image format conversion (future version) |
| CLI API | ❌ Basic | ✅ Full JSON-based automation |

---

## 📜 Licensing

- **Application Code:** Proprietary — © 2026–present MWBM Partners Ltd
- **FFmpeg:** LGPL 2.1 / GPL 2+ (bundled, used as external tool — no linking)
- **dovi_tool:** MIT License
- **DDVT:** MIT License
- **MP4Box (GPAC):** LGPL 2.1
- **libcdio / cdparanoia:** GPL 3 / GPL 2 (disc reading — subprocess)
- **libdvdread / libdvdnav:** GPL 2 (DVD reading — subprocess)
- **libbluray:** LGPL 2.1 (Blu-ray reading)
- **sacd_extract:** GPL (SACD reading — subprocess)
- **Tesseract OCR:** Apache 2.0 (bitmap subtitle OCR)
- **libmediainfo:** BSD-2-Clause (detailed media analysis)
- **Other dependencies:** Respective open-source licenses (see THIRD_PARTY_LICENSES.md)

> ⚠️ FFmpeg and disc reading tools are invoked as subprocesses (direct distribution) or linked via LGPL-compatible builds (App Store), maintaining license compatibility with the proprietary application license.

---

## 🔄 Standing Tasks (Automated After Every Prompt)

These tasks are automatically performed after every development action:

1. 📋 **GitHub Issues** — Create/update GitHub issue for each action taken
2. 🔍 **Code Quality** — Run syntax, lint, and security checks; fix all issues
3. ♿ **Accessibility** — Ensure accessibility compliance
4. 📝 **Documentation** — Update README, CHANGELOG, PROJECT_STATUS, help docs
5. 🗂️ **Claude Context** — Update .claude/ memory and context files
6. 📁 **Gitignore** — Keep .gitignore current for all dev environments
7. ✅ **Commit** — Commit changes (do NOT push — manual push only)
8. 🧹 **Cleanup** — Remove temporary development files

---

## 📊 App Store Compliance Notes

The macOS App Store has specific guidelines that may affect certain features:

| Feature | App Store Compatible | Notes |
| ------- | ------------------- | ----- |
| FFmpeg bundling | ✅ Compatible | Invoked as subprocess (not linked) — GPL/LGPL does not affect app license. Bundled as signed helper tool in app bundle |
| Sandboxing | ⚠️ Partial | File access requires user consent via file pickers; some features may need entitlements |
| Auto-update | ✅ Dual strategy | **Direct distribution:** Sparkle 2 for auto-updates. **App Store:** excluded via build config, Apple handles updates natively |
| CLI tool | ❌ Not in sandbox | CLI distributed separately from App Store version |
| Kernel extensions | ❌ Not allowed | Not needed for this application |

> 📌 **Distribution Strategy:**
>
> - **App Store** — Sandboxed, Apple-managed updates, code signed & notarized
> - **Direct Download** — Full-featured, Sparkle 2 auto-updates, Developer ID signed & notarized
> - Both versions support the full codec/format feature set (FFmpeg is a subprocess, not linked)
> - Build configurations (`APP_STORE` vs `DIRECT`) conditionally include/exclude Sparkle

---

Last updated: 2026-04-03
