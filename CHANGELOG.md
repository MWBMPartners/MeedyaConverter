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

### Added -- 2026-05-18 (UI gap closure for #381 + audit follow-ups)

- **Subtitle tone-mapping UI** -- `OutputSettingsView` gains a new
  Subtitles section with a master toggle, HDR source profile picker,
  target luminance stepper, and preserve-alpha toggle. Bound to a new
  optional `EncodingProfile.subtitleTonemap: SubtitleTonemapConfig?`.
  (PR #397, addresses #396 / part of #381)
- **MeedyaSuite-core metadata backend UI** -- new "Metadata" tab in
  Settings → Encoding with a picker over `SuiteCoreMetadataBackend`,
  AppStorage persistence, and a live status line. The `.suiteCore`
  option is rendered as disabled when `SuiteCoreAvailability.isAvailable`
  is false. (PR #399, addresses #398 / part of #381)
- **AccurateRip submission UI** -- new "Audio CD" tab in Settings →
  Encoding with toggle + drive model + read offset stepper (±500
  samples) + software identifier + Link to the AccurateRip drive-offset
  table. Subordinate fields are `.disabled` when the master toggle is
  off. (PR #401, addresses #400 / part of #381)
- **Vector Conversion UI** -- new "Vector Conversion" view under the
  Tools sidebar, bound to `RasterToVectorConfig` with Input/Preset/
  Tracing/Alpha/Animation/Other sections. Preset auto-drives tracing
  mode + colour count except for `.custom`. Animation section only
  renders when input format is animated. (PR #403, addresses #402 /
  part of #381)
- **ProRes → Vector UI** -- new "ProRes to Vector" view under the
  Tools sidebar, bound to `ProResToVectorConfig` with Source/Alpha/
  embedded-tracing-editor/Animation/Assembly/Warning sections. Reuses
  the new factored `RasterToVectorConfigEditor`. Output-size warning
  fires when `shouldWarnAboutOutputSize(...)` returns true.
  (PR #405, addresses #404 / part of #381)
- **Render Farm settings UI** -- new "Render Farm" tab in Settings →
  Services with insecure-transport toggle + acknowledgement, Bonjour
  discovery interval stepper, chunk size segmented picker (1/4/16/64
  MiB), agents list with discovered/manual badges, and an Add-agent
  modal sheet. AppStorage-backed today; engine consumer reads the keys
  when #346 transport lands. (PR #407, addresses #406 / part of #381)

### Fixed -- 2026-05-18 (release.yml stabilisation)

- **Keychain tests in release-mode CI** -- a fresh GitHub Actions
  `macos-15` runner has no unlocked default user keychain, causing all
  four `APIKeyManagerKeychainTests` cases to report empty secrets on
  hydrate. The tests now probe Keychain round-trip in `setUpWithError`
  and `XCTSkip` cleanly when persistence is unavailable, instead of
  falsely failing. (PR #394)
- **release.yml changelog extraction on BSD sed** -- the trailing-
  blank-strip in `scripts/extract-changelog.sh` used the GNU-sed idiom
  `-e :a -e '/^\n*$/{$d;N;ba}'`, which BSD sed (macOS default) rejects
  with "unexpected EOF (pending }'s)". Replaced with portable awk that
  buffers all lines, tracks the last non-blank, and emits up to that
  point. (PR #395)
- **AppIcon asset catalog** -- previously contained only `app-icon.svg`,
  which SPM's asset-catalog compiler does not consume at multiple sizes,
  producing a built bundle with a generic/missing icon. Rasterized PNGs
  at the seven distinct macOS sizes (16/32/64/128/256/512/1024) added
  to `AppIcon.appiconset/`. `scripts/export-icons.sh` extended to keep
  the catalog in sync on regeneration. (PR #385)

### Security -- 2026-05-18 (#380 audit closure)

All four deferred items from the #380 security + memory audit closed:

- **FTP credentials no longer on curl argv** -- `SFTPUploader` now writes
  a `0600`-permissioned temp config file consumed via `curl -K <path>`;
  credentials no longer appear in `ps aux` for the duration of an upload.
  (PR #382 commit 53ba286)
- **API key secrets moved to Keychain** -- `APIKeyManager` persistence
  now splits metadata (v2 envelope on disk) from secrets (kSecClassGeneric-
  Password, one item per `(provider, label)`). Legacy `[StoredAPIKey]`
  JSON files are auto-migrated on first load. (PR #382 commit 34d7987)
- **TempFileManager orphan cleanup on init** -- new
  `cleanupOrphansOnInit: Bool = true` parameter so production gets
  defensive cleanup for free; tests can opt out. (PR #382 commit ccdc46d)
- **RenderFarmClient `.plainHTTP` gated by InsecureTransportOverride
  token** -- replaces the bare `allowInsecureTransports: Bool` flag
  with a capability-token type whose factory forces every override
  site to write `.developmentOnly(acknowledgement: …)` — a static
  review signal. (PR #382 commit 750aaf5)

### Operations -- 2026-05-18

- **TestFlight workflow guardrails** -- `testflight.yml`'s `push.tags`
  trigger fired unexpectedly on `v0.1.0-rc.1` and uploaded build 244
  to App Store Connect, where Apple's validators flagged seven ITMS
  findings. The workflow is now `disabled_manually` at the registry
  AND the `push.tags` trigger is commented out — both must be reversed
  to resume automated submissions. Re-enable preconditions tracked in
  #392. The seven ITMS items are tracked individually in #386-#391.
  (PR #393)
- **CodeQL workflow timeout** -- bumped `timeout-minutes` from 45 to
  75 after the post-#382 codebase growth started producing intermittent
  cancel-on-timeout results. CodeQL is not a required branch-protection
  check, so this is informational hygiene.
- **Dependency Review workflow fix** -- removed the redundant
  `deny-licenses` from `dependency-review.yml`; `actions/dependency-
  review-action@v4` rejects passing both `allow-licenses` and
  `deny-licenses`. (PR #382 commit d468ece)

### Added -- 2026-04-20 (integration batch #371–#378, #178)

- **MeedyaSuite-core Swift Package integration scaffolding** -- `Package.swift`
  adds `SUITE_CORE=1` env flag (with optional `SUITE_CORE_PATH` for local
  development) that pulls in `MWBMPartners/MeedyaSuite-core` and wires the
  `MeedyaCore` product into `ConverterEngine` (#373)
- **SuiteCoreBridge** -- `Sources/ConverterEngine/SuiteCore/SuiteCoreBridge.swift`
  exposes `SuiteCoreAvailability`, `SuiteCoreBridgeError`, and
  `SuiteCoreSmokeTest.ping()` for end-to-end bridge verification (#373)
- **SuiteCoreTypes** -- `SuiteCoreMetadataProvider`, `SuiteCoreCodecDescriptor`,
  and `SuiteCoreFingerprintResult` mirror the Rust types from meedya-core (#373)
- **SuiteCoreMetadataAdapter** -- routes metadata lookups through
  MeedyaSuite-core when linked, falling back to the inline providers
  otherwise; advertises 12 additional providers (imdb, acoustid,
  rottentomatoes, metacritic, tvmaze, anidb, kitsu, animeplanet,
  last_fm, deezer, spotify_metadata, apple_music) when suite-core is on (#371)
- **SuiteCoreCodecClassifier** -- unified codec classification with a
  table-driven fallback covering lossless codecs (FLAC, ALAC, TrueHD, MLP,
  DTS-HD MA, PCM), always-spatial codecs (Atmos, MPEG-H 3D Audio, IAMF,
  DTS:X, AC-4 IMS), and spatial channel layouts (#372)
- **Metadata cleanup tracking** -- `docs/migration/suite-core-cleanup.md`
  file-by-file checklist for removing the inline TheTVDB client once
  MeedyaSuite-core is default-on (#374)
- **Subtitle tone-mapping** -- `SubtitleTonemapWrapper` integrates
  quietvoid/subtitle_tonemap following the DoviToolWrapper pattern, with
  full HDR10/HDR10+/Dolby Vision/HLG support and accepted formats .sup,
  .sub, .idx, .ass, .ssa (#369)
- **Render-farm subsystem** -- `RenderFarmAgent` + `RenderFarmClient` pure
  value types + agent registry + pluggable `RenderFarmTransportAdapter`;
  Bonjour service type `_meedyaconverter-agent._tcp`, per-chunk SHA-256,
  versioned REST paths, and `progressStream` AsyncThrowingStream with
  terminal-state auto-stop (#346)
- **Raster ↔ vector image conversion scaffolding** -- covers 30+ Phase 15
  raster formats, SVG 1.1/2.0 output, 4 tracing modes, 6 editability
  presets, 3 alpha strategies, 4 animation methods, plus
  `buildVTracerArguments`/`buildPotraceArguments`/`buildRsvgConvertArguments`
  pure argument builders (#376)
- **ProRes alpha → animated SVG scaffolding** -- extends the raster/vector
  pipeline with ProRes 4444 / 4444 XQ / 4444 HDR variant detection,
  rational-accurate frame rates (23.976, 29.97, 59.94 etc), HDR tone-map
  chain for 4444 HDR, SMIL/CSS/hybrid/frame-sequence SVG assembly, and
  output-size warnings (#377)
- **FFplay bundling** -- `FFmpegBundleManager.locateFFplay()` +
  `isFFplayAvailable()` soft-fail helper; `scripts/bundle-ffmpeg.sh`
  downloads and stages ffmpeg + ffprobe + **ffplay** from a static-build
  distribution for arm64 or x86_64 and validates each with -version (#378)
- **App Store Connect metadata** -- `metadata/en-US/` fastlane-ready
  description, subtitle, promotional text, keywords, release notes,
  support/marketing/privacy URLs plus `metadata/copyright.txt`,
  category files, and `review_information.yml` with reviewer notes;
  `docs/distribution/app-store-submission.md` 7-section runbook (#178)

### Fixed -- 2026-04-20

- **potrace alphamax clamp** -- was always 1.0 because of a typo in the
  min/max expression; now maps the 0..10 simplification knob onto
  potrace's 0.0..1.3 range (#379)
- **Critical: Mega.nz JSON command injection** -- login and upload-complete
  commands no longer string-interpolate user-supplied fields into JSON;
  switched to `JSONSerialization` (#380)
- **Critical: Mux direct-upload JSON injection** -- same fix pattern (#380)
- **Critical: SFTP rsync SSH command injection** -- key-file path is now
  single-quoted with `'\\''`-escaped embedded quotes (#380)
- **Major: FFmpegProcessController unbounded stderr buffer** -- added 10 MiB
  soft cap with line-drop trimming (#380)
- **Major: RenderFarmClient progressStream task leak** -- task is now
  assigned to a box the termination closure captures, preventing detached
  tasks when the caller abandons the stream between init and first poll (#380)

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
