# MeedyaConverter — Project Brief

> Saved for Claude AI context continuity across sessions.
> Last updated: 2026-04-06

## Project Summary

MeedyaConverter is a cross-platform professional media conversion application by MWBM Partners Ltd. A modern HandBrake alternative with 100+ features including passthrough, adaptive streaming (HLS/MPEG-DASH), HDR preservation/tone-mapping, spatial audio, optical disc ripping/authoring, cloud upload, image conversion, video editing tools, and monetization infrastructure.

## Current Status (2026-04-06)

**macOS app is feature-complete** with 33 sidebar navigation items, 100+ SwiftUI views, and comprehensive engine.

- **Phases Complete**: 0-12, 15, 17 (15 of 19 phases)
- **Issues**: 366+ created, 344+ closed, ~22 open
- **Tests**: 866+ unit tests passing, 0 warnings, 0 security issues
- **CI/CD**: 7 GitHub Actions workflows (build, codeql, dependency-review, beta-alpha, release, testflight, dev-build)
- **Distribution**: Developer ID signing verified, notarization pipeline ready, TestFlight workflow configured
- **Apple Developer**: Both App IDs registered, App Group created, App Store Connect app record created

### Key Milestones Achieved This Session

- Implemented 100+ GitHub issues across encoding, UI, tools, professional features, cloud, security, monetization
- Full UI audit: 33 sidebar items surfacing all functionality
- Settings organized into 4 TabSections with 15+ tabs
- Code signing + notarization + DMG creation pipeline
- TestFlight submission workflow
- Dev Build workflow for downloadable test artifacts
- Dual bundle IDs (Direct + App Store Lite)
- Comprehensive DEV_NOTES.md with packaging/secrets guide
- All documentation updated (wiki, OpenAPI, CHANGELOG, etc.)

## Architecture

- **ConverterEngine** — Cross-platform core library (SPM)
- **meedya-convert** — CLI tool (ArgumentParser)
- **MeedyaConverter** — macOS SwiftUI app

### Technology Stack

- Swift 6.3, macOS 15.0+ (Sequoia), SwiftUI
- MVVM: @Observable @MainActor AppViewModel
- FFmpeg subprocess (direct) / FFmpegKit (App Store)
- External tools: dovi_tool, hlg-tools, hdr10plus_tool (planned), subtitle_tonemap (planned)
- StoreKit 2 + Stripe + RevenueCat for monetization
- Sparkle 2 for direct distribution updates

### Bundle IDs

| Platform             | Bundle ID                                  |
| -------------------- | ------------------------------------------ |
| App Store            | Ltd.MWBMpartners.MeedyaConverter.Lite      |
| Direct/Windows/Linux | Ltd.MWBMpartners.MeedyaConverter           |
| App Group            | group.Ltd.MWBMpartners.MeedyaConverter     |

### Remaining Open Issues (22)

- #178 App Store Submission
- #346 Remote encoding, #364 AI cost estimation
- #368 hdr10plus_tool, #369 subtitle_tonemap
- #235-#237 AI features (subscription tier)
- #147-#153 Windows (7 issues), #154-#160 Linux (7 issues)
