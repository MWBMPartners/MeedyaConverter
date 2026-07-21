// ============================================================================
// MeedyaConverter — FFmpegBackend protocol (low-level ffmpeg/ffprobe invocation)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
//
// `FFmpegBackend` is the LOW-LEVEL abstraction over actually invoking the
// `ffmpeg` and `ffprobe` binaries. It is distinct from `EncodingBackend`
// in `Backend/EncodingBackend.swift`:
//
//   * `EncodingBackend` is the HIGH-LEVEL job-orchestration boundary
//     (encode a complete `EncodingJob`, probe a `MediaFile`). It is
//     where the job queue, the UI progress bindings, and the public
//     CLI all attach.
//
//   * `FFmpegBackend` (this file) is the COMMAND-LEVEL boundary —
//     "given this argument vector, run ffmpeg and stream its progress"
//     or "run ffprobe and give me the JSON output". Everything below
//     `EncodingBackend` ultimately routes here.
//
// Why two layers? The high-level job model is stable across the lifetime
// of the project. The low-level invocation, however, has to differ
// fundamentally between the **Direct** (Developer-ID signed) build and
// the **App Store Lite** (sandboxed) build:
//
//   * Direct builds spawn the bundled `ffmpeg` binary via
//     `Foundation.Process`. This is the Process backend
//     (`ProcessFFmpegBackend.swift`).
//
//   * App Store builds cannot spawn arbitrary subprocesses — Apple's
//     sandbox forbids it. They use the FFmpegKit XCFramework, which
//     embeds ffmpeg's libraries and runs them in-process. This is the
//     FFmpegKit backend (`FFmpegKitBackend.swift`), gated behind
//     `#if APP_STORE` and conditionally added to `Package.swift` only
//     when `APP_STORE=1` is set in the build environment.
//
// `FFmpegBackendFactory.swift` picks the right one for the current build.
//
// ---------------------------------------------------------------------------
// MARK: - Migration plan for existing call sites
// ---------------------------------------------------------------------------
//
// As of the scaffold cycle that introduces this file, the existing
// call sites in `FFmpeg/CropDetector.swift`,
// `FFmpeg/HardwareEncoderDetector.swift`, `FFmpeg/AIUpscaler.swift`,
// `FFmpeg/ProResToVectorConverter.swift`, `FFmpeg/PQToHLGPipeline.swift`,
// `FFmpeg/ImageConverter.swift`, `FFmpeg/FFmpegProbe.swift`,
// `Encoding/PostEncodeActions.swift`, and the GUI views
// (`EmailSettingsView`, `ImageConversionView`, `BurnSettingsView`,
// `VoiceIsolationView`) all instantiate `Foundation.Process` directly.
//
// They CONTINUE TO WORK unchanged. The new protocol is the migration
// TARGET for follow-up cycles, not a forced refactor right now. Each
// existing call site will move over to the backend in its own focused
// cycle (one file at a time) so that any regression is bisectable and
// the App Store build can be incrementally enabled file-by-file with
// `#if APP_STORE` guards as the migration progresses.
//
// New code SHOULD use the backend from day one — instantiate it via
// `FFmpegBackendFactory.makeDefault()` rather than calling `Process()`
// directly.
// ---------------------------------------------------------------------------

// MARK: - FFmpegBackendError

/// Errors that can be returned by any `FFmpegBackend` implementation.
///
/// This is intentionally a small superset of `FFmpegProcessError` (in
/// `FFmpegProcessController.swift`) — the Process backend bridges
/// `FFmpegProcessError` to these cases, and the FFmpegKit backend
/// raises the same cases for parallel failure modes (a non-zero
/// FFmpegKit `ReturnCode`, an in-process exception, etc.).
public enum FFmpegBackendError: LocalizedError, Sendable {

    /// The invocation exited with a non-zero status. For the Process
    /// backend this is the actual exit code; for the FFmpegKit backend
    /// this is the `ReturnCode.value`. `stderr` carries whatever the
    /// underlying invocation captured.
    case nonZeroExit(exitCode: Int32, stderr: String)

    /// The caller invoked `cancelCurrent()` during execution.
    case cancelled

    /// The invocation timed out (the backend can configure the cap).
    case timeout

    /// No `ffmpeg` / `ffprobe` binary is available. For the Process
    /// backend this means `FFmpegBundleManager` resolved nothing; for
    /// the FFmpegKit backend this should never fire because the
    /// framework is statically linked.
    case noBinary

