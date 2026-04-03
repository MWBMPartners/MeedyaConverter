// ============================================================================
// MeedyaConverter — Encoding backend protocol and supporting types
// Copyright (c) 2026-2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// This file defines the `EncodingBackend` protocol — the central abstraction
// that decouples the engine's job-scheduling layer from the actual media
// processing implementation.
//
// Two concrete backends are planned:
//
//   1. **FFmpegProcessBackend** — Spawns the system-installed `ffmpeg`
//      binary via `Foundation.Process`. Used in DIRECT (non-App-Store)
//      builds and in the CLI tool.
//
//   2. **FFmpegKitBackend** — Uses the FFmpegKit XCFramework to run
//      FFmpeg in-process. Required for sandboxed App Store builds where
//      launching external processes is prohibited.
//
// Both backends conform to `EncodingBackend` so the rest of the engine
// (job queue, progress UI bindings, error handling) can remain agnostic
// to the underlying execution strategy.
//
// This file also defines the placeholder value types that flow through
// the protocol:
//   - `EncodingJob`    — Describes *what* to encode (input, profile, output).
//   - `EncodingResult` — Describes the *outcome* of a completed encode.
//   - `MediaFile`      — Describes a probed media file's metadata.
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - EncodingJob
// ---------------------------------------------------------------------------
/// A value type that fully describes a single encoding task.
///
/// An `EncodingJob` captures everything the backend needs to produce an
/// output file (or set of files, in the case of HLS/DASH segmented output):
///
///   - The input file URL
///   - The encoding profile (codec, bitrate, resolution, etc.)
///   - The desired output location and container format
///   - Optional overrides (crop, trim, subtitle burn-in, HDR flags)
///
/// ### Design Notes
/// - `EncodingJob` is a struct (value type) so it can be safely passed
///   across actor boundaries without requiring `@Sendable` closures.
/// - It conforms to `Sendable` to satisfy Swift 6 strict concurrency.
/// - It conforms to `Identifiable` for SwiftUI list diffing in the queue.
///
/// ### Future Properties (to be added)
/// ```
/// public let id: UUID
/// public let input: URL
/// public let output: URL
/// public let profile: EncodingProfile
/// public let trim: ClosedRange<TimeInterval>?
/// public let subtitleBurnIn: Bool
/// public let hdrMode: HDRMode
/// ```
// ---------------------------------------------------------------------------
public struct EncodingJob: Sendable, Identifiable {
    /// Stable unique identifier for this job, generated at creation time.
    public let id: UUID

    /// Creates a new encoding job with a fresh UUID.
    ///
    /// Once the full property set is defined, this initializer will accept
    /// input/output URLs, the encoding profile, and optional overrides.
    public init() {
        self.id = UUID()
    }
}

// ---------------------------------------------------------------------------
// MARK: - EncodingResult
// ---------------------------------------------------------------------------
/// A value type that describes the outcome of a completed encoding task.
///
/// After a backend finishes processing an `EncodingJob`, it returns an
/// `EncodingResult` containing:
///
///   - Whether the job succeeded or failed
///   - The output file URL(s)
///   - Encoding statistics (duration, average bitrate, file size)
///   - Any warnings or non-fatal issues encountered
///
/// ### Future Properties (to be added)
/// ```
/// public let jobID: UUID
/// public let outputURL: URL
/// public let duration: TimeInterval
/// public let fileSize: Int64
/// public let averageBitrate: Int
/// public let warnings: [String]
/// ```
// ---------------------------------------------------------------------------
public struct EncodingResult: Sendable {
    /// Creates a new encoding result placeholder.
    ///
    /// Will be expanded to accept output metrics once the encoding pipeline
    /// is fully implemented.
    public init() {}
}

