// ============================================================================
// MeedyaConverter — EncodingEngine
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodingEngineError

/// Errors from the encoding engine.
public enum EncodingEngineError: LocalizedError, Sendable {
    /// FFmpeg binary was not found or configured.
    case ffmpegUnavailable(String)

    /// The input file does not exist.
    case inputNotFound(String)

    /// The output directory does not exist or is not writable.
    case outputDirectoryInvalid(String)

    /// Encoding failed with FFmpeg error output.
    case encodingFailed(exitCode: Int32, stderr: String)

    /// Insufficient disk space for encoding.
    case insufficientDiskSpace(available: String, estimated: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable(let details):
            return "FFmpeg is not available: \(details)"
        case .inputNotFound(let path):
            return "Input file not found: \(path)"
        case .outputDirectoryInvalid(let path):
            return "Output directory is not writable: \(path)"
        case .encodingFailed(let code, let stderr):
            return "Encoding failed (exit \(code)): \(stderr.prefix(500))"
        case .insufficientDiskSpace(let available, let estimated):
            return "Insufficient disk space. Available: \(available), estimated needed: \(estimated)"
        }
    }
}

// MARK: - EncodingEngine

/// The main encoding engine that orchestrates FFmpeg-based media conversion.
///
/// Ties together all Phase 1 components: bundle manager, process controller,
/// probe, argument builder, profiles, temp files, and job queue.
///
/// Usage:
/// ```swift
/// let engine = EncodingEngine()
/// try engine.configure()
///
/// // Probe a file
/// let mediaFile = try await engine.probe(url: fileURL)
///
/// // Encode with a profile
/// let job = EncodingJobConfig(inputURL: fileURL, outputURL: outputURL, profile: .webStandard)
/// let progress = try await engine.encode(job: job) { info in
///     print("Progress: \(info.fractionComplete ?? 0)")
/// }
/// ```
public final class EncodingEngine: @unchecked Sendable {

    // MARK: - Properties

    /// The FFmpeg bundle manager for locating binaries.
    public let bundleManager: FFmpegBundleManager

    /// The temp file manager for intermediary files.
    public let tempManager: TempFileManager

    /// The encoding profile store.
    public let profileStore: EncodingProfileStore

    /// The encoding job queue.
    public let queue: EncodingQueue

    /// The feature gate for checking feature availability.
    public let featureGate: FeatureGateProtocol

    /// The hardware encoder detector for VideoToolbox/NVENC/QSV capability discovery.
    public let hardwareDetector: HardwareEncoderDetector

    /// Cached FFmpeg binary info (populated after configure()).
    public private(set) var ffmpegInfo: FFmpegBinaryInfo?

    /// Cached FFprobe binary info.
    public private(set) var ffprobeInfo: FFmpegBinaryInfo?

    /// The currently active process controller (for the running job).
    private var activeController: FFmpegProcessController?

    /// Lock for thread-safe state access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create a new encoding engine with default configuration.
    ///
    /// - Parameters:
    ///   - ffmpegPath: Optional user-specified FFmpeg path.
    ///   - ffprobePath: Optional user-specified FFprobe path.
    ///   - tempDirectory: Optional custom temp directory.
    ///   - featureGate: Feature gate instance (defaults to all-unlocked).
    public init(
        ffmpegPath: String? = nil,
        ffprobePath: String? = nil,
        tempDirectory: URL? = nil,
        featureGate: FeatureGateProtocol = DefaultFeatureGate()
    ) {
        self.bundleManager = FFmpegBundleManager(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath)
        self.tempManager = TempFileManager(baseDirectory: tempDirectory)
        self.profileStore = EncodingProfileStore()
        self.queue = EncodingQueue()
        self.featureGate = featureGate
        self.hardwareDetector = HardwareEncoderDetector()
    }

    // MARK: - Configuration

    /// Configure the engine by locating FFmpeg binaries.
    ///
    /// Must be called before any encoding or probing operations.
    /// Locates FFmpeg and FFprobe, validates their versions, and
    /// cleans up any orphaned temp directories from previous sessions.
    ///
    /// - Throws: `FFmpegBundleError` if FFmpeg cannot be found.
    public func configure() throws {
        // Locate FFmpeg binary
        let ffmpeg = try bundleManager.locateFFmpeg()
        ffmpegInfo = ffmpeg

        // Locate FFprobe binary
        let ffprobe = try bundleManager.locateFFprobe()
        ffprobeInfo = ffprobe

        // Clean up any orphaned temp directories from previous sessions
        let orphansCleanedUp = tempManager.cleanupOrphanedJobs()
        if orphansCleanedUp > 0 {
            print("Cleaned up \(orphansCleanedUp) orphaned temp director(ies) from previous session")
        }
    }

