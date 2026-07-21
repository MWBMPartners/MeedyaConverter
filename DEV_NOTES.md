<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# MeedyaConverter — Developer Notes

This document covers packaging, release, signing, and CI/CD configuration for MeedyaConverter.

---

## Table of Contents

- [Build Configurations](#build-configurations)
- [Bundle IDs](#bundle-ids)
- [Local Development Build](#local-development-build)
- [Code Signing](#code-signing)
- [Notarization](#notarization)
- [GitHub Secrets Reference](#github-secrets-reference)
- [App Store Connect API Key Setup](#app-store-connect-api-key-setup)
- [Apple Developer Certificates Setup](#apple-developer-certificates-setup)
- [TestFlight Submission](#testflight-submission)
- [Production Release](#production-release)
- [Pre-Release Tags](#pre-release-tags)
- [FFmpeg Bundling & Supply Chain](#ffmpeg-bundling--supply-chain)
- [External Tools](#external-tools)
- [CI/CD Workflows](#cicd-workflows)
- [Troubleshooting](#troubleshooting)

---

## Build Configurations

| Configuration | Flag | Bundle ID | Features |
|--------------|------|-----------|----------|
| **Direct Distribution** | (default) | `Ltd.MWBMpartners.MeedyaConverter` | Hardened runtime, system FFmpeg via Process, Sparkle updates, full disk access |
| **App Store** | `-Xswiftc -DAPP_STORE` | `Ltd.MWBMpartners.MeedyaConverter.Lite` | App Sandbox, FFmpegKit (embedded), no Sparkle, no subprocess calls |

```bash
# Direct distribution build (single-arch, matches your local Mac)
swift build -c release

# Direct distribution build, universal (arm64 + x86_64) -- what release.yml runs
swift build -c release --arch arm64 --arch x86_64

# App Store build
swift build -c release -Xswiftc -DAPP_STORE
```

**Universal builds**: `release.yml` builds the app itself universal
(`--arch arm64 --arch x86_64`) so the shipped `.app` runs natively on both
Apple Silicon and Intel with no Rosetta translation -- Apple has signalled
Rosetta 2 will eventually be decommissioned, so a real arm64 slice from day
one is required either way. SwiftPM writes universal output under a
distinct build path; resolve it with `swift build -c release --arch arm64
--arch x86_64 --show-bin-path` rather than assuming `.build/release`. A
plain local `swift build -c release` (no `--arch` flags) still produces a
single-arch binary matching your Mac, which is fine for day-to-day
development.

---

## Bundle IDs

| Platform | Bundle ID | Notes |
|----------|-----------|-------|
| Apple App Store | `Ltd.MWBMpartners.MeedyaConverter.Lite` | Sandboxed, reduced features |
| Apple Direct | `Ltd.MWBMpartners.MeedyaConverter` | Full features, hardened runtime |
| Windows | `Ltd.MWBMpartners.MeedyaConverter` | Shares direct distribution ID |
| Linux | `Ltd.MWBMpartners.MeedyaConverter` | Shares direct distribution ID |

**App Group** (shared data between App Store and Direct builds):
`group.Ltd.MWBMpartners.MeedyaConverter`

---

## Local Development Build

See [docs/LOCAL_BUILD.md](docs/LOCAL_BUILD.md) for detailed instructions.

```bash
# Quick build
make build

# Create .app bundle
make bundle

# Create DMG
make dmg

# Sign with Developer ID
make sign SIGNING_IDENTITY="Developer ID Application: MWBM Partners LTD (Y5XK559SV9)"

# Full pipeline
make all
```

---

## Code Signing

### Entitlements Files

| File | Purpose |
|------|---------|
| `Sources/MeedyaConverter/Resources/MeedyaConverter.entitlements` | Direct distribution (hardened runtime) |
| `Sources/MeedyaConverter/Resources/MeedyaConverter-AppStore.entitlements` | App Store (sandboxed) |
| `Sources/meedya-convert/Resources/meedya-convert.entitlements` | CLI tool |

### Signing Locally

```bash
# Find your signing identity
security find-identity -v -p codesigning

# Sign the app
codesign --sign "Developer ID Application: MWBM Partners LTD (Y5XK559SV9)" \
  --entitlements Sources/MeedyaConverter/Resources/MeedyaConverter.entitlements \
  --options runtime --force --timestamp \
  MeedyaConverter.app

# Verify
codesign --verify --deep --strict MeedyaConverter.app
```

### Certificate Details

- **Identity**: `Developer ID Application: MWBM Partners LTD (Y5XK559SV9)`
- **Team ID**: `Y5XK559SV9`
- **Expiry**: February 16, 2031
- **Type**: Developer ID Application (for direct distribution outside App Store)

---

## Notarization

```bash
# Submit for notarization
xcrun notarytool submit MeedyaConverter.dmg \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "Y5XK559SV9" \
  --wait

# Staple the ticket
xcrun stapler staple MeedyaConverter.dmg
```

**Note**: For CI, use App Store Connect API Key instead of Apple ID + password to avoid 2FA issues.

---

## GitHub Secrets Reference

All secrets are configured at the **organization level** (MWBMPartners) and available to all repositories.

### Apple Signing Secrets

| Secret Name | Description | How to Obtain |
|------------|-------------|---------------|
| `APPLE_CERTIFICATE` | Base64-encoded .p12 signing certificate | Export from Keychain Access (see below) |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 file | Set when exporting from Keychain |
| `APPLE_ID` | Apple ID email for notarization | Your Apple Developer account email |
| `APPLE_PASSWORD` | App-specific password for Apple ID | Generate at appleid.apple.com (see below) |
| `APPLE_SIGNING_IDENTITY` | Full signing identity string | `Developer ID Application: MWBM Partners LTD (Y5XK559SV9)` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `Y5XK559SV9` (from developer.apple.com) |

### App Store Connect API Secrets (for TestFlight)

| Secret Name | Description | How to Obtain |
|------------|-------------|---------------|
| `ASC_KEY_ID` | App Store Connect API Key ID | From App Store Connect > Integrations (see below) |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID | From App Store Connect > Integrations (see below) |
| `ASC_API_KEY` | Contents of the .p8 private key file | Downloaded from App Store Connect (one-time download) |

---

## App Store Connect API Key Setup

**The API key is per Apple Developer Program account, NOT per app.** One key manages all apps.

### Step-by-Step Instructions

1. **Navigate to App Store Connect**
   - Go to [https://appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - Sign in with your Apple ID
   - You must have **Admin** or **Account Holder** role

2. **Open Integrations**
   - Click **Users and Access** in the top navigation bar
   - Click the **Integrations** tab
   - Click **App Store Connect API** in the left sidebar

3. **Generate a New Key**
   - Click the **+** (plus) button next to "Active"
   - **Name**: Enter `MeedyaConverter CI` (or any descriptive name)
   - **Access**: Select **Admin** (required for TestFlight uploads and app management)
   - Click **Generate**

4. **Download the .p8 Key File**
   - **IMPORTANT**: Click **Download** immediately
   - Apple only allows you to download the .p8 file **ONCE**
   - If you lose it, you must revoke and create a new key
   - Save the file securely (e.g., encrypted vault, 1Password, etc.)

5. **Record the Key ID**
   - The **Key ID** is displayed next to the key name in the list
   - Example: `ABC1234DEF`
   - This goes into the `ASC_KEY_ID` GitHub secret

6. **Record the Issuer ID**
   - The **Issuer ID** is displayed at the top of the Integrations page
   - It's a UUID like: `57246542-96fe-1a63-e053-0824d011072a`
   - This is the same for all keys in your account
   - This goes into the `ASC_ISSUER_ID` GitHub secret

7. **Add to GitHub Secrets**
   - Go to GitHub > MWBMPartners org > Settings > Secrets and variables > Actions
   - Click **New organization secret** for each:
     - `ASC_KEY_ID` = the Key ID from step 5
     - `ASC_ISSUER_ID` = the Issuer ID from step 6
     - `ASC_API_KEY` = the **entire contents** of the .p8 file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines

---

## Apple Developer Certificates Setup

### Exporting the Signing Certificate as .p12

1. **Open Keychain Access** on your Mac
2. Click **login** keychain in the sidebar
3. Click **My Certificates** category
4. Find `Developer ID Application: MWBM Partners LTD (Y5XK559SV9)`
5. Right-click > **Export...**
6. Choose **Personal Information Exchange (.p12)** format
7. Set a strong password (this becomes `APPLE_CERTIFICATE_PASSWORD`)
8. Save the file

### Base64 Encoding for GitHub

```bash
# Encode the .p12 file to base64
base64 -i Certificates.p12 | pbcopy
# The base64 string is now on your clipboard
```

Paste this into the `APPLE_CERTIFICATE` GitHub secret.

### Generating an App-Specific Password

The `APPLE_PASSWORD` secret is an **app-specific password**, NOT your Apple ID password.

1. Go to [https://appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Go to **Sign-In and Security** > **App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Label: `MeedyaConverter CI`
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)
7. Add this as the `APPLE_PASSWORD` GitHub secret

---

## TestFlight Submission

### Automatic (CI)

```bash
# Push a beta tag to trigger TestFlight workflow
git tag v0.1.0-beta.1
git push origin v0.1.0-beta.1

# Or trigger manually from GitHub Actions UI
# Go to Actions > TestFlight Submission > Run workflow
```

### Manual

```bash
# Build for App Store
swift build -c release -Xswiftc -DAPP_STORE

# Create and sign app bundle (use make target)
make bundle

# Upload via xcrun
xcrun altool --upload-app \
  --type macos \
  --file MeedyaConverter.zip \
  --apiKey "YOUR_KEY_ID" \
  --apiIssuer "YOUR_ISSUER_ID"
```

### Required App Store Connect Setup

Before the first TestFlight submission:

1. Create the app record in App Store Connect:
   - Bundle ID: `Ltd.MWBMpartners.MeedyaConverter.Lite`
   - Platform: macOS
   - Name: MeedyaConverter
   - SKU: `meedyaconverter-lite`
   
2. Register the bundle ID in the Apple Developer Portal:
   - Go to developer.apple.com > Certificates, IDs & Profiles > Identifiers
   - Click + and register `Ltd.MWBMpartners.MeedyaConverter.Lite`

---

## Production Release

```bash
# Tag a release version
git tag v1.0.0
git push origin v1.0.0
```

This triggers `.github/workflows/release.yml` which:
1. Builds the app itself in release configuration, **universal**
   (`swift build -c release --arch arm64 --arch x86_64`)
2. Runs all tests
3. Imports signing certificate from secrets
4. Creates the .app bundle
5. Runs `scripts/bundle-ffmpeg.sh` to stage universal `ffmpeg`/`ffprobe`/`ffplay`
   into `Contents/Helpers/` -- see
   [FFmpeg Bundling & Supply Chain](#ffmpeg-bundling--supply-chain) below
6. Signs with Developer ID
7. Notarizes with Apple (`xcrun notarytool submit ... --wait`)
8. Creates DMG with /Applications symlink
9. Signs and notarizes the DMG, then staples the notarization ticket
   (`xcrun stapler staple`)
10. Creates the GitHub Release with the `.dmg` and a signed/notarised CLI
    tarball as assets

**Versions < v1.0.0 are automatically marked as pre-release** per semver.
For the current v0.1.0 line this means every `v0.1.0-rc.N` and the eventual
`v0.1.0` GA tag are all "Direct distribution only" -- the same
sign/notarise/staple/GitHub-Release pipeline described above, with App
Store Lite submission deferred (see `PROJECT_STATUS.md`).

---

## Pre-Release Tags

| Tag Pattern | Channel | Workflow |
|------------|---------|----------|
| `v0.1.0-alpha.1` | Alpha | `beta-alpha.yml` |
| `v0.1.0-beta.1` | Beta | `beta-alpha.yml` + `testflight.yml` |
| `v0.1.0-rc.1` | Release Candidate | `testflight.yml` |
| `v1.0.0` | Production | `release.yml` |

---

## FFmpeg Bundling & Supply Chain

`scripts/bundle-ffmpeg.sh <DEST_DIR>` stages the `ffmpeg` / `ffprobe` /
`ffplay` binaries that ship inside the Direct-distribution `.app` at
`Contents/Helpers/`. It is called by `release.yml` (and can be run locally
for a fully self-contained checkout). This is also SECURITY.md finding
**F-011** -- closed as of 2026-07.

**Source -- first-party, pinned, universal:**

- The sole source is the first-party mirror
  **[`MeedyaSuite/MeedyaDL-Tools`](https://github.com/MeedyaSuite/MeedyaDL-Tools)**,
  pinned in the script to an immutable dated release tag (`MDLT_TAG`,
  e.g. `2026-07-05.3`). There is no third-party fallback in this repo --
  the mirror is the only source, so the supply chain is entirely
  first-party.
- The mirror itself fetches real native static builds for both macOS
  arches (arm64 from osxexperts.net, x86_64 from evermeet.cx),
  repackages each as `<tool>-macos-<arch>.tar.gz`, and publishes a
  `SHA256SUMS` asset alongside them.
- `bundle-ffmpeg.sh` downloads both per-arch archives for each tool and
  `lipo -create`s them into a single **universal (arm64 + x86_64)**
  binary, then asserts the result actually reports both arches
  (`lipo -archs`) before accepting it.

**Integrity -- fail-closed SHA-256 verification:**

- Every archive is SHA-256-verified against the pinned release's own
  `SHA256SUMS` **before** it is unpacked. Missing `SHA256SUMS` or a
  missing pin exits `6`; a hash **mismatch** exits `7` (always fatal,
  even for the optional `ffplay`). Nothing unverified reaches the
  sign/notarise step.
- The trust root is the first-party tagged release's own `SHA256SUMS` --
  no local checksum list is maintained in this repo. (An earlier
  revision used a URL-keyed `scripts/ffmpeg-checksums.txt` bridge file;
  it has been removed now that the mirror publishes its own
  `SHA256SUMS`.)
- `ffmpeg` and `ffprobe` are **required** -- either arch missing for
  either tool is fatal (exit `6`/`8`). `ffplay` (in-app preview only) is
  best-effort but still hash-gated when it is present.

**Bumping the FFmpeg version**: edit `MDLT_TAG` in
`scripts/bundle-ffmpeg.sh` to a newer MeedyaDL-Tools release -- that is
the single deliberate edit. MeedyaDL-Tools tracks upstream FFmpeg on its
own update schedule, so newer builds flow through automatically once you
bump the pin.

See `SECURITY.md`'s Findings Register (F-011) for the full incident
write-up and verification log.

---

## External Tools

MeedyaConverter bundles or detects several external tools:

| Tool | Purpose | Source | Detection |
|------|---------|--------|-----------|
| **FFmpeg** | Media encoding/decoding | Bundled: first-party [MeedyaDL-Tools](https://github.com/MeedyaSuite/MeedyaDL-Tools) mirror (universal, SHA-256-verified -- see above). User-installed: [ffmpeg.org](https://ffmpeg.org) | PATH, Homebrew, bundled |
| **FFprobe** | Media analysis | Included with FFmpeg | Same as FFmpeg |
| **dovi_tool** | Dolby Vision metadata | [github.com/quietvoid/dovi_tool](https://github.com/quietvoid/dovi_tool) | PATH, bundled |
| **hlg-tools** | PQ→HLG conversion | [github.com/wswartzendruber/hlg-tools](https://github.com/wswartzendruber/hlg-tools) | PATH, bundled |
| **hdr10plus_tool** | HDR10+ metadata | [github.com/quietvoid/hdr10plus_tool](https://github.com/quietvoid/hdr10plus_tool) | PATH, bundled (planned) |
| **subtitle_tonemap** | HDR subtitle colors | [github.com/quietvoid/subtitle_tonemap](https://github.com/quietvoid/subtitle_tonemap) | PATH, bundled (planned) |
| **Tesseract** | Subtitle OCR | [github.com/tesseract-ocr/tesseract](https://github.com/tesseract-ocr/tesseract) | PATH, Homebrew |

All tools are checked for updates via `ToolUpdateChecker` which queries GitHub Releases API.

---

## CI/CD Workflows

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| **CI Build & Test** | `build.yml` | Push/PR to main/beta/alpha | Build, test, SwiftLint |
| **CodeQL Security** | `codeql.yml` | Push/PR + weekly cron | Static security analysis |
| **Dependency Review** | `dependency-review.yml` | PRs | Scan dependency changes |
| **Security Check** | `security-check.yml` | Push + PRs touching `.github/workflows/**` or `scripts/security-check-*.sh` | F-010 static linters (Actions tag-pin regression gate) |
| **Beta & Alpha Pre-Release** | `beta-alpha.yml` | Push to beta/alpha | Auto-tag, pre-release |
| **Dev Build** | `dev-build.yml` | Manual dispatch + push to alpha | Signed .app/DMG/CLI artefacts for internal testing, pre-TestFlight |
| **Production Release** | `release.yml` | Push `v*` tag | Universal build, sign, notarize, staple, DMG + CLI tarball, GitHub Release |
| **TestFlight** | `testflight.yml` | Manual + beta/RC tags (currently `disabled_manually`, see #392) | App Store build, upload |

---

## Troubleshooting

### "No signing identity found"
```bash
security find-identity -v -p codesigning
```
If empty, the Developer ID certificate is not installed in your keychain.

### "notarytool: unable to authenticate"
- Ensure `APPLE_PASSWORD` is an **app-specific password**, not your Apple ID password
- Regenerate at [appleid.apple.com](https://appleid.apple.com) if expired

### "The app is damaged and can't be opened"
Testers need to remove the quarantine attribute:
```bash
xattr -cr MeedyaConverter.app
```

### "xcrun altool: Unable to upload"
- Verify `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY` are correct
- Ensure the .p8 key has **Admin** access level
- Check the app record exists in App Store Connect with matching bundle ID

### CI build fails with "unhandled files"
Add new resource files to the `exclude` list in `Package.swift`.

### SwiftLint shows errors from dependencies
The `.swiftlint.yml` config limits scanning to `Sources/` and `Tests/`. If annotations still appear from `.build/`, verify the config is being loaded.
