<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Architecture

MeedyaConverter follows a three-layer architecture: a shared engine library, a command-line tool, and a macOS SwiftUI application. All encoding logic lives in the engine, ensuring feature parity between the GUI and CLI.

---

## System Overview

```
┌──────────────────────────────────────────────────────────┐
│                    User Interfaces                        │
│                                                          │
│  ┌─────────────────────┐    ┌──────────────────────────┐ │
│  │  MeedyaConverter     │    │  meedya-convert          │ │
│  │  (SwiftUI App)       │    │  (CLI via ArgumentParser)│ │
│  │                      │    │                          │ │
│  │  - Drag & drop       │    │  - encode, probe, batch  │ │
│  │  - Queue management  │    │  - JSON progress output  │ │
│  │  - Profile editor    │    │  - Job file processing   │ │
│  │  - Real-time progress│    │  - CI/CD integration     │ │
│  │  - Settings/prefs    │    │                          │ │
│  └──────────┬───────────┘    └────────────┬─────────────┘ │
│             │                             │               │
└─────────────┼─────────────────────────────┼───────────────┘
              │                             │
              └──────────────┬──────────────┘
                             │
┌────────────────────────────▼─────────────────────────────┐
│                    ConverterEngine                        │
│                    (Swift Library)                        │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Models       │  │ Encoding     │  │ FFmpeg          │ │
│  │              │  │              │  │                 │ │
│  │ MediaFile    │  │ EncodingJob  │  │ ArgumentBuilder │ │
│  │ MediaStream  │  │ EncodingEngine│ │ ProcessController│ │
│  │ VideoCodec   │  │ EncodingProfile│ │ BundleManager  │ │
│  │ AudioCodec   │  │ PerStreamSettings│ │ Probe (FFprobe)│ │
│  │ ContainerFmt │  │ Statistics   │  │ HW Detector    │ │
│  │ SubtitleFmt  │  │              │  │                 │ │
│  │ FeatureGate  │  │              │  │                 │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ HDR          │  │ Subtitles    │  │ Manifest        │ │
│  │              │  │              │  │                 │ │
│  │ PolicyEngine │  │ Converter    │  │ HLS Generator   │ │
│  │ PQ→HLG      │  │ ExtendedFmts │  │ DASH Generator  │ │
│  │ HLG→DV      │  │              │  │                 │ │
│  │ ToneMapping  │  │              │  │                 │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Audio        │  │ Disc         │  │ Cloud           │ │
│  │              │  │              │  │                 │ │
│  │ Processor    │  │ CD/DVD/BD    │  │ S3 Uploader     │ │
│  │ Normalizer   │  │ Imager       │  │ Cloud Providers │ │
│  │ SpatialAudio │  │ Author       │  │ Media Server    │ │
│  │ Fingerprint  │  │ AccurateRip  │  │ API Key Mgr     │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Backend      │  │ Platform     │  │ Utilities       │ │
│  │              │  │              │  │                 │ │
│  │ EncodingBack │  │ FormatPolicy │  │ TempFile Mgr    │ │
│  │ (protocol)   │  │              │  │ Disk Monitor    │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
└──────────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────┐
│                    External Tools                         │
│                                                          │
│  FFmpeg / FFprobe      — Encoding, probing, filtering    │
│  dovi_tool             — Dolby Vision RPU extract/inject │
│  hlg-tools             — PQ→HLG conversion               │
│  MediaInfo (optional)  — Extended media analysis          │
└──────────────────────────────────────────────────────────┘
```

---

## Module Responsibilities

### ConverterEngine (Library)

The shared core library. Contains no UI code. Targets both the CLI and GUI.

| Module | Purpose |
|--------|---------|
| **Models** | Data types: `MediaFile`, `MediaStream`, `VideoCodec`, `AudioCodec`, `ContainerFormat`, `SubtitleFormat`, `FeatureGate` |
| **Encoding** | `EncodingJob` (job definition and state), `EncodingEngine` (orchestration), `EncodingProfile` (presets), `PerStreamSettings`, `EncodingStatistics` |
| **FFmpeg** | `FFmpegArgumentBuilder` (settings to CLI args), `FFmpegProcessController` (start/pause/stop/progress), `FFmpegBundleManager` (binary discovery), `FFmpegProbe` (file inspection), `HardwareEncoderDetector` |
| **HDR** | `HDRPolicyEngine` (automatic HDR handling decisions), `PQToHLGPipeline`, `HLGToDolbyVision`, tone-mapping filter setup |
| **Subtitles** | `SubtitleConverter` (format conversion), extended format support (SCC, EBU STL, MCC) |
| **Manifest** | `ManifestGenerator` (HLS and DASH manifest creation) |
| **Audio** | `AudioProcessor` (normalization, downmix), `SpatialAudioProcessor` (Atmos, Auro-3D, Ambisonics), `AudioFingerprinter` |
| **Disc** | `AudioCDReader`, `DVDReader`, `BlurayReader`, `DiscImager`, `DiscAuthor`, `DiscBurner`, `AccurateRipVerifier` |
| **Cloud** | `S3Uploader`, `CloudProviders` (12+ providers), `MediaServerNotifier`, `APIKeyManager` |
| **Backend** | `EncodingBackend` protocol — abstraction for FFmpeg subprocess vs. AVFoundation/FFmpegKit |
| **Platform** | `PlatformFormatPolicy` — platform-specific codec availability |
| **Utilities** | Temp file management, disk space monitoring |