// ---------------------------------------------------------------------------
// MARK: - MediaFile
// ---------------------------------------------------------------------------
/// A value type that represents the metadata of a probed media file.
///
/// When the backend's `probe(file:)` method inspects a media file (via
/// FFprobe or AVAsset), it returns a `MediaFile` containing:
///
///   - Container format (e.g., MOV, MKV, MP4)
///   - Duration, overall bitrate, file size
///   - An ordered list of streams (video, audio, subtitle, data)
///   - Per-stream details (codec, resolution, frame rate, channels, etc.)
///   - HDR metadata (color primaries, transfer function, mastering display)
///   - Chapter markers, if present
///
/// ### Future Properties (to be added)
/// ```
/// public let url: URL
/// public let container: String
/// public let duration: TimeInterval
/// public let fileSize: Int64
/// public let streams: [MediaStream]
/// public let chapters: [Chapter]
/// ```
// ---------------------------------------------------------------------------
public struct MediaFile: Sendable {
    /// Creates a new media file metadata placeholder.
    ///
    /// Will be expanded to accept probed metadata once the FFprobe
    /// integration is complete.
    public init() {}
}

// ---------------------------------------------------------------------------
// MARK: - EncodingBackend Protocol
// ---------------------------------------------------------------------------
/// The fundamental protocol that all media-processing backends must conform
/// to within the ConverterEngine.
///
/// `EncodingBackend` defines the four operations that the engine's job
/// scheduler needs:
///
/// 1. **`encode(job:)`** — Perform a full encoding pass for the given job.
///    Returns an `EncodingResult` on success or throws on failure.
///
/// 2. **`probe(file:)`** — Inspect a media file and return its metadata
///    without performing any transcoding. This is used to populate the
///    UI's media inspector and to validate that an encoding profile is
///    compatible with the source material.
///
/// 3. **`cancel()`** — Request graceful cancellation of the currently
///    running operation. The backend should terminate the FFmpeg process
///    (or FFmpegKit session) and clean up partial output files.
///
/// 4. **`progress`** — An `AsyncStream<Double>` that emits normalised
///    progress values in the range `0.0 ... 1.0`. The stream completes
///    when the encode finishes (or is cancelled). Consumers (the CLI's
///    progress bar, the GUI's circular indicator) subscribe to this
///    stream to display real-time feedback.
///
/// ### Concurrency Model
/// All methods are `async` so that backends can perform I/O without
/// blocking the caller's thread. The protocol itself is not marked
/// `@MainActor` because backends run their heavy lifting on background
/// threads / tasks — only the *consumer* of `progress` should hop to
/// the main actor for UI updates.
///
/// ### Error Handling
/// `encode(job:)` and `probe(file:)` throw errors. Concrete backends
/// should define their own error types (e.g., `FFmpegError`,
/// `FFmpegKitError`) that conform to `LocalizedError` for user-facing
/// messages and to `CustomNSError` for structured logging.
///
/// ### Sendable Conformance
/// Concrete backends are expected to be classes (since they manage
/// mutable process state) but must still be `Sendable`. The recommended
/// pattern is to use an `actor` or to protect mutable state with a lock
/// and declare `@unchecked Sendable`.
// ---------------------------------------------------------------------------
public protocol EncodingBackend: Sendable {

    /// Encodes the media described by `job` and returns the result.
    ///
    /// - Parameter job: A fully specified encoding task.
    /// - Returns: An `EncodingResult` containing output metrics.
    /// - Throws: If the encoding process fails (invalid input, codec error,
    ///   disk full, process crash, etc.).
    func encode(job: EncodingJob) async throws -> EncodingResult

    /// Probes a media file and returns its metadata without transcoding.
    ///
    /// - Parameter file: The URL of the media file to inspect.
    /// - Returns: A `MediaFile` value containing container info, stream
    ///   details, duration, and other metadata.
    /// - Throws: If the file cannot be read or the probe output cannot be
    ///   parsed.
    func probe(file: URL) async throws -> MediaFile

    /// Requests cancellation of any in-progress operation.
    ///
    /// After calling `cancel()`, the `progress` stream should complete
    /// and the `encode(job:)` call should throw a cancellation error.
    /// Partial output files should be cleaned up by the backend.
    func cancel() async

    /// A stream of normalised progress values (`0.0 ... 1.0`).
    ///
    /// - Emits `0.0` at the start of an encode.
    /// - Emits intermediate values as frames are processed.
    /// - Completes (finishes the async sequence) when the encode ends.
    ///
    /// Consumers should iterate this stream with `for await`:
    /// ```swift
    /// for await fraction in backend.progress {
    ///     updateProgressBar(fraction)
    /// }
    /// ```
    var progress: AsyncStream<Double> { get }
}
