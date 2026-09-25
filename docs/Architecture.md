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
│  │              │  │              │  │                 │ │
│  │ FeatureGate  │  │ Lookup       │  │ QualityMetrics  │ │
│  │ ProductCat.  │  │ Providers    │  │                 │ │
│  │ StoreManager │  │ TMDB/MB svc  │  │                 │ │
│  │ RevenueCat   │  │ AutoTagRunner│  │                 │ │
│  │ LicenseKey   │  │ AutoTagger   │  │                 │ │
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
| **Models** | Data types: `MediaFile`, `MediaStream`, `VideoCodec`, `AudioCodec`, `ContainerFormat`, `SubtitleFormat`, `FeatureGate`, `PlatformFormatPolicy`. `Models/SpatialAudioProcessor.swift` (the file name does not match either type it defines) also holds `Video3DConverter` and `SpatialAudioConverter` — both dormant, see "Dormant modules" below. |
| **Encoding** | `EncodingJob` (job definition and state), `EncodingEngine` (orchestration), `EncodingProfile` (presets and custom profiles), `PerStreamSettings`, `EncodingStatistics`, `EncodingPipeline` (step/rule data model — its `PipelineExecutor` has zero callers, see "Dormant modules"), `ConditionalRule` (source-based auto-settings, applied at enqueue), `PostEncodeActions` (post-job automation, including the failure path — `runOnFailure` actions now actually run), `EncodingCheckpoint` (resumable jobs), `ProfileSharing` (import/export), `EncodingStatisticsRecorder` / `PostEncodeHookRunner` (Issue #286 — serialise, respectively, statistics writes and post-encode hook chains, so two jobs finishing together can't clobber a statistics entry or run two hook chains concurrently once more than one job is allowed to encode at once — see "Encoding Queue Architecture" below) |
| **FFmpeg** | `FFmpegArgumentBuilder` (settings to CLI args), `FFmpegProcessController` (start/pause/stop/progress), `FFmpegBundleManager` (binary discovery), `FFmpegProbe` (file inspection), `FFmpegBackend` / `FFmpegBackendFactory` (one-shot ffmpeg/ffprobe runs), `HardwareEncoderDetector`, `SceneDetector` (now wired — see below), `CropDetector`, `FrameComparisonExtractor` (wired — drives `ComparisonView`'s A/B capture), `QualityMetrics` (VMAF/SSIM), `WatchFolderManager`. **Dormant:** `ContentAnalyzer`, `AIUpscaler`, `ForensicWatermark`, `StreamingEnhancements`, `MatrixEncodingPreserver` — see "Dormant modules" below. |
| **HDR** | Handled inside `FFmpegArgumentBuilder`: `ToneMapAlgorithm` + `toneMap*` options build the `tonemap` filter chain, `preserveHDRMetadata` drives `buildHDR10MetadataArguments`, and `buildPQPreservationArguments` emits PQ colour signalling. **Dormant:** `HLGToDolbyVision`, `ColorSpaceConverter`, `CodecMetadataPreserver`. |
| **Subtitles** | Handled inside `FFmpegArgumentBuilder` (copy / convert / burn-in decisions and per-stream `SubtitleStreamOverride`s) plus `SubtitleFormat` in **Models**. There is no separate subtitle-conversion module. |
| **Manifest** | `ManifestGenerator` (HLS, DASH, and CMAF manifest creation), `StreamingEnhancements` |
| **Audio** | `AudioProcessor` (normalization, downmix), `NormalizationPresets` (EBU R128, ReplayGain), `VoiceIsolator` (centre-channel dialogue boost, wired to `VoiceIsolationView`), `LoudnessReporter`. **Dormant:** `SurroundUpmixer`, `AudioFingerprinter`, `MatrixEncodingPreserver`, `SpatialAudioConverter` (spatial-audio/Atmos/Ambisonics rendering — see "Dormant modules" below; this document previously named a non-existent `SpatialAudioProcessor` module here). |
| **Disc** | `DiscBurner` (real, and the only wired member of this group — see `docs/decisions/0001-gpl-disc-tools.md` for why raw-device imaging is Direct-distribution-only). **Dormant:** `AudioCDReader`, `DVDReader`, `BlurayReader`, `DiscImager`, `DiscAuthor`, `AccurateRipVerifier`, `AudioDiscFidelity` — see "Dormant modules" below. `DiscModels` holds shared types used by the dormant readers/authors. |
| **Cloud** | `S3Uploader` (+ `AWSV4Signer`), `CloudStorageUploader`/`CloudUploadExecutor` (real upload execution for Dropbox, Google Drive, OneDrive, and S3/S3-compatible endpoints — chunked/resumable where the provider's API supports it), `SFTPUploader`. `CloudProviders.CloudProvider` is a separate, wider enum (11 cases, including Azure Blob, iCloud Drive, Cloudflare Stream, Mux, Backblaze B2) used for display metadata only — no UI references it, and `CloudUploadExecutor` only switches on the narrower `CloudStorageProvider` (Dropbox/OneDrive/Google Drive/S3). Do not read "12+ providers" claims as 12+ working upload paths. `MediaServerNotifier`, `APIKeyManager`, `CloudUploadProtocol` |
| **Licensing** | `EntitlementGating` (feature tier enforcement), `ProductCatalog` (purchasable items), `FreeGateProvider`, `RevenueCatProvider`, `LicenseKeyValidator` |
| **Metadata** | `MetadataLookup` and `MetadataProviders` are URL builders only — neither performs HTTP itself. `TMDBLookupService` and `MusicBrainzLookupService` (also in this directory) DO perform real HTTP, through the testable `MetadataHTTPClient` seam: the Metadata Tag Editor's "Look Up…" button already used them for a user-triggered lookup (#493/#502/#503), and since #508 `AutoTagRunner` uses the same two services for an automatic, opt-in lookup during a real encode (see "Auto-tagging during an encode" below) — for the app's own `EncodingEngine` only; the CLI, the API server's standalone engine, and encoding pipelines never auto-tag. `AutoTagger` itself is no longer dormant: its `determineLookupOrder`/`meetsThreshold`/`generateNFOPath` helpers back that feature; its rename/artwork helpers remain unused. Metadata *writing* is real and lives elsewhere: `MetadataTagEditorView` invokes ffmpeg directly (#467). |
| **Backend** | `Backend/EncodingBackend.swift` — an unused protocol scaffold retained deliberately (name-collision risk); the live abstraction is `FFmpeg/FFmpegBackend.swift` + `FFmpegBackendFactory`. Tracked by #477. |
| **Settings** | Export and import of MeedyaConverter's own settings between installations (#506) — `SettingsKeyRegistry` (the allow-list of every stored setting: 106 settings + 13 Application Support stores, each marked allowed, "This Mac only", or never, with a reason), `SettingsCategory`, `SettingsDocument` (the file envelope), `SettingsExporter`/`SettingsImporter`, `SettingsValueCodecs` (redaction and merge rules for JSON-blob settings), `SettingsSectionHandlers`, `SettingsCredentialNeeds` ("still needs a key", attributes-only), `SettingsExportSchema`/`SettingsCLIReportSchema` (generate the two JSON Schema files under `docs/schemas/`), and `SettingsCLIReport` (the CLI's `--format json` shape). See "Settings export and import" below. |
| **Server** | `APIServer` — real, and the only thing in this row that is: it is what `meedya-convert serve` starts (see the CLI table below), and all five HTTP routes call the real engine. `RenderFarmAgent`, `RenderFarmClient`, `RenderFarmConfigurationLoader` (Issue #346) are scaffolding for remote-agent submission with no working network transport — see "Dormant modules" below. |
| **Native** | Native platform integrations (Intents, App Intents) |
| **Platform** | `PlatformFormatPolicy` — platform-specific codec availability |
| **Utilities** | Temp file management, disk space monitoring |

#### Dormant modules

Code in `ConverterEngine` that compiles and is unit-tested but has **no call site
outside its own file**. It is listed here rather than omitted, so that this diagram
is not read as a claim that the capability ships. Verified by grep against
`wip/alpha-consolidation` on 2026-09-02; the same set is tracked in `FEATURES.md`
under "Known dead / orphaned code" — keep the two in step — and most of it
under issue #477.

| Module | Status |
| ------ | ------ |
| `ContentAnalyzer` | zero references outside its own file |
| `AIUpscaler` | named only in two comments (`FFmpegBackend.swift:52`, `FFmpegBackendFactory.swift:35`) — no call site |
| `ForensicWatermark` | zero references outside its own file |
| `StreamingEnhancements` (incl. `HLSEncryption`, `ThumbnailSpriteGenerator`) | zero references outside its own file |
| `HLGToDolbyVision` | zero references outside its own file |
| `ColorSpaceConverter` | zero references outside its own file; the live tone-map path is `FFmpegArgumentBuilder.ToneMapAlgorithm` |
| `CodecMetadataPreserver` | zero references outside its own file |
| `MatrixEncodingPreserver` | zero references outside its own file — not even from `FFmpegArgumentBuilder`'s downmix path. `audio-format-compatibility.md` previously described this as shipped ("Enabled by default (app-wide)"); corrected |
| `Stereo3DConverter` / `Video3DConverter` | zero references outside their own file (#477) |
| `SpatialAudioConverter` | zero references outside its own file — no Atmos/Ambisonics conversion UI exists anywhere in the app |
| `DRMPreparation` | zero references outside its own file — no caller besides its own unit tests |
| `SurroundUpmixer` | zero references outside its own file — no upmix UI exists anywhere in the app |
| `AudioFingerprinter` | zero references outside its own file |
| `AudioCDReader` / `DVDReader` / `BlurayReader` / `DiscImager` / `DiscAuthor` / `AccurateRipVerifier` | zero instantiation sites (`AccurateRipVerifier` is referenced only from a doc comment). `DiscBurner` is the one member of the Disc group that is real and wired |
| `Backend/EncodingBackend.swift` | unused protocol scaffold, retained deliberately (name-collision risk, #477) |
| `PipelineExecutor` (in `Encoding/EncodingPipeline.swift`) | zero references outside its own file; `PipelineEditorView` has no `onSave` wired to it |
| `Server/RenderFarmClient.swift`'s `RenderFarmTransportAdapter` | protocol with no concrete implementation outside unit tests (mock adapter only) — `RenderFarmAgent`/`RenderFarmClient` are real scaffolding around it, and `RenderFarmSettingsTab` is reachable, but no code path actually talks to a remote agent (#346, still `awaiting-user` in `FEATURES.md`'s gate ledger) |

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
| `DiscCommand.swift` | `disc` parent subcommand — `drives`/`toc`/`identify`/`image` |
| `SettingsCommand.swift` | `settings` parent subcommand — `export`/`import` (#506 commit 7); thin argument plumbing over `ConverterEngine`'s `SettingsExporter`/`SettingsImporter`, always targeting the Direct build's own settings domain, never `.standard` |
| `CLIUtilities.swift` | Shared utilities: exit codes, stderr printing |

### MeedyaConverter (SwiftUI App)

The macOS GUI application:

| Directory / File | Purpose |
| ---------------- | ------- |
| `Views/` | SwiftUI views — content, sidebar, source, stream inspector, output settings, queue, log, settings, help, dashboard |
| `Views/` (advanced) | Pipeline editor, schedule, conditional rules, post-encode actions, normalization, scene detector, comparison library + comparison viewer, FFmpeg preview, quality preview, profile suggestion, bitrate heatmap, audio waveform, encoding graphs, image conversion, metadata editor, media server settings, webhook settings, analytics settings, burn settings, keyboard shortcuts editor, render farm settings, license entry, paywall, resumable jobs, `SettingsTransferTab`/`SettingsImportPreviewSheet` (Settings › Import & Export, #506 commit 8 — a thin SwiftUI shell over `SettingsTransferViewModel`, which does all the logic and is unit-tested on its own) |
| `ViewModels/` | `@Observable` view models bridging the UI to the engine |
| `Components/` | Reusable UI components (progress bars, stream badges, etc.), plus `MenuBarController` — owns the `NSStatusItem` for menu-bar mode (Issue #281), toggled from Settings and persisted via `@AppStorage("menuBarMode")` |
| `Services/` | App-level services: `StoreManager` (StoreKit/RevenueCat), `AppUpdateChecker` (Sparkle), `ThumbnailCache`, `HardwareAccelerationPreference` (Issue #475 — the app-wide hardware-encoding kill switch, applied at all seven of the app's `EncodingJobConfig` build sites; the CLI and HTTP API are deliberately exempt), `KeyboardShortcutManager` (Issue #331 — user-assignable shortcuts, persisted to `UserDefaults`, with conflict detection), `URLSchemeHandler` (Issue #356 — parses `meedyaconverter://encode\|probe\|open` URLs; `MeedyaConverterApp` routes the parsed action against the live `AppViewModel`), `ComparisonLibraryManager` (Issue #329 — JSON persistence for the A/B comparison library) |
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
7. **Metadata** — Title, tags, chapter markers, cover art. When auto-tagging
   (below) found tags the file was missing, they are already sitting in
   `outputMetadata` by this point, so this stage needs no auto-tag-specific
   code of its own.
8. **Container settings** — Muxer options, faststart, fragment settings.
9. **Two-pass setup** — Generates separate pass-1 and pass-2 argument arrays if enabled.

---

## Auto-tagging during an encode (#508)

An opt-in switch (Settings › Metadata › "Tag files automatically while
converting", **off by default**) that looks a file up while it is being
converted, and adds whichever of its tags the file is missing — never
renaming it, never touching a tag it already has. The whole thing runs
inside `EncodingEngine.encode(job:onProgress:)`, between the source probe and
the first FFmpeg pass:

```text
Source probe (FFmpegProbe)
    │
    ▼
AutoTagRunner.plan(for:)          <- film, music, or skip — from the probe alone,
    │                                no network yet (TV names, no running
    │                                time, no artist for music, etc. skip here)
    ▼
AutoTagRunner.run(...)
    │  chooses TMDB (film) or MusicBrainz (music), or skips
    │  ("not connected yet" for TVDB/Discogs/fingerprinting, "no TMDB key"
    │  for a film with none saved)
    │
    │  races the actual lookup against:
    │    - a 30s deadline (AutoTagSettingsSource.deadline)
    │    - a 0.25s poll of "has Stop been pressed for this job?"
    │  — the first of the three to finish wins; the other two are cancelled
    │
    ▼
scored candidates (DiscIdentifier.rank for film,
MusicBrainzTagMapping.ranked + a duration-tolerance rule for music)
    │
    ▼
AutoTagRunner.judge(...) / judgeMusic(...)
    │  meetsThreshold (0.7 confidence) and an ambiguity check (two different
    │  candidates within 0.05 of each other are trusted to neither)
    │
    ▼
AutoTagMerge.additions(existing:jobTags:applying:)
    │  keeps ONLY the tags that were genuinely missing — a value the job or
    │  the source file already carries (matched case-insensitively, through
    │  aliases such as date/year) is never replaced
    │
    ▼
enrichedJob.outputMetadata  (merged in; the job's own tags still win)
    │
    ▼
FFmpegArgumentBuilder's existing `-metadata key=value` arguments
    │  (no change needed here — see step 7 above)
    ▼
FFmpeg pass(es) run, exactly as they would have without auto-tagging
    │
    ▼
AutoTagNFOWriter.write(...)        <- LAST step, only for an identified film
    │                                  whose config asked for a .nfo, and only
    │                                  once the output file genuinely exists;
    │                                  an existing .nfo is left untouched
    ▼
AutoTagJobEvent → EncodingEngine.autoTagEvents → AutoTagWording → Activity Log
```

**Never fails the encode.** A lookup that is off, skipped, not confident
enough, ambiguous, unreachable, or too slow is not an error: the file is
converted exactly as it would have been without auto-tagging, and what
happened is one line in the Activity Log. Only the user pressing Stop while
a lookup is in flight throws — the same `CancellationError` a Stop pressed
during FFmpeg itself would throw.

**Only one engine carries a settings source.** `EncodingEngine.autoTagSettings`
defaults to `nil`, and only `AppViewModel.init` passes one (reading the same
`UserDefaults` the Settings switch writes). The `meedya-convert` CLI, the
`APIServer`'s standalone engine (`APIServerView`/`APIServerViewModel`'s
default `EncodingEngine()`), and any encoding pipeline all build their own
`EncodingEngine` with no settings source at all, so none of them ever
auto-tags — whatever the switch says, and whatever `AutoTagConfig`'s fields
are set to. This is also why the REST API's `POST /encode` cannot reach
auto-tagging today even in principle: it only queues a job on whichever
engine the server was given, and the app's UI has no path yet that hands
`APIServer` the app's own (auto-tag-capable) engine instead of a fresh one.

See `.claude/plans/autotag-encode-plan.md` for the full design record,
including the confidence-scoring rules, the reasons TV episodes and artwork
are deferred, and the follow-up issues.

---

## Settings export and import (#506)

Moves preferences, connection details and the person's own encoding profiles
between installations, without ever writing a password, API key, token,
webhook address or hook to the file. All in `Sources/ConverterEngine/Settings/`
(`ConverterEngine`, not the app or the CLI), so the app's Settings › Import &
Export screen and `meedya-convert settings export`/`import` call the exact
same functions and never disagree about what a given file does.

```text
SettingsKeyRegistry                     <- the allow-list: ONE decision per
  (106 settings + 13 file stores)          setting (.allowed(category),
    │                                       .thisMac, or .never(reason)).
    │                                       A setting with no decision is
    │                                       never exported — the safe miss.
    ▼
SettingsCategory                        <- general / encoding /
  (5 tick-box groups)                      encodingProfiles / connections /
    │                                       thisMac (off by default, warns)
    ▼
SettingsExporter ───────► SettingsDocument (the envelope)
    │  reads a UserDefaults snapshot         { format, version, exportedAt,
    │  (never live defaults); redacts         appVersion, categories: {…},
    │  via SettingsValueCodecs; before         notIncluded: [names only] }
    │  returning, re-reads its OWN
    │  output through the importer so
    │  it can never write a file it
    │  would itself refuse
    ▼
SettingsImporter.prepare(data)          <- validates the WHOLE file, writes
    │                                      nothing yet. One bad value refuses
    │                                      the whole file (never half-read).
    ▼
SettingsImporter.preview(plan, …)       <- counts, what differs, warnings,
    │                                      cross-checks (e.g. "default
    │                                      profile isn't here, using X"),
    │                                      "still needs a key" (via
    │                                      SettingsCredentialNeeds — asks the
    │                                      Keychain only "does this exist?",
    │                                      never reads a secret)
    ▼
SettingsImporter.apply(plan, mode, …)   <- writes profiles FIRST (the only
                                            step that can fail), then
                                            UserDefaults (cannot fail) — so a
                                            failure never leaves a half-import
```

**Merge vs. replace**, both handled inside `SettingsValueCodecs` and
`SettingsImporter.apply`: merge only changes what the file mentions, and
merges list-type settings (SFTP servers, cloud destinations, conditional
rules, saved pipelines, profiles) by `id`; replace, within the ticked groups
only, also removes what the file doesn't have. Neither mode ever touches a
`.never` setting, a Keychain item, or an unticked group.

**Two JSON Schema files, both generated, never hand-edited**
(`SettingsExportSchema.generate()` / `SettingsCLIReportSchema.generate()`),
committed at `docs/schemas/settings-export-v1.schema.json` and
`docs/schemas/settings-cli-report-v1.schema.json`. `SettingsSchemaTests`
fails if either committed file differs from a fresh regeneration. A
test-only `SettingsSchemaMiniValidator` (in `ConverterEngineTests`, not
shipped) understands a deliberately small subset of JSON Schema keywords and
fails on any other keyword, so the schema can never quietly rely on
something the checker would silently ignore. Three safeguards in the export
schema catch a leak independently of the registry: an SFTP password must be
`""`, a cloud access token must be `""`, and a cloud refresh token / S3
secret key are forbidden outright (`additionalProperties: false` with
neither one listed).

**Two safety nets that don't trust each other:**

- **`SettingsKeyCoverageTests`** (the tripwire) scans every file under
  `Sources/` for `@AppStorage`/`forKey:`/`settingKey:` uses and fails,
  naming them, whenever a setting exists in the code with no registry
  decision, or the registry lists a setting nothing uses any more. It also
  feeds the scanner synthetic source to prove what it catches and what it
  cannot (documented in the scanner's own header) — a private constant
  whose string changes without a matching map entry being the main blind
  spot.
- **`SettingsKeyRegistrySentinelTests`** separately pins the secrets and
  other risky settings (`mediaServerAPIKey`, `webhookURL`,
  `postEncodeActionChain`, the analytics ID, the licence cache, and so on)
  to `.never`, by a hand-written list, without relying on the scan at all —
  so a bug in the scanner itself cannot silently reclassify a secret as
  safe.
- Independently of both, **`SettingsExportNoSecretTests`** plants sentinel
  strings in every place a secret could hide, exports every group, and
  re-reads the **bytes on disk** to assert the sentinel appears nowhere —
  the one test that checks the real output rather than the registry's
  intentions.

See `.claude/plans/settings-export-import-plan.md` for the full design
record, including the complete key-by-key inventory, the owner decisions,
and the follow-up issues.

---

## Encoding Queue Architecture

The encoding queue manages multiple jobs with priority ordering:

- Jobs have states: `pending`, `running`, `paused`, `completed`, `failed`, `cancelled`.
- The queue respects a configurable concurrency limit, re-read on every slot
  top-up so a mid-queue change takes effect immediately (default: 1
  concurrent encode; Issue #286). Raising it above 1 additionally requires
  the `.parallelEncoding` entitlement — an unentitled install is clamped to
  1 regardless of the stored setting. Multi-job concurrency has not been
  exercised against a real multi-process FFmpeg run in this environment
  (tests cannot execute here and CI cannot spawn a second encode), so treat
  width > 1 as unverified in practice even though the gating logic is
  reviewed.
- `EncodingStatisticsRecorder` and `PostEncodeHookRunner` (Issue #286) exist
  specifically for width > 1: they serialise statistics writes and
  post-encode hook chains respectively, so two jobs finishing at the same
  moment cannot clobber each other's statistics entry or run their hook
  chains concurrently.
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
