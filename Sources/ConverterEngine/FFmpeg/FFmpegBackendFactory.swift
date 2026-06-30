// ============================================================================
// MeedyaConverter — FFmpegBackendFactory
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegBackendFactory

/// Picks the right `FFmpegBackend` implementation for the running build:
///
///   * `#if APP_STORE` (App Store Lite, sandboxed) → `FFmpegKitBackend`.
///   * Otherwise (Direct distribution, CLI, library, test bundles)
///     → `ProcessFFmpegBackend`.
///
/// The `APP_STORE` SwiftSetting define is applied to the
/// ConverterEngine target only when `APP_STORE=1` is in the build
/// environment at SPM resolve time — see `Package.swift`'s
/// `appStoreSwiftSettings` array. In a default build neither the
/// define nor the FFmpegKit dependency is present, so the factory
/// always returns the Process backend.
///
/// Usage in new code:
/// ```swift
/// let backend = FFmpegBackendFactory.makeDefault()
/// let result = try await backend.runFFmpegOneShot(
///     arguments: ["-i", path, "-c:v", "copy", out],
///     timeout: 60
/// )
/// ```
///
/// Existing call sites that launch `Foundation.Process` directly
/// (CropDetector, HardwareEncoderDetector, AIUpscaler, ProResToVector-
/// Converter, PQToHLGPipeline, ImageConverter, FFmpegProbe, the GUI
/// views, etc.) CONTINUE TO WORK without migration. They will be
/// moved over to the factory one file at a time in follow-up cycles,
/// so each migration is bisectable and the App Store build can be
/// incrementally enabled file-by-file.
public enum FFmpegBackendFactory {

    /// The default backend for the current build configuration. Always
    /// returns a fresh instance — backends are cheap to construct
    /// (`ProcessFFmpegBackend` does a single `FFmpegBundleManager`
    /// init; `FFmpegKitBackend` does nothing).
    ///
    /// Callers that want a long-lived backend instance (e.g. a worker
    /// queue) should cache the returned value themselves.
    public static func makeDefault() -> any FFmpegBackend {
        #if APP_STORE
        return FFmpegKitBackend()
        #else
        return ProcessFFmpegBackend()
        #endif
    }

    /// Explicit Process-backed backend. Useful for CLI tests and for
    /// code paths that need the Process backend even in App Store
    /// builds (which there shouldn't be — but a clearly-named alias
    /// reads better than a `#if APP_STORE` ladder at the call site).
    public static func makeProcess(
        bundleManager: FFmpegBundleManager = FFmpegBundleManager()
    ) -> ProcessFFmpegBackend {
        ProcessFFmpegBackend(bundleManager: bundleManager)
    }

    #if APP_STORE
    /// Explicit FFmpegKit-backed backend. Only available in App Store
    /// builds (the FFmpegKit framework is conditional on the same
    /// build flag).
    public static func makeFFmpegKit() -> FFmpegKitBackend {
        FFmpegKitBackend()
    }
    #endif
}
