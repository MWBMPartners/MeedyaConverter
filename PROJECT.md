# MeedyaConverter — Autopilot Project Brief

> Machine-authoritative state: `.dev-team/autopilot.json`. This file is the
> human-readable narrative. Read both together.

## Mission

Drive MeedyaConverter to a **fully-shipped v0.1.0 GA Direct-distribution
release** (signed, notarised, stapled DMG distributed via GitHub Releases),
then continue on a continuous-improvement loop covering security hardening,
API + OpenAPI/Swagger completeness, and feature-gap closure within scope.

**Distribution priority**: Direct first. App Store Lite path prepared (ITMS
fixes, FFmpegKit backend scaffold) but its actual submission is deferred —
the App Store path requires additional user-side cert work and is feature-
limited by App Store sandboxing constraints.

## Aim (scope yardstick)

An Apple-first (macOS 14+, iPadOS 17+, iOS 17+, visionOS 1+) feature-complete
video/audio converter. Companion to the broader MeedyaSuite product family:
MeedyaSubtitler (subtitle editor — separate app, separate org), MeedyaDL
(downloader), MeedyaManager (library), MeedyaDB (metadata service),
MeedyaSuite-core (shared Rust crates).

**Hard scope boundaries** (per `.claude/CLAUDE.md` and the
`feedback_subtitle_scope_split` memory):
- MeedyaConverter does: conversion, muxing, subtitle muxing/sync (timing-only).
- MeedyaConverter does NOT do: subtitle text editing, formatting controls, OCR,
  style management, quality analysis — those live in MeedyaSubtitler.

## Codebase Map (high-level — seeded from PROJECT_STATUS.md + audit)

| Area | Location | State |
|------|----------|-------|
| Core conversion engine | `Sources/ConverterEngine/` | Feature-complete |
| GUI app | `Sources/MeedyaConverter/` | Feature-complete; 7+ phases of UI shipped |
| CLI tool | `Sources/meedya-convert/` | Feature-complete; argument-parser based |
| Tests | `Tests/` | 967 XCTest passing; safety net intact |
| Build system | `Package.swift` (SPM) + Xcode targets | Swift 6.3 strict concurrency |
| CI/CD | `.github/workflows/` (7 workflows) | release.yml + testflight.yml + dev-build.yml + build.yml + codeql.yml + dependency-review.yml + beta-alpha.yml |
| Signing scripts | `scripts/codesign.sh`, `notarize.sh`, `create-dmg.sh`, `bundle-ffmpeg.sh` | Direct path wired |
| Entitlements | separate Direct + Lite (App Store) entitlements files | Differentiated |
| Suite-core integration | Behind `SUITE_CORE` flag | Optional |
| In-app help | `Resources/Help/` (currently scaffold) | Needs population |
| CLI API docs | `docs/api/` (OpenAPI/Swagger) | Needs audit + update |

## Definition of Done

Concrete, checkable criteria (full list in `autopilot.json#definition_of_done`):
- Builds + runs from clean checkout — signed/notarised/stapled DMG mounts,
  drags to Applications, launches, completes a conversion E2E (VERIFY-established)
- Core conversion task works E2E (GUI + CLI)
- 967/967 tests still passing
- No unresolved Critical/High security finding
- No High correctness/UX backlog item
- Docs sufficient for a Direct-download user (README, in-app help, release notes)
- #428 must-do list closed (release tracking umbrella)
- App Store Lite preparation complete (gated on user-side cert work)
- CLI API + OpenAPI/Swagger comprehensive and current
- CONTRIBUTING.md + CODE_OF_CONDUCT.md in place
- Tag/branch strategy documented and applied; stale alpha/beta branches resolved

## Run Branch

`autopilot/2026-06-30` (from `main` at `1d9aaa2`). Every cycle commits here.
Never pushed without explicit user instruction.

## Trajectory ledger

| Cycle | Phase | Work | Commit | Status |
|-------|-------|------|--------|--------|
| 1 | Bootstrap + STABILIZE adoption | Cherry-picked 6 prior committed ship-blocker branches + committed 2 in-progress ones from killed workflow `wf_7bae08f4-b10`. Builds clean. State files committed at `aaecfed`. | `5dcd791` → `aaecfed` | ✅ |
| 2 | STABILIZE | Package.swift consolidation: `.sdef` resource declaration (AppleScript now bundled — build log confirms `Copying MeedyaConverter.sdef`); Sparkle SPM dep conditional on `DIRECT=1`; FFmpegKit SPM dep conditional on `APP_STORE=1`. Build verifies clean default-config. | `ec28625` | ✅ |
| 3 | STABILIZE | Sparkle Option A — `GitHubReleaseChecker` (new) polls `releases/latest` with 1-hour cache; `AppUpdateChecker` rewrites dispatch into three mechanisms (sparkle / githubReleases / appStore) selected by bundle ID + framework presence; `SettingsView`'s `UpdateSettingsTab` shows three distinct UI variants; `Resources/Help/updates.md` documents the v0.1.0 manual-DMG flow + DMG signature verification + the v0.2.0 Sparkle roadmap. Build clean. | `41f4994` | ✅ |

## Adopted prior work (from killed workflow wf_7bae08f4-b10)

8 of the 13 #428 must-do items now in the run branch:

