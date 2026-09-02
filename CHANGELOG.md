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

> NOTE for the release cut: fold these into a dated `[0.1.0-rc.4]` block AND
> correct the existing rc.4 "Vector Conversion / ProRes to Vector are now
> first-class sidebar entries" highlight — those views are now HIDDEN
> (`NavigationItem.unavailable`, #473) because their converters can't execute
> yet. This backfill assumes `wip/alpha-consolidation` merges to `main` first.

### Added

- **Video stabilization** (two-pass vid.stab: detect → transform) with Light/
  Medium/Heavy presets and a progress/cancel UI (#323).
- **Deinterlacing** at encode — a per-profile Off/Fast(yadif)/Quality(bwdif)
  picker applied as the first `-vf` stage (#324).
- **Watermarks are now applied at encode** (text via drawtext, image via the
  `movie` source filter) and persist on the encoding profile (#298).
- **Scene-detected chapters embed into the output** encode (#288).
- **Multi-output** enqueues one full-fidelity job per output through the queue
  (#335); **encoding pipelines execute** and persist, with a Run action (#278).
- **AppleScript / JXA scripting** activated (encode / probe / list profiles),
  with a Help page (#302).
- **Settings undo/redo** (⌘Z / ⌘⇧Z) for profile changes (#330), a working
  **keyboard-shortcut recorder** (#331), a **live mini-player** (#280), an
  honest **menu-bar status** dropdown (#281), and live **parallel-encoding
  throughput tiles** (#286).
- CLI `batch --dir --output-mode mirror` mirrors the source folder tree (#275).
- Team-profile pull now surfaces real local-vs-remote **conflicts** (#482).
- Team Profile's **Git Repository sync now runs real git** — clone/fetch/
  checkout/commit/push against your own credentials — instead of writing a
  loose file to the "repository" path (#345).
- **Filter Graph editor** can now **attach its composed filter to the next
  encode** ("Apply to Next Encode" — video composed after any crop, audio into
  `-af`), not just copy to the clipboard.
- **Background Removal** can now **save the single processed image** ("Save…"),
  writing the exact encoded bytes so the PNG/TIFF alpha channel is preserved
  (#300).
- **Smart Crop** now analyses the **selected video** — it samples frames with
  ffmpeg, runs Vision face/saliency detection on each, and computes a stable
  crop at the chosen aspect ratio (inside the auto-detected black-bar area when
  one is present), with a preview frame, progress and Cancel; "Apply to Next
  Encode" stages it onto the next queued job (#299).

### Changed

- The app module was split into a thin `MeedyaConverter` executable plus a
  testable `MeedyaConverterCore` library (#499), giving app-module code unit
  tests for the first time.

### Fixed

- A staged or auto-detected crop is now dropped (with a warning) when the
  profile copies the video stream, instead of emitting `-vf crop=…` next to
  `-c:v copy`, which FFmpeg rejects and which failed the whole job.
- **Storage Analysis** now reads codec, resolution, HDR and duration with
  **ffprobe** (a few concurrent probes, with progress and Cancel) instead of
  guessing them from file names; files ffprobe cannot read keep the file-name
  guess and the report says how many did (#365).
- **ffmpeg resolution** in Image conversion, Voice Isolation and the Media
  Browser now goes through the bundled binary (Contents/Helpers) instead of
  PATH/Homebrew, so those features work in a Finder-launched notarized app.
- **Dual Dynamic HDR** wrappers (`dovi_tool`, `hdr10plus_tool`) now resolve
  their binaries via the shared bundled-tool locator (Contents/Helpers →
  Homebrew → PATH), instead of a hardcoded path list that never checked the
  app's bundled tools.
- **Voice Isolation** removed the placeholder "ML Sound Analysis" method (it ran
  the same band-pass as the basic method) and the inert centre-channel toggle.
- **Disc burn "Simulate"** no longer writes a real disc on the hdiutil/growisofs
  paths (only the Audio-CD `-dummy` path is a genuine dry run); "Verification
  passed" is reported only when a verify actually ran.
- **Video Trimmer** now seeds the timeline from the real file duration (was a
  hardcoded 120 s); **metadata tag editor** reads existing tags and writes
  losslessly without dropping the audio/video when embedding artwork (#320).
- Queue drag-reorder moves the correct job when finished jobs are present; a
  zero-condition conditional rule can no longer be saved (it matched everything);
  CMX3600 EDL export no longer emits garbage columns (dangling-pointer UB).
- Hidden dead-end surfaces: Vector Conversion / ProRes-to-Vector (#473) and
  iCloud Cloud Sync (no iCloud entitlement in Direct).

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

- **Audio CD → BIN/CUE imaging executor + `disc` CLI (#495 P1)** -- the executor
  half of the disc-backup-imaging feature (#492). `meedya-convert disc`
  (`drives` / `toc` / `image`) reads a Red Book Audio CD via cdrdao and writes a
  verified BIN/CUE, feeding the existing serialiser core. New engine types
  (`RawCDReadPlanner`, `CdrdaoTocParser`, `CdrdaoProgressParser`,
  `DiscImagingController`, `BundledToolLocator`, `DiscProtectionDetector`,
  `DriveListingParser`); `ImagingConfig.imageFormat` is finally consumed and
  `DiscImageFormat.ccd` added. 29 unit tests incl. a `.toc` → `DiscTableOfContents`
  → CUE round-trip. A DRM detect-and-warn gate (raw imaging only, never
  circumvention) is built in. Device I/O is hardware-verified on the manual
  matrix — there is no optical drive in CI; the pure logic is unit-tested.
  Direct distribution only (the App Store sandbox has no raw-device access).
  Also fixes the fabricated `/dev/rdisk` device paths in `BurnSettingsView`.
- **Cloud-upload execution (PR #472)** -- real, authenticated upload to S3
  (SigV4), Dropbox, Google Drive, OneDrive (chunked/resumable), and SFTP
  (`scp`), reachable from `CloudStorageView` and the `.uploadCloud`
  post-encode action. YouTube/Vimeo remain disabled pending OAuth (#446).
  Not in a tagged release yet.
- **Unified statistics dashboard** -- `AggregateStatistics`, `DashboardView`,
  and `StatisticsExportView` roll per-job encoding stats into an aggregate
  view with export.
- **Email + webhook completion notifications** -- `WebhookSender` fires on
  job success/failure from the queue's per-job completion path in
  `AppViewModel`.
- **Watch-folder auto-encode** -- monitored folders now auto-enqueue new
  files for encoding rather than only appearing in the UI.
- **Recent files & pinned favourites** -- `RecentFilesManager` +
  `RecentFilesView`, wired into navigation.
- **Scheduled encoding** -- `EncodingScheduler` + `ScheduleView` let a job
  be queued for a future start time.
- **IntAppsAPI remote feature-flags + alpha/beta update channels** --
  `IntAppsAPIClient` reads remote flags and update-channel selection.
- **Overwrite-existing / delete-source-after-encode toggles** -- both now
  read from settings and take effect at encode completion.
- **Automatic media-server library-scan on encode completion** --
  `AppViewModel.triggerMediaServerAutoScan()` fires
  `MediaServerIntegration.triggerLibraryScan` from the per-job success path
  in `startQueue()`; the `mediaServerAutoScan` toggle in
  `MediaServerSettingsView` previously had no reader. The manual "Trigger
  Library Scan Now" button already worked before this change.
- **Navigation exposure of 10 previously-orphaned views** -- views that
  existed as source files but had no sidebar/menu entry are now reachable
  from the app.

  None of the ten items above are in the released `v0.1.0-rc.3` build;
  they land in the next alpha build. See the "Documentation" entry below
  for the doc corrections that came out of auditing these against the
  actual call graph.

- **Metadata / ID-tag passthrough guards + SUITE_CORE bindings tracking
  (#478)** -- the cross-repo media-ID program's correctness obligation for
  MeedyaConverter is that a conversion must NOT strip a file's external /
  catalogue identifier tags (ISRC, UPC/ICPN, MusicBrainz IDs, ISWC, …).
  Added argv-level guards in `ConverterEngineTests+FFmpegArguments.swift`
  pinning the load-bearing property: a **default** encode emits
  `-map_metadata 0` (copies the entire global metadata dictionary — every
  tag family, not drop-unknown) and `-map_chapters 0`, and must not emit
  `-map_metadata -1`; `copySourceMetadata = false` omits the copy-all
  (negative control); and the `--no-copy-metadata` opt-out's trailing
  `-map_metadata -1` is proven to come *after* the copy-all so ffmpeg's
  last-arg-wins precedence genuinely strips. Added value-exact assertions
  for `MetadataPassthroughBuilder` (`copyAll` == `-map_metadata 0`,
  `strip` == `-map_metadata -1`) that close the positional wrong-but-green
  gap in the pre-existing `contains(...)`-only tests. **Deliverable 1
  (SUITE_CORE bindings) is tracking-only**: a note on `SuiteCoreMetadataAdapter`
  records that the shared identifier vocabulary (MeedyaSuite-core's
  `identifier_types` registry + `CommonTag`, MeedyaSuite-core#65) will reach
  this app through that adapter once the core Swift bindings ship
  (MeedyaSuite-core#28) — and that NO MeedyaConverter-local identifier model
  should be added meanwhile (it would be throwaway). No dep bump; no new
  identifier modelling. NOTE: this container has no Swift toolchain, so the
  new tests were authored by source-review against the existing test idioms
  and **compilation + `swift test` must be validated by CI** — not run
  locally.

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

### Changed

CLI contract changes on `wip/alpha-consolidation` (PR #472). Not in the
released `v0.1.0-rc.3`; `docs/api/meedya-convert-api.yaml` and
`help/cli-reference.md` are updated to match.

- **`encode --video-codec`/`--audio-codec`/`--container` now reject
  unrecognised values** -- previously an unrecognised value was silently
  dropped (video/audio stream disabled, or container left unchanged) and
  the command still exited 0; `applyOverrides(to:)` now throws a
  `ValidationError` listing the accepted values. `copy` is now an
  accepted `--video-codec`/`--audio-codec` value, routed to the existing
  `--video-passthrough`/`--audio-passthrough` flags rather than a nonexistent
  codec case (#466).
- **`batch --job-file` now exits non-zero if any job fails** -- previously
  always exited 0 even when every job failed, unlike `--dir`'s existing
  behaviour. `runJobFileBatch` now tracks failures across the loop and
  throws `ExitCode(ExitCodes.encodingFailed.rawValue)` (4) if any job
  failed, matching `--dir` mode exactly. Both modes still process every
  job before exiting (#484).
- **`profiles --show`/`--export`/`--validate` and `validate --profile`
  now resolve against the persisted profile store, not just built-ins**
  -- same built-ins-first-then-store order as `encode --profile`, so a
  profile imported via `profiles --import` is now found by these
  commands instead of reported "not found". `profiles --list` now
  sources `EncodingProfileStore().allProfiles()` (#489).
- **`manifest --hdr` now rejected** with a validation error
  ("`--hdr is not yet supported for manifest generation`") instead of
  being silently accepted and ignored -- the manifest encode path has no
  HDR colour-signalling implementation, unlike the main `encode`
  pipeline's `FFmpegArgumentBuilder`. `manifest --video-codec`/
  `--audio-codec` now reject unrecognised values the same way `encode`
  does, instead of silently defaulting to h264/aac; and
  `manifest --variants custom` now requires `--ladder-file`, instead of
  silently falling through to the default ladder (#490).

### Fixed

- **Bounded-concurrency queue, opt-in and defaulted to width 1 (#286)** -- the
  queue runner (`startQueue()`) is now a `TaskGroup` whose width is re-read
  from the Max Concurrent Jobs setting on every slot top-up, replacing the
  previous `while ... nextPendingJob()` loop. At width 1 -- the default, and
  what an unentitled install is unconditionally clamped to via
  `FeatureGateManager`/`.parallelEncoding` (`FreeGateProvider` grants only
  `.free`-tier features, and `parallelEncoding` requires `.plus`) -- the
  sequence degenerates to exactly the old claim-run-await-claim behaviour.
  Going concurrent surfaced three bugs that were already latent in the
  sequential code: `EncodingEngine` held a single `activeController` optional
  cleared unconditionally by a `defer`, racing `cancelCurrentJob` even today
  (now a keyed `[UUID: FFmpegProcessController]` registry so a finishing pass
  can only clear its own entry); both statistics-write call sites constructed
  a fresh `EncodingStatisticsStore` per write, whose `NSLock` protects nothing
  across instances (writes now go through one serialising
  `EncodingStatisticsRecorder` actor); and `EncodingActivityIndicator`'s
  `guard !isTracking` meant the first job to finish would tear down the
  menu-bar/dock indicators while others were still running (lifecycle moved
  to the queue: start on first claim, stop only once the queue drains). Also
  fixed: `PostEncodeHookRunner` was an `actor` whose doc comment promised
  strictly-one-at-a-time execution, but Swift actors are reentrant and its
  body was one bare `await chain.execute(...)`, so two completions landing
  together ran their hook chains in parallel regardless -- real serialisation
  now comes from chaining each run behind a stored tail `Task`, in
  `EncodingPersistenceActors.swift`. **Width > 1 has never been run**:
  `swift test` cannot execute in this environment and CI cannot spawn a real
  multi-job FFmpeg encode, so concurrent execution is unverified at runtime --
  which is exactly why it ships opt-in, entitlement-gated, and defaulted off.
- **A/B comparison now has a working capture -> persist -> compare loop
  (#329)** -- `ComparisonLibraryView` was a permanently empty screen:
  `entries` had no writer anywhere, `ComparisonView` was never instantiated,
  and `ComparisonCapture`/`FrameComparisonExtractor`'s argument builders were
  referenced only from a comment. A capture sheet now extracts frames through
  a real `FFmpegProcessController` and computes real SSIM/PSNR/VMAF; entries
  persist as JSON via the new `ComparisonLibraryManager`
  (`~/Library/Application Support/MeedyaConverter/comparison_library.json`,
  mirroring `RecentFilesManager`'s convention), and selecting a persisted
  entry opens the comparison instead of the view staying permanently empty.
- **Menu-bar mode now works (#281)** -- `MenuBarController` was a complete
  `NSStatusItem` implementation that was never constructed anywhere, and the
  `showMenuBarStatus` toggle it was meant to obey was itself read by nothing.
  The controller is now held for the app's lifetime with its visibility
  tracking the toggle live from both the main window's scene and the Settings
  scene -- previously the sync was attached only to the main window's scene,
  so toggling the setting with the main window closed (menu-bar-only use, the
  exact scenario this feature exists for) did nothing.
- **`meedyaconverter://` URLs now route through `URLSchemeHandler` (#356)** --
  `onOpenURL` silently discarded every non-profile URL while
  `URLSchemeHandler` (encode/probe/open, fully implemented) had zero
  references anywhere in the app. Non-profile URLs are now routed through it
  against the live `AppViewModel`; unparseable URLs and unmapped view names
  now produce a visible warning instead of silence, and the dead
  `routeAction` placeholder was removed.
- **"Prefer hardware acceleration" is now a real kill switch (#475)** -- the
  setting was persisted by Settings and read by nothing. A new
  `HardwareAccelerationPreference` now applies it at all seven of the app's
  `EncodingJobConfig`-building enqueue paths (`enqueueSelectedFile`,
  `enqueueWatchFolderFile`, `ScriptingBridge`, the Automator
  `EncodeMediaAction`, `ResumableJobsView`, `ScheduleView`, and
  `FFmpegPreviewView`, the last so the command preview doesn't show hardware
  arguments the encode won't actually use) -- deliberately excluding the CLI
  and HTTP API, which keep their own explicit options and should not change
  behaviour because of a GUI checkbox. It is a kill switch, not a duplicate
  of the per-profile `EncodingProfile.useHardwareEncoding`: on, profiles
  decide as before; off, hardware encoding is forced off even when the
  profile asks for it. Fixed in the process: the stored default was `false`
  and was read via `UserDefaults.bool(forKey:)`, which answers `false` for a
  key that was never written -- so the kill switch would have been engaged on
  every fresh install and for every existing user who never touched the
  (previously dead) toggle, silently downgrading the built-in `hardwareH264`/
  `hardwareH265` profiles to software encoding. The default is now `true`,
  read via `object(forKey:)` so "absent" is distinguished from "explicitly
  off".
- **Post-encode hooks now fire on job failure too (#277)** -- the hook chain
  (`PostEncodeActionChain`) was invoked only from the success branch, so
  every `runOnFailure` action configured in the Hooks tab was dead. The
  failure branch now loads the persisted chain and executes it with
  `success: false`, guarded and fire-and-forget exactly like the success
  path, so a throwing action cannot take down the queue runner.
- **Toolbar commands resolve through the shortcut manager, and five
  View-menu navigation commands now exist (#331)** --
  `KeyboardShortcutManager.binding(for:)` had zero callers, so rebinding a
  shortcut in Settings changed nothing; the File menu's Import command and
  the Encode toolbar command (and their tooltips, previously hard-coded
  "(Cmd+O)"/"(Cmd+Return)") now resolve through it, with `ShortcutBinding.
  keyEquivalent` made failable so a corrupt or multi-character key persisted
  in `UserDefaults` degrades to the caller's fallback instead of trapping via
  `KeyEquivalent(Character(binding.key))`. The five `navigate.*` shortcuts
  (Cmd+1-5) had no command anywhere, so their rows in the shortcut editor
  were decorative; a new View-menu `CommandGroup` now provides all five
  (`navigate.settings` opens the Settings scene, there being no
  `NavigationItem` case for it).
- **ScriptingBridge's `probe(file:)` no longer blocks a thread on a semaphore
  for up to 60 seconds (#451)** -- replaced with Cocoa Scripting's own
  suspend/resume idiom (`NSScriptCommand.current()` +
  `suspendExecution()` / `resumeExecution(withResult:)`), with the timeout
  outcome preserved by a structured `TaskGroup` race instead of a blocking
  wait. The method's own former comment claimed this "would require
  restructuring as an NSScriptCommand subclass ... out of scope"; that was
  verified wrong against the real SDK header. This describes how the method
  behaves *if* AppleScript dispatch reaches it -- it still doesn't:
  `MeedyaConverter.sdef` has no `<cocoa>` mapping elements and nothing
  registers `ScriptingBridge.shared` (#302), so the semaphore removal is real
  but the code path is presently unreachable via a live Apple Event.
- **Scene detection now runs ffmpeg (#288)** -- `detectScenes()` built FFmpeg
  arguments, logged "requested", and returned without spawning anything;
  `detectedScenes` was only ever populated by manually-added markers. It now
  runs ffmpeg, drains progress, reads the metadata file, and parses real
  scene timestamps -- `SceneDetector.swift` itself is unchanged, since its
  `buildDetectionArguments`/`parseSceneOutput` already matched ffmpeg's
  output format; the capability was never missing engine code, only a
  caller. "Apply to Job" stays disabled with a stated reason, because
  `EncodingJobConfig` genuinely has nowhere to put chapters -- that part of
  #288 remains open.
- **Concatenation now has a working Start action (#322)** -- the
  Concatenate screen offered file reordering, a method picker, a crossfade
  slider and live compatibility warnings, but contained no process
  invocation at all, so it could never produce output. `startConcatenation()`
  now runs `VideoConcatenator.buildDemuxerConcatArguments` through a real
  `FFmpegProcessController`, surfaces live progress and real errors, and
  verifies the joined file exists before reporting success. The re-encode/
  filter path (`buildFilterConcatArguments`, still zero callers) is left
  visibly disabled with an honest label rather than as a crossfade slider
  that silently does nothing. Also fixed: the error banner was shared with
  the file-import alert, so a dismissed import error lingered as red text in
  the Concatenate section, implying a join had failed that was never
  attempted -- now separate state.
- **Inline metadata search no longer fabricates an empty result (#493)** --
  `SuiteCoreMetadataAdapter.searchViaInline` returned `[]` behind a comment
  claiming it was "a pass-through" to the `MetadataProviders` implementations.
  The comment was false -- no provider was ever called -- and an empty array is
  indistinguishable from "the provider ran and found nothing", so any caller
  would have reported a successful lookup that never happened. There is nothing
  to pass through to: every inline client in `Sources/ConverterEngine/Metadata/`
  builds request URLs only, and that directory contains no `URLSession`, no
  `URLRequest` and no `JSONDecoder` for any of TMDB, TheTVDB, MusicBrainz,
  Discogs, FanArt.tv, OpenSubtitles or OMDb. The method now throws a new
  `SuiteCoreBridgeError.notImplemented(_:)` naming the requested source. No
  production code calls the adapter and no test asserted the old behaviour, so
  nothing regresses; three regression tests were added.
- **CI now runs on the working branch (#496)** -- `build.yml` triggered only on
  push/PR to `main`/`beta`/`alpha`. Because the project deliberately avoids PR
  stacking and keeps all work on one long-lived `wip/**` branch, the moment a PR
  merged that branch lost every trigger: six commits accumulated with no build
  and no test run, including ~1,350 lines of disc-imaging code whose own commit
  message said "not yet built/tested". `'wip/**'` added to the push branch list;
  the first run retro-verified all six. CodeQL and Dependency Review still gate
  only the eventual PR, deliberately.

- **MusicBrainz search queries now Lucene-escaped and phrase-quoted, base URL
  centralised (#493, Part A)** -- `MusicBrainzClient.buildRecordingSearchURL` /
  `buildReleaseSearchURL` previously interpolated titles/artists raw into the
  Lucene `query=` parameter, so multi-word values only bound their first token
  to the field (`recording:Bohemian Rhapsody` searched only `Bohemian`), Lucene
  special characters (`: ( ) " \` …) corrupted the query, and URL-reserved
  characters (`& + / :`) could break the request under the permissive
  `.urlQueryAllowed` set. Each field value is now emitted as a phrase-quoted,
  backslash-escaped Lucene clause (`field:"value"`) and percent-encoded with a
  tightened character set. The MusicBrainz base URL, previously duplicated as a
  hard-coded literal in `AudioCDReader.buildMusicBrainzLookupURL`, now resolves
  from the single `MetadataSource.musicBrainz.baseURL` source of truth. No API
  endpoints, parameters, or public signatures changed; new unit tests cover
  phrase-quoting and reserved-character escaping. (Preparatory hardening ahead
  of the reported MusicBrainz search-API changes tracked in #493. The Nov 30
  2026 changes were subsequently assessed against every MusicBrainz call in the
  codebase and require **no migration** -- none of the breaking tickets
  (SEARCH-444/642/666/752/764) touch the entities, fields, or response
  properties we use; see #493 Part B.)
- **HDR PQ/HDR10 colour signalling now emitted, and a latent HLG-signalling
  regression fixed alongside it** -- `buildPQPreservationArguments()`
  existed but was never wired in, so PQ/HDR10/Dolby-Vision-base-layer
  sources (the most common HDR input) silently lost BT.2020/SMPTE ST 2084
  colour signalling. Fixing this surfaced that the HDR argument block ran
  *before* `extraArguments` was assigned, so both the new PQ args and the
  pre-existing HLG colour-signalling args were being overwritten and
  dropped before ffmpeg ever saw them; the block now runs after, so both
  paths reach `build()` (#486).
- **Per-stream subtitle overrides now applied** (#485) --
  `PerStreamSettings.subtitleOverrides` was collected by the UI but
  `toArgumentBuilder` never consumed it, unlike the audio/video overrides
  which already worked. `-map -0:s:<i>` exclusion and forced
  `-c:s:<i> copy` are now applied the same way the audio/video paths do.
- **Profile import now preserves `subtitleTonemap`** (#487) -- both
  `EncodingProfileStore.importProfile(from:)` and
  `ProfileSharing.importFromJSON` omitted the field when reconstructing a
  profile, so an imported or shared profile silently lost its subtitle
  tone-mapping setting. Note: `ProfileSharing`'s share-link generation/
  consumption flow itself remains separately broken and was not touched
  by this fix (#491, still open).
- **Post-encode action hooks now persist and fire on job completion, and
  watch-folder move/delete post-actions are honoured** -- the Hooks tab's
  action chain (`PostEncodeActionChain` -- real scp/cloud/scripts/trash/
  notify) previously only ran from its own dry-run Test button; it's now
  persisted to `UserDefaults` and executed from the queue's success path.
  `WatchFolderConfig.postAction` (move-to-completed / delete-source) is
  now honoured too, previously a no-op. Failure-path `runOnFailure`
  invocation is deliberately still out of scope (#277).
- **Output "Folder Structure" mode now honoured** (#275) -- the
  `outputMode` picker (mirror source tree vs. flat) had no readers;
  output was always flat regardless of the setting. A new
  `OutputPathResolver.resolveOutputDirectory(...)` now picks the
  destination directory per `outputMode`, composed with the existing
  filename-template/overwrite logic.
- **Metadata Tag editor now writes tags via ffmpeg** --
  `MetadataTagEditorView` built the ffmpeg argument list for display only
  and never ran it; a "Write Tags..." action now runs ffmpeg for real via
  `FFmpegProcessController`, reporting success only on exit 0 with the
  output file present (#467).
- **Loudness "Measure Levels" now runs ffmpeg** --
  `NormalizationSettingsView.measureLevels()` built ffmpeg arguments but
  never launched a process, so the button spun with no result; it now
  runs ffmpeg and populates measured LUFS/True Peak/LRA, mirroring
  `LoudnessReportView`'s pattern from #433 (#292).
- **Conditional encoding rules now applied at enqueue, and the rules view
  is reachable** -- `RuleEngine.evaluateRules` was fully implemented but
  had zero callers; a matching rule now overrides the profile for that
  job only (the manual Output Settings selection is left untouched).
  `ConditionalRulesView` is also now reachable from the sidebar (Tools
  group), previously orphaned (#469).
- **Team-profile HTTP push now actually sends** --
  `TeamProfileManager.pushProfiles`'s `.httpServer` case built the PUT
  request but never sent it, while the view reported "Pushed N profiles
  successfully" regardless; it now awaits the request via `URLSession`
  and only reports success on a 2xx response. The team-profile
  conflict-resolution UI remains unwired and is tracked separately, not
  touched by this fix (#482).
- **Bitrate-heatmap "Export Image" now renders the real heatmap** --
  `exportAsImage()` previously drew only a flat background rectangle and
  swallowed write errors with `try?`; it now renders the same
  `drawHeatmap(context:size:analysis:)` routine used on-screen through an
  off-screen `ImageRenderer` and surfaces failures through an error
  banner instead (#483).
- **Background-removal batch honours the chosen output directory** -- the
  batch path built an `NSSavePanel` but never called `runModal()` on it,
  and hardcoded output to `~/Desktop/BackgroundRemoved`. Replaced with an
  `NSOpenPanel` for directory selection; cancelling now returns without
  processing instead of silently falling back to Desktop (#488).
- **Dead Settings toggles wired up** -- `autoScrollLog`, `defaultProfileName`,
  custom ffmpeg/ffprobe paths, and `confirmBeforeEncoding` were persisted
  but read by nothing; all four now take effect (`ActivityLogView`,
  `AppViewModel.init`, `EncodingEngine.init`, and the Queue tab's Start
  Queue confirmation respectively) (#475).
- **History-weighted queue ETA** -- the orphaned `ETAPredictor` is now
  wired into the queue: `predictETA` supersedes the naive linear estimate
  once matching per-profile encode-speed history exists (cold-start still
  falls back to linear), and `recordEncode` logs each successful encode's
  speed on completion (#470).
- **QueueOptimizer's reorder now applies to the live queue** --
  `applyOptimisation()` previously animated a checkmark and dismissed
  without writing the reordered queue back; a new
  `EncodingQueue.reorder(to:)` now permutes the live queue to match
  (#448).
- **SmartCrop "Apply to Job" now wired in** -- `applyCropToJob()` was an
  empty method body; the chosen crop now merges into the enqueue filter
  chain, with precedence over auto-crop (#474).
- **Help menu / Cmd+? now opens the Help window** -- it previously called
  the `meedyaconverter://help` URL scheme, which has no registered
  handler (a silent no-op); it now calls `openWindow(id: "help")`
  directly (#481).

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
- **`BenchmarkView` wired to real FFmpeg benchmark execution (#435)** --
  `runStandardBenchmarks()` built real FFmpeg arguments for each
  codec/preset/resolution combination via `EncodingBenchmark.
  buildBenchmarkArguments` but then fabricated a "simulated" fps figure
  from hard-coded per-codec/preset multipliers instead of ever running
  them, so the Phase 13 encoding-speed benchmark feature (#325) showed
  entirely made-up numbers. It now mirrors `QualityMetricsView`'s
  proven pattern (#434), the closest reference since benchmarks also
  loop multiple sequential FFmpeg passes: locates FFmpeg via
  `FFmpegBundleManager`, then for each `standardBenchmarks` entry runs
  the real arguments through `FFmpegProcessController.startEncoding`
  (output discarded via `-f null -`; `BenchmarkResult` has no size
  field, so no temp output file is needed), measures real wall-clock
  encode time with `Date()`, and reads the real frame count from the
  last `-progress` update. A new pure helper, `EncodingBenchmark.
  makeResult(codec:preset:resolution:frames:encodeTime:
  hardwareAccelerated:)`, computes `fps = frames / encodeTime` so the
  figure reflects genuine throughput rather than FFmpeg's `speed=`
  multiplier. Runs on a `Task.detached` (mirroring `QualityMetricsView`)
  so the blocking FFmpeg-locate probe and the passes themselves can't
  block the UI thread; a missing FFmpeg binary surfaces a clear error
  instead of showing fabricated data; a new Cancel button and
  `.onDisappear` stop the running process and benchmark task cleanly,
  with results already collected up to that point retained. Verified
  end-to-end against real FFmpeg 8.1.2 on the dev machine: `h264/
  ultrafast@1920x1080` measured 300 frames / 0.463s = 648.55 fps,
  `h264/medium@1920x1080` measured 300 frames / 1.938s = 154.76 fps --
  sane, clearly differentiated real numbers. Added 14 pure unit tests
  for the previously-untested `EncodingBenchmark` (argument building,
  stderr-output parsing, and the new `makeResult` helper) (re #325,
  re #428).
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

- **DR-0001 recorded: GPL disc tools bundled in Direct builds only (#494)** --
  `docs/decisions/0001-gpl-disc-tools.md` decides that `cdrdao` / `ddrescue` /
  `wodim` are bundled in the Direct `.dmg` under GPLv2 §2 / GPLv3 §5 "mere
  aggregation" (each tool's licence text shipped alongside it, plus a written
  offer for source), invoked only as subprocesses and never linked into
  `ConverterEngine`. The original framing of #494 treated the App Store
  question as a licensing decision; it is in fact settled by a technical
  fact that made that framing moot: `MeedyaConverter-AppStore.entitlements`
  declares `com.apple.security.app-sandbox` with no raw optical-device
  entitlement, and Apple offers none -- disc imaging cannot work in an App
  Store build under any tool licence, so the feature stays Direct-only on
  technical grounds regardless. The drafted `ToolBundleManifest` entries are
  recorded in the decision but deliberately not added to `defaultManifest`
  until the binaries are actually staged, which would otherwise assert
  binaries the app does not yet bundle.
- **The HTTP API is no longer documented as fabricated (#497)** --
  `docs/api/meedya-http-api.yaml`, its README section and the Swagger UI banner
  were written on 2026-07-28, when `APIServer`'s endpoints really were stubs.
  They were wired to the real engine afterwards and the documents were never
  updated, so anyone opening the bundled Swagger UI saw four of five routes
  struck through as `deprecated` with summaries beginning "NOT IMPLEMENTED --
  fabricated". All five routes in fact call the real engine
  (`EncodingQueue.addJob`, `EncodingEngine.probe(url:)`, `jobsSnapshot()`,
  `profileStore.allProfiles()`, real version and uptime). `deprecated` and
  `x-status: not-implemented` removed; response schemas corrected against the
  handlers' actual output (`/probe` had reused one existence-only schema for
  both 200 and 404 and omitted its 503 branch entirely; `/status` documented
  `uptime` where the handler emits `uptimeSeconds`; `/profiles` documented
  FFmpeg binary names where the handler emits Swift enum raw values). The one
  genuine limitation -- `POST /encode` enqueues but nothing starts the queue
  runner -- is now documented in its place.
- **`meedya-convert serve` documented (#497)** -- the subcommand shipped in
  `1773763` but appeared in neither the CLI OpenAPI spec nor the in-app CLI
  reference, so `--help` was the only way to find it. Both now cover `--port`,
  `--api-key`, the mandatory bearer token, the all-interfaces bind, the queue
  runner limitation and the exit codes. Three documents also claimed "there is
  no `meedya-convert serve` -- the CLI cannot start this server"; in fact
  `APIServerView` has no `NavigationItem` case, so the CLI is the *only* way to
  start it -- the exact inverse of what was written.
- **Architecture and feature docs reconciled with the source tree (#497)** --
  `docs/Architecture.md` was presenting seven modules deleted by the orphan
  sweep as live architecture (`EncodingReport`, `HDRPolicyEngine`,
  `MetadataPassthrough`, `MetadataTagger`, `PQToHLGPipeline`,
  `SmartCropIntegration`, `SubtitleConverter`), and listed six more that exist
  but have no call site. Deleted entries removed, the HDR/Subtitles/Metadata/
  Backend rows rewritten to describe the paths that actually run, and a new
  "Dormant modules" subsection added so the diagram cannot be read as a claim
  that dormant capabilities ship. `FEATURES.md` and `PROJECT_STATUS.md`
  dead-code tables were stale in both directions -- five rows described files
  that no longer exist, five more still called a feature dead after the
  2026-08-04 wave fixed it -- and are now correct.
- **Two false capability claims removed (#497)** -- `docs/Home.md` advertised
  "MusicBrainz, TMDB, TVDB, Discogs, FanArt.tv integration" and `docs/FAQ.md`
  listed metadata lookup among the reasons the app touches the network. Neither
  is possible. The FAQ's network list now names only what genuinely makes
  requests, each checked for a live caller.
- **MusicBrainz Nov 30 2026 re-verified against primary sources (#493)** -- the
  announcement and all twelve linked SEARCH tickets were fetched first-hand
  this session (MetaBrainz egress, previously HTTP 403, now returns 200), so
  the "verified safe" conclusion no longer rests on transcribed text. Two
  ticket details not present in the announcement are now recorded in
  `MusicBrainzClient`'s doc comment: SEARCH-666 shows `quality:low|normal|high`
  are broken *today* and only the numeric forms work, with the fix making the
  names correct -- the previous comment told a future implementer the opposite;
  and SEARCH-681 adds Genre as a search *target type*, not a search *field*,
  with genre-name search already available through `tag`.

- **README / PROJECT_STATUS / FEATURES honesty reconciliation** -- audited
  every user-facing feature claim in README.md, PROJECT_STATUS.md, and
  FEATURES.md against the actual call graph (static analysis; no
  `swift build` available in this environment). Relabelled orphaned/
  arg-builder-only code as "Planned / scaffolded" instead of removing the
  roadmap context, and separated real-but-unreleased branch work (cloud
  upload execution, unified statistics, email/webhook notifications,
  watch-folder auto-encode, recent files, scheduled encoding, IntAppsAPI,
  orphaned-view navigation, overwrite/delete-source toggles -- see Added,
  above) into its own "landing in the next alpha build" section so it's
  not confused with the released `v0.1.0-rc.3`. Two previously-unflagged
  findings surfaced during the audit: the Scene Detection view builds
  FFmpeg arguments but never launches FFmpeg (logs "requested" and
  returns -- #288, same class of bug #433-#435 fixed elsewhere but this
  one wasn't caught at the time), and AccurateRip verification has no real
  caller (`AudioCDReader` has zero instantiation sites). Also reworded
  unverifiable specifics (exact test counts) to "full suite, verified in
  CI" rather than restating stale numbers, and corrected the open-issue
  count to 98 (verified).
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
  to post-autopilot reality: full test suite green in CI with 0 compiler
  warnings, the F-001..F-012 security findings register status,
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
- **Audio format compatibility guide** -- Comprehensive conversion matrix documentation (`Sources/MeedyaConverter/Resources/Help/audio-format-compatibility.md`)
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
