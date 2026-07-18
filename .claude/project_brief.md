# MeedyaConverter — Project Brief

> Saved for Claude AI context continuity across sessions.
> Last updated: 2026-04-20

## Project Summary

MeedyaConverter is a cross-platform professional media conversion application by MWBM Partners Ltd. A modern HandBrake alternative with 100+ features including passthrough, adaptive streaming (HLS/MPEG-DASH), HDR preservation/tone-mapping, spatial audio, optical disc ripping/authoring, cloud upload, image conversion, video editing tools, and monetization infrastructure.

## Current Status (2026-04-20)

**macOS app is feature-complete** with 33 sidebar navigation items, 100+ SwiftUI views, and comprehensive engine.

- **Phases Complete**: 0-12, 15, 17 (15 of 19 phases)
- **Issues**: 381+ created, 370+ closed, ~11 open
- **Tests**: 950+ unit tests passing, 0 warnings, 0 security issues
- **CI/CD**: 7 GitHub Actions workflows (build, codeql, dependency-review, beta-alpha, release, testflight, dev-build)
- **Distribution**: Developer ID signing verified, notarization pipeline ready, TestFlight workflow configured
- **Apple Developer**: Both App IDs registered, App Group created, App Store Connect app record created
- **App Store**: Metadata, screenshots placeholder, review info, and submission runbook complete

### Key Milestones Achieved (2026-04-20 Session)

- MeedyaSuite-core integration scaffolding (#373) — feature-flagged Rust FFI bridge
- SuiteCoreMetadataAdapter (#371) — unified metadata provider routing with 12 additional providers
- SuiteCoreCodecClassifier (#372) — lossless/spatial codec classification tables
- Redundant metadata provider prep for removal (#374) — migration guide created
- SubtitleTonemapWrapper (#369) — HDR→SDR subtitle colour correction (PGS/VobSub/ASS)
- Render Farm subsystem (#346) — chunked upload, Bonjour discovery, 7-state job lifecycle
- Raster↔Vector conversion (#376) — 30+ raster formats, vtracer/potrace/rsvg-convert arg builders
- ProRes→animated SVG (#377) — SMIL animation wrapper, frame extraction pipeline
- FFplay bundling (#378) — A/B preview player support
- App Store submission prep (#178) — metadata, runbook, review_information.yml
- Security audit (#380) — fixed 3 critical (JSON injection) + 2 major (SSH injection, OOM buffer)
- UI audit → created tracking issue #381 for 36+ missing controls
- Documentation fully updated (CHANGELOG, PROJECT_STATUS, Sources/MeedyaConverter/Resources/Help/, docs/)

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

### Remaining Open Issues (~11)

- #364 AI cost estimation
- #368 hdr10plus_tool binary integration
- #235-#237 AI features (subscription tier)
- #380 FTP password exposure (deferred — needs API change)
- #381 UI controls gap (36+ missing toggles/fields)
- #147-#153 Windows (7 issues), #154-#160 Linux (7 issues)
