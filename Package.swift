// ============================================================================
// MeedyaConverter — Swift Package Manager manifest
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Swift Tools Version
// ---------------------------------------------------------------------------
// Declares the minimum version of the Swift Package Manager required to build
// this package. Version 6.0 enables Swift 6-era features including strict
// concurrency checking, full Sendable enforcement, and the latest macro APIs.
// ---------------------------------------------------------------------------
// swift-tools-version: 6.0

import PackageDescription

// ---------------------------------------------------------------------------
// MARK: - Build-Configuration Flags
// ---------------------------------------------------------------------------
// These environment-driven flags allow the CI pipeline (or a local developer)
// to toggle dependency sets at resolve-time without editing the manifest.
//
//   APP_STORE   - When set, pulls in FFmpegKit (the GPL-free, App-Store-safe
//                 build of FFmpeg wrapped as an XCFramework).
//   DIRECT      - When set, pulls in Sparkle for auto-update support.
//                 Sparkle is not permitted in App Store builds because Apple
//                 requires updates to go through the Mac App Store.
//
// Usage:
//   DIRECT=1 swift build          # Includes Sparkle
//   APP_STORE=1 swift build       # Includes FFmpegKit
//   swift build                   # Neither conditional dependency
// ---------------------------------------------------------------------------
// Note: ProcessInfo is available in Package.swift via Foundation (implicitly
// imported by the Swift package manifest runtime). Uncomment these lines when
// the conditional Sparkle / FFmpegKit dependencies below are activated.
//
// let isDirectBuild  = ProcessInfo.processInfo.environment["DIRECT"] != nil
// let isAppStoreBuild = ProcessInfo.processInfo.environment["APP_STORE"] != nil

