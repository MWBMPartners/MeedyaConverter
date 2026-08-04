<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Session Handoff / Continuity Doc

**Purpose:** crash-safe resume point. If a session ends unexpectedly, read this
first to pick up exactly where we left off. Updated after each completed task.

**Last updated:** 2026-08-04 · VERSION 0.1.0

## 🎉 SESSION OUTCOME — MERGED & RELEASED (2026-08-04)

**PR #472 (`wip/alpha-consolidation` → `alpha`) is MERGED** as merge commit **`f9943bf`** (merge commit, 280
commits preserved). The `beta-alpha.yml` pre-release workflow (run #4) completed **success**, minting public
pre-release **`v0.1.0-alpha.3`** (https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.1.0-alpha.3).
All PR CI green (Build & Test macOS, CodeQL, Dependency Review, actionlint, pin hygiene).

- **24 fully-complete issues CLOSED** (landed in alpha): #459 #284 #348 #296 #268 #334 #279 #470 #486 #484 #485
  #487 #483 #467 #292 #469 #488 #489 #490 #466 #474 #481 #355 #491.
- **Left OPEN (genuine partials / deferred):** #448, #475, #277 (failure-path hook), #482 (r25 conflicts UI),
  #451, #476 (rip/author), #473 (vector executor), #278 (pipeline exec), #288 (scene-detect exec), #477 (orphan
  remainder: ColorSpaceConverter US / EncodingBackend / FeatureGate + surgical cuts + 3D/disc/DCP/app-service),
  #468 (honest-minimal shipped; true seek-resume future), #471 (client shipped; dormant until server provisioned).
- **⚠️ IMPORTANT for the next session:** PR #472 is MERGED and FINISHED. `wip/alpha-consolidation`'s PR must NOT
  be reused. Any follow-up = a FRESH change: restart from `alpha` (`git fetch origin alpha && git checkout -B
  <new-branch> origin/alpha`), do the work, open a NEW PR.

---


> **Location note:** this doc lives at `.claude/HANDOFF.md` (moved from repo root 2026-07-22).

## 🟡 Current session — 2026-08-04 (project-state reconciliation + new-work proposals + docs)

**User directive (this session):** full sweep of ALL GitHub Issues (open + closed) reconciled
against the ACTUAL codebase (no assumptions); refresh all `.claude/` memory/context + this handoff;
propose ranked new-work for the alpha cycle; thorough docs update (`.md` + in-app help + OpenAPI +
Swagger UI); codify the workflow directive as repo-wide standing tasks. NO PR stacking — all commits
to `wip/alpha-consolidation`.

