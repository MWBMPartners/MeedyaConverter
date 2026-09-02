# MeedyaConverter — Feature Gap Ledger

> Seeded from GitHub issue corpus (98 open, verified 2026-08-04) rather than
> a from-scratch `featurefind` run, since the project's issue tracker IS the
> authoritative feature-gap ledger for this product. Updated by the autopilot
> loop as new gaps surface.
>
> **Last reconciled:** 2026-09-02, against the actual call graph on
> `wip/alpha-consolidation` (static analysis; no `swift build` available in
> this environment). See "Known dead / orphaned code" below for items this
> pass found presented elsewhere in the docs as shipped when they have no
> real caller.

## Classification scheme

| Tier | Meaning |
|------|---------|
| **table-stakes** | Category-standard for a Mac video/audio converter; users expect it |
| **differentiator** | Beyond category baseline; shapes product positioning |
| **out-of-scope** | Foreign to product purpose; explicitly NOT in MeedyaConverter |
| **deferred** | In-scope but tracked as a multi-month effort; Phase A scaffolding only in autopilot |

## In-scope gaps the autopilot may build autonomously (Bucket 1)

**Recent DISCOVER audit found autonomously-buildable gaps**, now tracked as GitHub issues. Status as of 2026-08-04:

- **FIXED & merged to main:** #444 (VideoTrimmer real trim), #445 (QualityCheck real QC)
- **FIXED on `wip/alpha-consolidation` (PR #472, not yet released):** #450
  (post-encode SFTP/cloud) — cloud-upload execution now real for S3
  (SigV4), Dropbox, Google Drive, OneDrive (chunked/resumable), and SFTP
- **ADDRESSED (disabled/probed pending resolution):** #447 (real SFTP probe), #446 (VideoUpload/YouTube-Vimeo still disabled pending OAuth — PR #472 did not touch this one), #449 (DuplicateFinder Perceptual hidden pending pHash)
- **OPEN backlog:** #448 (placeholder UIs: DualDynamicHDR/BitrateHeatmap/AnimatedImage/EncodingGraphs/CloudSync), #451 (Swift 6 concurrency audit)

Earlier cycles' defensive infrastructure additions (SECURE phase: `PathSanitizer`, `MetadataSanitizer`, `SFTPCredentialStore`, FFmpegProbe watchdog) did not surface new in-scope gaps at that time, but subsequent adversarial review and DISCOVER passes have identified the gaps above. The remaining v0.1.0 must-do items are user-driven or tag-strategy decisions, not autonomously-buildable features.

## In-scope gaps awaiting user approval (Bucket 2 — gate-ledger)

All currently tracked as GitHub issues; full spec discussion is in the issue
bodies (linked here). Status mirrors `autopilot.json#gate_ledger`.

| Issue | Title | Tier | Effort | Status |
|-------|-------|------|--------|--------|
| #419 | OpenFX (OFX) plugin host support | differentiator | 3-5 months | awaiting-user |
| #420 | OpenColorIO integration | differentiator | 9-15 weeks | awaiting-user |
| #421 | Audio offset sync (fixed-offset multi-track muxing) | differentiator | 8-11 weeks | awaiting-user |
| #422 | Audio drift correction + cuts + spatial | differentiator | 15-19 weeks | awaiting-user |
| #423 | Audio-sync test corpus | infrastructure | 5-9 weeks | awaiting-user |
| #424 | Premium-tier feature gating + Expert Mode | infrastructure | 8-12 weeks | awaiting-user |
| #425 | Audio-sync waveform visualisation | infrastructure | 5-6 weeks | awaiting-user |
| #426 | Subtitle muxing with offset+drift sync (sync only) | differentiator | 7-10 weeks | awaiting-user |
| #427 | Subtitle sync via audio reference (follow-up to #422+#426) | differentiator | 3-4 weeks (after #422+#426) | awaiting-user |
| #416 | Long-term in-app updater (update.mwbm.io Cloudflare Worker) | infrastructure | 1-2 weeks | partially-approved (Sparkle B scaffolded this cycle) |
| #383 | Full LyricsFile (.lyrics) interconversion via MeedyaSuite-core | nice-to-have | TBD | awaiting-user |
| #364 | Cost estimation for cloud AI features | nice-to-have | TBD | awaiting-user |
| #346 | Remote encoding / render farm submission enhancements | nice-to-have | TBD | awaiting-user |

## Out-of-scope (explicitly NOT in MeedyaConverter)

Per the `feedback_subtitle_scope_split` memory and the project brief:

| Feature class | Home |
|---------------|------|
| Subtitle text editing | MeedyaSubtitler (separate repo, separate org) |
| Subtitle formatting controls (bold/italic/underline/colour) | MeedyaSubtitler |
| OCR for image subtitles | MeedyaSubtitler |
| Subtitle style management (ASS/SSA) | MeedyaSubtitler |
| Subtitle quality analysis / auto-fix | MeedyaSubtitler |
| Media downloading | MeedyaDL |
| Library management | MeedyaManager |
| Metadata aggregation | MeedyaDB |

## Platform expansion (deferred until macOS Direct GA ships)

| Issue | Phase | Status |
|-------|-------|--------|
| #147-#153 | Phase 13: Windows (build setup, WinUI 3, FFmpeg bundling, hardware encoding, installer, CI/CD, optical) | deferred to post-v0.1.0 |
| #154-#160 | Phase 14: Linux (build setup, GTK4, FFmpeg, hardware encoding, Pi, packaging, optical) | deferred |

## AI wishlist (Phase 18)

| Issue | Title | Status |
|-------|-------|--------|
| #235 | AI audio translation — multi-language voice synthesis | wishlist |
| #236 | AI video upscaling — neural network resolution enhancement | wishlist |
| #237 | AI HDR enhancement — SDR to HDR-like visual enhancement | wishlist |

## App Store Lite path (gated on user-side cert work)

| Issue | ITMS code | Type | Owner |
|-------|-----------|------|-------|
| #178 | (umbrella) | Phase 13.3 App Store Submission tracking | Mixed |
| #386 | ITMS-90270 | Unsupported toolchain → xcodebuild archive | Autopilot (code) |
| #387 | ITMS-90237 | 3rd Party Mac Developer Installer cert | User (cert acquisition) |
| #388 | ITMS-90230 | Invalid product-identifier/version | Autopilot (code) |
| #389 | ITMS-90264 | LSMinimumSystemVersion mismatch | Autopilot (code) |
| #390 | ITMS-90236 | Missing required 512@2x ICNS icon | Autopilot (icon regen) |
| #391 | ITMS-90889 | Bundle missing provisioning profile | User (profile) + Autopilot (embed) |
| #392 | (tracking) | Pre-conditions before re-enabling auto-submission | Mixed |

## Known dead / orphaned code (verified not wired)

Code that exists (argument builders, data models, or even reachable UI) but
has no caller/executor that actually runs it — a `Process` launch or a
non-test call site outside the defining file. Tracked here so README /
PROJECT_STATUS don't re-present it as shipped. Verified by grep against
`wip/alpha-consolidation` on **2026-09-02** (previous passes: 2026-09-01,
2026-08-04).

Since the 2026-09-01 pass: **A/B Comparison** (#329), **Scene Detection**
(#288), the menu bar (#281), URL-scheme routing (#356), user-assignable
keyboard shortcuts (#331), post-encode failure hooks (#277) and the hardware
kill switch (#475) were all wired up and are no longer dead — see the rows
below for what each one now actually does, and what (if anything) is still
missing. This pass also found three items presented as shipped elsewhere in
the docs that have no real implementation at all: matrix-encoding
preservation, spatial-audio (Atmos/Ambisonics) conversion, and the render-farm
network transport.

| Feature | Finding | Issue |
|---------|---------|-------|
| 3D / Stereoscopic (MV-HEVC, MV-H264) | `Stereo3DConverter` / `Video3DConverter` — zero callers | #477 |
| Spatial audio conversion (Atmos / Ambisonics / Auro-3D rendering) | `SpatialAudioConverter`, in the same file as `Video3DConverter` above (`Models/SpatialAudioProcessor.swift` — the file name does not match either public type it defines) — zero references outside that file, no UI. See the correction to `docs/Architecture.md`, which previously named a `SpatialAudioProcessor` module that does not exist under that name | *(none filed — found this pass)* |
| Matrix encoding preservation (Dolby Pro Logic II / DTS Neo:6 metadata on downmix) | `MatrixEncodingPreserver` (`FFmpeg/MatrixEncodingPreserver.swift`) — zero references anywhere outside its own file, not even a call from `FFmpegArgumentBuilder`'s downmix path. No UI exposes it | *(none filed — found this pass)* |
| Media Metadata **lookup** / auto-tagging | Dead in full: `Sources/ConverterEngine/Metadata/` contains no `URLSession`/`URLRequest`/`JSONDecoder` at all, so every provider (MusicBrainz, TMDB, TVDB, Discogs, FanArt, OpenSubtitles, OMDb) is a URL *builder* only; `AutoTagger` has zero references outside its own file; `MetadataEditorView` is orphaned; `MetadataTagEditorView` has no lookup affordance | #205, #493 |
| A/B Comparison viewer | **FIXED** — `ComparisonView` now runs a real capture → persist → compare loop: `ComparisonLibraryView` (reachable from the sidebar) probes source/encoded frame pairs and whole-clip SSIM/PSNR via real `FFmpegProcessController` runs, and `ComparisonLibraryManager` persists entries as JSON so the library survives relaunch | #329 |
| AI Upscaling | `AIUpscaler` — named only in comments at `FFmpegBackend.swift:52` and `FFmpegBackendFactory.swift:35`; no call site | #236, #477 |
| Forensic Watermarking | `ForensicWatermark` orphaned | #477 |
| DCP generator, VVC encoder, TrueHD-MP4 muxer, surround upmixer, speech-to-text, audio fingerprinter, content analyzer | all orphaned | #477 |
| Vector conversion / ProRes→Vector | arg-builders exist, no executor, no source-file flow; confirmed again this pass — `VectorConversionView` is a settings editor only (no file picker, no "Convert" action) | #473 |
| Conditional rules | **FIXED** (`27b42dd`) — applied at enqueue, and the rules view is reachable | #469 |
| Resumable jobs | **Honest-minimal shipped** (`444bde1`) — checkpoints written on cancel/fail, view surfaced, "Resume" relabelled "Re-queue". True seek-resume is still future work | #468 |
| REST API server mode | **FIXED** (`1773763`) — `meedya-convert serve` starts the real `APIServer`, and all five routes call the real engine. `APIServerView` remains orphaned (no `NavigationItem` case — its only call site is a `#Preview`), so the CLI is the only entry point | #355, #448 |
| Post-encode hook chains | **FIXED** (`761101c`) — chain persisted and invoked on completion, watch-folder `postAction` honoured, and the failure path now runs too: `AppViewModel`'s failure handler loads the persisted chain and calls `PostEncodeHookRunner.run(..., success: false)`, so `runOnFailure` actions actually fire | #277 |
| Disc ripping & authoring | readers/authors orphaned — disc **burning** is real and unaffected. Per `docs/decisions/0001-gpl-disc-tools.md` (#494), raw-device imaging is Direct-distribution-only forever regardless of tooling, since the App Sandbox has no raw-optical-device entitlement | #476 |
| DRM & Encryption (AES-128 HLS; Widevine/FairPlay/PlayReady) | `HLSEncryption` and `DRMPreparation` — no caller outside their own unit tests. `adaptive-streaming.md` and `faq.md` previously described this as shipped; corrected | *(none filed — found this pass)* |
| Thumbnail Sprites | `ThumbnailSpriteGenerator` — exercised only by a unit test | *(none filed — found this pass)* |
| Scene Detection | **Mostly fixed** — `SceneDetectorView.detectScenes()` now builds FFmpeg args via `SceneDetector.buildDetectionArguments` and actually runs them through `FFmpegProcessController`, parsing real scene-change timestamps back from the filter's output file. The remaining gap: "Apply to Job" is still permanently disabled, because `EncodingJobConfig` has no field to attach a chapters file to | #288 |
| AccurateRip verification / audio disc fidelity | `AudioCDReader` has zero instantiation sites; `AccurateRipVerifier` only referenced from a doc comment | *(none filed — found this pass; falls under #476)* |
| Colour space converter | `ColourSpaceConverter` and `HDRPolicyEngine` were **deleted** (`7f59196`). `ColorSpaceConverter` (US spelling) survives with zero references outside its own file, retained deliberately for a name collision | #477 |
| Multi-stream selector | **Deleted** (`7f59196`) — no longer in the source tree | #477 |
| Encoding reports | **Deleted** (`7f59196`) — no longer in the source tree | #477 |
| Encoding pipelines (generic, user-configurable) | `PipelineEditorView` has no `onSave` wired; `PipelineExecutor` has zero callers anywhere | *(none filed — found this pass)* |
| Render-farm submission (`meedya-convert` remote agents) | `RenderFarmSettingsTab` and its `RenderFarmClient`/`RenderFarmAgent` scaffolding are real, but `RenderFarmTransportAdapter` — the protocol that would actually talk SSH/TLS/HTTP to an agent — has no concrete implementation anywhere outside unit tests (mock adapter only); Bonjour discovery is not active. The settings tab's own code comments say as much. `render-farm.md` previously documented this as a complete, shipped feature (companion agent app, chunked SHA-256 uploads, live job polling); corrected. Matches the gate ledger above ("In-scope gaps awaiting user approval"), where #346 is still `awaiting-user`, not an approved-and-built feature | #346 |

Also verified dormant on 2026-09-02 — present, compiling, unit-tested where
noted, but with **zero references outside their own file**: `ContentAnalyzer`,
`ForensicWatermark`, `StreamingEnhancements` (which contains `HLSEncryption`
and `ThumbnailSpriteGenerator`), `HLGToDolbyVision`, `CodecMetadataPreserver`,
`DRMPreparation`, `Stereo3DConverter`, `SpatialAudioConverter`,
`MatrixEncodingPreserver`, `SurroundUpmixer`, `AudioFingerprinter`,
`DiscImager`, `DiscAuthor`, `DVDReader`, `BlurayReader`. The same list appears
under "Dormant modules" in `docs/Architecture.md`; keep the two in step.

Deleted outright by the orphan sweep (`af83104`, `7f59196`) and therefore no
longer dead code — do not re-add them to this table: `AudioMixer`,
`ClosedCaptionHandler`, `SubtitleOCR`, `SubtitleConverter`, `EncodingReport`,
`MediaInfoIntegration`, `MetadataPassthrough`, `MetadataTagger`,
`MultiStreamSelector`, `SmartCropIntegration`, `HDRPolicyEngine`,
`ColourSpaceConverter`, `PQToHLGPipeline`, and the four `Extended*` modules.

Items marked "found this pass" were not in the prior gap ledger and don't
yet have a filed issue; file one before building against them so the work
is trackable.

## Refresh policy

Re-evaluate at the start of each COMPLETE-phase cycle. New issues surfacing
on GitHub mid-loop are added here at REHYDRATE if they classify as in-scope
gaps.
