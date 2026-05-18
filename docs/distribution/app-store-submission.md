<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — App Store Submission Checklist (Issue #178)

This document is the authoritative reference for preparing and submitting
MeedyaConverter to the Mac App Store. Work items are tracked against the
acceptance criteria in GitHub issue #178.

## 1. Build configuration

- [x] `APP_STORE` environment flag toggles FFmpegKit in `Package.swift`
      (`isAppStoreBuild`). Direct builds keep the FFmpeg subprocess pipeline.
- [x] `Sources/MeedyaConverter/Resources/MeedyaConverter-AppStore.entitlements`
      declares App Sandbox, network client, user-selected read-write, and
      app-scope bookmarks. Kept minimal — only entitlements that map to an
      actively-used feature.
- [x] Sparkle excluded from App Store builds (`isDirectBuild`-gated in
      `Package.swift`). TestFlight and Release Candidate builds use
      App Store-managed updates.
- [x] SUITE_CORE (MeedyaSuite-core) is compatible with sandbox — the Rust
      static library runs in-process so no XPC/helper is required.
- [ ] Verify `FFmpegKit` XCFramework product is the LGPL (not GPL) variant.
      The App Store licence restrictions require LGPL. Check the
      Package.resolved pin once FFmpegKit is actively linked.

## 2. App Store Connect metadata

All content lives in `metadata/` and is consumed by `fastlane deliver`:

- [x] `metadata/en-US/description.txt` — full App Store description
- [x] `metadata/en-US/subtitle.txt` — short tagline
- [x] `metadata/en-US/keywords.txt` — comma-separated search keywords
- [x] `metadata/en-US/promotional_text.txt` — 170-char promo banner
- [x] `metadata/en-US/release_notes.txt` — per-version release notes
- [x] `metadata/en-US/support_url.txt` — GitHub issues URL
- [x] `metadata/en-US/marketing_url.txt` — product landing page
- [x] `metadata/en-US/privacy_url.txt` — privacy policy
- [x] `metadata/copyright.txt`, `primary_category.txt`, `secondary_category.txt`
- [x] `metadata/review_information.yml` — review notes, contact, demo
      credentials (none required)

## 3. Screenshots

Stored in `screenshots/` under Apple's naming convention. Required sizes
for macOS apps:

- [ ] 1280×800 (required, minimum)
- [ ] 1440×900
- [ ] 2560×1600 (Retina baseline)
- [ ] 2880×1800 (Retina 15-inch)

Minimum 1 screenshot per size, maximum 10. Captures should showcase:

1. Main window with a job in progress
2. Profile editor with a custom profile
3. Encoding queue with multiple jobs
4. Quality metrics panel (VMAF graph)
5. Cloud delivery dashboard
6. Dark mode variant of the main window

## 4. TestFlight beta

- [x] `.github/workflows/testflight.yml` — workflow builds, signs, and
      uploads to TestFlight on `v*-beta*` / `v*-rc*` tags
- [x] Required secrets documented in the workflow header (`APPLE_CERTIFICATE`,
      `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `ASC_KEY_ID`,
      `ASC_ISSUER_ID`, `ASC_API_KEY`) — configured at org level per #178
      acceptance criterion
- [ ] Recruit internal-testers-group in App Store Connect (≤100 testers, no
      review required)
- [ ] Recruit external-testers-group (up to 10,000 testers, Beta Review
      required)

## 5. Submission flow

1. Tag a build: `git tag v1.0.0-rc.1 && git push --tags`
2. TestFlight workflow runs, produces the signed IPA, and uploads to ASC
3. Verify the build appears in ASC > TestFlight
4. Send to internal testers for smoke-testing
5. Fix any issues, repeat 1-4
6. Once stable, promote to external testing (Beta Review ~1 day)
7. Run `fastlane deliver --submit_for_review` — this reads `metadata/` and
   `screenshots/` and submits to ASC
8. Respond to reviewer questions if any

## 6. Known review risks

- **Optical disc ripping**: App Store builds limit ripping to unencrypted
  audio CDs only. The CSS/AACS decryption paths are compiled out under
  `APP_STORE`. Confirmed in `Sources/ConverterEngine/Disc/*` — no CSS
  imports when the flag is on.
- **FFmpegKit licensing**: Must be LGPL variant. GPL would violate the
  App Store's share-alike requirement. Pin verification is a pre-submit
  step (see §1 above).
- **Sandbox + temp file management**: `TempFileManager` uses
  `FileManager.default.temporaryDirectory` which is sandbox-compatible.
  Confirmed tested in `ConverterEngineTests` (`test_tempFileManager_*`).
- **Hardened runtime**: required for App Store; set in the build pipeline
  via `codesign --options=runtime`.

## 7. Post-approval

- [ ] Switch Sparkle update channel for the direct-distribution build to a
      separate appcast so App Store users are not prompted
- [ ] Monitor ASC > App Analytics for crash reports
- [ ] Plan v1.0.1 release with any hot-fix items flagged in review

## Acceptance-criteria mapping to issue #178

| Criterion | Status |
|-----------|--------|
| APP_STORE build configuration produces sandbox-compliant binary | Done |
| App Sandbox entitlements correctly configured | Done |
| Sparkle framework excluded from App Store build | Done |
| FFmpegKit linked as library (not subprocess) in App Store build | Pending — LGPL variant confirmation |
| App Store Connect listing created with metadata | Metadata committed; ASC listing is a manual one-time ASC step |
| Screenshots for all required sizes | Pending — captures required |
| App description, keywords, categories configured | Done |
| Privacy policy URL configured | Done |
| App Review information prepared | Done |
| TestFlight beta testing before submission | Workflow ready |
| Build uploaded via Xcode or xcrun altool | Workflow ready |
| Pass App Review | Post-submission |
| In-app purchase setup | Deferred — free tier ships first |