| # | Concern | Commit | Files |
|---|---------|--------|-------|
| 1 | Bundle FFmpeg + HDR tools in Direct DMG; PlistBuddy version sub | `45ee9f6` | release.yml, dev-build.yml, FFmpegBundleManager.swift |
| 2 | Sign nested Helpers/Resources Mach-O executables before sealing | `0ddd127` | scripts/codesign.sh |
| 3 | Refresh README.md for v0.1.0 public Direct release | `8e9f088` | README.md |
| 4 | Reconcile SECURITY.md Supported Versions for 0.1.0 | `a7c8201` | .github/SECURITY.md |
| 5 | Editorial pass on CHANGELOG.md for rc.4 ship | `07733a4` | CHANGELOG.md |
| 6 | Fix wrong org slug + CLI binary name in help/getting-started.md | `22cb576` | help/getting-started.md |
| 7 | Sync AppInfo.Version from CFBundleShortVersionString at runtime | `a376f11` | AppInfo.swift, ConverterEngine.swift, tests |
| 8 | Fix 3 real bugs (VideoStabilizer / DropHandler / ResourceMonitor) | `5dcd791` | 3 swift files |

## Remaining must-do for v0.1.0 GA (per audit / #428)

| Item | Type | Owner | Status |
|------|------|-------|--------|
| Package.swift consolidation (.sdef resource, Sparkle dep scaffold, FFmpegKit dep) | Code | Autopilot | Next cycle (Cycle 2) |
| Sparkle Option A — GitHub-Releases poll + honest UI copy + Resources/Help/updates.md | Code | Autopilot | Cycle 3 |
| Sparkle Option B — Cloudflare Worker code + SparkleConfig.swift + deploy workflow | Code + Docs | Autopilot (scaffolding only; deployment by user) | Cycle 4 |
| Fail-fast precheck job at top of release.yml asserting Apple secrets present | Code | Autopilot | Cycle 5 |
| CONTRIBUTING.md | Docs | Autopilot | Cycle 6 |
| CODE_OF_CONDUCT.md | Docs | Autopilot | Cycle 6 (parallel) |
| docs/distribution/apple-secrets-setup.md (web-UI flow only) | Docs | Autopilot | Cycle 7 |
| docs/distribution/sparkle-cloudflare-worker.md (deployment guide) | Docs | Autopilot | Cycle 7 |
| docs/distribution/tag-strategy.md (needs gh auth + branch inspection) | Docs | Autopilot once auth refreshed | Cycle 8 |
| End-to-end dry-run of release.yml on a test tag | User-driven | User + Autopilot | Awaiting Apple-secrets verification |
| Apple secrets verification (web UI) | User action | User | Awaiting |

## Phase 2 — App Store Lite preparation (prepare, don't ship)

| Item | Issue | Status |
|------|-------|--------|
| ITMS-90270 unsupported toolchain → xcodebuild archive flow | #386 | Pending cycle |
| ITMS-90237 3rd Party Mac Developer Installer cert | #387 | Pending cycle (user cert needed) |
| ITMS-90230 invalid product-identifier/version | #388 | Pending cycle |
| ITMS-90264 LSMinimumSystemVersion mismatch | #389 | Pending cycle |
| ITMS-90236 missing 512@2x ICNS icon | #390 | Pending cycle |
| ITMS-90889 missing provisioning profile | #391 | Pending cycle (user profile needed) |
| FFmpegKitBackend scaffold (#if APP_STORE sibling to ProcessFFmpegBackend) | n/a | Pending cycle |

## Phase 3-5 — Continuous improvement, security, API completeness

Will engage after Phase 1 (must-do) and Phase 2 (App-Store prep) are settled.
Phase 3 (improvement): runs after `gh auth refresh` per user (needs issue/comment access).
Phase 4 (security): runs SECURITY.md Phase-0 setup as first iteration.
Phase 5 (API + OpenAPI): audit + update CLI completeness, file new tracking issue.

## Phase 6 — Future features (Phase A scaffolding only, OUT OF SCOPE for v0.1.0)

#419 (OFX), #420 (OCIO), #421-#427 (audio + subtitle sync). All in
`gate_ledger` as `awaiting-user` per scope split. Multi-month each.

## Gates currently awaiting user

See `autopilot.json#gate_ledger` for the full list. Highlights for this turn:
- **G-010** Apple secrets verification (web UI, org-admin permissions)
- **G-011** gh CLI auth refresh (`gh auth refresh -h github.com`)
- **G-013** tag strategy decision (deferred until gh auth + branch inspection complete)
- **G-012** Sparkle Options A & B: **APPROVED** — user authorised both this turn

## Standing tasks compliance

Per `.claude/standing_tasks.md` (14 mandatory per-prompt tasks). The autopilot
loop honours these on every commit-worthy cycle:
- task #1 (issue creation/reference) — every commit references issue numbers
- task #2 (acceptance criteria tracking) — per-cycle
- tasks #3 + #4 (lint + security loops) — applied pre-commit
- task #6 (CHANGELOG) — updated per phase
- task #10 (incremental commits) — per cycle
- task #11 (CLI API docs) — addressed in Phase 5
- task #12 (dev cache cleanup) — quick after each PR merge
- task #13 (Claude context updates) — this file + autopilot.json

Compliance was previously sliding (per the audit's standing-tasks recon —
"12 of 12 recently-closed issues have no milestone; 8 of 9 sampled closed
issues have 0/N acceptance-criteria checkboxes ticked"). Backfill is in
the should-do list for Phase 5 / POLISH.
