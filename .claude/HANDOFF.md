<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Session Handoff / Continuity Doc

**Purpose:** crash-safe resume point. If a session ends unexpectedly, read this
first to pick up exactly where we left off. Updated after each completed task.

**Last updated:** 2026-07-28 · **working branch `wip/alpha-consolidation`** (= `main` + audit doc) · VERSION 0.1.0

> **Location note:** this doc lives at `.claude/HANDOFF.md` (moved from repo root 2026-07-22).

## ⚠️ Read this first — branch model (as of 2026-07-22)

- **`wip/alpha-consolidation`** is THE single work-in-progress branch. All work commits here.
  It will eventually be merged into **`alpha`** via ONE pull request (deliberately **no PR stacking**).
- `main` = trunk, contains all completed work. `alpha`/`beta` = live pre-release channel branches
  wired to `.github/workflows/beta-alpha.yml` (**never delete; a push to them mints a public pre-release**).
- **Consolidated + verified obsolete (2026-07-22):** `claude/branch-audit-consolidate-g87lr4`,
  `autopilot/2026-06-30-clean`, `consolidate/autopilot-2026-07-18`. Content-level verification confirmed
  zero loss (audit doc cherry-picked byte-identical; the two autopilot branches are strict ancestors of main).
  **Deletion is pending a manual step** — this environment's git proxy refuses ref deletions and the GitHub
  MCP has no delete-branch tool, so they must be deleted in the GitHub UI.
- **Forecast for the eventual `wip/alpha-consolidation` → `alpha` PR:** exactly 2 conflicts, both resolve
  **wip-side**: `.github/workflows/dependency-review.yml` and `.github/workflows/lint.yml`.

---

## Where we are

- Code is **feature-complete for v0.1.0**; the GA *release ritual* (#428) is still pending.
- The project runs a **dev-team / autopilot** convention: state in `.dev-team/autopilot.json`,
  custom subagents in `.claude/agents/` (`deep-architect`, `quick-edits`), context in `.claude/`.
- **Orchestration model (per user standing instructions):** Fable 5 (sequential, not parallel)
  for all analysis / deep planning — fall back to Opus only if Fable is unavailable, then retry
  Fable next time. Implementation via **Sonnet / Haiku** (Opus only if truly necessary).
  Efficient credit/token use; GIRFT (get it right first time). No local macOS build available —
  CI (`Build & Test (macOS)`) is the correctness gate for all Swift changes.

## Merged to `main` this session (2026-07-21)

| PR | Summary |
|----|---------|
| #430, #443 | Branch consolidation: autopilot 2026-07-18 batch + Dependabot bumps + actionlint |
| #454 | GA honesty fixes — real trim #444, real QC #445, SFTP probe #447, disabled fake upload #446, hid Perceptual #449 |
| #455 | Swift 6 concurrency audit #451 (ScriptingBridge 60s block deferred) + doc-honesty #453 |
| #456 | Wired BitrateHeatmap / CloudSync / EncodingGraphs to real engine (#448 partial) |
| #439 | Dependabot: actions/checkout → 7.0.1 |
| #457 | SFTP post-encode action → real scp upload (#450); cloud part honestly gated |
| #458 | Split 12k-line ConverterEngineTests monolith into 20 per-domain files (#452) |

Also: **#436 → `alpha`** (actionlint workflow) — merged, minting an `alpha` pre-release.

## Per-task protocol (follow for every task)

1. **Issue** — ensure a GitHub issue exists; **create** it, or **reopen** if it was closed in error.
2. **Implement** — Sonnet/Haiku on a branch → PR → `Build & Test (macOS)` green → merge.
3. **Update the issue** — comment progress and/or close on completion.
4. **Update this HANDOFF.md** — move the task to the log below with its outcome, bump `main @ <sha>`, commit.

## Active program — 2026-07-21 autonomous dev-team cycle

Directive: implement the cloud-upload execution gap (file issue + fix), **#449** perceptual-hash
properly (per original spec), **#448 remainder** (DualDynamicHDR + EncodingStatisticsCollector
pipeline wiring); run a full open+closed GitHub issue review (Fable) → roadmap; loop for new
tweaks/enhancements/features. Bundle work for efficiency.

## Task log (most recent first)

