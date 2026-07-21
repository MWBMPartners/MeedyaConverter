# MeedyaConverter — Feature Gap Ledger

> Seeded from GitHub issue corpus (41+ open, ~345 closed) rather than a
> from-scratch `featurefind` run, since the project's issue tracker IS the
> authoritative feature-gap ledger for this product. Updated by the autopilot
> loop as new gaps surface.

## Classification scheme

| Tier | Meaning |
|------|---------|
| **table-stakes** | Category-standard for a Mac video/audio converter; users expect it |
| **differentiator** | Beyond category baseline; shapes product positioning |
| **out-of-scope** | Foreign to product purpose; explicitly NOT in MeedyaConverter |
| **deferred** | In-scope but tracked as a multi-month effort; Phase A scaffolding only in autopilot |

## In-scope gaps the autopilot may build autonomously (Bucket 1)

**Recent DISCOVER audit found autonomously-buildable gaps**, now tracked as GitHub issues. Status as of 2026-07-21:

- **FIXED & merged to main:** #444 (VideoTrimmer real trim), #445 (QualityCheck real QC)
- **ADDRESSED (disabled/probed pending resolution):** #447 (real SFTP probe), #446 (VideoUpload disabled pending OAuth), #449 (DuplicateFinder Perceptual hidden pending pHash)
- **OPEN backlog:** #448 (placeholder UIs: DualDynamicHDR/BitrateHeatmap/AnimatedImage/EncodingGraphs/CloudSync), #450 (post-encode SFTP/cloud), #451 (Swift 6 concurrency audit — in progress on this branch)

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

## Refresh policy

Re-evaluate at the start of each COMPLETE-phase cycle. New issues surfacing
on GitHub mid-loop are added here at REHYDRATE if they classify as in-scope
gaps.
