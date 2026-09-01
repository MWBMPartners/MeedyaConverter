<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Architecture

MeedyaConverter follows a three-layer architecture: a shared engine library, a command-line tool, and a macOS SwiftUI application. All encoding logic lives in the engine, ensuring feature parity between the GUI and CLI.

---

## System Overview

```text
┌──────────────────────────────────────────────────────────┐
│                    User Interfaces                        │
│                                                          │
│  ┌─────────────────────┐    ┌──────────────────────────┐ │
│  │  MeedyaConverter     │    │  meedya-convert          │ │
│  │  (SwiftUI App)       │    │  (CLI via ArgumentParser)│ │
│  │                      │    │                          │ │
│  │  - Drag & drop       │    │  - encode, probe, batch  │ │
│  │  - Queue management  │    │  - profiles, manifest    │ │
│  │  - Profile editor    │    │  - validate              │ │
│  │  - Real-time progress│    │  - JSON progress output  │ │
│  │  - Pipeline editor   │    │  - Job file processing   │ │
│  │  - Schedule view     │    │  - CI/CD integration     │ │
│  │  - Settings/prefs    │    │                          │ │
│  │  - Paywall/licensing │    │                          │ │
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
│  │ AudioCodec   │  │ PerStreamSett│ │ Probe (FFprobe) │ │
│  │ ContainerFmt │  │ Pipeline     │  │ HW Detector    │ │
│  │ SubtitleFmt  │  │ Conditional  │  │ SceneDetector  │ │
│  │ FeatureGate  │  │ PostActions  │  │ CropDetector   │ │
│  │ PlatformFmt  │  │ Checkpoint   │  │ SmartCrop      │ │
│  │ SpatialAudio │  │ ProfileShare │  │ ContentAnalyzer│ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ HDR          │  │ Subtitles    │  │ Manifest        │ │
│  │              │  │              │  │                 │ │
│  │ PolicyEngine │  │ Converter    │  │ HLS Generator   │ │
│  │ PQ-to-HLG   │  │ ExtendedFmts │  │ DASH Generator  │ │
│  │ HLG-to-DV   │  │              │  │ CMAF            │ │
│  │ ToneMapping  │  │              │  │ Streaming Enh.  │ │
│  │ ColourSpace  │  │              │  │                 │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Audio        │  │ Disc         │  │ Cloud           │ │
│  │              │  │              │  │                 │ │
│  │ Processor    │  │ CD/DVD/BD    │  │ S3 Uploader     │ │
│  │ Normalizer   │  │ Imager       │  │ Cloud Providers │ │
│  │ SpatialAudio │  │ Author       │  │ Extended Cloud  │ │
│  │ Fingerprint  │  │ Burner       │  │ Media Server    │ │
│  │ SurroundMix  │  │ AccurateRip  │  │ API Key Mgr     │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Licensing    │  │ Metadata     │  │ Quality         │ │
│  │              │  │ (builders)   │  │                 │ │
│  │ FeatureGate  │  │ Lookup       │  │ QualityMetrics  │ │
│  │ ProductCat.  │  │ Providers    │  │                 │ │
│  │ StoreManager │  │ AutoTagger*  │  │                 │ │
│  │ RevenueCat   │  │              │  │                 │ │
│  │ LicenseKey   │  │              │  │                 │ │
│  │ Entitlement  │  │              │  │                 │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Backend      │  │ Platform     │  │ Utilities       │ │
│  │              │  │              │  │                 │ │
│  │ EncodingBack │  │ FormatPolicy │  │ TempFile Mgr    │ │
│  │ (protocol)   │  │              │  │ Disk Monitor    │ │
│  │ Native       │  │              │  │ WatchFolder     │ │
│  └─────────────┘  └──────────────┘  └─────────────────┘ │
└──────────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────┐
│                    External Tools                         │
│                                                          │
│  FFmpeg / FFprobe      — Encoding, probing, filtering    │
│  dovi_tool             — Dolby Vision RPU extract/inject │
│  hlg-tools             — PQ-to-HLG conversion            │
│  MediaInfo (optional)  — Extended media analysis          │
└──────────────────────────────────────────────────────────┘
```