- **[done]** Fable DISCOVER/STRATEGIZE pass (2026-07-22) — enumerated all 419 issues (50 open / 369
  closed); produced the 7-bundle roadmap below. Key finding: ~11 CLOSED issues are **closed-in-error**
  (feature never executes in current code): cloud upload #161–175/#347, YouTube/Vimeo #294,
  DualDynamicHDR #370, GIF/APNG #321, Slate #343, metadata-tag write #320, comparison #329,
  CSV #363, dashboard stats #284, QC #344.

## Roadmap / next steps — 7 bundles (execute in order; each = its own issue(s) + PR + CI + issue-update + handoff-update)

- **Bundle 1 — Cloud-upload execution layer** (committed). Shared `CloudUploadExecutor` (URLSession
  upload, real status/retry/progress); wire Dropbox/GDrive/OneDrive (token-paste v1), YouTube/Vimeo
  (#446), S3 SigV4 signer, `PostEncodeActions.uploadCloud` (#450). NEW umbrella issue. **1f full OAuth
  PKCE = HUMAN-BLOCKED** (needs user OAuth client IDs) — do token-paste v1 only.
- **Bundle 2 — #449 perceptual hash** (committed). New `PerceptualHasher` (AVAssetImageGenerator frame
  sample → 32×32 gray → DCT → 64-bit pHash → Hamming grouping); un-hide the Perceptual option. CI-testable.
