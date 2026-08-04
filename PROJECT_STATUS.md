<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter -- Project Status

> **Last Updated:** 2026-08-04
>
> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overall Progress

| Metric | Value |
| ------ | ----- |
| **Current Version** | `v0.1.0-rc.3` published (2026-05-18); `v0.1.0-rc.4` (short soak release) pending |
| **Last Release** | `v0.1.0-rc.3` (2026-05-18) -- direct distribution DMG + CLI tarball |
| **v0.1.0 GA scope** | **Complete.** The autopilot security + release-engineering mission reached TERMINAL: the full test suite green in CI, 0 compiler warnings, security findings F-001..F-012 closed/mitigated/risk-accepted, FFmpeg now sourced as a universal (arm64 + x86_64) binary from a first-party, SHA-256-verified mirror |
| **Current Phase** | Phase 16 -- Polish and Distribution (ongoing); GA release engineering |
| **Next Target** | Cut `v0.1.0-rc.4` for a short soak, then tag `v0.1.0` GA -- Direct distribution only (signed + notarised + stapled `.app` in a `.dmg`, plus a signed/notarised CLI tarball, via GitHub Releases). App Store Lite is explicitly deferred (#392) |
| **Active Work** | rc.4 soak validation and GA tag prep. Full 19-phase roadmap (Phases 10-18: optical disc, Windows/Linux, image conversion, etc.) continues post-GA per [Project_Plan.md](Project_Plan.md) -- v0.1.0 GA is a release milestone, not "everything in the plan is done" |

---

## Recent milestones (2026-07-22 to 2026-08-04 -- `wip/alpha-consolidation`)

- **Cloud-upload execution landed (PR #472)** -- real, authenticated upload
  to S3 (SigV4), Dropbox, Google Drive, OneDrive (chunked/resumable), and
  SFTP (`scp`). YouTube/Vimeo remain disabled pending OAuth (#446). Not yet
  in a tagged release.
- **Post-encode / completion automation wired** -- unified statistics
  dashboard, email + webhook completion notifications, watch-folder
  auto-encode, recent files & pinned favourites, scheduled encoding,
  IntAppsAPI remote feature-flags + alpha/beta update channels, and
  overwrite-existing / delete-source-after-encode toggles. Ten previously
  orphaned views were also wired into app navigation. All of this is real
  code on this branch, none of it is in the released `v0.1.0-rc.3` build.
- **Docs honesty reconciliation (this pass)** -- README, this file,
  CHANGELOG, and FEATURES.md were audited against the actual call graph
  (static analysis; no `swift build` available in this environment).
  Several "What's Complete" claims turned out to reference orphaned code
  with no real caller/executor -- see the new "Planned / scaffolded" group
  below. Two findings worth flagging explicitly: the **Scene Detection**
  view builds FFmpeg arguments but never runs FFmpeg (it logs "requested"
  and returns -- #288, same class of bug `LoudnessReportView`/
  `QualityMetricsView`/`BenchmarkView` had before #433-#435 fixed them, but
  this one was never fixed), and **AccurateRip verification** has no real
  caller either (`AudioCDReader` has zero instantiation sites). Issue count
  and test counts below are stated only where verifiable from this
  environment; unverifiable specifics were reworded rather than restated.

---

## Recent milestones (2026-06-30 to 2026-07-21 -- autopilot security & release-engineering mission)

- **Autopilot mission reached TERMINAL** at commit `b58d676` -- the full test
  suite green and 0 compiler warnings at that checkpoint (re-verified in CI
  as of 2026-07-21; exact test counts are not reproduced in this document
  since they can only be confirmed by CI, not by static review -- see
  [CHANGELOG.md](CHANGELOG.md) for dated entries).
- **Security findings F-001..F-010 closed or risk-accepted** across a
  red-team/blue-team/purple-team review rotation documented in
  [SECURITY.md](SECURITY.md): FFmpeg argument-construction audit (F-001),
  AppleScript path-traversal fix (F-002), GitHub-release download host
  allow-listing (F-003), Keychain accessibility hardening (F-004), SFTP
  password migration out of `UserDefaults` into Keychain (F-005), probe
  metadata sanitisation against terminal/log forgery (F-006), FFprobe
  watchdog + buffer caps (F-007), ScriptingBridge/Shortcuts input hardening
  (F-008), and the `MeedyaSuite-core` branch-pin risk acceptance (F-009).
  GitHub Actions tag-pin linting + Dependabot wiring (F-010) is
  mostly-fixed, with the one-shot SHA-pin conversion kept as optional
  hygiene, not a GA blocker.
- **A post-VERIFY adversarial review surfaced two further findings**, both
  now closed: **F-011** (FFmpeg supply chain -- `scripts/bundle-ffmpeg.sh`
  previously downloaded from a third-party static-build host with no
  integrity check) and **F-012** (a PID-reuse TOCTOU nit in the FFprobe
  watchdog's terminate/kill path).
- **F-011 fixed -- FFmpeg is now a universal, first-party, verified
  supply chain.** `scripts/bundle-ffmpeg.sh` sources `ffmpeg` / `ffprobe` /
  `ffplay` solely from the first-party mirror **MeedyaSuite/MeedyaDL-Tools**,
  pinned to an immutable dated release tag, and `lipo`-combines the
  mirror's per-arch archives (arm64 + x86_64) into a single universal
  binary per tool. Every archive is SHA-256-verified against the release's
  own `SHA256SUMS` **before** unpack, fail-closed (missing pin/checksums ->
  exit 6, mismatch -> exit 7). The old URL-keyed
  `scripts/ffmpeg-checksums.txt` bridge has been removed -- the trust root
  is now the tagged release itself, no local hash list to maintain.
  `.github/workflows/release.yml` builds the app itself universal too
  (`swift build -c release --arch arm64 --arch x86_64`).
- **F-012 mitigated** -- the FFprobe watchdog's finished-check,
  `isRunning` re-check, and the actual terminate/kill now happen under a
  single lock, closing the realistic "timer fires after normal completion"
  race window. A sub-microsecond kernel-level race remains inherent to
  signalling any `Foundation.Process` by PID and is accepted (documented
  inline).
- **Documentation refresh (this pass)** -- `Sources/MeedyaConverter/Resources/Help/cli-reference.md`
  rewritten against the real `meedya-convert` command surface (it
  previously called the binary `meedya-cli` and claimed the CLI was
  unimplemented -- both were stale; the CLI shipped in Phase 4), a new
  `Sources/MeedyaConverter/Resources/Help/vector-conversion.md` help topic added for the Vector Conversion
  and ProRes-to-Vector Tools views, and this file, `Project_Plan.md`,
  `DEV_NOTES.md`, and `CHANGELOG.md` brought back in line with the current
  state of the repository.
- **GA-honesty fixes landed (2026-07-21)** -- Recent DISCOVER audit identified autonomously-buildable feature gaps and UI fabrications. Fixes: #444 (VideoTrimmer real trim) and #445 (QualityCheck real QC) merged to main; #446 (VideoUpload OAuth), #447 (SFTP probe), #449 (DuplicateFinder Perceptual) addressed with honest disable/probe status; #448/#450/#451 open for backlog triage (#451 is Swift 6 concurrency audit in progress on fix/quality-sweep). FEATURES.md updated to reflect actual discovered gaps rather than stale "none identified" claim.

---

## Recent milestones (2026-05-18 / -19)

- **#382 integration batch merged** — Suite-core scaffolding (#371-#374),
  subtitle tone-mapping (#369), render farm scaffolding (#346),
  raster/vector engine (#376/#377), FFplay bundling (#378), App Store
  metadata + runbook (#178). ~3700 lines, 21 commits.
- **#380 security audit fully closed** — all four deferred items landed
  (FTP creds → 0600 config file, API keys → Keychain, TempFileManager
  orphan auto-cleanup, RenderFarmClient `.plainHTTP` → InsecureTransport-
  Override token).
- **#381 UI gap fully closed** — six new SwiftUI surfaces shipped:
  Subtitles section in OutputSettingsView, Metadata + Audio CD +
  Render Farm tabs in Settings, Vector Conversion + ProRes to Vector
  views in the Tools sidebar.
- **TestFlight workflow guardrails in place (#392/#393)** — automated
  App Store submissions cannot fire on tag pushes until explicit
  re-enable AND completion of #386-#391 ITMS findings.
- **`v0.1.0-rc.3` published** — signed (Developer ID) and notarized
  DMG + CLI tarball available at the GitHub Releases page.

---

## Release Gates

| Release | Phases | Description | Status |
| ------- | ------ | ----------- | ------ |
| **Alpha 0.1** | 0, 1, 2 | Core engine + macOS app -- first testable build | Complete |
| **Alpha 0.2** | 3, 4 | Essential codecs, passthrough, HDR + CLI tool | Complete |
| **Beta 0.5** | 5, 6 | Subtitles, audio normalisation, HLS/DASH | In Progress |
| **Beta 0.7** | 7, 8 | Extended formats, spatial audio, advanced audio | In Progress |
| **RC 0.9** | 9 | Professional features (VMAF, watch folders, AI upscaling) | In Progress |
| **Ongoing** | 16 | Polish and Distribution -- runs throughout development | Ongoing |
| **v1.1+** | 10, 11 | Optical disc ripping and authoring | Planned |
| **v1.3+** | 12 | Cloud uploads | In Progress |
| **v1.5+** | 15 | Media metadata lookup | In Progress |
| **v2.0** | 13, 14 | Windows and Linux | Planned |
| **v3.0+** | 17 | Image conversion | Planned |

> 📌 The `v0.1.0` GA milestone tracked in this document is a **Direct
> distribution release milestone** layered on top of the release-gate
> roadmap above (Alpha 0.1 through RC 0.9 phases feeding it), not a
> stand-in for "every phase in the plan is finished." Phases 10-18 continue
> after GA per [Project_Plan.md](Project_Plan.md).

---

## Phase Status Overview

| Phase | Name | Status | Progress | Release |
| ----- | ---- | ------ | -------- | ------- |
| **0** | Project Setup and Architecture | Complete | 100% | -- |
| **1** | Core Engine Foundation | Complete | 100% | Alpha 0.1 |
| **2** | macOS SwiftUI Application (MVP) | Complete | 100% | Alpha 0.1 |
| **3** | Essential Encoding and Passthrough | Complete | 100% | Alpha 0.2 |
| **4** | CLI Tool (meedya-convert) | Complete | 100% | Alpha 0.2 |
| **5** | Subtitles and Core Audio Processing | In Progress | 70% | Beta 0.5 |
| **6** | Adaptive Streaming (HLS/MPEG-DASH) | In Progress | 80% | Beta 0.5 |
| **7** | Extended Formats and Spatial Audio | In Progress | 60% | Beta 0.7 |
| **8** | Advanced Audio Processing | In Progress | 50% | Beta 0.7 |
| **9** | Professional Features | In Progress | 60% | RC 0.9 |
| **10** | Optical Disc Ripping (22 types) | In Progress | 30% | v1.1+ |
| **11** | Disc Image Creation and Burning | In Progress | 20% | v1.2+ |
| **12** | Cloud Integration and Uploads | In Progress | 50% | v1.3+ |
| **13** | Platform Expansion -- Windows | Planned | 0% | v2.0 |
| **14** | Platform Expansion -- Linux | Planned | 0% | v2.0 |
| **15** | Media Metadata Lookup | In Progress | 40% | v1.5+ |
| **16** | Polish and Distribution | Ongoing | 35% | Ongoing |
| **17** | Image Conversion (future) | In Progress | 10% | v3.0+ |
| **18** | AI-Powered Features (wishlist) | In Progress | 10% | TBD |

---

## Phase 0: Project Setup -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 0.1 | Project scaffolding (SPM, directories) | Complete | Package.swift, 3 targets, builds and tests pass |
| 0.2 | Documentation | Complete | README, Plan, Status, Changelog, Sources/MeedyaConverter/Resources/Help/, docs/ wiki |
| 0.3 | .gitignore | Complete | All platforms covered |
| 0.4 | GitHub Actions CI | Complete | build.yml, release.yml, beta-alpha.yml, codeql.yml, dependency-review.yml, security-check.yml, dev-build.yml, testflight.yml |
| 0.5 | GitHub Project Board | Complete | Project #13, 246 issues, 19 milestones |
| 0.6 | License file | Complete | Proprietary + third-party acknowledgments |
| 0.7 | Claude context | Complete | Project brief, standing tasks, prompt history |
| 0.8 | Clean up legacy code | Complete | All prior iteration files removed |
| 0.9 | Remote repo URL | Complete | Updated to MWBMPartners/MeedyaConverter |

---

## Phase 1: Core Engine Foundation -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 1.1 | FFmpeg bundle manager | Complete | Binary discovery, version detection, validation, caching |
| 1.2 | FFmpeg process controller | Complete | Start, pause, resume, stop with progress monitoring |
| 1.3 | Media file probing (FFprobe) | Complete | Streams, HDR, chapters, metadata |
| 1.4 | Data models | Complete | MediaFile, MediaStream, VideoCodec, AudioCodec, ContainerFormat, SubtitleFormat |
| 1.5 | FFmpeg argument builder | Complete | Translates encoding settings to FFmpeg CLI arguments |
| 1.6 | Encoding profile system | Complete | Presets, CRUD, JSON persistence, 7 built-in profiles |
| 1.7 | Encoding job and queue | Complete | Job config, state tracking, priority queue management |
| 1.7a | Temp file management | Complete | Per-job directories, cleanup, disk space monitoring |
| 1.8/1.9 | Encoding engine | Complete | Video and audio encoding orchestration, multipass support |
| 1.10 | Unit tests | Complete | Grew substantially from the Phase 1 baseline; full suite green (verified in CI) |
| 1.11 | Feature gating system | Complete | ProductTier, Feature, FeatureGateProtocol |

---

## Phase 2: macOS SwiftUI Application -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 2.1 | App shell and navigation | Complete | Sidebar, main content, inspector |
| 2.2 | Source file import | Complete | Drag-and-drop, file picker, recent files |
| 2.3 | Stream inspector | Complete | Video, audio, subtitle track details |
| 2.4 | Output settings | Complete | Codec, quality, container, per-stream config |
| 2.5 | Encoding queue | Complete | Queue management, progress, pause/resume/cancel |
| 2.6 | Log viewer | Complete | Real-time FFmpeg output |
| 2.7 | Settings/preferences | Complete | General, encoding, paths, updates |
| 2.8 | Help system | Complete | In-app help, Sources/MeedyaConverter/Resources/Help/ documentation |
| 2.9 | Profile management | Complete | Create, edit, delete, import, export profiles |

---

## Phase 3: Essential Encoding and Passthrough -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 3.1 | Video passthrough | Complete | Copy video without re-encoding |
| 3.2 | Audio passthrough | Complete | Copy audio without re-encoding |
| 3.3 | Subtitle passthrough | Complete | Copy subtitles without conversion |
| 3.4 | HDR-to-SDR tone mapping | Complete | Hable, Reinhard, Mobius, BT.2390, Clip |
| 3.5 | PQ-to-HLG conversion | Complete | hlg-tools preferred, FFmpeg zscale fallback |
| 3.6 | PQ-to-DV conversion | Complete | Profile 8.4 + HLG combined, three-tier fallback |
| 3.7 | Dolby Vision preservation | Complete | RPU extract/encode/inject via dovi_tool |
| 3.8 | HLG-to-DV conversion | Complete | Auto-generate via dovi_tool |
| 3.9 | Container-codec validation | Complete | Compatibility matrix with UI warnings |
| 3.10 | Crop detection | Complete | FFmpeg cropdetect |
| 3.11 | Hardware encoder detection | Complete | VideoToolbox, NVENC, QSV, AMF, VA-API |
| 3.12 | Stream metadata editor | Complete | Edit title, language, disposition |

---

## Phase 4: CLI Tool -- Detail

| # | Task | Status | Notes |
| - | ---- | ------ | ----- |
| 4.1 | CLI entry point and subcommand routing | Complete | `MeedyaConvert.swift` with ArgumentParser; binary name is `meedya-convert` |
| 4.2 | encode subcommand | Complete | Full options: codec, CRF, bitrate, preset, resolution, HDR, passthrough, stream selection |
| 4.3 | probe subcommand | Complete | Text and JSON output, streams-only, HDR details |
| 4.4 | profiles subcommand | Complete | Flag-driven: `--list`, `--show`, `--export`, `--import`, `--validate`, `--platform` |
| 4.5 | batch subcommand | Complete | Directory scan and job file modes, recursive, extension filter |
| 4.6 | manifest subcommand | Complete | HLS, DASH, CMAF with variant ladders, dry-run |
| 4.7 | validate subcommand | Complete | Profile, profile-file, manifest validation with strict mode |
| 4.8 | Exit codes | Complete | POSIX-compliant: 0, 1, 2, 3, 4, 5, 6, 130 -- see `Sources/MeedyaConverter/Resources/Help/cli-reference.md` |
| 4.9 | JSON progress output | Complete | Machine-readable progress and result output |
| 4.10 | OpenAPI CLI specification | Complete | Full spec in docs/api/meedya-convert-api.yaml, cross-checked against source this pass |

---

## What's Complete

- Project plan with 19 phases (0-18), release gates, feature gating, and 215+ tasks
- Full documentation suite: README, Project Plan, Project Status, Changelog, 9 help docs, 10 wiki pages, OpenAPI spec
- Architecture: ConverterEngine (library) + meedya-convert (CLI) + MeedyaConverter (SwiftUI app)
- SPM package with 3 targets -- builds and the full test suite passes (verified in CI, 0 compiler warnings)
- Hybrid encoding engine (FFmpeg subprocess + AVFoundation/FFmpegKit)
- Dual update strategy (Sparkle 2 direct + Apple-managed App Store)
- Three-tier file access for App Store sandbox
- GitHub: 19 milestones, 26+ labels, 246 issues, project board
- CI/CD: 8 GitHub Actions workflows (build, release, beta/alpha, codeql, dependency-review, security-check, dev-build, testflight)
- Issue templates, security policy, CODEOWNERS, PR template, LICENSE
- FFmpeg bundle manager, process controller, argument builder
- **Universal (arm64 + x86_64) FFmpeg supply chain** -- `ffmpeg`/`ffprobe`/`ffplay`
  sourced solely from the first-party `MeedyaSuite/MeedyaDL-Tools` mirror,
  pinned to an immutable release tag, SHA-256-verified against the release's
  own `SHA256SUMS` before unpack, fail-closed (F-011). The app itself also
  builds universal via `swift build -c release --arch arm64 --arch x86_64`.
- Media probing via FFprobe -- streams, HDR detection, chapters, metadata
- Complete data models -- 16 video codecs, 30+ audio codecs, 25+ containers, 14+ subtitle formats
- Encoding profile system with 7+ built-in presets and JSON persistence
- Job queue with priority ordering, state tracking, batch management
- Temp file management with per-job directories and disk monitoring
- Encoding engine orchestrating full video/audio conversion pipeline
- Feature gating system (free/pro/studio tiers)
- Full macOS SwiftUI app: 35+ views including sidebar, source import, stream inspector, output settings, queue, log, dashboard, pipeline editor, schedule, conditional rules, post-encode actions, bitrate heatmap, audio waveform, quality preview, FFmpeg preview, paywall, analytics settings, media server settings, Vector Conversion, ProRes to Vector -- **note:** the view existing and being reachable does not mean its backend is wired; see "Planned / scaffolded" below for the ones that aren't (pipeline editor, conditional rules, Vector Conversion, and ProRes to Vector among them)
- Passthrough (video/audio/subtitle), stream selection, metadata editor, HDR warnings
- HDR-to-SDR tone mapping with auto-trigger for incompatible settings
- PQ-to-HLG conversion, PQ-to-DV Profile 8.4, Dolby Vision RPU pipeline
- HLG-to-DV auto-conversion, three-tier DV/HLG/SDR fallback
- Container-codec compatibility matrix with validation and UI warnings
- Automatic black bar crop detection, hardware encoder detection
- In-app help system, settings view, profile management
- CLI tool with 6 subcommands: encode, probe, profiles, batch, manifest, validate
- Licensing module: EntitlementGating, ProductCatalog, StoreManager, RevenueCat, LicenseKeyValidator
- Quality metrics (VMAF/SSIM/PSNR) and encode benchmarking, both wired to real FFmpeg execution (#433-#435)
- Image converter
- Audio loudness normalisation (EBU R128) wired to real FFmpeg execution (#433)
- Post-encode webhook notifications and manual media-server library-scan
  trigger (Plex/Jellyfin/Emby -- real `URLSession` calls from Settings);
  automatic media-server scan and cloud-upload post-encode actions are
  real on `wip/alpha-consolidation` but **not yet in a tagged release**
  (see "Landing in the next alpha build" below)
- MeedyaSuite-core integration scaffolding: Swift Package dependency
  (feature-flagged via `SUITE_CORE=1`), bridge + adapters for metadata
  and codec classification, and 12+ additional providers available
  through the unified system (#371, #372, #373, #374)
- Subtitle tone-mapping via quietvoid/subtitle_tonemap, wired end-to-end
  through the encoding pipeline via `SubtitleTonemapPipeline` (#369, #413)
- Render-farm submission subsystem: agent registry, chunked upload with
  per-chunk SHA-256, progress AsyncStream, pluggable transport, Settings UI
  (#346) -- transport implementations (SSH/TLS), Bonjour discovery, and the
  agent binary remain outstanding, #346 stays open
- App Store Connect metadata suite under `metadata/` and submission
  runbook at `docs/distribution/app-store-submission.md` (#178) -- App
  Store Lite ship itself remains explicitly deferred per #392

---

## Landing in the next alpha build

Implemented and real on `wip/alpha-consolidation` (PR #472 and follow-on
work), but **not in the released `v0.1.0-rc.3` build** -- do not describe
these as shipped until they land in a tagged release:

- Cloud-upload execution: real, authenticated upload to S3 (SigV4),
  Dropbox, Google Drive, OneDrive (chunked/resumable), and SFTP (`scp`).
  YouTube/Vimeo remain disabled pending OAuth (#446)
- Unified statistics dashboard (`AggregateStatistics`, `DashboardView`,
  `StatisticsExportView`)
- Email + webhook completion notifications (`WebhookSender`,
  `NotificationActionHandler`)
- Watch-folder auto-encode
- Recent files & pinned favourites (`RecentFilesManager`, `RecentFilesView`)
- Scheduled encoding (`EncodingScheduler`, `ScheduleView`)
- IntAppsAPI remote feature-flags + alpha/beta update channels
  (`IntAppsAPIClient`)
- Overwrite-existing / delete-source-after-encode toggles
- Automatic media-server library-scan trigger on encode completion
  (the manual "Trigger Library Scan Now" button already works today; the
  automatic on-completion trigger is the new part)
- Navigation exposure of 10 previously-orphaned views

---

## Planned / scaffolded (not yet wired into the app)

These have argument builders, data models, or UI, but no code path that
actually invokes them end-to-end -- no `Process` launch, no executor, or
the UI never calls the backend it displays. Grouped here instead of under
"What's Complete" so the roadmap context is kept without presenting them
as working. Verified by grepping for real callers outside each feature's
own defining file (a live check against this repository, not a claim
carried over from an earlier draft):

- **DRM & Encryption** -- `HLSEncryption` (AES-128 HLS) and
  `DRMPreparation` (Widevine/FairPlay/PlayReady CPIX/PSSH) are argument/
  document builders with no caller outside their own unit tests
- **Thumbnail Sprites** -- `ThumbnailSpriteGenerator` is exercised only by
  a unit test; no UI or pipeline calls it
- **Scene Detection** -- `SceneDetectorView.detectScenes()` builds FFmpeg
  arguments via `SceneDetector.buildDetectionArguments` but never launches
  FFmpeg; it logs "Scene detection requested... with N arguments" and
  immediately clears the in-progress flag. No scene is ever actually
  detected, despite the view being reachable from the Analysis Hub (#288)
- **AccurateRip verification / audio disc fidelity** -- `AudioCDReader`
  has zero instantiation call sites; `AccurateRipVerifier`'s API is only
  referenced from a doc comment in `SettingsView.swift`. Falls under the
  broader disc-ripping-is-orphaned finding below (#476)
- **Colour space converter** -- `ColorSpaceConverter`/`ColourSpaceConverter`
  are only called from `HDRPolicyEngine`, which itself has zero external
  callers. The real, shipped HDR tone-mapping path runs through
  `FFmpegArgumentBuilder.ToneMapAlgorithm` instead, a separate code path
- **Multi-stream selector** -- `MultiStreamSelector` has no callers outside
  its own file
- **Encoding reports** -- `EncodingReport` has no callers outside its own
  file (referenced only from a test)
- **Encoding pipelines** -- `PipelineEditorView`/`EncodingPipeline`/
  `PipelineExecutor`: the editor is presented from Output Settings with no
  `onSave` handler wired up, and `PipelineExecutor` (the generic multi-step
  runner) has zero callers anywhere in the app or engine
- **Conditional rules** -- never applied at encode time (#469)
- **Resumable jobs** -- no checkpoint writer; "resume" restarts at 0 (#468)
- **REST API server mode** -- implemented and unit-tested, but has no
  entry point; unreachable from the app or CLI (#355)
- **Post-encode hook chains** -- the generic chain engine
  (`PostEncodeActionChain`) is real but not persisted and not invoked on
  completion; note this is distinct from the webhook/media-server-scan
  wiring above, which calls those senders directly rather than through the
  chain (#277)
- **3D / Stereoscopic** -- `Stereo3DConverter`/`Video3DConverter` have zero
  callers (#477)
- **Media Metadata Lookup / Auto-Tagging** -- `AutoTagger` is orphaned; the
  metadata tag editor is display-only (#467, #205)
- **A/B Comparison** -- `ComparisonView` is orphaned (#329)
- **AI Upscaling** -- `AIUpscaler` exists only as a comment reference
  (#236, #477)
- **Forensic Watermarking** -- `ForensicWatermark` is orphaned (#477)
- **DCP generator, VVC encoder, TrueHD-MP4 muxer, HLG→Dolby Vision (dup),
  surround upmixer, speech-to-text, audio fingerprinter, content
  analyzer** -- all orphaned (#477)
- **Vector conversion / ProRes→Vector** -- argument builders exist
  (`RasterVectorConverter`, `ProResToVectorConverter`) but there is no
  executor and no source-file flow (#473)
- **Optical disc ripping & authoring** -- disc readers/authors are
  orphaned; disc **burning** is real and unaffected by this (#476)

---

## What's Next

1. **`v0.1.0-rc.4` soak, then `v0.1.0` GA tag** -- Direct distribution only:
   signed + notarised + stapled `.app` in a `.dmg`, plus a signed/notarised
   CLI tarball, both via GitHub Releases. App Store Lite stays deferred.
2. **MeedyaSuite-core binding stabilisation** -- Once MeedyaSuite-core
   publishes a Swift Package tag, migrate `Package.swift`'s branch pin to
   `from: "X.Y.Z"` (closes gate-ledger item G-014 / finding F-009), flip
   `SUITE_CORE` to default-on, and execute the #374 cleanup checklist
3. **Render-farm agent binary** -- Standalone agent app that runs on
   remote Macs and services the REST protocol defined in #346
4. **Optional POLISH-tier follow-ups** (not GA blockers): one-shot SHA-pin
   conversion for GitHub Actions `uses:` references (gate-ledger G-015,
   F-010), gitleaks CLI wiring for historical-secret scanning, and the
   ~17 remaining `appendingPathComponent` call sites that could be
   defensively migrated to `PathSanitizer` (F-002 follow-up)
5. **Phase 5/6/7/8/9 feature completion** -- Subtitles/streaming/extended-
   format/advanced-audio/professional-features work continues per
   [Project_Plan.md](Project_Plan.md); these are post-GA roadmap items,
   not blockers for the v0.1.0 Direct release
6. **App Store submission** -- Deferred until #392's re-enable
   preconditions are met and the #386-#391 ITMS findings are resolved;
   produce screenshot captures and verify the FFmpegKit LGPL variant
   when that work resumes

---

## Known Issues and Blockers

| Issue | Severity | Status | Notes |
| ----- | -------- | ------ | ----- |
| FFmpeg App Store strategy | Resolved | Resolved | Hybrid engine: AVFoundation/FFmpegKit for App Store |
| App Store sandbox file access | Resolved | Resolved | Three-tier: user-selected, bookmarks, Full Disk Access |
| FFmpeg supply-chain integrity (F-011) | Resolved | Fixed | Universal, first-party (MeedyaDL-Tools), SHA-256 fail-closed verification |
| Probe-watchdog PID-reuse (F-012) | Low (nit) | Mitigated | Single-lock terminate/kill; sub-microsecond kernel race accepted as inherent |
| `MeedyaSuite-core` branch pin (F-009) | Low | Risk-accepted | Gated behind `SUITE_CORE=1`, not on the v0.1.0 ship path; migrate once a tagged release exists |
| GitHub Actions tag pins vs SHA pins (F-010) | Low | Mostly-fixed | Tag-pin linter + Dependabot wired into CI; one-shot SHA conversion is optional hygiene |
| Optical disc DRM legality | Medium | Noted | CSS/AACS legality varies by jurisdiction |
| Swift 6.3 Windows maturity | Low | Noted | Windows UI framework TBD |

---

## Metrics

| Metric | Count |
| ------ | ----- |
| Total tasks across all phases | 215+ |
| GitHub Issues (open) | 98 (verified 2026-08-04) |
| Automated tests | Full suite green, 0 compiler warnings (verified in CI; exact count not restated here -- see CHANGELOG.md for dated entries) |
| Supported video codecs | 16 |
| Supported audio codecs | 30+ (including spatial) |
| Supported subtitle formats | 14+ |
| Supported containers | 25+ |
| Supported optical disc formats | 22 (target scope; ripping/authoring readers are scaffolded, not wired -- burning is) |
| Supported image formats | 20+ (future) |
| Cloud upload providers (execution) | 5 real on `wip/alpha-consolidation` (S3, Dropbox, Google Drive, OneDrive, SFTP), not yet released; 12+ is the target-scope count |
| Target platforms | 3 (macOS, Windows, Linux) |
| Wiki documentation pages | 10 |
| Help documentation files | 9 |
| SwiftUI views | 35+ |
| ConverterEngine modules | 15 |
| CLI subcommands | 6 |

---

*Updated automatically during development. See [Project_Plan.md](Project_Plan.md) for full task breakdown and [SECURITY.md](SECURITY.md) for the security findings register.*