    // MARK: - Probing

    /// Probe a media file and return its metadata.
    ///
    /// Uses FFprobe to analyse the file's streams, format, chapters, and metadata.
    ///
    /// - Parameter url: The file URL to probe.
    /// - Returns: A fully populated `MediaFile` instance.
    /// - Throws: `FFmpegProbeError` if probing fails.
    public func probe(url: URL) async throws -> MediaFile {
        guard let probePath = ffprobeInfo?.path else {
            throw EncodingEngineError.ffmpegUnavailable("FFprobe not configured. Call configure() first.")
        }

        let prober = FFmpegProbe(ffprobePath: probePath)
        return try await prober.analyze(url: url)
    }

    // MARK: - Encoding

    /// Encode a single job and report progress.
    ///
    /// This is the main encoding entry point. It:
    /// 1. Validates the input file exists
    /// 2. Creates a temp directory for intermediary files
    /// 3. Builds FFmpeg arguments from the job config
    /// 4. Launches FFmpeg and monitors progress
    /// 5. Cleans up temp files on completion
    ///
    /// - Parameters:
    ///   - job: The encoding job configuration.
    ///   - onProgress: Callback for progress updates.
    /// - Throws: `EncodingEngineError` if encoding fails.
    public func encode(
        job: EncodingJobConfig,
        onProgress: @escaping @Sendable (FFmpegProgressInfo) -> Void = { _ in }
    ) async throws {
        guard let ffmpegPath = ffmpegInfo?.path else {
            throw EncodingEngineError.ffmpegUnavailable("FFmpeg not configured. Call configure() first.")
        }

        // Validate input exists
        guard FileManager.default.fileExists(atPath: job.inputURL.path) else {
            throw EncodingEngineError.inputNotFound(job.inputURL.path)
        }

        // Validate output directory exists and is writable
        let outputDir = job.outputURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: outputDir.path) else {
            throw EncodingEngineError.outputDirectoryInvalid(outputDir.path)
        }

        // Check disk space
        if !tempManager.hasMinimumSpace() {
            throw EncodingEngineError.insufficientDiskSpace(
                available: tempManager.availableSpaceString,
                estimated: "at least 1 GB"
            )
        }

        // Create temp directory for this job
        let tempDir = try tempManager.createJobDirectory(for: job.id)

        defer {
            // Always clean up temp files when done
            tempManager.cleanupJob(job.id)
        }

        // Probe the source to get duration (for progress calculation)
        let sourceInfo = try? await probe(url: job.inputURL)
        let sourceDuration = sourceInfo?.duration

        // Build FFmpeg arguments
        let arguments = job.buildArguments()

        // Handle multipass encoding
        if job.profile.encodingPasses == 2 {
            // Pass 1: analysis pass (fast, no audio, output to /dev/null)
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: arguments,
                pass: 1,
                multipassLogPath: tempDir.appendingPathComponent("multipass/pass").path,
                sourceDuration: sourceDuration,
                onProgress: { info in
                    // Scale pass 1 progress to 0-50%
                    var scaled = info
                    scaled.fractionComplete = (info.fractionComplete ?? 0) * 0.5
                    onProgress(scaled)
                }
            )