`*` marks a module that is present and compiles but has no call site — see
[Dormant modules](#dormant-modules) below.

---

## Module Responsibilities

### ConverterEngine (Library)

The shared core library. Contains no UI code. Targets both the CLI and GUI.

| Module | Purpose |
| ------ | ------- |
| **Models** | Data types: `MediaFile`, `MediaStream`, `VideoCodec`, `AudioCodec`, `ContainerFormat`, `SubtitleFormat`, `FeatureGate`, `PlatformFormatPolicy`, `SpatialAudioProcessor` |
| **Encoding** | `EncodingJob` (job definition and state), `EncodingEngine` (orchestration), `EncodingProfile` (presets and custom profiles), `PerStreamSettings`, `EncodingStatistics`, `EncodingPipeline` (multi-step workflows), `ConditionalRule` (source-based auto-settings), `PostEncodeActions` (post-job automation), `EncodingCheckpoint` (resumable jobs), `ProfileSharing` (import/export) |
| **FFmpeg** | `FFmpegArgumentBuilder` (settings to CLI args), `FFmpegProcessController` (start/pause/stop/progress), `FFmpegBundleManager` (binary discovery), `FFmpegProbe` (file inspection), `FFmpegBackend` / `FFmpegBackendFactory` (one-shot ffmpeg/ffprobe runs), `HardwareEncoderDetector`, `SceneDetector`, `CropDetector`, `FrameComparisonExtractor`, `QualityMetrics` (VMAF/SSIM), `WatchFolderManager`. **Dormant:** `ContentAnalyzer`, `AIUpscaler`, `ForensicWatermark`, `StreamingEnhancements` — see "Dormant modules" below. |
| **HDR** | Handled inside `FFmpegArgumentBuilder`: `ToneMapAlgorithm` + `toneMap*` options build the `tonemap` filter chain, `preserveHDRMetadata` drives `buildHDR10MetadataArguments`, and `buildPQPreservationArguments` emits PQ colour signalling. **Dormant:** `HLGToDolbyVision`, `ColorSpaceConverter`, `CodecMetadataPreserver`. |
| **Subtitles** | Handled inside `FFmpegArgumentBuilder` (copy / convert / burn-in decisions and per-stream `SubtitleStreamOverride`s) plus `SubtitleFormat` in **Models**. There is no separate subtitle-conversion module. |
| **Manifest** | `ManifestGenerator` (HLS, DASH, and CMAF manifest creation), `StreamingEnhancements` |
| **Audio** | `AudioProcessor` (normalization, downmix), `NormalizationPresets` (EBU R128, ReplayGain), `SurroundUpmixer`, `AudioFingerprinter`, `MatrixEncodingPreserver`, `SpatialAudioProcessor` (Atmos, Auro-3D, Ambisonics) |
| **Disc** | `AudioCDReader`, `DVDReader`, `BlurayReader`, `DiscImager`, `DiscAuthor`, `DiscBurner`, `AccurateRipVerifier`, `AudioDiscFidelity`, `DiscModels` |
| **Cloud** | `S3Uploader`, `CloudProviders` (12+ providers), `ExtendedCloudProviders`, `MediaServerNotifier`, `APIKeyManager`, `CloudUploadProtocol` |
| **Licensing** | `EntitlementGating` (feature tier enforcement), `ProductCatalog` (purchasable items), `FreeGateProvider`, `RevenueCatProvider`, `LicenseKeyValidator` |
| **Metadata** | `MetadataLookup` and `MetadataProviders` — **URL builders only**. Neither file performs HTTP, and nothing in `Sources/ConverterEngine/Metadata/` decodes a provider response; there is no `URLSession` in that directory. `AutoTagger` is dormant (zero references outside its own file). Metadata *writing* is real and lives elsewhere: `MetadataTagEditorView` invokes ffmpeg directly (#467). |
| **Backend** | `Backend/EncodingBackend.swift` — an unused protocol scaffold retained deliberately (name-collision risk); the live abstraction is `FFmpeg/FFmpegBackend.swift` + `FFmpegBackendFactory`. Tracked by #477. |
| **Native** | Native platform integrations (Intents, App Intents) |
| **Platform** | `PlatformFormatPolicy` — platform-specific codec availability |
| **Utilities** | Temp file management, disk space monitoring |

#### Dormant modules

Code in `ConverterEngine` that compiles and is unit-tested but has **no call site
outside its own file**. It is listed here rather than omitted, so that this diagram
is not read as a claim that the capability ships. Verified by grep against
`wip/alpha-consolidation`; the same set is tracked in `FEATURES.md` and issue #477.

| Module | Status |
| ------ | ------ |
| `ContentAnalyzer` | zero references outside its own file |
| `AIUpscaler` | named only in two comments (`FFmpegBackend.swift:52`, `FFmpegBackendFactory.swift:35`) — no call site |
| `ForensicWatermark` | zero references outside its own file |
| `StreamingEnhancements` (incl. `HLSEncryption`, `ThumbnailSpriteGenerator`) | zero references outside its own file |
| `HLGToDolbyVision` | zero references outside its own file |
| `ColorSpaceConverter` | zero references outside its own file; the live tone-map path is `FFmpegArgumentBuilder.ToneMapAlgorithm` |
| `CodecMetadataPreserver` | zero references outside its own file |
| `AutoTagger` | zero references outside its own file — the metadata-lookup pipeline has no consumer |
| `Backend/EncodingBackend.swift` | unused protocol scaffold, retained deliberately (name-collision risk, #477) |

Modules that used to appear in this document and have since been **deleted** from the
source tree in the orphan sweep (`af83104`, `7f59196`) are not listed above and are no
longer referenced anywhere here: `EncodingReport`, `HDRPolicyEngine`, `MetadataPassthrough`,
`MetadataTagger`, `PQToHLGPipeline`, `SmartCropIntegration`, `SubtitleConverter`,
`MultiStreamSelector`, `ColourSpaceConverter`, `AudioMixer`, `ClosedCaptionHandler`,
`SubtitleOCR`, `MediaInfoIntegration`.

### meedya-convert (CLI)

A thin command-routing layer built on Swift Argument Parser:

| File | Purpose |
| ---- | ------- |
| `MeedyaConvert.swift` | Root command (`@main`), subcommand registration |
| `EncodeCommand.swift` | `encode` subcommand — single file transcode |
| `ProbeCommand.swift` | `probe` subcommand — media inspection |
| `BatchCommand.swift` | `batch` subcommand — multi-file processing |
| `ProfilesCommand.swift` | `profiles` subcommand — profile management |
| `ManifestCommand.swift` | `manifest` subcommand — HLS/DASH/CMAF generation |
| `ValidateCommand.swift` | `validate` subcommand — settings and manifest validation |
| `ServeCommand.swift` | `serve` subcommand — starts `APIServer` (the only way to start the HTTP API) |
| `CLIUtilities.swift` | Shared utilities: exit codes, stderr printing |

### MeedyaConverter (SwiftUI App)

The macOS GUI application:

| Directory / File | Purpose |
| ---------------- | ------- |
| `Views/` | SwiftUI views — content, sidebar, source, stream inspector, output settings, queue, log, settings, help, dashboard |
| `Views/` (advanced) | Pipeline editor, schedule, conditional rules, post-encode actions, normalization, scene detector, comparison, FFmpeg preview, quality preview, profile suggestion, bitrate heatmap, audio waveform, encoding graphs, image conversion, metadata editor, media server settings, webhook settings, analytics settings, burn settings, license entry, paywall, resumable jobs |
| `ViewModels/` | `@Observable` view models bridging the UI to the engine |
| `Components/` | Reusable UI components (progress bars, stream badges, etc.) |
| `Services/` | App-level services: `StoreManager` (StoreKit/RevenueCat), `AppUpdateChecker` (Sparkle), `ThumbnailCache` |
| `Intents/` | App Intents for Shortcuts and Siri integration |
| `Resources/` | Assets, Info.plist, entitlements |

---

## Data Flow: Encoding Pipeline

```text
Source File
    │
    ▼
┌──────────────┐
│ FFmpegProbe   │  <- Runs ffprobe, parses JSON output
│ -> MediaFile  │  <- Populated with streams, metadata, HDR info
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ User Configuration│  <- Profile selection, per-stream settings
│ -> EncodingJob    │  <- Defines input, output, all codec settings
└──────┬───────────┘
       │
       ▼
┌───────────────────────┐
│ FFmpegArgumentBuilder  │  <- Translates EncodingJob into FFmpeg CLI args
│                        │  <- Applies HDR policy, filter graphs, maps
│ -> [String] arguments  │
└──────┬────────────────┘
       │
       ▼
┌───────────────────────┐
│ FFmpegProcessController│  <- Launches FFmpeg as a subprocess
│                        │  <- Parses stderr for progress (frame, fps, speed)
│                        │  <- Emits progress via AsyncStream
│                        │  <- Supports pause/resume/cancel
└──────┬────────────────┘
       │
       ▼
┌──────────────┐
│ Output File   │  <- Encoded media in target container
│ + Statistics  │  <- Duration, size, bitrate, quality metrics
│ + PostActions │  <- Move, upload, notify, webhook
└──────────────┘
```

---

## FFmpegArgumentBuilder Pipeline

The argument builder is the critical translation layer. It processes an `EncodingJob` through these stages:

1. **Input mapping** — `-i <source>` with seek/duration if trimming.
2. **Stream selection** — `-map` directives for included video, audio, and subtitle streams.
3. **Video encoding** — Codec, CRF/bitrate, preset, pixel format, resolution, crop.
4. **HDR policy** — Preserves HDR10/PQ/HLG signalling, or inserts a `tonemap` filter chain, based on the builder's own `toneMap` / `convertPQToHLG` / `preserveHDRMetadata` flags.
5. **Audio encoding** — Per-stream codec, bitrate, sample rate, channel layout, normalization.
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
- Resumable encoding with checkpoint support for long-running jobs.

---

## Encoding Pipeline Architecture

Encoding pipelines chain multiple encoding steps:

- Each step has its own profile, filters, and output settings.
- Steps can depend on previous step outputs.
- Pipelines are defined as ordered arrays of `EncodingPipeline.Step` objects.
- Conditional rules can dynamically modify pipeline behaviour based on source properties.
- Post-encode actions run after the final step or after each step.

---

## Licensing and Monetisation Architecture

The licensing system controls feature availability based on subscription tier:

- `FeatureGate` defines which features require which tier (Free, Pro, Studio).
- `EntitlementGating` enforces access at runtime.
- `ProductCatalog` defines purchasable products and their associated entitlements.
- `StoreManager` handles StoreKit transactions (App Store) and integrates with `RevenueCatProvider` for cross-platform subscription management.
- `LicenseKeyValidator` supports direct-sale license keys for non-App Store distribution.
- `FreeGateProvider` provides the baseline free-tier gating.

---

## Hybrid Engine Strategy

MeedyaConverter uses two encoding backends depending on distribution channel:

| Distribution | Backend | FFmpeg Source | Auto-Update |
| ------------ | ------- | ------------ | ----------- |
| **Direct** (DMG) | `FFmpegProcessBackend` — spawns system FFmpeg | System/Homebrew/bundled | Sparkle 2 |
| **App Store** | `AVFoundationBackend` + FFmpegKit | Embedded XCFramework | App Store |

The `EncodingBackend` protocol abstracts these differences so the rest of the engine is backend-agnostic.
