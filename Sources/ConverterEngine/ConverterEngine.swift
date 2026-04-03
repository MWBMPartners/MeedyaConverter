// ============================================================================
// MeedyaConverter — ConverterEngine module entry point
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// `ConverterEngine` is the platform-agnostic core of MeedyaConverter. It
// provides all transcoding, probing, manifest-generation, and delivery logic
// without any dependency on AppKit, SwiftUI, or other GUI frameworks.
//
// Both the CLI (`meedya-convert`) and the macOS app (`MeedyaConverter`)
// import this module to access:
//
//   - Media probing (via FFprobe or AVFoundation)
//   - Encoding job creation, scheduling, and execution
//   - Encoding profiles (YAML-backed, codec-aware presets)
//   - HLS / DASH manifest generation
//   - Subtitle extraction and format conversion
//   - HDR metadata parsing and tone-mapping helpers
//   - Cloud upload adapters (S3, GCS, Backblaze B2)
//   - Structured logging through swift-log
//
// This file serves as the public facade of the module. It exposes the
// library version and a convenience namespace for discovery / diagnostics.
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - ConverterEngine
// ---------------------------------------------------------------------------
/// The top-level namespace for the MeedyaConverter encoding engine.
///
/// `ConverterEngine` itself is a lightweight value type that carries no state.
/// Its primary purpose is to:
///
/// 1. **Expose the library version** — useful for log preambles, `--version`
///    flags in the CLI, and the "About" window in the GUI app.
///
/// 2. **Act as a discovery point** — downstream consumers can check
///    `ConverterEngine.version` at runtime to verify that the expected
///    engine build is linked.
///
/// 3. **Provide a future extension surface** — factory methods for creating
///    pre-configured `EncodingBackend` instances, default profile bundles,
///    and diagnostic reports will be added here as the engine matures.
///
/// ### Thread Safety
/// `ConverterEngine` is `Sendable` by virtue of containing only immutable,
/// compile-time-constant stored properties. It is safe to reference from any
/// actor or task without synchronization.
// ---------------------------------------------------------------------------
public struct ConverterEngine: Sendable {

    // ---------------------------------------------------------------------
    // MARK: Version
    // ---------------------------------------------------------------------
    /// Semantic version string for the ConverterEngine module.
    ///
    /// This value follows [Semantic Versioning 2.0.0](https://semver.org):
    ///   - **Major** — incremented for breaking API changes.
    ///   - **Minor** — incremented for backwards-compatible new features.
    ///   - **Patch** — incremented for backwards-compatible bug fixes.
    ///
    /// The version is a static constant so it can be read without
    /// instantiating a `ConverterEngine` value:
    /// ```swift
    /// print(ConverterEngine.version) // "0.1.0"
    /// ```
    ///
    /// During development (0.x.y), the public API is not yet considered
    /// stable and may change between minor versions.
    // ---------------------------------------------------------------------
    public static let version: String = "0.1.0"

    // ---------------------------------------------------------------------
    // MARK: Build Metadata
    // ---------------------------------------------------------------------
    /// A human-readable identifier for the engine build.
    ///
    /// Combines the module name with the semantic version. This string is
    /// suitable for embedding in log preambles, user-agent headers for
    /// cloud uploads, and diagnostic reports:
    /// ```
    /// [ConverterEngine/0.1.0] Starting encode job abc-123 ...
    /// ```
    // ---------------------------------------------------------------------
    public static let buildIdentifier: String = "ConverterEngine/\(version)"

    // ---------------------------------------------------------------------
    // MARK: Initializer
    // ---------------------------------------------------------------------
    /// Creates a new `ConverterEngine` instance.
    ///
    /// The initializer is intentionally public and parameter-free. In the
    /// future it may accept a `Configuration` value to customize logging,
    /// concurrency limits, or default profile paths.
    // ---------------------------------------------------------------------
    public init() {}
}
