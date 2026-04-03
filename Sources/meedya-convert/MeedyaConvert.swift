// ============================================================================
// MeedyaConverter — CLI tool entry point
// Copyright (c) 2026-2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// This file defines the entry point for `meedya-convert`, the command-line
// interface to MeedyaConverter's encoding engine.
//
// The CLI is designed for three primary use cases:
//
//   1. **CI/CD pipelines** — Automated transcoding triggered by GitHub
//      Actions, Jenkins, or similar systems after media assets are ingested.
//
//   2. **Batch processing** — Shell scripts that loop over directories of
//      source files and produce encoded outputs with consistent profiles.
//
//   3. **Remote encoding** — SSH sessions on headless render-farm nodes
//      where no GUI is available.
//
// ### Architecture
// The CLI is a thin layer over `ConverterEngine`. It:
//   - Parses command-line arguments (via swift-argument-parser, when enabled)
//   - Constructs an `EncodingJob` from the parsed options
//   - Instantiates the appropriate `EncodingBackend`
//   - Runs the job and reports progress to stderr / results to stdout
//   - Exits with POSIX-compliant status codes (0 = success, 1 = error)
//
// ### Planned Subcommands
//   meedya-convert encode   --input <file> --profile <name> [--output <dir>]
//   meedya-convert probe    --input <file> [--format json|yaml|text]
//   meedya-convert manifest --type hls|dash --input <master> [--output <dir>]
//   meedya-convert profiles --list | --show <name> | --validate <path>
//
// ### swift-argument-parser Integration
// Once the `swift-argument-parser` dependency is uncommented in Package.swift,
// this file will be refactored to use `ParsableCommand` with `@Argument`,
// `@Option`, and `@Flag` property wrappers. The current implementation uses
// a plain `@main` struct with a static `main()` method as a temporary
// bootstrapping approach.
// ---------------------------------------------------------------------------

import Foundation
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - MeedyaConvert (Entry Point)
// ---------------------------------------------------------------------------
/// The root command for the `meedya-convert` CLI tool.
///
/// This struct is annotated with `@main` to designate it as the process
/// entry point. Swift synthesises the platform-appropriate `main()` call
/// site (Darwin `_main`, Linux entry, etc.) from this attribute.
///
/// ### Why a static `main()` instead of `ParsableCommand.run()`?
/// The `swift-argument-parser` dependency is currently commented out in
/// `Package.swift`. Once it is enabled, this struct will conform to
/// `AsyncParsableCommand` and the static `main()` will be replaced by
/// the argument-parser runtime's entry point, which provides automatic
/// help generation, error formatting, and shell completion scripts.
///
/// ### Migration Path
/// When swift-argument-parser is enabled:
/// ```swift
/// import ArgumentParser
///
/// @main
/// struct MeedyaConvert: AsyncParsableCommand {
///     static let configuration = CommandConfiguration(
///         commandName: "meedya-convert",
///         abstract: "Transcode, probe, and package media files.",
///         version: ConverterEngine.version,
///         subcommands: [Encode.self, Probe.self, Manifest.self, Profiles.self]
///     )
/// }
/// ```
// ---------------------------------------------------------------------------
@main
struct MeedyaConvert {

    // ---------------------------------------------------------------------
    // MARK: - Static Entry Point
    // ---------------------------------------------------------------------
    /// The process entry point.
    ///
    /// This method serves as a minimal bootstrapping shim until the full
    /// argument-parser integration is in place. It:
    ///
    /// 1. Prints the engine build identifier so the user can verify which
    ///    version is running.
    /// 2. Exits cleanly with status code 0.
    ///
    /// ### Concurrency Note
    /// The method is intentionally synchronous. Once `AsyncParsableCommand`
    /// is adopted, the runtime will set up a cooperative thread pool and
    /// this will become an `async` method.
    // ---------------------------------------------------------------------
    static func main() {
        // -----------------------------------------------------------------
        // Print a banner with the engine version. This is useful for CI
        // logs where operators need to confirm which build produced the
        // output artifacts.
        // -----------------------------------------------------------------
        print("""
            meedya-convert \(ConverterEngine.version)
            \(ConverterEngine.buildIdentifier)

            Usage: meedya-convert <command> [options]

            Available commands:
              encode      Transcode a media file using a named profile
              probe       Inspect a media file and print its metadata
              manifest    Generate HLS/DASH manifests
              profiles    List, show, or validate encoding profiles

            Run 'meedya-convert <command> --help' for details.
            """)
    }
}