    /// The backend is already running another invocation and cannot
    /// start a second concurrent one. The Process backend is currently
    /// single-cursor; the FFmpegKit backend may relax this in future.
    case alreadyRunning

    /// The backend's specific implementation is not yet present
    /// (e.g. the FFmpegKit backend's stub methods). Carries a brief
    /// description of which capability is missing so the caller can
    /// surface a clear "Not supported in this build" message.
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            return "FFmpeg exited with status \(code): \(stderr.prefix(500))"
        case .cancelled:
            return "FFmpeg invocation was cancelled."
        case .timeout:
            return "FFmpeg invocation timed out."
        case .noBinary:
            return "No FFmpeg binary is available in this build."
        case .alreadyRunning:
            return "An FFmpeg invocation is already in progress."
        case .notImplemented(let what):
            return "Not supported in this build: \(what)"
        }
    }
}

// MARK: - FFmpegOneShotResult

/// Result of a short, non-streaming ffmpeg/ffprobe invocation. Used by
/// detectors (crop, hardware-encoder probe, codec info) that need the
/// full stdout/stderr output rather than a streaming progress feed.
public struct FFmpegOneShotResult: Sendable {

    /// The exit code reported by the underlying invocation.
    public let exitCode: Int32

    /// Captured stdout. May be large for `ffprobe -print_format json`
    /// over long files; callers can stream-parse if needed.
    public let stdout: String

    /// Captured stderr. Carries ffmpeg's progress / diagnostic chatter.
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

// MARK: - FFmpegBackend

/// Low-level boundary over the ffmpeg/ffprobe invocation surface.
///
/// Implementations:
///
///   * `ProcessFFmpegBackend` — launches `Foundation.Process` against the
///     bundled (or system-installed) `ffmpeg` / `ffprobe` binaries.
///     Default for the **Direct** build.
///
///   * `FFmpegKitBackend` (`#if APP_STORE`) — calls FFmpegKit's
///     in-process API. Required for the App Store Lite build because
///     the App Sandbox forbids `Process` launches.
///
/// Pick one via `FFmpegBackendFactory.makeDefault()` rather than
/// instantiating directly.
///
/// All methods are `async`; the streaming `runEncode(...)` method
/// returns an `AsyncThrowingStream` so the caller can observe progress
/// in real time and so that cancellation cleanly tears down the
/// underlying invocation.
public protocol FFmpegBackend: Sendable {

    // MARK: - Streaming encode

    /// Runs `ffmpeg` with the given argument vector and streams progress
    /// updates as the encode proceeds.
    ///
    /// The returned `AsyncThrowingStream`:
    ///   * Emits `FFmpegProgressInfo` values as ffmpeg reports progress.
    ///   * Throws an `FFmpegBackendError` if the encode fails.
    ///   * Completes normally when the encode succeeds (exit code 0).
    ///
    /// `sourceDuration` is used to convert ffmpeg's reported `out_time`
    /// into a normalised progress fraction. If unknown, pass `nil` and
    /// progress will emit time updates only.
    ///
    /// Implementations should ensure that cancelling the stream's
    /// consumer (via `Task` cancellation) cleanly tears down the
    /// underlying invocation and removes any partial output files.
    func runEncode(
        arguments: [String],
        sourceDuration: TimeInterval?
    ) -> AsyncThrowingStream<FFmpegProgressInfo, Error>

    // MARK: - One-shot invocations

    /// Runs `ffmpeg` with the given argument vector to completion and
    /// returns its full stdout/stderr capture. Use for short, non-
    /// streaming invocations (crop detect, hardware-encoder probe,
    /// quick metadata operations). For real encodes use `runEncode`.
    ///
    /// Throws `FFmpegBackendError.nonZeroExit` if the binary returned
    /// a non-zero status, with stderr included in the error.
    func runFFmpegOneShot(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult

    /// Runs `ffprobe` with the given argument vector. Used by
    /// `FFmpegProbe` for media inspection. The caller is responsible
    /// for adding the JSON-output flags (`-print_format json`) if they
    /// want structured output.
    ///
    /// Throws `FFmpegBackendError.nonZeroExit` on non-zero status.
    func runFFprobe(
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> FFmpegOneShotResult

    // MARK: - Cancellation

    /// Cancels any currently-running invocation. Idempotent; safe to
    /// call when nothing is running. Streaming consumers should also
    /// receive `FFmpegBackendError.cancelled` from their stream.
    func cancelCurrent() async
}
