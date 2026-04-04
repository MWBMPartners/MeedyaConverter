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

    /// The Dolby Vision tool wrapper for RPU handling.
    public let doviTool: DoviToolWrapper

    /// The hlg-tools wrapper for PQ → HLG conversion.
    public let hlgTools: HlgToolsWrapper

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
        self.doviTool = DoviToolWrapper()
        self.hlgTools = HlgToolsWrapper()
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

        // Probe the source to get duration and DV/HDR info
        let sourceInfo = try? await probe(url: job.inputURL)
        let sourceDuration = sourceInfo?.duration

        // Validate container-codec compatibility before encoding
        try validateCodecContainerCompatibility(job: job)

        // Dolby Vision preservation pipeline (Phase 3.8)
        // If source has DV and we're re-encoding video (not passthrough),
        // extract the RPU to a temp file for re-injection after encoding.
        var rpuPath: String?
        let sourceHasDV = sourceInfo?.hasDolbyVision ?? false
        let needsDVPreservation = sourceHasDV
            && !job.profile.videoPassthrough
            && job.profile.preserveHDR
            && doviTool.isAvailable
            && job.profile.containerFormat.supportsDolbyVision

        if needsDVPreservation {
            let rpuFile = tempDir.appendingPathComponent("dovi_rpu.bin")
            // Extract HEVC elementary stream from source, then extract RPU
            let hevcES = tempDir.appendingPathComponent("source_hevc.hevc")
            // Use FFmpeg to extract raw HEVC stream
            let extractArgs = [
                "-y", "-i", job.inputURL.path,
                "-c:v", "copy", "-bsf:v", "hevc_mp4toannexb",
                "-an", "-sn", "-f", "hevc", hevcES.path
            ]
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: extractArgs,
                pass: nil,
                multipassLogPath: nil,
                sourceDuration: sourceDuration,
                onProgress: { _ in } // Silent extraction
            )
            do {
                try await doviTool.extractRPU(
                    inputPath: hevcES.path,
                    outputPath: rpuFile.path
                )
                rpuPath = rpuFile.path
            } catch {
                // RPU extraction failed — continue without DV preservation
                rpuPath = nil
            }
            // Clean up extracted ES
            try? FileManager.default.removeItem(at: hevcES)
        }

        // Automatic HDR-to-SDR tone mapping trigger (Phase 3.9c / Issue #248)
        // When the source is HDR but the output codec or container cannot carry HDR,
        // automatically enable tone mapping to prevent washed-out colours.
        var enrichedJob = job
        if let sourceInfo, sourceInfo.hasHDR,
           !job.profile.videoPassthrough,
           !job.profile.toneMapToSDR,
           !job.profile.convertPQToHLG {
            let codecSupportsHDR = job.profile.videoCodec?.supportsHDR ?? false
            let containerSupportsHDR = job.profile.containerFormat.supportsHDR
            if !codecSupportsHDR || !containerSupportsHDR {
                // Auto-enable tone mapping — output cannot carry HDR
                enrichedJob.profile.toneMapToSDR = true
                if enrichedJob.profile.toneMapAlgorithm == nil {
                    enrichedJob.profile.toneMapAlgorithm = "hable"
                }
                enrichedJob.profile.preserveHDR = false
            }
        }

        // Automatic hlg-tools routing for PQ→HLG (Issue #256)
        // When PQ→HLG conversion is requested and hlg-tools is available, prefer it.
        if enrichedJob.profile.convertPQToHLG,
           !enrichedJob.profile.useHlgTools,
           hlgTools.isAvailable {
            enrichedJob.profile.useHlgTools = true
        }

        // HLG metadata preservation signalling (Issue #245)
        // When source is HLG and we're preserving HDR (not tone mapping or converting),
        // ensure the output gets correct HLG colour signalling.
        if let sourceInfo, sourceInfo.hasHLG,
           !enrichedJob.profile.videoPassthrough,
           enrichedJob.profile.preserveHDR,
           !enrichedJob.profile.toneMapToSDR,
           !enrichedJob.profile.convertPQToHLG {
            enrichedJob.hdrTransferFunction = .hlg
        }

        // Inject HDR10 metadata from source into the job's argument builder
        // This ensures MDCV/CLL metadata is carried through to the output when
        // re-encoding HDR content (Phase 3.7 / Issue #43, #245).
        if let sourceInfo,
           let video = sourceInfo.primaryVideoStream,
           !enrichedJob.profile.videoPassthrough,
           enrichedJob.profile.preserveHDR,
           !enrichedJob.profile.toneMapToSDR {
            if let cp = video.colourProperties {
                enrichedJob.hdrMaxCLL = cp.maxCLL
                enrichedJob.hdrMaxFALL = cp.maxFALL
                enrichedJob.hdrMasteringDisplayMaxLuminance = cp.masteringDisplayMaxLuminance
                enrichedJob.hdrMasteringDisplayMinLuminance = cp.masteringDisplayMinLuminance
                // Build MDCV string if we have luminance data
                // Format for x265: G(gx,gy)B(bx,by)R(rx,ry)WP(wpx,wpy)L(max,min)
                // Default BT.2020 primaries with DCI-P3 white point
                if let maxLum = cp.masteringDisplayMaxLuminance,
                   let minLum = cp.masteringDisplayMinLuminance {
                    enrichedJob.hdrMasteringDisplay =
                        "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(\(maxLum * 10000),\(minLum))"
                }
            }
        }

        // Build FFmpeg arguments
        let arguments = enrichedJob.buildArguments()

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

        // Dolby Vision RPU re-injection (Phase 3.8)
        // If we extracted an RPU earlier, inject it into the encoded output.
        if let rpuPath = rpuPath {
            let encodedOutput = job.outputURL
            let hevcOutput = tempDir.appendingPathComponent("encoded_hevc.hevc")
            let injectedOutput = tempDir.appendingPathComponent("injected_hevc.hevc")

            // Extract HEVC ES from the encoded output
            let extractArgs = [
                "-y", "-i", encodedOutput.path,
                "-c:v", "copy", "-bsf:v", "hevc_mp4toannexb",
                "-an", "-sn", "-f", "hevc", hevcOutput.path
            ]
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: extractArgs,
                pass: nil, multipassLogPath: nil,
                sourceDuration: nil,
                onProgress: { _ in }
            )

            // Inject RPU into the encoded HEVC stream
            try await doviTool.injectRPU(
                hevcPath: hevcOutput.path,
                rpuPath: rpuPath,
                outputPath: injectedOutput.path
            )

            // Remux the DV-injected stream back into the final container
            let remuxArgs = [
                "-y", "-i", injectedOutput.path,
                "-i", encodedOutput.path,
                "-map", "0:v:0",  // Video from DV-injected stream
                "-map", "1:a?",   // Audio from original encode
                "-map", "1:s?",   // Subtitles from original encode
                "-c", "copy",
                "-map_metadata", "1",  // Metadata from original encode
                "-map_chapters", "1",  // Chapters from original encode
                encodedOutput.path
            ]
            try await runFFmpegPass(
                ffmpegPath: ffmpegPath,
                arguments: remuxArgs,
                pass: nil, multipassLogPath: nil,
                sourceDuration: nil,
                onProgress: { _ in }
            )

            // Clean up intermediary files
            try? FileManager.default.removeItem(at: hevcOutput)
            try? FileManager.default.removeItem(at: injectedOutput)
            try? FileManager.default.removeItem(atPath: rpuPath)
        }

        // PQ → DV Profile 8.4 + HLG combined pipeline (Issue #255)
        // After encoding with PQ→HLG zscale filter applied, generate a DV Profile 8.4
        // RPU from the HLG output and inject it. This produces a three-tier compatible
        // stream: Dolby Vision → HLG → SDR fallback.
        // Only runs when: convertPQToDVHLG is set, source was PQ, dovi_tool available,
        // container supports DV, codec is HEVC, and we didn't already inject a DV RPU above.
        let needsDVHLGConversion = job.profile.convertPQToDVHLG
            && (sourceInfo?.hasPQ ?? false)
            && !job.profile.videoPassthrough
            && doviTool.isAvailable
            && job.profile.containerFormat.supportsDolbyVision
            && job.profile.videoCodec == .h265
            && rpuPath == nil // Don't double-inject if DV preservation already ran

        if needsDVHLGConversion {
            let dvRPU = tempDir.appendingPathComponent("dv_hlg_rpu.bin")
            let hevcES = tempDir.appendingPathComponent("dvhlg_hevc.hevc")
            let injectedES = tempDir.appendingPathComponent("dvhlg_injected.hevc")

            // Generate DV Profile 8.4 RPU for the HLG output
            // Use source HDR metadata for luminance values
            let video = sourceInfo?.primaryVideoStream
            do {
                try await doviTool.generateRPU(
                    outputPath: dvRPU.path,
                    maxCLL: video?.colourProperties?.maxCLL,
                    maxFALL: video?.colourProperties?.maxFALL,
                    minLuminance: video?.colourProperties?.masteringDisplayMinLuminance,
                    maxLuminance: video?.colourProperties?.masteringDisplayMaxLuminance
                )

                // Extract HEVC ES from the encoded output
                let extractArgs = [
                    "-y", "-i", job.outputURL.path,
                    "-c:v", "copy", "-bsf:v", "hevc_mp4toannexb",
                    "-an", "-sn", "-f", "hevc", hevcES.path
                ]
                try await runFFmpegPass(
                    ffmpegPath: ffmpegPath,
                    arguments: extractArgs,
                    pass: nil, multipassLogPath: nil,
                    sourceDuration: nil,
                    onProgress: { _ in }
                )

                // Inject DV Profile 8.4 RPU into the HEVC stream
                try await doviTool.injectRPU(
                    hevcPath: hevcES.path,
                    rpuPath: dvRPU.path,
                    outputPath: injectedES.path
                )

                // Remux the DV-injected stream back into the final container
                let remuxArgs = [
                    "-y", "-i", injectedES.path,
                    "-i", job.outputURL.path,
                    "-map", "0:v:0",
                    "-map", "1:a?",
                    "-map", "1:s?",
                    "-c", "copy",
                    "-map_metadata", "1",
                    "-map_chapters", "1",
                    job.outputURL.path
                ]
                try await runFFmpegPass(
                    ffmpegPath: ffmpegPath,
                    arguments: remuxArgs,
                    pass: nil, multipassLogPath: nil,
                    sourceDuration: nil,
                    onProgress: { _ in }
                )
            } catch {
                // DV RPU generation/injection failed — output still has HLG, which is valid.
                // Log but don't fail the encode.
            }

            // Clean up intermediary files
            try? FileManager.default.removeItem(at: dvRPU)
            try? FileManager.default.removeItem(at: hevcES)
            try? FileManager.default.removeItem(at: injectedES)
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

    // MARK: - Container-Codec Validation (Phase 3.11)

    /// Validate that the job's codec/container combination is compatible.
    ///
    /// Throws `EncodingEngineError` if the video or audio codec cannot be
    /// muxed into the selected container format.
    private func validateCodecContainerCompatibility(job: EncodingJobConfig) throws {
        let container = job.profile.containerFormat

        // Validate video codec compatibility (skip if passthrough — codec comes from source)
        if !job.profile.videoPassthrough, let videoCodec = job.profile.videoCodec {
            if !container.supportsVideoCodec(videoCodec) {
                throw EncodingEngineError.encodingFailed(
                    exitCode: -1,
                    stderr: "\(videoCodec.displayName) is not compatible with \(container.displayName). Choose a different container or video codec."
                )
            }
        }

        // Validate audio codec compatibility (skip if passthrough)
        if !job.profile.audioPassthrough, let audioCodec = job.profile.audioCodec {
            if !container.supportsAudioCodec(audioCodec) {
                throw EncodingEngineError.encodingFailed(
                    exitCode: -1,
                    stderr: "\(audioCodec.displayName) is not compatible with \(container.displayName). Choose a different container or audio codec."
                )
            }
        }
    }

    // MARK: - Dolby Vision / HLG Conversion (Phase 3.9a)

    /// Generate a Dolby Vision RPU from HLG or HDR10 content.
    ///
    /// This enables automatic DV creation from non-DV HDR sources.
    /// The generated RPU can be injected into the re-encoded HEVC stream.
    ///
    /// - Parameters:
    ///   - mediaFile: The probed source file (must have HDR metadata).
    ///   - outputPath: Path where the generated RPU will be written.
    ///   - targetProfile: DV profile to generate (default: Profile 8.1 for HDR10,
    ///     Profile 8.4 for HLG).
    /// - Throws: `DoviToolError` if generation fails or dovi_tool is not available.
    public func generateDolbyVisionRPU(
        for mediaFile: MediaFile,
        outputPath: String,
        targetProfile: DoviProfile? = nil
    ) async throws {
        guard doviTool.isAvailable else {
            throw DoviToolError.binaryNotFound
        }

        guard let video = mediaFile.primaryVideoStream else {
            throw DoviToolError.noDolbyVision
        }

        // Determine the target DV profile based on source HDR type
        let profile = targetProfile ?? (mediaFile.hasHLG ? .profile8_4 : .profile8_1)

        // Extract HDR metadata from the source for RPU generation
        // MaxCLL/MaxFALL come from the stream's content light level metadata
        let maxCLL = video.colourProperties?.maxCLL
        let maxFALL = video.colourProperties?.maxFALL
        let maxLuminance = video.colourProperties?.masteringDisplayMaxLuminance
        let minLuminance = video.colourProperties?.masteringDisplayMinLuminance

        try await doviTool.generateRPU(
            outputPath: outputPath,
            maxCLL: maxCLL,
            maxFALL: maxFALL,
            minLuminance: minLuminance,
            maxLuminance: maxLuminance
        )

        _ = profile // Profile selection will be used in dovi_tool convert step
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

    // MARK: - PQ → HLG (Issue #254)

    /// Whether the external hlg-tools (pq2hlg) binary is available on this system.
    ///
    /// When available, the engine can use hlg-tools for higher-quality PQ→HLG
    /// conversion. When unavailable, the FFmpeg zscale filter chain is used instead.
    public var isHlgToolsAvailable: Bool {
        hlgTools.isAvailable
    }

    /// Get the version of the installed hlg-tools, if available.
    public var hlgToolsVersion: String? {
        hlgTools.version()
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

    /// Run an arbitrary FFmpeg command with progress reporting.
    ///
    /// Used by the CLI manifest command and other tools that need to execute
    /// FFmpeg directly with custom arguments (e.g., variant encoding).
    public func runFFmpeg(
        arguments: [String],
        onProgress: @escaping @Sendable (FFmpegProgressInfo) -> Void
    ) async throws {
        guard let ffmpegPath = ffmpegInfo?.path else {
            throw EncodingEngineError.ffmpegUnavailable("FFmpeg not configured. Call configure() first.")
        }
        try await runFFmpegPass(
            ffmpegPath: ffmpegPath,
            arguments: arguments,
            pass: nil,
            multipassLogPath: nil,
            sourceDuration: nil,
            onProgress: onProgress
        )
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
