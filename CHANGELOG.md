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

### Security

- **F-002 defence-in-depth complete -- remaining user-derived path
  components sanitised** -- the last ~13 `appendingPathComponent` call
  sites that build a filename from user-supplied data (rename-rule
  find/replace output, user-typed profile/template names, media-file
  basenames) now route through `PathSanitizer.sanitizeFilenameComponent`,
  matching the migration already completed for the GUI views in an
  earlier cycle. The highest-value fix is `BatchRenamer.apply` --
  unlike a plain `lastPathComponent`, a rename rule's `replaceWith`
  text is fully attacker-controllable and previously flowed unsanitised
  into the destination path. Multi-segment relative directory paths
  (which intentionally contain `/`) were left untouched to avoid
  flattening legitimate subdirectory structure. See `SECURITY.md`
  finding F-002 for the full site-by-site breakdown (re #428).
- **FFmpeg supply chain hardened -- universal, first-party, verified
  (F-011)** -- `scripts/bundle-ffmpeg.sh` now sources `ffmpeg` / `ffprobe` /
  `ffplay` solely from the first-party mirror `MeedyaSuite/MeedyaDL-Tools`,
  pinned to an immutable dated release tag, instead of an unverified
  third-party static-build host. Each per-arch archive is SHA-256-verified
  against the release's own `SHA256SUMS` **before** unpack, fail-closed
  (missing pin/checksums -> exit 6, mismatch -> exit 7). The two per-arch
  archives are `lipo`-combined into a genuinely **universal (arm64 +
  x86_64)** binary per tool, and the app itself is now built universal too
  (`swift build -c release --arch arm64 --arch x86_64` in `release.yml`).
  The former URL-keyed `scripts/ffmpeg-checksums.txt` bridge (and its
  `--refresh-checksums` mode) has been removed -- the trust root is the
  first-party tagged release's own checksums, so there is no local hash
  list to keep in sync. Found by the post-VERIFY adversarial review; fixed
  across two commits (re #428).
- **Probe-watchdog PID-reuse TOCTOU mitigated (F-012)** -- `FFmpegProbe`'s
  finished-check, `isRunning` re-check, and the actual terminate/kill now
  happen under a single `ProbeRunState` lock, closing the realistic window
  where a timer could fire just after the process had already exited. A
  sub-microsecond kernel-level PID-reuse race remains inherent to signalling
  any `Foundation.Process` by PID and is accepted, documented inline (re #428).

### Added

- **`RenderFarmConfigurationLoader` consumes `RenderFarmSettingsTab`'s
  AppStorage settings (#346)** -- a new pure, Foundation-only
  `ConverterEngine.RenderFarmConfigurationLoader` reads the
  `renderFarm.*` `UserDefaults` keys the settings tab already persists
  and builds a `RenderFarmClient.Configuration` plus the initial
  `[RenderFarmAgentInfo]` registry from them. It enforces the same
  insecure-transport contract as `RenderFarmClient` itself: plain HTTP
  is only permitted when the user has both enabled the toggle **and**
  supplied a non-blank acknowledgement string, otherwise no
  `InsecureTransportOverride` is produced. Malformed or empty
  `agentsJSON` decodes to an empty registry rather than throwing/
  crashing, and the discovery-interval/chunk-size settings are clamped
  to sane bounds before conversion. `RenderFarmSettingsTab` now shares
  its exact `UserDefaults` key strings with the loader via
  `RenderFarmConfigurationLoader.Keys` so the two sides cannot drift.
  This lands the settings-to-engine bridge the tab's header comment
  described as deferred; the transport implementations (SSH/TLS),
  Bonjour discovery, and the agent binary remain and #346 stays open.
- **Lossless/spatial audio badges in the Stream Inspector (#372)** --
  `FFmpegProbe` now tags each audio stream with a
  `SuiteCoreCodecDescriptor` via `SuiteCoreCodecClassifier` (codec name +
  channel layout + sample format), using its built-in fallback
  classification table by default -- no `SUITE_CORE` build flag required.
  `MediaStream` gains an optional `suiteCoreCodecDescriptor` field (and
  `isLosslessAudio`/`isSpatialAudio` convenience accessors), defaulted to
  `nil` so existing call sites and previously-persisted `Codable` data
  are unaffected. The Stream Inspector shows "Lossless"/"Spatial" badges
  on audio streams accordingly. This is the default-build fallback
  slice; the live MeedyaSuite-core Rust classification path remains
  gated on its tagged release (#372 stays open).
- **SHA-256 checksums attached to Direct release assets** -- `release.yml`
  now generates `<asset>.sha256` for both the DMG and the CLI tarball
  after they're built/signed/notarised, and attaches both `.sha256`
  files to the GitHub Release alongside the DMG and tarball. Closes a
  #428 Direct-distribution must-do; README already documented a
  `shasum -a 256 -c` verification step that had no file to check
  against until now (re #428).

### Fixed

- **`LoudnessReportView` wired to real EBU R128 / ITU-R BS.1770 loudness
  analysis (#433)** -- `runAnalysis()` was a stub that set `isAnalysing =
  false` immediately and never ran anything, so the Phase 12 loudness
  compliance feature (#340) showed no results despite `LoudnessReporter`
  being fully implemented. It now locates FFmpeg via
  `FFmpegBundleManager`, runs `LoudnessReporter.buildAnalysisArguments`
  through `FFmpegProcessController` for each queued source file
  (mirroring `QualityPreviewView`'s proven execution pattern), parses the
  `loudnorm` JSON block from the captured stderr with
  `LoudnessReporter.parseAnalysisOutput`, and evaluates compliance with
  `LoudnessReporter.checkCompliance` against the selected standard. A
  missing FFmpeg binary now surfaces a clear error message instead of
  silently doing nothing, and cancelling (or navigating away) stops the
  running FFmpeg process and analysis task cleanly -- no leaked process
  or task. Also fixes a latent crash in `LoudnessReporter.
  parseAnalysisOutput` found while adding test coverage: it subscripted a
  `ClosedRange` up to `jsonEnd.upperBound`, which equals `String.
  endIndex` (an invalid, one-past-the-end index) whenever the loudnorm
  JSON's closing `}` was the last captured character, crashing with an
  out-of-bounds fatal error; switched to a half-open range, which is both
  correct and crash-safe.
- **`QualityMetricsView` wired to real VMAF/SSIM/PSNR analysis (#434)** --
  `runAnalysis()` built the FFmpeg argument list for the selected
  metric(s), populated the command preview, and immediately set
  `isAnalysing = false` without ever executing FFmpeg, so the Phase 7
  quality-scoring feature (#291) -- gauges, quality grade, per-frame
  chart -- could never show real data despite `QualityMetrics` being
  fully implemented. It now mirrors `LoudnessReportView`'s proven
  pattern (#433): locates FFmpeg via `FFmpegBundleManager`, and for
  each selected metric ("All" runs VMAF, SSIM, and PSNR as three
  sequential passes) builds arguments with `QualityMetrics.build*
  Arguments` and executes them through `FFmpegProcessController.
  startEncoding`. SSIM/PSNR scores are parsed from stderr via
  `QualityMetrics.parseSSIMOutput`/`parsePSNROutput`; VMAF writes a
  JSON log to a unique temp file which is parsed with `QualityMetrics.
  parseVMAFLog` for both the aggregate score and the per-frame series
  that feeds the chart (falling back to stderr parsing if the log
  can't be read), and the temp log is always deleted afterwards. A
  new pre-flight check probes `ffmpeg -hide_banner -filters` for
  `libvmaf` support before attempting VMAF -- if absent, VMAF is
  skipped with a clear message while SSIM/PSNR still run in "All"
  mode, rather than failing the whole pass with an obscure
  filter-not-found error. A missing FFmpeg binary surfaces a clear
  error message instead of silently doing nothing; a new Cancel
  button, `.onDisappear`, and `deinit` all stop the running process
  and analysis task cleanly, with no leaked process, task, or temp
  file. Verified end-to-end against real FFmpeg on the dev machine
  (Homebrew `ffmpeg-full` 8.1.2 with libvmaf): PSNR 36.79 dB, SSIM
  0.9749, VMAF mean 86.12 (20 frames) on a `crf 10` vs `crf 40`
  synthetic test clip. Added pure unit tests for the previously
  untested `QualityMetrics` (Utility) builders/parsers using
  real-captured FFmpeg stderr and a real-shaped VMAF JSON log (re
  #291, re #428).
- **`release.yml` header/precheck/FFmpeg comments corrected** -- three
  stale or incorrect comments fixed with no logic change: the header no
  longer implies GitHub can branch-filter a tag push to `main` (it
  can't -- tagging the right commit is a maintainer responsibility);
  the precheck job's recovery note now points at `gh run rerun
  <run-id>` instead of the non-existent `gh workflow run` (this
  workflow has no `workflow_dispatch` trigger); and the FFmpeg-bundling
  step comment no longer claims arm64-only output now that the script
  produces genuinely universal binaries (F-011) (re #428).
- **README install/verify instructions matched to the real asset
  names** -- README referenced `MeedyaConverter-<version>.dmg` and a
  bare `.dmg.sha256`; the actual asset (and the one `release.yml`
  now produces a checksum for) is `MeedyaConverter-<version>-macOS.dmg`.
  The CLI tarball name and the `shasum -a 256 -c` example are corrected
  to match (re #428).

### Documentation

- **New Direct-distribution release runbook**
  (`docs/distribution/direct-release.md`) documenting the actual
  `release.yml` flow end-to-end: pre-flight checklist, cutting an rc/GA
  tag, a step-by-step walkthrough of what CI does, a local smoke-test
  procedure for the published artefacts, failure/re-run guidance, a
  soak-window policy placeholder, and known gaps (the CHANGELOG-date
  step not being committed by CI; the CLI tarball being signed but not
  notarised; the FFmpeg pin being a single deliberate edit) (re #428).
- **`apple-secrets-setup.md` verification section rewritten** -- it
  told the reader to dry-run via Actions -> "Run workflow", but
  `release.yml` has no `workflow_dispatch` trigger; that button doesn't
  exist. Rewritten to state the precheck can only be observed on a real
  `v*` tag push, with a pointer to the new release runbook and a noted
  (but not implemented) option to add a `workflow_dispatch`
  precheck-only path later (re #428).
- **`help/cli-reference.md` rewritten** against the real `meedya-convert`
  command surface -- it previously called the binary `meedya-cli` and
  claimed "the CLI tool will be implemented in Phase 6"; both were stale,
  since the CLI shipped in Phase 4. All six subcommands (`encode`, `probe`,
  `profiles`, `batch`, `manifest`, `validate`), their real options, and the
  actual POSIX exit codes (0/1/2/3/4/5/6/130) are now documented from
  source and cross-checked against `docs/api/meedya-convert-api.yaml` (#429).
- **New help topic `help/vector-conversion.md`** documenting the Tools
  sidebar's Vector Conversion (raster -> SVG) and ProRes to Vector
  (ProRes 4444 -> animated SVG) views: input formats, editability presets,
  tracing modes, alpha strategies, animation methods, and the ProRes
  output-size warning, sourced from `RasterVectorConverter.swift`,
  `ProResToVectorConverter.swift`, and the corresponding SwiftUI views (#429).
- **`PROJECT_STATUS.md`, `Project_Plan.md`, and `DEV_NOTES.md` refreshed**
  to post-autopilot reality: verified test count (1053, all green, 0
  compiler warnings), the F-001..F-012 security findings register status,
  the universal/first-party FFmpeg supply chain, and the `v0.1.0-rc.4`
  (soak) -> `v0.1.0` GA release posture. Removed a stale "CLI: Phase 6"
  platform-strategy row in `Project_Plan.md` (the CLI shipped in Phase 4)
  and corrected the `profiles`/`validate` CLI command descriptions there
  to match the shipped flag surface (#429).

---

## [0.1.0-rc.4] -- 2026-MM-DD (TBD)

### Highlights

User-facing summary of the changes since rc.3 (engineering detail follows
below):

- **HDR subtitles now actually render in the output.** The Subtitles
  section in Output Settings (added in rc.3 as a UI-only switch) is now
  wired all the way through the encoding engine via `SubtitleTonemapPipeline`,
  so toggling HDR-aware subtitle tone-mapping changes the bytes that get
  written to disk.
- **New Settings tabs.** Encoding → Metadata lets you pick a metadata
  backend (with a live availability indicator for MeedyaSuite-core);
  Encoding → Audio CD exposes the AccurateRip submission controls; and
  Services → Render Farm exposes the insecure-transport gate, Bonjour
  discovery, chunk-size and agent-list controls behind the new render
  farm subsystem.
- **New Tools views for vector workflows.** "Vector Conversion" (raster →
  SVG) and "ProRes to Vector" (ProRes 4444 → animated SVG) are now first-
  class sidebar entries instead of being CLI-only.
- **Distinct Render Farm icon.** The Render Farm sidebar entry no longer
  shares an icon with SFTP, so the two are visually distinguishable at a
  glance.
- **More reliable CI / release pipeline.** SPM dependency caching now
  actually keys off something that exists at checkout time, CodeQL no
  longer falsely cancels on slow runners, and branch protection accepts
  the same status-check name CI actually reports — so PRs merge on green
  without needing the admin override.

### Added -- 2026-05-20 (subtitle tone-mapping end-to-end + workflow polish)

- **Subtitle tone-mapping reaches the output bytes** -- the
  OutputSettingsView toggle that landed in PR #397 was previously
  cosmetic: the per-profile `subtitleTonemap` config was stored but
  no encoding-pipeline code consumed it. PR #413 closes the loop in
  five steps:
    1. `FFmpegArgumentBuilder.SubtitleStreamAction` (passthrough /
       replaceWith(URL) / drop) + `subtitleStreamActions` field
       drives per-source-stream subtitle mapping when non-empty
    2. Five unit tests for the builder
    3. `EncodingJobConfig` threads `subtitleStreamActions` to the
       builder (introduced `SubtitleStreamActionEntry` Codable struct)
    4. `EncodingEngine.encode()` calls `SubtitleTonemapPipeline.run(...)`
       as a pre-processing stage and populates
       `enrichedJob.subtitleStreamActions` from the result
    5. Integration test pinning the full data flow
  (PR #413, closes #409 / completes the chain that started with #369
  engine and #397 UI binding)

### Fixed -- 2026-05-20 (workflow infrastructure)

- **CodeQL workflow cancellations**: the 75-minute timeout cap was
  insufficient on slow `macos-15` runners — same code completing in
  24 minutes on one runner but cancelling at 77 minutes on another.
  Diagnosis revealed CodeQL's Swift extractor re-instruments every
  compile invocation, so SPM caching cannot short-circuit the
  dominant cost. Timeout raised to 120 minutes for hardware-variance
  headroom. (PR #412)
- **SPM cache step in codeql.yml**: previously cold every run, now
  matches the pattern in build.yml/release.yml. The cache itself
  saves only ~30 s of SPM-download time but provides a baseline for
  future tuning. (PR #411)
- **SPM cache key was hashing a gitignored file**: all six workflows
  used `hashFiles('Package.resolved')`, but Package.resolved is in
  .gitignore and absent at runner checkout time — the hash was
  always empty and every cache went to a single per-prefix bucket.
  Fixed to `hashFiles('Package.swift', 'Package.resolved')` so the
  always-tracked Package.swift drives discrimination today, and a
  future policy change to commit Package.resolved adds exact-version
  precision for free. Affects build.yml, beta-alpha.yml, codeql.yml,
  dev-build.yml, release.yml, testflight.yml. (this batch)

### Changed -- 2026-05-20

- **Branch protection cleanup**: removed the PR-review requirement
  on main, updated the required-status-check context name to match
  what CI actually reports (`Build & Test (macOS)`), and rewrote the
  "Protect main branch" repository ruleset to require the actual
  check name rather than the template defaults (`Frontend
  (ubuntu-latest)` / `Backend (ubuntu-latest)`) it had been carrying
  since project creation. PRs now merge without `--admin` once
  Build & Test passes.

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

### Changed -- 2026-05-18

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

## Version History

> **Version format:** `MAJOR.MINOR.PATCH`
>
> - **MAJOR** -- Breaking changes or significant milestones
> - **MINOR** -- New features or capabilities
> - **PATCH** -- Bug fixes and minor improvements

| Version | Date | Highlights |
| ------- | ---- | ---------- |
| 0.1.0-rc.4 | 2026-MM-DD (TBD) | Subtitle tone-mapping wired end-to-end, new Metadata / Audio CD / Render Farm settings tabs, Vector Conversion and ProRes-to-Vector tools surfaced in sidebar, distinct Render Farm icon, CI/release hardening (SPM cache key, CodeQL timeout, branch-protection check name) |
| 0.1.0-rc.3 | 2026-05-18 | Release-pipeline stabilisation: portable `awk`-based changelog extraction in `scripts/extract-changelog.sh` (replaces a GNU-sed idiom BSD sed rejected) so `release.yml` runs to completion on macOS runners |
| 0.1.0-rc.2 | 2026-05-18 | `APIKeyManagerKeychainTests` skip cleanly via `XCTSkip` when the CI runner has no unlocked default keychain, unblocking `release.yml` |
| 0.1.0-rc.1 | 2026-05-18 | Rasterised AppIcon PNGs (16 → 1024 px) added to `AppIcon.appiconset/` so the built bundle ships with the correct icon; first release candidate carrying the integration batch and #380 audit closure |
| 0.1.0-beta.1 | 2026-04-08 | Beta channel cut: DV + HDR10+ dual-dynamic HDR pipeline, dual bundle IDs (Direct vs App Store Lite), TestFlight + dev-build workflows, full UI surfacing of 33 views, REST API server, watch folders, watermark/voice-isolation/background-removal, full metadata-tag editor, cloud upload providers, quality scoring (VMAF/SSIM/PSNR), and the first comprehensive code review pass |
| 0.1.0-alpha | 2026-04-08 | Alpha cut from the same commit as beta.1: core engine, SwiftUI app, CLI tool, HDR workflows (PQ→HLG, DV preservation, HDR→SDR tone mapping), 7+ encoding profiles, licensing module, encoding pipelines, AccurateRip, metadata lookup |

---

*This changelog is updated with every code change during development.*
