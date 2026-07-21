# MeedyaConverter — Project Brief

> Saved for Claude AI context continuity across sessions.
> Last updated: 2026-07-18

## Project Summary

MeedyaConverter is a cross-platform professional media conversion application by MWBM Partners Ltd. A modern HandBrake alternative with 100+ features including passthrough, adaptive streaming (HLS/MPEG-DASH), HDR preservation/tone-mapping, spatial audio, optical disc ripping/authoring, cloud upload, image conversion, video editing tools, and monetization infrastructure.

## Current Status (2026-07-18)

**v0.1.0 GA scope is COMPLETE**; the app is feature-complete and in release engineering. Next milestone: cut **`v0.1.0-rc.4`** (short soak) → **`v0.1.0` GA**, Direct distribution only (signed + notarised + stapled `.app` in a `.dmg`, plus a signed/notarised CLI tarball, via GitHub Releases). App Store Lite deferred (#392).

- **Autopilot mission TERMINAL** at commit `b58d676` — a security + release-engineering mission ran DISCOVER → STABILIZE → SECURE → COMPLETE → POLISH → VERIFY (26 cycles).
- **Tests**: **1128** unit tests passing (1039 at the TERMINAL checkpoint; grew with continuous feature/test work), 0 compiler warnings.
- **Security**: findings **F-001..F-012** all closed / mitigated / risk-accepted. **F-011** (FFmpeg supply chain) finalised — universal arm64+x86_64, sourced solely from first-party mirror `MeedyaSuite/MeedyaDL-Tools` (pinned `MDLT_TAG`), SHA256SUMS-verified fail-closed. **F-012** (probe-watchdog PID-reuse) mitigated.
- **Release engineering**: `release.yml` builds the app universal AND generates + attaches SHA-256 checksums. Direct-release runbook at `docs/distribution/direct-release.md`.
- **Issues**: **42 open**. #429 (standing-tasks audit) and #371 (Suite-core metadata) closed this session.
- **Branch**: all work lives on **`autopilot/2026-06-30-clean`** — NOT merged to `main`; **no PRs** per current workflow (avoids merge-race stacking).

### Key work — Session 2026-07-18 (this handoff)

- **F-011 finalised & pushed** — universal, first-party, SHA256SUMS-verified FFmpeg supply chain; removed the `scripts/ffmpeg-checksums.txt` local-pin bridge. (Also: reverted 408 accidental `chmod +x` flips before committing; gitignored `.claude/settings.local.json`.)
- **#429 standing-tasks audit fully remediated & CLOSED** — 12 milestones back-filled; AC checkboxes synced on 8 closed issues with evidence comments; docs refreshed (PROJECT_STATUS / Project_Plan / DEV_NOTES / cli-reference + new `help/vector-conversion.md`); **in-app Help wired** to bundled markdown (single source of truth under `Sources/MeedyaConverter/Resources/Help/`, unit-tested `HelpTopicParser`); **latent defect fixed** — `release.yml`/`dev-build.yml` now copy the SwiftPM resource bundle (Help + `.sdef` + Assets) into the `.app`; `.gitignore` `*.icns`; PR merge-gate checklist; standing-task #1a policy clarified; CI housekeeping-reminder workflow; dev-cache cleaned (2 GiB).
- **#428 release-readiness advanced** — Fable-5 signing audit confirmed `release`/`dev-build`/`beta-alpha` consistency; added SHA-256 checksums to `release.yml`; wrote the Direct-release runbook; fixed README/secrets-doc drift; tracked a latent `testflight.yml` cert-family bug on **#392**.
- **11 commits** pushed to `autopilot/2026-06-30-clean`.

### Key work — Session 2026-07-18 (cont.) — feature-functionality batch

Fable-5-planned batch of autonomous-eligible work (safe, bounded, release-branch-safe). 7 items, one commit each, all pushed; suite 1068 → **1128** (+60 tests):

- **#431** ResourceMonitorView — replaced fabricated `Double.random` disk write-speed with an honest "N/A" (no public per-process API; encode writes are in the ffmpeg child).
- **#372 slice** — adopted `SuiteCoreCodecClassifier`'s no-`SUITE_CORE` fallback table in `FFmpegProbe` (additive optional `suiteCoreCodecDescriptor`) + lossless/spatial badges in Stream Inspector. #372 stays open (live Rust path gated on the sibling tag).
- **#432** F-002 follow-up — found SECURITY.md's site list stale; re-audited and sanitised **13 more** genuinely user-derived path components (incl. a real gap in `BatchRenamer`), conservatively leaving multi-segment/bounded/static paths.
- **#346 slice** — `RenderFarmConfigurationLoader` (injected `UserDefaults` → `RenderFarmClient.Configuration` + agent registry), enforces the insecure-transport acknowledgement contract, tolerant of empty/malformed `agentsJSON`. #346 stays open (transport/Bonjour/agent-binary remain).
- **#433** LoudnessReportView — wired the stub `runAnalysis()` to real ffmpeg ebur128/loudnorm; **fixed a genuine crash bug** in `LoudnessReporter.parseAnalysisOutput` (ClosedRange→endIndex OOB). Proven end-to-end.
- **#434** QualityMetricsView (re #291) — wired VMAF/SSIM/PSNR to real execution (libvmaf pre-flight, temp-log cleanup); **fixed a real "All"-mode bug** (combined args only applied the last filter). Proven end-to-end.
- **#435** BenchmarkView — replaced simulated results with real per-benchmark FFmpeg execution (frame count from `-progress`, real fps/time). Proven end-to-end.

All view-layer wirings (#433/#434/#435) are engine-tested and end-to-end-proven with real ffmpeg, but the SwiftUI views have no CI coverage — **in-GUI visual confirmation is best done during the rc.4 soak** (gauges/charts/cancel behaviour).

**Available next (not yet done):** `DuplicateDetector.perceptual` returns `[]` (needs a real perceptual-hash algo OR a UX decision on presenting "not available"); the G-015 GitHub-Actions SHA-pin sweep (deferred — rewrites `release.yml`, poor risk/reward right before the cut). Gated: #374 (unsafe to remove — `TheTVDBClient` is the only default-path impl), #373/#383 (blocked on the MeedyaSuite-core tag), #364/#416/#419–#427/AI/platform (need product/user decisions).

### Next steps — GATED ON USER (release cannot be cut autonomously)

- **G-010** — verify the 6 Apple org secrets exist (org-admin; Claude can't read them): `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY` (must contain "Developer ID Application"), `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`.
- **G-013** — tag-strategy decision (trunk-based vs keep alpha/beta).
- **Soak-window duration** — runbook has a `TODO` placeholder pending the policy call.
- **The cut**: bump version string → `git tag v0.1.0-rc.4 <sha-on-main>` → `release.yml` (tag-triggered `v*`; no `workflow_dispatch`; 0.x always `--prerelease`) → notarytool → staple → Gatekeeper smoke test → publish. GUI Help visual smoke-test + `SuiteCoreAvailability.isAvailable` shipped-build check are best done during the rc.4 soak.

## Architecture

- **ConverterEngine** — Cross-platform core library (SPM)
- **meedya-convert** — CLI tool (ArgumentParser)
- **MeedyaConverter** — macOS SwiftUI app
- **MeedyaSuite-core** — Optional Rust workspace with Swift/C FFI (feature-flagged via SUITE_CORE env)

### Technology Stack

- Swift 6.3, macOS 15.0+ (Sequoia), SwiftUI
- MVVM: @Observable @MainActor AppViewModel
- FFmpeg subprocess (direct) / FFmpegKit (App Store)
- External tools: dovi_tool, hlg-tools, hdr10plus_tool, subtitle_tonemap
- StoreKit 2 + Stripe + RevenueCat for monetization
- Sparkle 2 for direct distribution updates
- MeedyaSuite-core (Rust): optional codec/metadata acceleration via FFI

### Bundle IDs

| Platform             | Bundle ID                                  |
| -------------------- | ------------------------------------------ |
| App Store            | Ltd.MWBMpartners.MeedyaConverter.Lite      |
| Direct/Windows/Linux | Ltd.MWBMpartners.MeedyaConverter           |
| App Group            | group.Ltd.MWBMpartners.MeedyaConverter     |

### Remaining Open Issues (42 open)

- **Release**: #428 (v0.1.0-rc.4 → GA umbrella — the active track)
- **App Store / TestFlight compliance**: #392 (tracking) + ITMS children #386–#391, #178
- **Feature-gap gate-ledger** (all awaiting explicit user greenlight, multi-month each): #419 OFX host, #420 OpenColorIO, #421 audio offset, #422 audio drift, #423 audio-sync corpus, #424 premium tier + Expert Mode, #425 waveform viz, #426 subtitle muxing, #427 subtitle sync via audio
- **MeedyaSuite-core**: #372, #373, #374 (redundant-provider cleanup), #383 LyricsFile interconversion
- **AI (Phase 18, subscription tier)**: #235–#237, #364 cost estimation
- **In-app updater**: #416 route via update.mwbm.io
- **Render farm**: #346 engine-side consumption (UI shipped; engine deferred)
- **Platform expansion**: #147–#153 Windows (7), #154–#160 Linux (7)