            // Pass 2: actual encoding with analysis data
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: arguments,
                pass: 2,
                multipassLogPath: tempDir.appendingPathComponent("multipass/pass").path,
                sourceDuration: sourceDuration,
                onProgress: { info in
                    // Scale pass 2 progress to 50-100%
                    var scaled = info
                    scaled.fractionComplete = 0.5 + (info.fractionComplete ?? 0) * 0.5
                    onProgress(scaled)
                }
            )
        } else {
            // Single pass encoding
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: arguments,
                pass: nil,
                multipassLogPath: nil,
                sourceDuration: sourceDuration,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Crop Detection

    /// Detect black bars in a video file using FFmpeg's cropdetect filter.
    ///
    /// - Parameter mediaFile: The probed media file to analyse.
    /// - Returns: Crop detection result, or nil if no video stream exists.
    /// - Throws: If FFmpeg analysis fails.
    public func detectCrop(for mediaFile: MediaFile) async throws -> CropDetectionResult? {
        guard let ffmpegPath = ffmpegInfo?.path else {
            throw EncodingEngineError.ffmpegUnavailable("FFmpeg not configured. Call configure() first.")
        }
        guard let video = mediaFile.primaryVideoStream,
              let width = video.width, let height = video.height else {
            return nil
        }

        let detector = CropDetector(ffmpegPath: ffmpegPath)
        return try await detector.detect(
            url: mediaFile.fileURL,
            duration: mediaFile.duration,
            sourceWidth: width,
            sourceHeight: height
        )
    }

    // MARK: - Hardware Encoding

    /// Detect available hardware encoders on this system.
    ///
    /// Must be called after `configure()` has located the FFmpeg binary.
    /// Results are cached for the session.
    ///
    /// - Returns: Array of available hardware encoders, empty if none or not configured.
    public func detectHardwareEncoders() -> [HardwareEncoderInfo] {
        guard let ffmpegPath = ffmpegInfo?.path else { return [] }
        return hardwareDetector.detectEncoders(ffmpegPath: ffmpegPath)
    }

    /// Check if hardware encoding is available for a specific codec.
    ///
    /// - Parameter codec: The video codec to check.
    /// - Returns: Available hardware encoder info, or nil if not supported.
    public func hardwareEncoder(for codec: VideoCodec) -> HardwareEncoderInfo? {
        guard let ffmpegPath = ffmpegInfo?.path else { return nil }
        // Prefer VideoToolbox on macOS
        return hardwareDetector.encoder(for: codec, api: .videoToolbox, ffmpegPath: ffmpegPath)
            ?? hardwareDetector.encoders(for: codec, ffmpegPath: ffmpegPath).first
    }

    // MARK: - Process Control

    /// Pause the currently running encoding process.
    public func pauseEncoding() {
        lock.lock()
        defer { lock.unlock() }
        activeController?.pauseEncoding()
    }

    /// Resume a paused encoding process.
    public func resumeEncoding() {
        lock.lock()
        defer { lock.unlock() }
        activeController?.resumeEncoding()
    }

    /// Cancel/stop the currently running encoding process.
    public func stopEncoding() {
        lock.lock()
        defer { lock.unlock() }
        activeController?.stopEncoding()
    }

    /// Whether an encoding process is currently running.
    public var isEncoding: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeController?.isRunning ?? false
    }

    // MARK: - Private Helpers

    /// Thread-safe setter for the active controller (avoids NSLock in async context).
    private nonisolated func setActiveController(_ controller: FFmpegProcessController?) {
        lock.lock()
        activeController = controller
        lock.unlock()
    }

    /// Run a single FFmpeg pass (or the entire encode for single-pass).
    private func runFFmpegPass(
        ffmpegPath: String,
        arguments: [String],
        pass: Int?,
        multipassLogPath: String?,
        sourceDuration: TimeInterval?,
        onProgress: @escaping @Sendable (FFmpegProgressInfo) -> Void
    ) async throws {
        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        controller.sourceDuration = sourceDuration

        setActiveController(controller)

        defer {
            setActiveController(nil)
        }

        // Modify arguments for multipass if needed
        var passArgs = arguments
        if let pass = pass {
            // Insert pass arguments before the output file
            let passArguments = ["-pass", "\(pass)"]
            if let logPath = multipassLogPath {
                passArgs.insert(contentsOf: passArguments + ["-passlogfile", logPath], at: max(0, passArgs.count - 1))
            }

            if pass == 1 {
                // First pass: disable audio, output to null
                passArgs.insert("-an", at: max(0, passArgs.count - 1))
                if let lastIndex = passArgs.indices.last {
                    passArgs[lastIndex] = "/dev/null"
                }
            }
        }

        // Start FFmpeg and monitor progress
        let progressStream = try controller.startEncoding(arguments: passArgs)

        for await progressInfo in progressStream {
            onProgress(progressInfo)
        }

        // Check exit code
        if let exitCode = controller.exitCode, exitCode != 0 {
            throw EncodingEngineError.encodingFailed(
                exitCode: exitCode,
                stderr: controller.errorOutput
            )
        }
    }
}
