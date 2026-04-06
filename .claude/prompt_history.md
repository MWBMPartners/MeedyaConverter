# MeedyaConverter — Claude Prompt History

> Log of significant development prompts and decisions.
> Maintained for project continuity across sessions.

## Session: 2026-04-03

### Prompts 1-12: Foundation & Architecture

- Project brief, FFmpeg licensing, architecture naming (ConverterEngine/meedya-convert/MeedyaConverter)
- App Store subprocess strategy (hybrid encoding: subprocess for direct, AVFoundation for App Store)
- Sparkle auto-updates for direct distribution
- MV-HEVC/MV-H264 3D video, optical disc ripping (22 formats)
- Disc authoring/burning phase
- Full project setup: SPM targets, GitHub milestones/issues/wiki/workflows
- Feature expansions: matrix encoding, upmixing, spatial audio, media metadata, image conversion
- Project reorganisation: 19 phases, release gates Alpha→v3.0+
- Feature gating (free/pro/studio tiers), AI wishlist (Phase 18)

**Result:** 240 GitHub issues, 19 milestones, full project infrastructure.

## Session: 2026-04-04

### Prompts 13-18: Phase 2-3 Implementation

- Phase 2 complete: macOS SwiftUI MVP (NavigationSplitView, import, stream inspector, output settings, queue, log, settings, help)
- Phase 3 complete: Passthrough, stream selection, metadata editor, HDR warnings, hardware encoder detection, crop detection, DV pipeline, tone mapping, PQ→HLG, PQ→DV+HLG combined conversion
- 25 built-in encoding profiles
- Tool bundling strategy (hlg-tools, dovi_tool)

## Session: 2026-04-05 — 2026-04-06 (Major Implementation Sprint)

### Phase Completion Sprint

Implemented and closed 150+ GitHub issues across multiple phases:

**Phase 3.5**: Per-stream encoding settings (PerStreamSettings model, FFmpegArgumentBuilder, PerStreamSettingsView)
**Phase 9**: Sparkle 2 update checker (AppUpdateChecker with conditional compilation)
**Phase 11**: Burn settings UI (BurnSettingsView with drive detection, progress, verify)
**Phase 17**: Image conversion UI (ImageConversionView with thumbnail grid, batch processing)
**Phase 16**: Code signing, notarization, release pipeline, Touch Bar, dock/menu bar activity indicators, analytics, GitHub Wiki (10 pages), documentation, semver versioning

### Enhancement Implementation (100+ features)

Implemented in parallel batches using multiple agents:

- **Encoding**: Per-stream settings, filename templates, file size estimation, FFmpeg command preview, A/B quality preview, smart profile suggestions, encoding pipelines, scheduled encoding, conditional rules, post-encode actions, watch folders, resume interrupted encodes, profile sharing
- **Audio**: Normalization presets, scene detection, audio waveform, voice isolation, audio mixing
- **Video**: Trimming/splitting/snipping, frame-accurate trimming, concatenation, stabilization, deinterlacing
- **Professional**: SMPTE timecode, closed captions, loudness compliance, QC checks, EDL roundtrip, slate/leader generation
- **Analysis**: Bitrate heatmap, resource monitoring, benchmarks, smart queue ordering, predictive ETA, storage analysis, encode comparison, VMAF/SSIM/PSNR, duplicate detection
- **UI**: Dashboard, menu bar mode, mini player, filter graph editor, batch rename, metadata tag editor, onboarding wizard, keyboard shortcuts, undo/redo, recent files, color themes
- **Cloud**: SFTP/FTP, YouTube/Vimeo upload, Dropbox/OneDrive/Google Drive, iCloud sync, team profiles, webhook notifications, Plex/Jellyfin integration, email notifications, RSS/podcast feed
- **Security**: Secure deletion, AES encryption, DRM preparation (CPIX/PSSH)
- **Platform**: AppleScript/JXA, Siri Shortcuts, Finder extension, Automator, Stage Manager, Control Center widget, Lock Screen widget, interactive notifications, Handoff, drag-and-drop, URL scheme handler
- **Infrastructure**: Parallel encoding, REST API server, plugin system, localization (120+ strings)

### Monetization System

- Feature gating (EntitlementLevel: free/plus/pro, 24 gated features)
- Product catalog (Free/Plus/Pro tiers with StoreKit 2 product IDs)
- StoreKit 2 integration (purchase, restore, transaction listening)
- Stripe license key validation (Luhn-mod-36 checksum, Keychain storage)
- RevenueCat placeholder for cross-platform sync

### Distribution Infrastructure

- Dual bundle IDs: Ltd.MWBMpartners.MeedyaConverter (Direct) + Ltd.MWBMpartners.MeedyaConverter.Lite (App Store)
- App Group: group.Ltd.MWBMpartners.MeedyaConverter
- Code signing verified locally (Developer ID cert valid until 2031)
- 7 CI/CD workflows: build, codeql, dependency-review, beta-alpha, release, testflight, dev-build
- Makefile for local dev packaging
- DEV_NOTES.md with comprehensive secrets/packaging guide
- Apple Developer Portal: Both App IDs registered with capabilities (App Groups, iCloud, IAP, Push, Siri, MusicKit, ShazamKit)
- App Store Connect: MeedyaConverter Lite app record created
- 9 GitHub org secrets configured

### Code Quality

- 866+ unit tests passing (0 failures)
- 0 compiler warnings, 0 security issues
- SwiftLint configured to exclude third-party dependencies
- Comprehensive code reviews: security, accessibility, thread safety
- AccurateRip misaligned pointer crash fixed (root cause: unsafe UInt32 loads)

### Key Decisions

- **Bundle IDs**: Direct = Ltd.MWBMpartners.MeedyaConverter, App Store = Ltd.MWBMpartners.MeedyaConverter.Lite
- **App Store Connect API Key**: Account-wide (not per-app), Admin access for TestFlight
- **hdr10plus_tool and subtitle_tonemap**: Approved for integration (GitHub issues #368, #369)
- **Primary Language**: English (U.K.) for App Store Connect
- **Node.js 20 warning**: GitHub-side deprecation, cannot eliminate — cosmetic only
- **SwiftLint annotations**: Fixed by creating .swiftlint.yml limiting to Sources/ and Tests/
