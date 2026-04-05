<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Building from Source

This guide covers compiling MeedyaConverter from source using Swift Package Manager.

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|-------------|----------------|-------|
| **macOS** | 15.0 (Sequoia) | Required for Swift 6 runtime and SwiftUI APIs |
| **Xcode** | 16.0+ | Provides the Swift toolchain and macOS SDK |
| **Swift** | 6.0+ | Swift 6 language mode with strict concurrency |
| **FFmpeg** | 6.0+ | Required at runtime for encoding (not at build time) |
| **Git** | Any recent version | For cloning the repository |

### Optional Dependencies

| Tool | Purpose | When Needed |
|------|---------|-------------|
| **Sparkle 2** | Auto-update framework | DIRECT distribution builds only |
| **FFmpegKit** | Embedded FFmpeg XCFramework | APP_STORE builds only |
| **dovi_tool** | Dolby Vision RPU handling | Dolby Vision workflows |
| **hlg-tools** | PQ to HLG conversion | HDR conversion workflows |
| **MediaInfo** | Extended media analysis | Optional enhanced probing |

---

## Clone the Repository

```bash
git clone https://github.com/MWBMPartners/MeedyaConverter.git
cd MeedyaConverter
```

---

## Build

### Standard Build

```bash
swift build
```

This builds all three targets:
- `ConverterEngine` (library)
- `meedya-convert` (CLI executable)
- `MeedyaConverter` (SwiftUI app)

### Release Build

```bash
swift build -c release
```

The built products are located at `.build/release/`.

### Build Variants

MeedyaConverter supports build-time flags to control optional dependencies:

```bash
# Direct distribution build (includes Sparkle for auto-updates)
DIRECT=1 swift build

# App Store build (includes FFmpegKit)
APP_STORE=1 swift build

# Standard build (no conditional dependencies)
swift build
```

### Build a Specific Target

```bash
# Build only the CLI tool
swift build --target meedya-convert

# Build only the engine library
swift build --target ConverterEngine
```

---

## Run

### CLI Tool

```bash
# Run directly via swift
swift run meedya-convert probe --input test.mkv

# Or use the built binary
.build/debug/meedya-convert probe --input test.mkv
```

### SwiftUI App

```bash
swift run MeedyaConverter
```

Or open the package in Xcode and run the `MeedyaConverter` scheme.

---

## Test

### Run All Tests

```bash
swift test
```

### Run Specific Test Targets

```bash
# Engine tests only
swift test --filter ConverterEngineTests

# CLI tests only
swift test --filter MeedyaConvertTests
```

### Test with Verbose Output

```bash
swift test --verbose
```

---

## Project Structure

```
MeedyaConverter/
├── Package.swift              # SPM manifest
├── Sources/
│   ├── ConverterEngine/       # Shared library (no UI code)
│   │   ├── Models/            # Data types (MediaFile, codecs, containers)
│   │   ├── Encoding/          # Job, engine, profiles, per-stream settings
│   │   ├── FFmpeg/            # Argument builder, process controller, probe
│   │   ├── HDR/               # HDR policy, tone mapping, DV/HLG pipelines
│   │   ├── Audio/             # Audio processing, spatial audio
│   │   ├── Subtitles/         # Subtitle conversion
│   │   ├── Manifest/          # HLS/DASH generation
│   │   ├── Disc/              # Optical disc ripping and authoring
│   │   ├── Cloud/             # Upload providers, media server notifications
│   │   ├── Backend/           # Encoding backend protocol
│   │   ├── Platform/          # Platform-specific format policies
│   │   └── Utilities/         # Temp files, disk monitoring
│   ├── meedya-convert/        # CLI tool
│   │   ├── Commands/          # Subcommands (encode, probe, batch, etc.)
│   │   └── MeedyaConvert.swift # Entry point (@main)
│   └── MeedyaConverter/       # SwiftUI app
│       ├── Views/             # SwiftUI views
│       ├── ViewModels/        # @Observable view models
│       ├── Components/        # Reusable UI components
│       ├── Services/          # App services
│       └── Resources/         # Assets, Info.plist
├── Tests/
│   ├── ConverterEngineTests/  # Engine unit tests
│   └── MeedyaConvertTests/    # CLI unit tests
├── docs/                      # Wiki documentation
├── help/                      # In-app help files
├── scripts/                   # Build and CI scripts
└── Tools/                     # Development tools
```

---

## Troubleshooting Builds

### "No such module" Errors

Run `swift package resolve` to fetch dependencies:

```bash
swift package resolve
swift build
```

### Xcode Build Issues

If building in Xcode, ensure:

1. The package is opened via File > Open (select the `Package.swift`).
2. The correct scheme is selected (`meedya-convert` or `MeedyaConverter`).
3. The macOS deployment target is set to 15.0+.

### Concurrency Warnings

MeedyaConverter uses Swift 6 strict concurrency. If you see `Sendable` warnings, ensure all types crossing concurrency boundaries conform to `Sendable` and use `@Sendable` closures.

---

## Installing FFmpeg for Development

FFmpeg is needed at runtime, not at build time. Install it via Homebrew:

```bash
brew install ffmpeg
```

Verify the installation:

```bash
ffmpeg -version
ffprobe -version
```

MeedyaConverter searches for FFmpeg in this order:
1. Bundled binary (in the app bundle).
2. Homebrew paths (`/opt/homebrew/bin/`, `/usr/local/bin/`).
3. System PATH.