### meedya-convert (CLI)

A thin command-routing layer built on Swift Argument Parser:

| File | Purpose |
|------|---------|
| `MeedyaConvert.swift` | Root command (`@main`), subcommand registration |
| `EncodeCommand.swift` | `encode` subcommand — single file transcode |
| `ProbeCommand.swift` | `probe` subcommand — media inspection |
| `BatchCommand.swift` | `batch` subcommand — multi-file processing |
| `ProfilesCommand.swift` | `profiles` subcommand — profile management |
| `ManifestCommand.swift` | `manifest` subcommand — HLS/DASH generation |
| `ValidateCommand.swift` | `validate` subcommand — settings validation |

### MeedyaConverter (SwiftUI App)

The macOS GUI application:

| Directory | Purpose |
|-----------|---------|
| `Views/` | SwiftUI views (main window, queue, settings, inspector) |
| `ViewModels/` | `@Observable` view models bridging the UI to the engine |
| `Components/` | Reusable UI components (progress bars, stream badges, etc.) |
| `Services/` | App-level services (file import, preferences, Sparkle updates) |
| `Resources/` | Assets, Info.plist, entitlements |

---

## Data Flow: Encoding Pipeline

```
Source File
    │
    ▼
┌──────────────┐
│ FFmpegProbe   │  ← Runs ffprobe, parses JSON output
│ → MediaFile   │  ← Populated with streams, metadata, HDR info
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ User Configuration│  ← Profile selection, per-stream settings
│ → EncodingJob     │  ← Defines input, output, all codec settings
└──────┬───────────┘
       │
       ▼
┌───────────────────────┐
│ FFmpegArgumentBuilder  │  ← Translates EncodingJob into FFmpeg CLI args
│                        │  ← Applies HDR policy, filter graphs, maps
│ → [String] arguments   │
└──────┬────────────────┘
       │
       ▼
┌───────────────────────┐
│ FFmpegProcessController│  ← Launches FFmpeg as a subprocess
│                        │  ← Parses stderr for progress (frame, fps, speed)
│                        │  ← Emits progress via AsyncStream
│                        │  ← Supports pause/resume/cancel
└──────┬────────────────┘
       │
       ▼
┌──────────────┐
│ Output File   │  ← Encoded media in target container
│ + Statistics  │  ← Duration, size, bitrate, quality metrics
└──────────────┘
```

---

## FFmpegArgumentBuilder Pipeline

The argument builder is the critical translation layer. It processes an `EncodingJob` through these stages:

1. **Input mapping** — `-i <source>` with seek/duration if trimming.
2. **Stream selection** — `-map` directives for included video, audio, and subtitle streams.
3. **Video encoding** — Codec, CRF/bitrate, preset, pixel format, resolution, crop.
4. **HDR policy** — Preserves metadata or inserts tone-mapping filter based on `HDRPolicyEngine` decisions.
5. **Audio encoding** — Per-stream codec, bitrate, sample rate, channel layout.
6. **Subtitle handling** — Copy, convert, or burn-in based on format and container compatibility.
7. **Metadata** — Title, tags, chapter markers, cover art.
8. **Container settings** — Muxer options, faststart, fragment settings.
9. **Two-pass setup** — Generates separate pass-1 and pass-2 argument arrays if enabled.

---

## Encoding Queue Architecture

The encoding queue manages multiple jobs with priority ordering:

- Jobs have states: `pending`, `running`, `paused`, `completed`, `failed`, `cancelled`.
- The queue respects a configurable concurrency limit (default: 1 concurrent encode).
- Jobs can be reordered, paused, resumed, or cancelled individually.
- Progress for each job is reported via `AsyncStream<EncodingProgress>`.
- The queue persists across app launches (jobs are serialised to disk).

---

## Hybrid Engine Strategy

MeedyaConverter uses two encoding backends depending on distribution channel:

| Distribution | Backend | FFmpeg Source | Auto-Update |
|-------------|---------|--------------|-------------|
| **Direct** (DMG) | `FFmpegProcessBackend` — spawns system FFmpeg | System/Homebrew/bundled | Sparkle 2 |
| **App Store** | `AVFoundationBackend` + FFmpegKit | Embedded XCFramework | App Store |

The `EncodingBackend` protocol abstracts these differences so the rest of the engine is backend-agnostic.
