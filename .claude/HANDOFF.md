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
- **[next]** Roadmap item #2 — chunked Dropbox/GDrive uploads. Also still open: Bundle 4 remainder
  (Slate #343, MetadataTag #320, Comparison #329), Bundle 5 (QC #445), Bundle 6 (test coverage),
  Bundle 7 (issue hygiene).

## Decisions / blockers needing the user

- **#446** VideoUpload real YouTube/Vimeo upload — needs the user to register OAuth apps + supply credentials.
- (others appended as they arise)
