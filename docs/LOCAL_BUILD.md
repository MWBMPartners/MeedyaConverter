# MeedyaConverter -- Local Development Build Guide

Copyright (c) 2026 MWBM Partners Ltd. All rights reserved.

---

## Prerequisites

| Requirement       | Minimum Version | Notes                                    |
|-------------------|-----------------|------------------------------------------|
| macOS             | 15.0+           | Required for Swift 6 and SwiftUI targets |
| Swift             | 6.0+            | Ships with Xcode 16+ or swift.org builds |
| Xcode CLI Tools   | 16.0+           | `xcode-select --install`                 |
| FFmpeg (optional) | 6.0+            | Only needed for external codec fallback   |
| Git               | 2.30+           | For build number generation               |

Verify your Swift version:

```bash
swift --version
```

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/MWBMPartners/MeedyaConverter.git
cd MeedyaConverter

# See all available build targets
make help

# Quick debug build (fastest iteration)
make build-debug

# Release build
make build

# Run tests
make test
```

---

## Build Targets

Run `make help` to see all available targets with descriptions:

```
help                 Show this help
all                  Full build pipeline
clean                Clean build artifacts
build                Build in release configuration
build-debug          Build in debug configuration
test                 Run all tests
sign                 Sign the app bundle with Developer ID
bundle               Create .app bundle structure
package              Create .app bundle (alias for bundle)
dmg                  Create DMG disk image
dmg-signed           Create signed DMG
install              Install to /Applications (requires sudo)
uninstall            Remove from /Applications
cli                  Build CLI tool only
version              Show version info
lint                 Run SwiftLint
validate             Validate app bundle structure
```

---

## Building the App Bundle

To create a `.app` bundle from the release binary:

```bash
make bundle
```

This will:
1. Build in release configuration (`swift build -c release`)
2. Create `MeedyaConverter.app/Contents/` directory structure
3. Copy the compiled binary into `Contents/MacOS/`
4. Substitute the version and build number into `Info.plist`
5. Copy entitlements into `Contents/Resources/`

The version is read from the `VERSION` file at the project root. The build
number is derived from the git commit count.

---

## Code Signing

### Ad-hoc signing (no Apple Developer account)

By default, `make bundle` produces an unsigned bundle. macOS will quarantine
it on first launch, but you can bypass Gatekeeper (see below).

### Developer ID signing

If you have a Developer ID certificate in your keychain:

```bash
make sign SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

This calls `scripts/codesign.sh` with hardened runtime and the project
entitlements.

### Listing available identities

```bash
security find-identity -v -p codesigning
```

---

## Creating a DMG

### Unsigned DMG (for local testing)

```bash
make dmg
```

### Signed DMG (for distribution)

```bash
make dmg-signed SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The DMG is named `MeedyaConverter-<version>-macOS.dmg` and placed in the
project root.

---

## Installing Locally

```bash
# Install to /Applications
sudo make install

# Remove from /Applications
sudo make uninstall
```

---

## Gatekeeper Bypass for Testers

If you receive a `.app` bundle or DMG that is not notarized (e.g., a local
dev build), macOS will block it. To allow it to run:

```bash
xattr -cr MeedyaConverter.app
```

Or for a DMG:

```bash
xattr -cr MeedyaConverter-0.1.0-macOS.dmg
```

Alternatively, right-click the app in Finder and select "Open" to bypass
Gatekeeper for that specific launch.

---

## Full Pipeline

To run the complete local build pipeline (clean, build, test, package, DMG):

```bash
make all
```

---

## Troubleshooting

### `swift build` fails with missing dependencies

```bash
swift package resolve
swift package clean
swift build
```

### "MeedyaConverter.app is damaged and can't be opened"

This is a Gatekeeper quarantine issue. Remove the quarantine attribute:

```bash
xattr -cr MeedyaConverter.app
```

### Code signing fails with "no identity found"

Ensure your Developer ID certificate is installed in the login keychain:

```bash
security find-identity -v -p codesigning
```

If no identities are listed, you need to install your certificate from the
Apple Developer portal or Xcode.

### Build number shows "1" instead of the commit count

Ensure you have a full git history (not a shallow clone):

```bash
git fetch --unshallow
```

### Tests fail in release mode but pass in debug

Release builds enable optimisations that can surface latent issues. Check for
uninitialised variables, race conditions, or assumptions about execution order.

### FFmpeg not found

FFmpeg is optional for most operations. If you need external codec support:

```bash
brew install ffmpeg
```

### `make lint` fails

Install SwiftLint:

```bash
brew install swiftlint
```

---

## Version Management

The project version is stored in the `VERSION` file at the repository root.
To change it:

```bash
echo "1.0.0" > VERSION
make version   # Verify
```

The Makefile reads this file for all version-dependent operations (bundle
creation, DMG naming, etc.).