**State at session start:**
- Branch `wip/alpha-consolidation` @ `2f58fc3` (PR #480 metadata-passthrough merged in). Tree clean.
- **PR #472** (draft, `wip/alpha-consolidation` → `alpha`) — ALL 6 checks GREEN: Build & Test (macOS),
  CodeQL, Analyze Swift, Review Dependencies, actionlint, GitHub Actions pin hygiene. 244 commits,
  mergeable_state `clean`. Still DRAFT (do not merge — work ongoing).
- **98 open issues** (was 42 at 2026-07-18; grew because the completeness audit reopened ~28
  closed-in-error issues + filed #473–#477).

**Progress this session (update as you go):**
- [x] Codified the workflow directive as repo-wide standing tasks → `.claude/standing_tasks.md`
      new "Workflow & Processing Standing Tasks" section (W1–W9). (commit `4a28e32`)
- [x] Fable-5 sequential deep-analysis agent: reconciled open issues vs current code + produced
      ranked new-work proposals. Register captured below.
- [x] Applied per-issue GitHub updates (17 comments) from the register — evidence-cited, honest that
      DONE items stay open until #472 merges.
- [x] Refreshed `.claude/project_brief.md` (branch, 98 issues, honesty status).
- [x] Thorough docs sweep — README/PROJECT_STATUS/CHANGELOG/FEATURES reconciled to the honest map
      (commit `f0bee18`). Docs agent grep-found NEW reachable-but-inert defects: **SceneDetectorView
      never launches Process (#288)**, **PipelineEditorView has no onSave / PipelineExecutor 0 callers
      (#278)** — commented on both. Also confirmed dead: thumbnail sprites, HLS AES-128/DRM, AccurateRip,
      multi-stream selector, encoding reports, ColourSpaceConverter. **OpenAPI reconciliation still owed**
      (do at end after code settles).
- [x] Presented ranked new-work proposals → **user chose "Whole ranked set #1–12", in ranked order,
      autonomously, per-task commits + per-issue updates. PAUSE on #12 (resumable-jobs delete-vs-minimal).**
- [x] **Quick wins #1–4 DONE + pushed** (all diffs reviewed for compile+runtime correctness):
      `ef2d8ca` #466 CLI codec/container honesty (copy→passthrough, reject unknown) ·
      `4e99dcf` #448 QueueOptimizer.reorder applied to live queue ·
      `685ff8e` #474 SmartCrop Apply-to-Job → pendingManualCropFilter merged at enqueue ·
      `a770ea3` #481 Help menu → openWindow(id:"help"). Issues #466/#448/#474/#481 updated.
- [x] **M-tier batch 1 DONE + pushed** (`b75aba4`, all 4 files reviewed compile-correct):
      **#475** wired `autoScrollLog`, `defaultProfileName`, `customFFmpeg/ffprobePath`, `confirmBeforeEncoding`
      (Queue tab Start only); left unwired w/ reasons: `useHardwareAcceleration` (per-profile), `showMenuBarStatus`
      (MenuBarController never instantiated → deeper orphan #477), `accurateRip.*` (orphaned engine #477).
      **#470** ETAPredictor wired (predictETA supersede + recordEncode + lastKnownInputDuration; cold-start→linear).
      Issues #475/#470 updated.
- [~] **CI:** HEAD `b75aba4` pushed; Build & Test (macOS) in progress (actionlint/deps/pin green).
      Earlier batch (`a770ea3` quick wins) already confirmed Build & Test GREEN.
- [~] **Fabrication-audit Workflow `wom8m9da9` RUNNING** (read-only, 9 Sonnet finders + Fable synth) — exhaustive
      code-first seam sweep for NEW fabricated-capability defects beyond those already catalogued. Apply its
      register (issue updates + new fixes/issues) when it lands. **Hold impl until it finishes** (keeps its reads clean).
- [x] **Exhaustive fabrication-audit Workflow `wom8m9da9` COMPLETE** (10 agents, 2.2M tokens) — **59 deduped
      seams** with grep evidence, mapped to issues. Full register archived in the workflow journal; key NEW
      HIGH-impact findings below. **GitHub bookkeeping DONE:** filed **#482** (team-push fake success), **#483** (heatmap blank
      PNG), **#484** (batch exits 0 on fail), **#485** (per-stream subtitle ignored), **#486** (PQ/HDR10 signalling),
      **#487** (import drops subtitleTonemap), **#488** (bg-removal save panel), **#489** (CLI profiles blind to
      imports), **#490** (ManifestCommand inert opts), **#491** (share links unconsumable) + 25 comments on existing.
      **In-flight:** M2 engine-fix agent → row8=#486, row9=#487, row3=#484, row7=#485.

### Audit register — HIGH-impact NEW seams (2026-08-04, verified vs code)
- **row 8 — PQ/HDR10 colour signalling never applied** (`FFmpegArgumentBuilder.buildPQPreservationArguments`
  unwired; `.hlg` sibling IS wired at EncodingJob.swift:198-201). REAL HDR bug. → M2 fixing.
- **row 9 — profile import drops `subtitleTonemap`** (EncodingProfile.swift:981-1026 + ProfileSharing.swift:91-132).
  Silent data loss. → M2 fixing.
- **row 3 — `batch --job-file` exits 0 on failure** (BatchCommand.swift:168-205; sibling runDirectoryBatch throws).
  → M2 fixing.
- **row 7 — per-stream subtitle overrides ignored** by `toArgumentBuilder`. → M2 fixing.
- row 1 — TeamProfile `.httpServer` push reports success, sends nothing; row 2 — BitrateHeatmap "Export Image"
  writes a blank PNG; row 4 — NormalizationSettings "Measure Levels" no-op (#292); row 5 — PostEncodeActionChain
  never invoked (#277); row 6 — outputMode/OutputPathResolver mirror-folder no-op (#275); rows 10/11/12-14/18 —
  bg-removal save panel, CLI ProfilesCommand blind to imports, ManifestCommand inert options, unconsumable share links.
- MED mapped to existing: #353,#286,#331,#340,#329,#377,#473,#281,#468,#333,#346,#241.
- **row 24 — checkpoint/resume unwired** (follow-up to #468).

### DECISIONS TO SURFACE (present, don't block — continue other work)
1. **Orphan-sweep (rows 28-59): ~6,000 lines of zero-caller engine code** — delete-or-wire. Several files carry
   FALSE "live call site" comments (PQToHLGPipeline, RasterVectorConverter, FFmpegBackend/Factory). Recommendation:
   DELETE the pure-dead duplicates/false-comment ones (SmartCropIntegration dup, ColorSpaceConverter US-spelled dup,
   EncodingBackend scaffold, PQToHLGPipeline), correct false prose; LEAVE the issue-tracked feature stubs
   (#324/#352/#350/#338/#257/#323/#285/#241/#346/#446). Needs user OK on deletions.
2. **#468 resumable jobs** — delete-vs-honest-minimal (already flagged).

- [x] **M2 engine-correctness batch DONE + pushed** (`75f2de0` #486, `aa0d66e` #484, `9b92932` #485+#487):
      #486 PQ/HDR10 signalling **+ latent HLG-clobber bug** (extraArguments overwrite reorder — HLG preservation
      was silently broken too); #484 batch --job-file non-zero exit on failure; #485 per-stream subtitle overrides
      (new FFmpegArgumentBuilder hook); #487 subtitleTonemap preserved on profile import (+new test). Issues updated.
      All symbols verified vs real code (CaseIterable, ExitCodes.encodingFailed, SubtitleStreamOverride, .dolbyVision).
- [x] **Agent A DONE (`3ee5072`):** #277 post-encode hooks (persist chain + invoke on completion + watchFolder
      postAction via side table; failure-path runOnFailure left out, noted), #275 outputMode (OutputPathResolver
      .resolveOutputDirectory extracted + used in enqueue). Verified vs real APIs. Issues updated.
- [x] **Agent B DONE (`8da5c9f`/`bb9e818`):** #482 team-push real PUT (stop faking success; conflictedProfiles
      r25 still open), #483 BitrateHeatmap real ImageRenderer export. Verified. Issues updated.
- [~] **CI:** HEAD `3ee5072` (B+A) Build & Test in progress. Prior batches all green.
- [x] **Agent C DONE (`3fe0538`/`54e530d`):** #489 CLI profiles/validate resolve against store; #490 ManifestCommand
      rejects --hdr / unknown codecs / custom-without-ladder. Verified. Issues updated.
- [x] **Agent D DONE (`0f1dc0f`/`8183a83`):** #467 MetadataTagEditorView real Write-Tags execution; #292
      NormalizationSettings measureLevels real ffmpeg. Verified. Issues updated.
- [x] **Agent E DONE (`27b42dd`/`4f9c012`):** #469 conditional rules apply-at-enqueue + surfaced view, #488
      bg-removal chosen output dir. Verified. Issues updated. Batch CI (`4f9c012`) Build & Test + CodeQL GREEN.
- [x] **Docs finalization DONE (`b81b546`):** CHANGELOG + README + PROJECT_STATUS + OpenAPI CLI spec +
      cli-reference.md reconciled to the fix wave (grounded in the 20 fix commits; YAML validated). Fixed a stale
      "conditional rules not wired" note.
- [x] **✅ AUTONOMOUS QUEUE COMPLETE (2026-08-04).** 21 issues fixed + full state reconciliation + honesty docs +
      exhaustive 59-seam audit + standing tasks W1–W9, all on `wip/alpha-consolidation`. PR #472 still DRAFT
      (do NOT merge). Fix commits: ef2d8ca #466 · 4e99dcf #448 · 685ff8e #474 · a770ea3 #481 · b75aba4 #475/#470 ·
      75f2de0 #486 · aa0d66e #484 · 9b92932 #485/#487 · 8da5c9f #482 · bb9e818 #483 · 3ee5072 #277/#275 ·
      3fe0538 #489 · 54e530d #490 · 0f1dc0f #467 · 8183a83 #292 · 27b42dd #469 · 4f9c012 #488 · b81b546 docs.
      Remaining = the 4 user DECISIONS below + lower-priority OPEN issues tracked in GitHub with evidence:
      #288, #278, #446, #482(r25 conflicts UI), #329, #333, #340, #353, #286, #331, #281, #241, #324, #352,
      #350, #338, #257, #323, #285.

### DECISIONS — USER DECIDED 2026-08-04, ALL 4 IMPLEMENTED ✅ — AUTONOMOUS QUEUE COMPLETE
> #355 serve (`1773763`), #491 URL-import+scheme (`3147c8d`), #468 honest-minimal resumable (`444bde1`),
> orphan-sweep batches 1+2 (`af83104`+`7f59196`, Build & Test GREEN). Only remainder = the documented
> kept-for-safety orphan follow-up + long-horizon backlog issues. Nothing else queued.
1. **Orphan-sweep** → IN PROGRESS. Fable delete-list DONE (verified; both ColorSpace spellings + their chains
   are production-dead). Orchestrator independently grep-confirmed. Execution in CI-gated batches:
   - **Batch 1 DONE+pushed (`af83104`):** deleted AudioMixer.swift, ClosedCaptionHandler.swift, SubtitleOCR.swift
     (0 refs in Sources AND Tests — no test trims needed).
   - **Batch 2 DONE+pushed (`7f59196`) — Build & Test macOS GREEN:** deleted 14 clearly-dead whole files
     (SubtitleConverter, Extended*×4, EncodingReport, MediaInfoIntegration, MetadataPassthrough, MetadataTagger,
     MultiStreamSelector, SmartCropIntegration, HDRPolicyEngine, ColourSpaceConverter, PQToHLGPipeline) + trimmed
     9 mixed-scope test files + fixed 3 false "live" comments. Independently verified: deleted-type grep=0 in
     Sources+Tests, no deleted file extended a live type / defined a called free func, test files brace-balanced.
     **Total sweep: 17 files / ~4,500 lines. #477 commented, left OPEN for the kept-for-safety remainder + the
     3D/disc/DCP/app-service clusters (not in this pass).**
   - **EXCLUDED for safety (kept + documented for a future pass):** `ColorSpaceConverter.swift` (US — its
     ToneMapAlgorithm name-collides with the live nested `FFmpegArgumentBuilder.ToneMapAlgorithm`),
     `Backend/EncodingBackend.swift` (EncodingJob name-collision risk), `Models/FeatureGate.swift` + the
     `EncodingEngine.featureGate` removal (Feature/ProductTier collision + engine edits), and the surgical
     in-live-file cuts (generateDolbyVisionRPU, AudioProcessor ReplayGain branch, MediaServerConfigStore,
     MiniPlayerView, StorageAnalyzer.estimateSavings). All are harmless dead code; removing them is deferred
     to avoid a blind build break. **KEEP per issue-tracking:** ExtendedCloudProviders (#163-173/#459),
     RasterVectorConverter (#473, comment fixed), AudioProcessor two-pass measurement branch (#292).
2. **#468 resumable** → **HONEST-MINIMAL** (checkpoint on cancel/fail, surface view, relabel Resume→Re-queue).
   Sonnet RUNNING (`a4863e…`). Files: AppViewModel/ResumableJobsView/ContentView/SidebarView.
3. **#355 API serve** → **ADD** `meedya-convert serve` subcommand. Sonnet RUNNING (`a44800…`). New ServeCommand.swift + MeedyaConvert.swift.
4. **#491 share links** → **WIRE** `meedyaconverter://profile/` onOpenURL import route. Sonnet RUNNING (`a14770…`). MeedyaConverterApp/URLSchemeHandler.
   (Each: orchestrator reviews diff → commit → push → CI-gate → update issue. Then final docs/CHANGELOG top-up + wrap-up.)

### Reconciliation register (verified vs code @ `2f58fc3`, 2026-08-04)

**DONE-ON-BRANCH (implemented + wired; closes on PR #472 merge):**
#459 cloud-upload execution (`CloudUploadExecutor`, real URLSession legs + scp; caller
`CloudStorageView`/`PostEncodeActions`) · #284 unified stats (`EncodingStatisticsStore` sole source,
collector in queue loop, persists on success+fail) · #348 email (`sendCompletionEmail`→curl) · #296
webhook (`WebhookSender` POST) · #268 watch-folder enqueue+encode · #334 recent files · #279
scheduled encoding (`onJobReady`→`startQueue`) · #471 IntAppsAPI (dormant/fail-safe) · overwrite +
delete-source toggles (part of #475).

**PARTIAL:** #448 (many views wired; still orphaned: MetadataEditorView, ResumableJobsView,
APIServerView, ConditionalRulesView, SlateGeneratorView, ComparisonView; still inert-but-reachable:
QueueOptimizer.applyOptimisation fabricates success, MetadataTagEditor display-only, Concatenation no
execute, MultiOutput display-only, Watermark config unused) · #475 (2 fixed, ~7 keys still write-only)
· #476 (burn real+reachable; rip/author no entry) · #355 (server real+tested, no nav/CLI entry) ·
#277 (chain engine real; not persisted, not invoked on completion, postAction ignored) · #451 (30
`Task.detached` + 6 `nonisolated(unsafe)` sites, mostly documented-safe).

**STILL-OPEN:** #467 (MetadataTagEditor never executes; MetadataEditorView orphaned) · #468 (no
checkpoint writer; view orphaned; "resume" restarts at 0) · #469 (rules never read at encode) · #470
(ETAPredictor 0 callers; naive inline ETA at AppViewModel:952) · #473 (no executor / no source flow) ·
#474 (`applyCropToJob()` empty) · #466 (CLI advertises `copy`/codecs that silently fall back) · #477
(dead clusters: 3D/Spatial, disc readers, DCP/ForensicWatermark/VVC/TrueHD/HLGToDolbyVision, AI/audio,
ColourSpaceConverter dup, + app-service orphans HandoffManager/URLSchemeHandler/etc.).

### Ranked new-work proposals (Fable, for user decision — NOT yet started)

1. CLI reject unknown codec/container + support `copy` (#466) — **S**
2. QueueOptimizer actually apply reorder (#448) — **S**
3. SmartCrop "Apply to Job" (#474) — **S**
4. Fix broken Help menu (Cmd+? no-op; `openHelpWindow` opens a URL scheme with no handler) — **S**
5. Honor/remove remaining dead Settings keys (#475) — **M** (each S)
6. Execute metadata tag writes (#467) — **M**
7. Persist + fire post-encode hooks, honor watch-folder postAction (#277) — **M**
8. Entry point for the real API server (#355/#448) — **S–M**
9. Wire ETAPredictor into queue ETA (#470) — **S–M**
10. Apply conditional rules at enqueue (#469) — **M**
11. Resumable-jobs honesty decision: delete vs honest-minimal (#468) — **M**
12. Orphaned app-service sweep: wire-or-delete (#477) — **M**

**Note:** local clones of the 3 consolidated branches still exist on disk (harmless); their REMOTE
counterparts are already deleted (origin has only alpha/beta/main/wip-alpha-consolidation).

---

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
- **[done 2026-07-28]** Roadmap items #7, #14, on `wip/alpha-consolidation`.

  **#7 — S3 real user surface + multipart (re #459, re #162).** Before this, `AWSV4Signer` +
  `S3Uploader.buildSignedUploadRequest` + `CloudUploadExecutor.uploadToS3` were unit-tested but had
  ZERO production callers — `CloudStorageProvider` had no `.s3` case, so a user could never actually
  pick S3 in the UI. Now user-reachable end to end:
  - `CloudStorageProvider` gained a `.s3` case, handled in every exhaustive switch it touches
    (`CloudStorageUploader.authURL` — now returns `URL?`, `nil` for `.s3`, rather than
    force-unwrapping; `CloudStorageProfileStore.apiKeyProvider(for:)` → `.awsS3`;
    `CloudUploadExecutor.uploadToCloudStorage`; `CloudStorageView`'s `providerIcon`/
    `providerDisplayName`). New `CloudStorageProvider.usesOAuth` flag (`false` only for `.s3`) gates
    which credential form `CloudStorageView.authSection` shows.
  - **Config/credential path** — `CloudStorageConfig` gained `secretAccessKey`/`bucket`/`region`/
    `endpoint` (all optional, `Codable`-backward-compatible with every pre-existing saved
    Dropbox/OneDrive/Google-Drive profile on disk — confirmed by a legacy-JSON decode test).
    `accessToken` does double duty as the AWS Access Key ID for `.s3` (documented on the field) so the
    existing "secret lives in `@State`, redacted before `UserDefaults`, restored from the Keychain"
    machinery needed no new chokepoint. Secrets go through the SAME `APIKeyManager` (provider
    `.awsS3`) every other provider already uses — access key ID → `StoredAPIKey.apiKey`, secret
    access key → `StoredAPIKey.secretKey` (the exact pair `S3Uploader.loadCredential` already read) —
    never `UserDefaults`, never `PostEncodeAction.config` (only the `cloudProfileID` reference, exactly
    like every other provider). `CloudStorageView` gets an S3-specific "AWS Credentials" section
    (Access Key ID / Secret Access Key (`SecureField`) / Bucket / Region / optional custom Endpoint)
    in place of the OAuth form.
  - **Multipart status: fully implemented, not stubbed**, gated behind `S3Uploader
    .shouldUseMultipart(fileSize:)`'s existing 100 MB threshold (which also covers the mandatory
    >5 GiB case, since 5 GiB > 100 MB). New `CloudUploadExecutor.uploadS3Multipart` drives a real
    `CreateMultipartUpload` → per-part signed `UploadPart` PUTs (each independently signed via
    `AWSV4Signer`, mirroring `uploadInDropboxSessionChunks`/`uploadInGoogleDriveResumableChunks`) →
    `CompleteMultipartUpload` with a real XML body (`PartNumber`+`ETag` per part, built by new
    `S3Uploader.buildCompleteMultipartXML`) → `AbortMultipartUpload` as best-effort cleanup on ANY
    failure once a real `UploadId` exists — the abort's own outcome never masks the original error
    (verified by a dedicated test). New `S3XMLElementExtractor` (a minimal `XMLParser`-based helper,
    not regex/substring matching) parses `UploadId`/`Location`/`ETag` out of S3's XML responses.
  - **Tests** (`Tests/ConverterEngineTests/S3MultipartUploadTests.swift`, new file, ~20 tests, plus 6
    more appended to `ConverterEngineTests+CloudAndMetadataLookup.swift`): small-file → single signed
    PUT (exactly one request); missing-credential-fields → throws before sending anything; large file
    (sparse-file trick) → routes to `CreateMultipartUpload` (fails fast on a mocked 403, no parts
    attempted); full multipart sequence with correct sequential `partNumber`s + shared `uploadId` and
    a byte-exact `CompleteMultipartUpload` XML body built from the real per-part `ETag` response
    headers; mid-part failure → `AbortMultipartUpload` called with the right `uploadId`, original
    `.httpError` never masked; `CreateMultipartUpload` failure → no abort attempted (no real
    `UploadId` to abort); every new request builder's method/URL/query/headers and
    nil-on-incomplete-credential behaviour; `CloudStorageProvider`/`CloudStorageProfileStore`/
    `CloudStorageConfig` unit tests (`usesOAuth`, `authURL` nil, `apiKeyProvider` mapping, `Codable`
    round trip, legacy-JSON backward compatibility).
  - Compile-uncertain for CI (no local macOS build available): the `XMLParserDelegate` method
    signatures on `S3XMLElementExtractor.ElementTextCollector` (verified by inspection against
    Foundation's documented overlay signatures, not by compiling); the `AWSV4Signer
    .canonicalQueryString(queryItems:)` reuse for both the literal request `URL` and the SigV4
    signature in the four new multipart request builders (same pattern `buildSignedUploadRequest`
    already uses for `canonicalURI(path:)`, but not independently compiled here); and
    `CloudStorageView`'s new `authSection`/credentials-form `@ViewBuilder` branching compiling as a
    single `some View` return type across the `if selectedProvider.usesOAuth { ... } else { ... }`
    split.

  **#14 — Swift 6 concurrency audit remainder (re #451).** Re-checked every `Task.detached`/
  `nonisolated(unsafe)` site in `BurnSettingsView`, `QualityMetricsView`, `TeamProfileView`,
  `CloudSyncView`, and `PostEncodeActions` against the genuine bug class (a `@MainActor` class `self`
  captured into `Task.detached` and mutated back via `MainActor.run`). Per-file finding — **all five
  were already correct-as-is; zero behaviour/scheduling changes made**, only doc comments recording
  the re-audit (so a future pass doesn't have to redo this analysis):

  | File | Sites checked | Verdict | Why |
  |---|---|---|---|
  | `BurnSettingsView` | `detectDrives()`, `startBurn()`, `eraseDisc()`, `ejectDisc()` | correct-as-is | First 3 already fixed by the #451 pass (`9deee21`): plain `Task {}` inherits the `View`'s main-actor isolation, inner `Task.detached` is `Sendable`-only capture/return, never `self`. `ejectDisc()` is a bare `Task.detached` capturing no `self`/state at all. |
  | `QualityMetricsView` (`QualityMetricsViewModel`, `@MainActor` class) | `runAnalysis()`'s 2 `Task.detached` blocks; `nonisolated(unsafe) analysisTask`/`currentController` | correct-as-is | `runAnalysis()` uses plain `Task { [weak self] }` (already fixed for #434, `2d8cde3`); only `locateFFmpeg()`/`probeLibvmafAvailable` are detached, `Sendable`-only. The `nonisolated(unsafe)` vars are the documented deinit-cancellation exception (mirrors `StoreManager.transactionListenerTask`), not the bug class. |
  | `TeamProfileView` | `pushProfiles()`, `pullProfiles()` | correct-as-is | Already fixed by #451 (`5f9f2d6`) — identical shape to `BurnSettingsView`. |
  | `CloudSyncView` | `performUpload()`, `performDownload()` | correct-as-is | `async` methods invoked via plain `Task { await ... }` from the view (main-actor isolated); only `CloudProfileSync`'s blocking I/O is detached, `Sendable`-only capture. |
  | `PostEncodeActions` (`PostEncodeActionChain`, a plain `Sendable` struct — not a `@MainActor` class) | `uploadViaSFTP`'s and `sendMacOSNotification`'s `Task.detached` | correct-as-is | No main-actor state to race on in the first place; `uploadViaSFTP`'s detached block is `Sendable`-only capture/return, `sendMacOSNotification`'s is bare fire-and-forget with no capture at all. |

  Out of scope per the task brief: the `ScriptingBridge` 60s semaphore (needs an `NSScriptCommand`
  refactor — tracked separately as roadmap #13).

  - Next queued: #13 (`ScriptingBridge` `NSScriptCommand` refactor), #16 (cloud-provider triage — needs
    human input), #12 (accessibility pass), then the closing phase (issue sweep, docs/OpenAPI refresh,
    new proposals).
- **[done 2026-07-28]** Completeness-audit cluster — "configured but never executed" (persisted setting,
  zero readers), on `wip/alpha-consolidation`, `899abd7` → `bc7fa4f`. Seven fixes, one commit each, all
  landing in `AppViewModel.startQueue()`/`enqueueSelectedFile()`/`init()` unless noted:
  1. **#279 — scheduled jobs never started.** `scheduler.onJobReady` called `addJob` and logged
     "Scheduled job started" but nothing called `startQueue()`. Now starts the queue if not already
     running; log message reflects which branch actually happened ("started" vs "added to running
     queue").
  2. **#268 — watch folders discarded every detection.** `WatchFolderView`'s `monitor.start(config:) { _
     in /* handled by app coordinator */ }` dropped every file; no coordinator existed. New
     `AppViewModel.enqueueWatchFolderFile(_:config:)` resolves the profile by name (falling back to Web
     Standard with a logged warning — `WatchFolderConfig`'s own default `profileName`, `"webStandard"`,
     doesn't match any built-in profile's display name, so this is the *common* case for a fresh watch
     folder, not an edge case), builds the output path via the existing `FileStabilityChecker.outputPath`
     helper (not `FilenameTemplate` — avoids an extra async probe per detected file; does not honour the
     Source tab's `filenameTemplate`/`overwriteExisting` settings for the same reason), adds the job, and
     starts the queue if needed. The view's callback hops onto the main actor
     (`Task { @MainActor in viewModel.enqueueWatchFolderFile(...) } }`) since `WatchFolderMonitor` fires
     `onNewFile` from its own background `monitorQueue` — same shape `DropHandler.extractURLs`'s
     completion handlers already use elsewhere (`ContentView`'s drop handling). **Still open, found but
     NOT fixed this session**: `WatchFolderConfig.postAction` (`.moveToCompleted`/`.deleteSource`) is
     itself another "configured but never executed" toggle — nothing consumes it after a watch-folder
     encode completes. Not in this session's assigned list; flagging for the backlog.
  3. **#296 — webhooks never fired on real events.** `WebhookSettingsView` persisted `webhookURL` +
     three trigger toggles + presets/custom headers; the only production `WebhookSender.send` call was
     the Test button. Extracted `WebhookSettingsView.loadWebhookConfig()` (static, mirrors
     `EmailSettingsView.loadSMTPConfig()`; the view's own `buildConfig()` now delegates to it — also
     tightens an edge case: the static version explicitly rejects an empty URL string before calling
     `URL(string:)`, which the original `buildConfig()` didn't). New
     `AppViewModel.sendWebhookNotification(...)` wired into the same three points
     `sendCompletionEmail` already covers (per-job success, per-job failure, end-of-queue); queue-finished
     has no single "job" so the summary counts stand in for the job fields and `status` reflects whether
     any job failed. Delivery runs in a plain (non-detached) `Task` — `WebhookSender.send` is already
     non-blocking `async`/`URLSession`, so a slow retry (`WebhookConfig.retryDelaySeconds`) never stalls
     the queue loop; failures are logged, never thrown.
  4. **#348 — queue-finished email never sent.** `EmailSettingsView.emailOnQueueFinished` had no reader
     (its siblings `emailOnComplete`/`emailOnFailure` were already wired). Added the third
     `sendCompletionEmail` call at end-of-queue, same summary-stand-in shape as the webhook leg above.
  5. **#295 / #203 — media-server auto-scan never triggered.** `MediaServerSettingsView.mediaServerAutoScan`
     had no reader. Extracted `MediaServerSettingsView.loadMediaServerConfig()` (static, same
     `loadSMTPConfig()` mirror; `currentConfig` now delegates to it). New
     `AppViewModel.triggerMediaServerAutoScan()` fires the same `MediaServerIntegration.triggerLibraryScan`
     the manual "Trigger Library Scan Now" button uses. Fires from the **per-job success path**, not
     queue-end — the toggle's own label is "Auto-scan after successful encode," and that wording was
     taken literally rather than choosing queue-end for convenience.
  6. **#334 — Recent Files could never populate.** `RecentFilesManager.addRecent(_:)` had exactly one
     caller — `RecentFilesView`'s own re-import action — a circularity that meant the list could never
     grow from a normal import. Added an `AppViewModel`-owned `RecentFilesManager` instance, called from
     `importFiles(_:)` for each successfully probed file. `RecentFilesView` keeps its own separate
     manager instance (unchanged), but both read/write the same on-disk JSON store and the view is torn
     down/recreated (reloading from disk) every time the user navigates to Recent Files, so no shared
     live instance is needed.
  7. **NEW-issue items (no GitHub issue filed yet) — `SettingsView.overwriteExisting` /
     `.deleteSourceAfterEncode`, both persisted, both read by nothing.**
     - `overwriteExisting`: added `FilenameTemplate.resolveOutputURL(..., overwriteExisting:)`, a small
       pure helper (genuinely unit-testable — see below) that delegates to the existing
       `resolveWithCollisionHandling` when `false` (today's auto-rename-on-collision behaviour,
       unchanged) and returns the plain resolved path when `true` (FFmpeg, invoked with `-y` for every
       job already, then overwrites it in place). Wired into `enqueueSelectedFile()`.
     - `deleteSourceAfterEncode`: judged safe to implement (not disabled) with conservative guards — new
       `AppViewModel.deleteSourceFileIfSafe(job:)`, called ONLY from the `.completed` success path in
       `startQueue()` (never reachable from the failure/cancel `catch` branch), additionally requiring
       the output file to exist and be non-empty and to have a different path from the input before
       deleting anything; every outcome (deleted / skipped-why / failed-why) is logged; deletion failures
       are caught, never thrown.
  - **Tests**: `Tests/ConverterEngineTests/FilenameTemplateResolveOutputURLTests.swift` (new, 4 tests) —
    the one piece of pure, public `ConverterEngine` logic this cluster introduced
    (`FilenameTemplate.resolveOutputURL`). Everything else is `AppViewModel`/View wiring in the
    `MeedyaConverter` executable target, which — like `meedya-convert` — cannot be `@testable import`ed
    (Swift forbids importing a module containing `@main` into a test target), so that half was verified
    by inspection only, same constraint every previous audit-cluster entry in this log has hit.
  - **Compile-uncertain for CI (no local macOS build available):** the `@Sendable` closure passed to
    `WatchFolderMonitor.start(config:onNewFile:)` capturing `viewModel` (a `@MainActor`, non-`Sendable`
    class) directly, used only inside a nested `Task { @MainActor in }` — verified by inspection against
    the identical, already-shipped shape `ContentView.swift`'s `DropHandler.extractURLs` completion
    closures use (also `@Sendable ([URL]) -> Void`, also capturing `viewModel` directly), not by
    compiling.
  - **Remaining audit backlog (large items, not touched this session)** — same categories the completeness
    audit that produced this task's brief flagged: #286 parallel encoding, #205 metadata lookup, disc
    ripping tracker, #353 plugins, #278 pipelines (note: `PostEncodeActionsView`/`PostEncodeActionChain`,
    issue #277, is a *separate* "configured but never executed"-shaped post-encode-hooks feature from
    this session's #296 webhook fix — its own `.webhook` action type is explicitly unsupported per
    `PostEncodeActionsTests.swift`; not touched here), #320/#322/#335/#298/#288 build-only views, #302
    AppleScript plist, #331 shortcuts, #281 menu bar, #359/#360 widget, #275 output modes
    (`AppViewModel.outputMode`/`OutputPathResolver` — also unused by `enqueueSelectedFile()`, which still
    resolves output paths via `FilenameTemplate` only; not touched by the `overwriteExisting` fix above),
    #345 team HTTP sync. Also newly noted: `WatchFolderConfig.postAction` (see #268 above).

## Decisions / blockers needing the user

- **#446** VideoUpload real YouTube/Vimeo upload — needs the user to register OAuth apps + supply credentials.
- (others appended as they arise)