// ---------------------------------------------------------------------------
// MARK: - Package Definition
// ---------------------------------------------------------------------------
let package = Package(

    // ---------------------------------------------------------------------
    // Package Identity
    // ---------------------------------------------------------------------
    // The package name is used as the default module name for targets that
    // do not specify an explicit module name. It also appears in dependency
    // resolution graphs and lock files.
    // ---------------------------------------------------------------------
    name: "MeedyaConverter",

    // ---------------------------------------------------------------------
    // Supported Platforms
    // ---------------------------------------------------------------------
    // macOS 15.0 (Sequoia) is required for:
    //   - Swift 6 runtime support (strict concurrency, typed throws)
    //   - AVFoundation improvements for HDR tone-mapping
    //   - SwiftUI enhancements (Inspector, custom containers)
    //   - Foundation.URL modern API surface
    // ---------------------------------------------------------------------
    platforms: [
        .macOS(.v15)
    ],

    // ---------------------------------------------------------------------
    // MARK: Products
    // ---------------------------------------------------------------------
    // Products define what this package vends to external consumers. Even
    // though `meedya-convert` and `MeedyaConverter` are executables (not
    // importable libraries), they are listed here so that higher-level
    // packages or Xcode workspaces can reference them as build targets.
    // ---------------------------------------------------------------------
    products: [
        // The core encoding/transcoding engine, importable by both the CLI
        // and the GUI app, as well as by any future plugins or extensions.
        .library(
            name: "ConverterEngine",
            targets: ["ConverterEngine"]
        ),

        // Command-line tool for headless / CI-driven transcoding.
        .executable(
            name: "meedya-convert",
            targets: ["meedya-convert"]
        ),

        // Full macOS SwiftUI application with drag-and-drop, queue
        // management, and real-time FFmpeg progress monitoring.
        .executable(
            name: "MeedyaConverter",
            targets: ["MeedyaConverter"]
        ),
    ],

    // ---------------------------------------------------------------------
    // MARK: Dependencies
    // ---------------------------------------------------------------------
    // Each dependency is commented out until the corresponding integration
    // work is ready to begin. The URLs and version pins are recorded here
    // so that developers can uncomment them without hunting for the correct
    // repository or compatible version range.
    //
    // Version pins use `.upToNextMinor` semantics where noted; otherwise
    // the default `.upToNextMajor` (the `~>` operator) is used.
    // ---------------------------------------------------------------------
    dependencies: [

        // -- swift-argument-parser ----------------------------------------
        // Provides the `@Argument`, `@Option`, `@Flag` property wrappers
        // and the `ParsableCommand` protocol used by `meedya-convert`.
        // Repository : https://github.com/apple/swift-argument-parser.git
        // Pin        : ~> 1.5.0
        // .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),

        // -- swift-log ----------------------------------------------------
        // Apple's structured logging facade. All subsystems log through
        // `Logger` so that the CLI and GUI can attach different log handlers
        // (stderr, OSLog, file rotation, etc.) without changing engine code.
        // Repository : https://github.com/apple/swift-log.git
        // Pin        : ~> 1.6.0
        // .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),

        // -- swift-collections --------------------------------------------
        // Adds `OrderedDictionary`, `Deque`, and `Heap` — useful for the
        // encoding queue, manifest track ordering, and priority scheduling.
        // Repository : https://github.com/apple/swift-collections.git
        // Pin        : ~> 1.1.0
        // .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),

        // -- KeychainAccess -----------------------------------------------
        // Type-safe wrapper around the macOS Keychain. Used for storing
        // cloud-provider OAuth tokens and API keys securely.
        // Repository : https://github.com/kishikawakatsumi/KeychainAccess.git
        // Pin        : ~> 4.2.2
        // .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),

        // -- SwiftSoup ----------------------------------------------------
        // HTML parser used when scraping metadata from web-based media
        // sources (e.g., YouTube info pages, embedded OG tags).
        // Repository : https://github.com/scinfu/SwiftSoup.git
        // Pin        : ~> 2.7.0
        // .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),

        // -- Yams ---------------------------------------------------------
        // YAML parser/emitter. Encoding profiles and batch job definitions
        // are authored in YAML for human readability. Yams handles the
        // serialization round-trip.
        // Repository : https://github.com/jpsim/Yams.git
        // Pin        : ~> 5.1.0
        // .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),

        // -- ZIPFoundation ------------------------------------------------
        // Pure-Swift ZIP archive library. Used for packaging completed
        // encode bundles (video + manifests + subtitles) for delivery.
        // Repository : https://github.com/weichsel/ZIPFoundation.git
        // Pin        : ~> 0.9.0
        // .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),

        // -----------------------------------------------------------------
        // Conditional / Build-Variant Dependencies
        // -----------------------------------------------------------------
        //
        // Sparkle (DIRECT builds only)
        // ----------------------------
        // Sparkle provides Cocoa-native auto-update functionality via the
        // EdDSA-signed appcast model. It is forbidden in Mac App Store
        // builds because Apple mandates that updates flow through the
        // App Store review process.
        //
        // Repository : https://github.com/sparkle-project/Sparkle.git
        // Pin        : ~> 2.6.0
        // Condition  : Only resolved when the DIRECT environment flag is set.
        //
        // if isDirectBuild {
        //     .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // }
        //
        // FFmpegKit (APP_STORE builds only)
        // ----------------------------------
        // FFmpegKit wraps FFmpeg (and its codec libraries) into an
        // XCFramework that can be embedded in sandboxed App Store apps.
        // For DIRECT builds, the system-installed FFmpeg binary is invoked
        // via Process (see FFmpegBackend), so this framework is not needed.
        //
        // Repository : https://github.com/arthenica/ffmpeg-kit.git
        // Pin        : ~> 6.0.0
        // Condition  : Only resolved when the APP_STORE environment flag is set.
        //
        // if isAppStoreBuild {
        //     .package(url: "https://github.com/arthenica/ffmpeg-kit.git", from: "6.0.0"),
        // }
    ],

    // ---------------------------------------------------------------------
    // MARK: Targets
    // ---------------------------------------------------------------------
    // Targets are the fundamental building blocks of this package. Each
    // target defines a Swift module, its source location, dependencies,
    // and any special build settings (e.g., Swift language mode).
    // ---------------------------------------------------------------------
    targets: [

        // =================================================================
        // ConverterEngine (Library)
        // =================================================================
        // The platform-agnostic core that houses:
        //   - Media probing (MediaFile, stream enumeration)
        //   - Encoding job definition and execution (EncodingJob, profiles)
        //   - FFmpeg process orchestration and argument building
        //   - HLS / DASH manifest generation
        //   - Subtitle extraction and conversion
        //   - HDR metadata handling and tone-mapping helpers
        //   - Cloud upload adapters (S3, GCS, Backblaze B2)
        //   - Progress reporting via AsyncStream
        //
        // Both the CLI (`meedya-convert`) and the GUI (`MeedyaConverter`)
        // depend on this target — no UI code lives here.
        // =================================================================
        .target(
            name: "ConverterEngine",
            dependencies: [
                // Uncomment as dependencies are integrated:
                // .product(name: "Logging", package: "swift-log"),
                // .product(name: "Collections", package: "swift-collections"),
                // .product(name: "KeychainAccess", package: "KeychainAccess"),
                // .product(name: "SwiftSoup", package: "SwiftSoup"),
                // .product(name: "Yams", package: "Yams"),
                // .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/ConverterEngine",
            swiftSettings: [
                // Enable strict concurrency checking at the "complete" level
                // to surface all Sendable violations at compile time. This is
                // the default in Swift 6 language mode, but we state it
                // explicitly for clarity and to prevent accidental regression
                // if the tools version were ever rolled back.
                .swiftLanguageMode(.v6),
            ]
        ),

        // =================================================================
        // meedya-convert (Executable — CLI)
        // =================================================================
        // A headless command-line tool designed for:
        //   - CI/CD pipelines (GitHub Actions, Jenkins, etc.)
        //   - Batch processing via shell scripts
        //   - Remote/SSH-based encoding on render farms
        //
        // Uses swift-argument-parser for ergonomic subcommand routing:
        //   meedya-convert encode --profile broadcast --input video.mov
        //   meedya-convert probe  --input video.mov --format json
        //   meedya-convert manifest --type hls --input master.m3u8
        // =================================================================
        .executableTarget(
            name: "meedya-convert",
            dependencies: [
                "ConverterEngine",
                // Uncomment when swift-argument-parser is integrated:
                // .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/meedya-convert",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // =================================================================
        // MeedyaConverter (Executable — macOS SwiftUI App)
        // =================================================================
        // The full graphical application featuring:
        //   - Drag-and-drop file import
        //   - Real-time encoding progress with waveform/bitrate graphs
        //   - Profile editor (YAML-backed, with visual preview)
        //   - Encoding queue with pause/resume/cancel per job
        //   - Cloud delivery dashboard
        //   - Preferences window with Sparkle update integration
        //
        // Declared as an `.executableTarget` rather than using an Xcode
        // project. SPM handles the Info.plist and entitlements via the
        // Resources directory.
        // =================================================================
        .executableTarget(
            name: "MeedyaConverter",
            dependencies: [
                "ConverterEngine",
                // Uncomment when dependencies are integrated:
                // .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MeedyaConverter",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // =================================================================
        // ConverterEngineTests (Unit Tests)
        // =================================================================
        // Tests for the ConverterEngine library covering:
        //   - Encoding profile parsing and validation
        //   - FFmpeg argument construction
        //   - Manifest generation (HLS/DASH output correctness)
        //   - Media probing result deserialization
        //   - Stream selection logic
        //   - Subtitle format conversion
        //
        // Test media fixtures live in Tests/ConverterEngineTests/Fixtures/.
        // =================================================================
        .testTarget(
            name: "ConverterEngineTests",
            dependencies: [
                "ConverterEngine",
            ],
            path: "Tests/ConverterEngineTests"
        ),

        // =================================================================
        // MeedyaConvertTests (Unit Tests)
        // =================================================================
        // Tests for the CLI tool covering:
        //   - Argument parsing and validation
        //   - Subcommand routing
        //   - Exit-code correctness
        //   - Help text generation
        //
        // These tests exercise the command layer in isolation by injecting
        // mock EncodingBackend instances.
        // =================================================================
        .testTarget(
            name: "MeedyaConvertTests",
            dependencies: [
                // Note: We depend on ConverterEngine rather than the
                // "meedya-convert" executable target because Swift does not
                // allow importing a module that contains a @main attribute
                // into a test target (the test harness has its own @main).
                // All testable CLI logic should be factored into
                // ConverterEngine or into non-@main helper files.
                "ConverterEngine",
            ],
            path: "Tests/MeedyaConvertTests"
        ),
    ]
)