- **Bundle 3 — #448 remainder** (committed). 3a DualDynamicHDR executor (dovi_tool/hdr10plus_tool via
  existing runAsync); 3b wire `EncodingStatisticsCollector` into `AppViewModel` queue runner (#284);
  3c CSV export (#363); 3d AnimatedImage real execution (#321).
- **Bundle 4 — Placeholder sweep round 3.** Slate (#343), MetadataTag write (#320), Comparison (#329),
  PluginManager handoff (spot-check first). SmartCrop/MediaBrowser exposure done as part of roadmap
  item #1 (2026-07-28, see below) — their nav entries are live and `MediaBrowserView`'s import path
  is real; remaining Bundle 4 items are still open.
- **Bundle 5 — QC residual detectors (#445).** levelCompliance (reuse ebur128), corruptFrames (ffmpeg
  null decode scan), formatConformance (ffprobe vs spec); audioSync stays gated on #421/#422.
- **Bundle 6 — Test coverage + CI.** Tests for #450 SFTP code, stats store, pHash, HDR executor; #437 actionlint.
- **Bundle 7 — Issue hygiene (continuous).** Close #447 (fix merged); evidence-comment + reopen the
  closed-in-error set as each bundle adopts it; backfill labels/milestones on #444–#453; refresh docs.

**Human blockers (do NOT schedule):** OAuth client IDs (1f), real cloud/YouTube accounts + dovi/hdr10plus
media for E2E (rc soak), G-015 SHA-pin timing, gate-ledger #419–#427, release cut G-010/G-013.

## Standing tasks note

- Added **standing task #14 — monitor GitHub PR security checks** (CodeQL/code-scanning, Dependency Review,
  secret scanning, `security-check` pin-hygiene, OpenSSF Scorecard) to `.claude/standing_tasks.md`. Applies to
  every PR, every session: a green macOS build is necessary but not sufficient — security checks must pass too.

## Current work-in-flight

- **[done 2026-07-22]** Bundle 1 core (#459 / #450) — cloud-upload execution: `CloudUploadExecutor`
  (real URLSession upload, 2xx-only, retry/backoff, byte progress, OneDrive chunked session) +
  Dropbox/GDrive/OneDrive real upload + `PostEncodeActions.uploadCloud` + 21 URLProtocol-mock tests.
  **PR #460 merged (`a902cb6`).**
- **[done 2026-07-22]** Bundle 1b (#459) — **S3 SigV4** signer (`AWSV4Signer`, AWS test-vector-verified) +
  real signed S3 PUT via `CloudUploadExecutor`. **PR #463 merged (`4af2bae`).** Cloud remaining: YouTube/Vimeo
  (OAuth-blocked, #446), S3 multipart >5 GiB TODO.
- **[done 2026-07-22]** Bundle 2 (#449) — perceptual hash: `PerceptualHasher` + un-hid Perceptual + 24 tests.
  **PR #461 merged.** #449 closed.
- **[PR #462 — CI re-running on fix `e4ac19d`]** Bundle 3 (#448 remainder) — DualDynamicHDR executor (#370),
  `EncodingStatisticsCollector` pipeline (#284), CSV export (#363), AnimatedImage (#321). Closes those 4 on merge.
- **[done 2026-07-28]** Roadmap item #3 — statistics unification (#284, #363), on `wip/alpha-consolidation`.
  `EncodingStatisticsStore` (the real per-job pipeline fed from `AppViewModel.startQueue()`) is now the ONE
  source of truth for both the Dashboard and the CSV/JSON export view — no more parallel, always-zero
  `StatisticsTracker` singleton. Changes:
  - `EncodingStatistics` gained three optional fields (`profileName`, `containerFormat`, `succeeded`;
    `nil` = legacy, treated as success) plus matching CSV columns; `EncodingStatisticsCollector` gained
    `markFailed()` so the failure path (previously statistics-silent) now persists too.
  - `EncodingStatisticsStore.exportAsJSON`/`exportAsCSV` gained optional `startDate`/`endDate` filtering.
  - `EncodingStats.init(aggregating:)` (in `AggregateStatistics.swift`) derives Dashboard aggregates from
    `EncodingStatisticsStore.allStatistics` on demand — replacing `StatisticsTracker` entirely (**deleted**,
    it persisted its own `statistics.json` but its only write path, `recordEncode`, had zero callers, so the
    Dashboard always read zeros).
  - `DashboardView` and `StatisticsExportView` now both read live from `EncodingStatisticsStore`.
    `StatisticsExportView` no longer builds `EncodingStats()`/`history: []` inline and reports fake export
    success — it writes the store's real CSV/JSON bytes. Its column-picker UI was removed (the store's
    export always emits the full real record) along with its unused `AppViewModel` environment dependency.
  - `Sources/ConverterEngine/Utilities/StatisticsExporter.swift` (`StatisticsExporter` + `ExportColumn`)
    **deleted** — sole consumer was `StatisticsExportView`, zero test references.
    `ETAPredictor`/`EncodeHistoryEntry` (separate file, separate concern) kept as-is, tracked by #470.
  - New/extended tests: `EncodingStatsAggregationTests.swift` (new), `EncodingStatisticsStoreTests.swift`
    (`markFailed`/`markComplete`, new-field round trip, legacy-decode pin), `EncodingStatisticsCSVExportTests.swift`
    (date-window CSV/JSON export). No data migration needed — `statistics.json` could only ever have been
    written by the zero-caller `recordEncode`, so there was nothing real to migrate.
- **[done 2026-07-28]** Roadmap item #1 — expose the safe orphaned views, on `wip/alpha-consolidation`
  (re #448, re #363, re #284, re #348). 16 fully-implemented views had no navigation entry; 6 stay
  hidden because their backends are fabricated/dead (tracked separately in #355, #343, #329, #467,
  #468, #469 — `APIServerView`, `MetadataEditorView`, `SlateGeneratorView`, `ComparisonView`,
  `ResumableJobsView`, `ConditionalRulesView` — **no enum cases / nav entries added for these**). The
  other 10 are now reachable:
  - **7 new sidebar destinations** (`NavigationItem` cases in `AppViewModel.swift` + `ContentView`
    detail-switch arms, both exhaustive switches updated): Media Browser, Encoding Graphs, Statistics
    Export, Dual Dynamic HDR, Smart Crop, Background Removal, Voice Isolation.
  - **Sidebar restructure** (`SidebarView.swift`): Workflow gains Media Browser; Monitor gains
    Encoding Graphs + Statistics Export; Tools gains Dual Dynamic HDR; new **"Images & Audio"**
    section holds Images, Animated Image, Vector Conversion, ProRes to Vector, Smart Crop, Background
    Removal, Voice Isolation (moved Images/Animated Image out of Tools). **Pre-existing bug fixed**:
    `vectorConversion` and `proresVector` already had enum cases + a `ContentView` switch arm but
    appeared in NO sidebar section — unreachable via the UI despite being fully wired. Now live in
    Images & Audio.
  - **2 embedded (non-sidebar) exposures** in `OutputSettingsView.swift` — these take init params so
    aren't sidebar destinations: `ProfileSuggestionView` banner inside "Encoding Profile"
    (`.id(file.id)` resets its `@State` suggestions when the selected file changes), and a
    `QualityPreviewView` sheet behind a new "Quality Preview..." button next to "Preview FFmpeg
    Command...".
  - **`MediaBrowserView.importSelectedFiles()` fixed** — was a documented no-op ("Queue integration
    would be handled by the parent"). Now calls `viewModel.importFiles(urls)` +
    `viewModel.selectedNavItem = .source`, mirroring `ContentView`'s proven drop-import path. Required
    before exposing the view at all, per plan — otherwise it'd be another fabricated surface.
  - **Part E shipped (#348), not skipped.** `EmailSettingsView` was orphaned AND its
    `emailOnComplete`/`emailOnFailure` toggles had zero consumers, so both had to land together
    (ship-both-or-neither). Added Settings → Services → "Email" tab; extracted
    `EmailSettingsView.loadSMTPConfig() -> SMTPConfig?` (and made `loadPasswordFromKeychain()`
    `static`) so it's callable without a live view instance; wired
    `AppViewModel.sendCompletionEmail(...)` into both the encode-success and encode-failure branches
    of `startQueue()`, next to the existing `sendNotification` calls, gated on
    `UserDefaults.standard.bool(forKey: "emailOnComplete"/"emailOnFailure")`. The blocking `curl`
    `Process` transport — the same one already proven inside
    `EmailSettingsView.sendTestEmail()` — runs in `Task.detached`, capturing only the prepared
    `Sendable` `String`/`[String]` values (subject/body/curl-args), never a `@MainActor self`.
  - Compile-uncertain spots for CI to confirm (no local macOS build available): the
    `ProfileSuggestionView(sourceFile:profiles:onSelectProfile:)` / `QualityPreviewView(sourceFile:
    profile:)` memberwise-init argument labels — verified by inspection against their `let`
    properties and cross-checked against the same `@Environment` + `let`-params pattern already
    proven by `StreamMetadataEditorView(mediaFile:)` elsewhere in `OutputSettingsView.swift`; and the
    `Task.detached` `Sendable`-capture shape in `sendCompletionEmail`.
- **[done 2026-07-28]** Roadmap item #2 — chunked/resumable Dropbox + Google Drive uploads (re #459),
  on `wip/alpha-consolidation`. `CloudUploadExecutor.uploadToCloudStorage` previously sent Dropbox and
  Google Drive as ONE whole-file request — Dropbox's `/2/files/upload` caps at 150 MB
  (`DropboxUploader.singleUploadMaxBytes`) and Google Drive's `uploadType=media` is documented for
  small files only (`GoogleDriveUploader.simpleUploadMaxBytes`, 5 MB) — so real media output routinely
  failed the upload feature outright. Mirrors the existing OneDrive `uploadInSessionChunks` shape
  (create/start request → `FileHandle` chunk loop → per-chunk `executeWithRetry` → final-response
  parse), reusing the previously-unused `DropboxUploader`/`GoogleDriveUploader` URL and size/chunk-size
  constants in `CloudProviders.swift`. Changes:
  - New builders in `CloudStorageUploader.swift` — `buildDropboxSessionStartRequest`,
    `buildDropboxSessionAppendRequest`, `buildDropboxSessionFinishRequest`,
    `buildGoogleDriveResumableInitRequest` — all via `JSONSerialization`, NOT the existing unused
    `DropboxUploader.buildSessionStartHeaders`/`buildSessionFinishHeaders` or
    `GoogleDriveUploader.buildUploadMetadata` (left untouched as existing public API): those build JSON
    by string interpolation (breaks on a filename containing a `"`), and `buildSessionFinishHeaders`
    hardcoded `"mode":"add"` where the simple upload path uses `"overwrite"` — the new
    `buildDropboxSessionFinishRequest` matches the simple path's `"overwrite"`.
  - `CloudUploadExecutor.executeWithRetry` gained a private `additionalSuccessStatusCodes: Set<Int> = []`
    parameter (existing call sites unaffected) — required because Google Drive's resumable-upload
    protocol answers **`308 Resume Incomplete`** for every non-final chunk as its real, documented
    success response, not `2xx`. New `uploadInDropboxSessionChunks(fileURL:config:chunkSize:progress:)`
    and `uploadInGoogleDriveResumableChunks(fileURL:initiateRequest:chunkSize:progress:)` on
    `CloudUploadExecutor`; `uploadToCloudStorage` now routes Dropbox above 150 MB and Google Drive above
    5 MB into these, mirroring the existing OneDrive (4 MB) branch — both existing callers
    (`CloudStorageView.performUpload`, `PostEncodeActions.uploadViaCloud`) needed no changes since
    routing is centralised there.
  - The 308-accept-set is scoped to non-final chunks ONLY: the final chunk always uses the plain
    `executeWithRetry` (no additional success codes), so a 308 on the final chunk — meaning the server
    is still missing bytes — fails honestly as `.httpError(308, …)` rather than ever being read as
    success.
  - **Known limitation (Dropbox), same semantics already accepted for the OneDrive path**: a chunk-level
    retry re-sends the identical cursor offset (the append request is built once, before `offset`
    advances, and reused verbatim across retry attempts). If the original request actually succeeded
    server-side and only its response was lost, the retried append lands at an offset the server has
    already moved past, and Dropbox answers `409 incorrect_offset` — surfaced honestly as
    `.httpError(409, …)`, never silently absorbed or retried into a fabricated success. A caller hitting
    this must restart the whole upload.
  - New tests: `Tests/ConverterEngineTests/CloudChunkedUploadTests.swift` (9 scenarios — small-file
    routing for both providers, large-file session/resumable routing, session-start / initiate
    failure-fast paths, append-offset and finish-cursor correctness, mid-chunk-retry same-offset
    pinning, the 308 non-final-vs-final accept-set boundary) plus 4 new request-builder tests appended
    to `CloudUploadExecutorTests.swift`'s existing "(d) Provider request-builder correctness" section.
  - Compile-uncertain for CI (no local macOS build available): the nested-heterogeneous-dictionary
    `Dropbox-API-Arg` JSON bodies (`cursor`/`commit`) are built as separate, explicitly-typed
    `[String: Any]` `let`s before assembly, specifically to sidestep Swift's "heterogeneous collection
    literal could only be inferred to '[String : Any]'" diagnostic on an inline nested literal; and the
    `HTTPURLResponse.value(forHTTPHeaderField:)` read of the Google Drive initiate response's `Location`
    header, which depends on `MockURLProtocol`/`URLSession` correctly propagating response headers
    through the mocked `URLProtocol` loading system in the new tests.
  - Next queued: roadmap item #9 (`PostEncodeActionChain` tests), then item #10 (ScriptingBridge 60s
    semaphore, deferred from #451).
- **[done 2026-07-28]** Roadmap items #9, #10, #8 (engine-layer batch), on `wip/alpha-consolidation`.
  **Numbering note**: the "item #10" description in the previous log entry above (ScriptingBridge 60s
  semaphore) turned out to be superseded — the actual task brief for #10 in this batch was "wire or
  descope FTP/rsync (re #174)"; the ScriptingBridge semaphore item is not yet scheduled (added to the
  queue below).
  - **#9 — `PostEncodeActionChain` test coverage (re #450).** Was at ZERO tests. New
    `Tests/ConverterEngineTests/PostEncodeActionsTests.swift`: `ActionError.errorDescription` for all 4
    cases; missing-`sftpProfileID`/`cloudProfileID` config resolution throws a real
    `ActionError.missingConfig` through the public `execute(inputURL:outputURL:success:)` API (never
    silently succeeds); chain ordering/skip/error-aggregation (disabled actions skipped, `runOnFailure`
    respected on both success and failure, first error surfaces even when a later action also fails);
    `substituteVariables` placeholder substitution; `PostEncodeActionType`/`PostEncodeAction`/
    `PostEncodeActionChain` Codable round trips. **One seam added, `@testable`-only**:
    `PostEncodeActionChain.execute(inputURL:outputURL:success:actionExecutor:)` — an internal overload
    the public 3-arg `execute` always calls with `actionExecutor: nil`, so production behaviour is
    unchanged; it lets tests inject a fake per-action dispatch instead of spawning real
    `scp`/`curl`/`osascript`/`zsh` processes or hitting the network. Also bumped
    `substituteVariables(in:inputURL:outputURL:profile:status:)` from `private` to internal (still
    unreachable outside the module without `@testable`) so its pure string-substitution logic has a
    direct test instead of only being observable through a real shell/notification process.
    **Correction to the task brief**: `execute`'s real, documented behaviour is "continue past a failing
    action, surface the first error" — NOT abort-on-first-failure as the brief assumed. Tests pin the
    real behaviour (`test_execute_runsEveryEnabledActionInOrder_andDoesNotAbortOnFailure`) rather than
    asserting the assumed one; production runtime behaviour was left untouched (changing it wasn't asked
    for and the brief itself says "WITHOUT changing public behaviour").
  - **#10 — FTP/rsync (re #174): DESCOPED, not wired.** `SFTPUploader.buildFTPUploadArguments`/
    `writeFTPCredentialsConfig`/`buildRsyncArguments` are real, correct, already-tested argument
    builders that are simply never called from any execution path — only `scp` (via
    `upload(localPath:config:)`) runs. Evaluated wiring them in: `SFTPServerConfig` (the one config type
    `PostEncodeActionChain`/`SFTPSettingsView`/`SFTPProfileStore` all share) has **no transfer-protocol
    selector field**, so dispatching between scp/rsync/ftp per profile requires adding one — which
    ripples into both the `Codable` migration story (mirroring the `id` field's backward-compatible
    decode) and `SFTPSettingsView`'s form, neither of which this no-local-build session could validate
    end to end. `FTPServerConfig` compounds this: it's a structurally different type with no `id`, no
    profile-store persistence, and no UI path to ever construct one. Chose the honest minimum per the
    task brief's own explicit fallback: added a type-level "Execution status" doc comment on
    `SFTPUploader` plus a `// TODO(#174)` on each of the three unwired builders, so nothing looks
    functional that isn't. Added 2 new tests strengthening `buildRsyncArguments`' auth-branch coverage
    (`.keyFile` escaping, `.password` `BatchMode=no`) in
    `ConverterEngineTests+CloudAndMetadataLookup.swift`, next to the pre-existing scp/rsync/FTP
    argument-building tests (which already covered the basics).
  - **#8 — two more QC detectors (re #445).** Implemented `corruptFrames` and `levelCompliance` for
    real in `QualityChecker.swift`, keeping its pure/process-free architecture: new
    `buildCorruptFrameDetectionArgs(inputPath:)` (`ffmpeg -v error -i <input> -f null -`) +
    `parseCorruptFrameOutput(_:)` (one `.failed` `QCResult` per non-blank `-v error` stderr line, a
    single `.passed` result when stderr is empty); new `buildLevelComplianceArgs(inputPath:)` (delegates
    to the existing, tested `LoudnessReporter.buildAnalysisArguments(inputPath:)` byte-for-byte) +
    `parseLevelComplianceOutput(_:standard:)` (thin adapter over the existing, tested
    `LoudnessReporter.parseAnalysisOutput`/`checkCompliance` — real EBU R128/ebur128 pass/fail, never a
    second loudness-math implementation) + a `normalizationStandard(forLoudnessStandard:)` helper
    mapping `QCProfile.loudnessStandard`'s free-form label to a `NormalizationStandard` (defaults to
    `.ebur128`). `runAllChecks` now skips both checks (added to the same "requires FFmpeg, resolved by
    the caller" `continue` case as `blackFrames`/`silenceDetection`) instead of returning
    `.notImplemented` for them. Wired real execution into `QualityCheckView.runQualityChecks()` with two
    new blocks mirroring the existing black-frame/silence `FFmpegProcessController` flow exactly (same
    cancellation handling, same error-message chaining). `audioSync` and `formatConformance` stay
    `.notImplemented` — `audioSync` is genuinely gated on #421/#422. New
    `Tests/ConverterEngineTests/QualityCheckerTests.swift` (QualityChecker had zero prior coverage):
    arg-builder assertions, parser tests against representative `-v error` decode-error lines
    (hand-written — no `ffmpeg`/corrupt-fixture available in this environment to capture a real one) and
    real `loudnorm` JSON shapes (compliant/non-compliant/unparsable), the
    `normalizationStandard(forLoudnessStandard:)` mapping, and `runAllChecks` regression guards for both
    the newly-real checks (now omitted, not stubbed) and the still-stub checks (still `.notImplemented`).
  - Compile-uncertain for CI (no local macOS build available): the `PostEncodeActionChain` seam overload
    resolves correctly against the public 3-arg `execute` (labelled-parameter overload, verified by
    inspection, not by compiling); `QualityCheckView`'s two new `FFmpegProcessController` blocks follow
    the exact structural shape of the pre-existing black-frame/silence blocks in the same function, so
    risk is low but unverified locally.
  - Next queued: #6 (APIServer honesty), #11 (email-on-completion — already wired per the #348 log entry
    above, needs verification not implementation), #7 (S3 UI surface + multipart >5 GiB), #15, #13, #14,
    #16, #12 (none of these have been scoped/read yet this session), plus the still-unscheduled
    ScriptingBridge 60s semaphore fix deferred from #451 (previously mislabelled "#10" above).
- **[done 2026-07-28]** Roadmap items #6, #11, #15, on `wip/alpha-consolidation`.

  **#6 — Make `APIServer` honest (re #355).** Added `EncodingEngine` initialiser injection
  (`APIServer(port:apiKey:engine:)`, default `EncodingEngine()` so `APIServerView` keeps compiling) and a
  `startTime: Date?` captured in `start()` (cleared in `stop()`). Per-endpoint outcome:
  | Endpoint | Before | Now | Notes |
  |---|---|---|---|
  | `GET /profiles` | 4 hardcoded fake profiles | **REAL** — `engine.profileStore.allProfiles()` (built-in + user-created) | New lock-protected `EncodingProfileStore.allProfiles()`; existing unsynchronised `profiles` property read left alone for its `@MainActor`-only UI call sites |
  | `GET /status` | hardcoded `"1.0.0"` / `"active"` | **REAL** — `AppInfo.Version.displayString` / `uptimeSeconds` computed from `startTime` | |
  | `GET /queue` | always empty | **REAL** — `engine.queue.jobsSnapshot()` | New lock-protected `EncodingQueue.jobsSnapshot()`, same rationale as `allProfiles()` |
  | `POST /encode` | invented `jobId`, never enqueued | **REAL** — validates input exists + profile resolves, then genuinely calls `engine.queue.addJob(_:)`; `jobId` in the response is the real job's UUID | Honestly disclosed via a `note` field: encoding only starts once something drives the queue (today only `AppViewModel.startQueue()` on `@MainActor`, which `ConverterEngine` has no reference to and must not reach into) — this mirrors the GUI's own "Add to Queue" vs "Start Queue" split, not a new limitation |
  | `POST /probe` | `FileManager.fileExists()` only | **REAL** — calls `try await engine.probe(url:)` (real FFprobe) | Deliberately does **not** call `engine.configure()` itself: `EncodingEngine.ffmpegInfo`/`ffprobeInfo` are unsynchronised `var`s that `configure()` writes to, and `AppViewModel.startQueue()` already calls `configure()` on `@MainActor` — having `APIServer` call it too from its own background dispatch queue would be a genuine concurrent-write race, exactly the cross-actor risk this task said not to take on blind. If the engine hasn't been configured by whoever owns it, this returns `503` with the real error instead of guessing. No endpoint needed a `501` — all five got a real (or honestly-failing) implementation |

  `routeRequest`/`handleConnection` became `async` (bridged via a plain `Task` in the `NWConnection` receive
  callback, not a blocking semaphore — see the #13 ScriptingBridge item below for why that pattern is
  avoided) solely so `POST /probe` can `await` the real probe. The five handler methods + `routeRequest`
  moved from `private` to `internal` (still not `public`) purely so `@testable import` can reach them for
  tests, mirroring the `PostEncodeActionChain.actionExecutor` precedent. New
  `Tests/ConverterEngineTests/APIServerTests.swift` (20 tests): JSON-shape assertions for all five
  endpoints against a real injected `EncodingEngine`, `routeRequest` auth/routing (401/404/204), and
  regression pins against the old fake values (`"1.0.0"`, the four fake profile names, always-empty queue).
  Deliberately never calls `profileStore.addProfile`/`deleteProfile` in tests — `EncodingEngine` has no
  injection point for a temp `EncodingProfileStore` directory, so that would persist a write to the real
  test-runner's `~/Library/Application Support/MeedyaConverter/Profiles/`; read-only assertions against the
  always-present built-ins are used instead. `APIServerView`/`APIServerViewModel` gained a matching
  `engine: EncodingEngine = EncodingEngine()` init parameter (still unused by anything — the view has no
  navigation entry) so a future caller can hand it `AppViewModel.engine` and get the real, shared
  profiles/queue instead of a disconnected standalone engine. **`APIServerView` is now honest end-to-end
  and could be exposed in navigation — not done here, per the task brief, tracked separately.**

  **#11 — Verify the email-on-completion wiring (re #348): already correct, nothing changed.** Read
  `AppViewModel.sendCompletionEmail`/`EmailSettingsView` end-to-end: `emailOnComplete`/`emailOnFailure`
  are read via `UserDefaults.standard.bool(forKey:)` using the exact same string keys
  `EmailSettingsView`'s `@AppStorage("emailOnComplete")`/`@AppStorage("emailOnFailure")` toggles write;
  `loadSMTPConfig()` reads the same `UserDefaults` keys as its own `@AppStorage` SMTP fields
  (`emailSMTPHost`/`Port`/`Username`/`UseTLS`/`emailFromAddress`/`emailToAddresses`), plus the password via
  `loadPasswordFromKeychain()`, which shares the exact `keychainService`
  (`"Ltd.MWBMpartners.MeedyaConverter.smtp"`) / `keychainAccount` (`"smtpPassword"`) constants
  `savePasswordToKeychain()` writes with — one Keychain item, read and written by the same two `static`
  constants. A missing/incomplete config makes `loadSMTPConfig()` return `nil`, which
  `sendCompletionEmail` guards on and returns early: no crash, no fabricated "sent" message (nothing logs
  or displays a success indicator for the email path at all — silent-but-safe, matching
  `sendNotification`'s existing fire-and-forget style; the `curl` `Process` failure path is caught and
  dropped the same way). No mismatch found. Added
  `Tests/ConverterEngineTests/EmailNotifierTests.swift` (13 tests, `import ConverterEngine`, no
  `@testable` — the tested surface is fully `public`) covering the parts of the feature that actually live
  in `ConverterEngine` and are therefore testable: MIME header/boundary construction, `curl` argument
  construction (scheme selection, one `--mail-rcpt` per recipient, credentials, stdin-piped upload — a
  regression guard confirms the raw email body is never interpolated into argv), and
  `formatJobCompletionEmail`'s HTML (including that file names / error messages are HTML-escaped). The
  `AppViewModel`/`EmailSettingsView` wiring itself has no reachable test target — `MeedyaConvertTests`
  depends on `ConverterEngine`, not the `MeedyaConverter` executable target, because Swift forbids
  importing a module containing `@main` into a test target — so that half was verified by inspection only.

  **#15 — `MediaEncryption`: DELETED (re #451-style cleanup), not streamed.** Grepped for every symbol it
  defines (`MediaEncryption`, `EncryptionConfig`, `EncryptionMode`, `EncryptionError`, `encryptFile`,
  `buildHLSEncryptionArguments`, `buildKeyInfoFile`) across `Sources/` and `Tests/`: zero references
  anywhere outside the file itself, confirming the task brief's "ZERO callers" claim. It's also a genuine
  duplicate: `Sources/ConverterEngine/FFmpeg/StreamingEnhancements.swift` already has a separate, unrelated
  `HLSEncryption` type covering the same ground (AES-128 key generation, `-hls_key_info_file` key-info-file
  construction) — also with no production call site, but at least exercised by one existing test
  (`HLSEncryption.generateKey()` in `ConverterEngineTests+Manifest.swift`), unlike `MediaEncryption` which
  had none. Deleted `Sources/ConverterEngine/Utilities/MediaEncryption.swift` outright rather than
  rewriting its `Data(contentsOf:)` full-file-read to stream — there is nothing calling it to preserve,
  and `HLSEncryption` is the type any future HLS-encryption work should extend instead of resurrecting a
  second, parallel implementation. `EncryptionError` had no naming collision with `HLSEncryptionError`, so
  no follow-on renames were needed elsewhere.

  **Compile-uncertain for CI (no local macOS build available):** `routeRequest`/`handleProbe` becoming
  `async` and being driven from a plain (non-detached) `Task` inside the `NWConnection.receive` completion
  closure — this assumes `NWConnection` is `Sendable`-compatible for capture in a `@Sendable` `Task`
  closure in this SDK, which the pre-existing code already implied by capturing `connection` in the
  nested `.contentProcessed` completion closure, but wasn't independently verified by compiling;
  `APIServerTests.test_handleStatus_afterStart_reportsRealPositiveUptime` binds a real loopback
  `NWListener` on port 58484 during `swift test --parallel` — the first test in the suite to open an
  actual socket (existing tests only construct/mock, never bind); and the `EncodingProfile`/`AudioCodec`/
  `VideoCodec`/`ContainerFormat` rawValue literals asserted in `APIServerTests` (`"h264"`, `"aac"`,
  `"mp4"`) and profile names (`"Web Standard"`, `"ProRes HQ"`) were checked by reading
  `EncodingProfile.swift`/`AudioCodec.swift`/`VideoCodec.swift`/`ContainerFormat.swift` directly, not by
  compiling.
  - Next queued: #7 (S3 UI surface + multipart >5 GiB), #13 (ScriptingBridge 60s semaphore — needs an
    `NSScriptCommand` refactor), #14 (concurrency audit remainder), #16 (cloud-provider triage — needs
    human input), #12 (accessibility pass).

## Decisions / blockers needing the user

- **#446** VideoUpload real YouTube/Vimeo upload — needs the user to register OAuth apps + supply credentials.
- (others appended as they arise)
