// ============================================================================
// MeedyaConverter — FFmpegKitBackend (App Store Lite — sandboxed)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - FFmpegKitBackend
// ---------------------------------------------------------------------------
//
// The `FFmpegBackend` implementation that runs ffmpeg/ffprobe in-process
// via the FFmpegKit XCFramework. This is the **App Store Lite**
// distribution path: Apple's App Sandbox forbids `Process` launches
// (the Direct backend), so we link FFmpegKit's libraries instead.
//
// Activation
// ----------
// This file is gated on `#if APP_STORE`. The corresponding SwiftSetting
// define is applied to the ConverterEngine target's `swiftSettings`
// only when `APP_STORE=1` is in the environment at `swift package
// resolve` time — see `Package.swift`'s `appStoreSwiftSettings` array.
// In a default Direct build neither this file nor the FFmpegKit
// dependency is compiled or linked.
//
// Scaffolding status
// ------------------
// As of this scaffold cycle the file is INTENTIONALLY STUBBED. All
// methods throw `FFmpegBackendError.notImplemented` with a clear label.
// The autopilot's mission scope for the App Store ship is explicitly
// deferred — only the protocol surface needs to exist now so that
// (a) follow-up cycles can fill in each method, (b) the existing
// Direct call sites can incrementally migrate to the `FFmpegBackend`
// protocol without waiting for App Store readiness, and (c) the
// FFmpegBackendFactory has a real type to instantiate when
// `#if APP_STORE` is true.
//
// FFmpegKit API references
// ------------------------
// When fleshing out the stubs, the FFmpegKit Swift API to use:
//
//   * Streaming encode:
//       `FFmpegKit.executeAsync(_ command: String, withExecuteCallback:
//        withLogCallback: withStatisticsCallback: )`
//     The `Statistics` callback fires with frame count, fps, bitrate,
//     out_time_ms, and total_size — map these to `FFmpegProgressInfo`
//     the same way `FFmpegProcessController.parseProgress` does for
//     the Process backend.
//
//   * One-shot ffmpeg:
//       `FFmpegKit.execute(_ command: String) -> FFmpegSession`
//     `session.getReturnCode()` is the exit-code analogue,
//     `session.getOutput()` returns the combined stdout/stderr capture.
//     Split into stdout/stderr is not straightforward via the public
//     API — likely accept the limitation and put the combined output
//     in `stderr` (where ffmpeg writes its diagnostics anyway), leaving
//     `stdout` empty.
//
//   * Ffprobe:
//       `FFprobeKit.execute(_ command: String) -> FFprobeSession`
//     Same shape as `FFmpegSession`.
//
//   * Cancellation:
//       `FFmpegKit.cancel()` cancels the most recent invocation;
//       `FFmpegKit.cancel(sessionId)` cancels a specific session.
//
// All these calls run on a background dispatch queue managed by
// FFmpegKit internally — no manual threading required.
//
// The FFmpegKit SPM dependency is wired into `Package.swift`'s
// `ffmpegKitPackageDependencies` array; consuming the product happens
// via `.product(name: "ffmpegkit-macos", package: "ffmpeg-kit")` in
// `ffmpegKitConverterEngineDeps`. Add `import ffmpegkit_macos` (or
// whatever the product's Swift module name turns out to be — check
// the SPM resolution log) below the `#if APP_STORE` guard once the
// dependency resolves.
//
// ---------------------------------------------------------------------------

#if APP_STORE

// import ffmpegkit_macos   // TODO: uncomment when FFmpegKit SPM module is verified

/// FFmpegKit-backed `FFmpegBackend` implementation for sandboxed App
/// Store builds. See file overview comments for the FFmpegKit API
/// mapping and the activation gate.
///
/// **Status: scaffold only.** All methods currently throw
/// `FFmpegBackendError.notImplemented`. App Store ship is deferred
/// per the autopilot's mission scope; flesh out each method in a
/// dedicated follow-up cycle alongside enabling the corresponding
/// call site.
public final class FFmpegKitBackend: FFmpegBackend, @unchecked Sendable {

    public init() {}

    // MARK: - Streaming encode

    public func runEncode(
        arguments: [String],
        sourceDuration: TimeInterval?
    ) -> AsyncThrowingStream<FFmpegProgressInfo, Error> {
        AsyncThrowingStream { continuation in
            // TODO: bridge to FFmpegKit.executeAsync with a Statistics
            // callback that yields FFmpegProgressInfo, an Execute
            // callback that finishes the stream with the appropriate
            // success/failure verdict, and a Log callback that buffers
            // stderr for inclusion in a non-zero-exit error.
            continuation.finish(throwing: FFmpegBackendError.notImplemented(
                "FFmpegKitBackend.runEncode (streaming encode)"
            ))
        }
    }

    // MARK: - One-shot ffmpeg / ffprobe

    public func runFFmpegOneShot(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult {
        // TODO: bridge to FFmpegKit.execute / wait on FFmpegSession;
        // map ReturnCode to FFmpegBackendError.nonZeroExit on failure,
        // FFmpegOneShotResult on success.
        throw FFmpegBackendError.notImplemented(
            "FFmpegKitBackend.runFFmpegOneShot (one-shot ffmpeg invocation)"
        )
    }

    public func runFFprobe(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult {
        // TODO: bridge to FFprobeKit.execute / wait on FFprobeSession;
        // same mapping as runFFmpegOneShot.
        throw FFmpegBackendError.notImplemented(
            "FFmpegKitBackend.runFFprobe (one-shot ffprobe invocation)"
        )
    }

    // MARK: - Cancel

    public func cancelCurrent() async {
        // TODO: call FFmpegKit.cancel() to cancel the most recent
        // invocation. If we ever support concurrent invocations,
        // switch to FFmpegKit.cancel(sessionId) per tracked session.
    }
}

#endif  // APP_STORE
