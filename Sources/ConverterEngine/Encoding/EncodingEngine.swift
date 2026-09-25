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

    /// The subtitle_tonemap wrapper for HDR subtitle colour correction
    /// (Issues #369 / #409). Used by the pre-processing pipeline below
    /// when a profile carries a non-nil `subtitleTonemap` config.
    public let subtitleTonemapper: SubtitleTonemapWrapper

    /// Cached FFmpeg binary info (populated after configure()).
    public private(set) var ffmpegInfo: FFmpegBinaryInfo?

    /// Cached FFprobe binary info.
    public private(set) var ffprobeInfo: FFmpegBinaryInfo?

    /// The process controllers for every FFmpeg pass currently in flight,
    /// keyed by the ID of the `EncodingJobConfig` that owns the pass
    /// (Issue #286).
    ///
    /// Previously a single `activeController` optional. That was correct
    /// only while exactly one job could ever be running: with two jobs in
    /// flight, whichever pass registered last owned the whole engine, so
    /// `stopEncoding()` killed an arbitrary job and the first pass to
    /// finish cleared the *other* job's controller — after which that job
    /// could no longer be paused or stopped at all. Keying by job ID makes
    /// every control operation route to the right process, and makes the
    /// pass-end teardown remove only its own entry.
    ///
    /// A single job's multipass encode registers and unregisters one
    /// controller per pass under the same key, so at most one entry per
    /// job exists at a time.
    private var activeControllers: [UUID: FFmpegProcessController] = [:]

    /// Every job currently inside `encode(job:onProgress:)`, keyed by its
    /// `EncodingJobConfig.id`, with how many `encode` calls for that id are
    /// running (#508 commit 6).
    ///
    /// Why this exists at all: `activeControllers` only knows about a job
    /// while one of its FFmpeg passes is actually running. Before the first
    /// pass starts — during the source probe and, from #508, during an
    /// auto-tag lookup that can take up to 30 seconds — a job has no
    /// controller, so a Stop pressed then used to reach nothing and was
    /// silently lost. This registry lets `stopEncoding()` and
    /// `stopEncoding(jobID:)` record a stop for a job in that phase, which
    /// `encode` honours before it starts FFmpeg.
    ///
    /// A COUNT, not a set, so that two `encode` calls for the same job id
    /// running at once (which `ScriptingBridge` can cause today — an
    /// existing bug, recorded in the #508 plan's follow-ups) cannot have the
    /// first to finish wipe out the second's registration and stop flag.
    ///
    /// Only ever touched with `lock` held.
    private var inFlightJobIDs: [UUID: Int] = [:]

    /// Jobs in `inFlightJobIDs` that the user has asked to stop. Only an id
    /// that is in flight is ever added, and an id is removed when its last
    /// `encode` call ends, so a stop can never linger and cancel a later run
    /// of the same job. Only ever touched with `lock` held.
    private var stopRequestedJobIDs: Set<UUID> = []

    /// Lock for thread-safe state access.
    private let lock = NSLock()

    // MARK: - Auto-tagging (#508)

    /// Where this engine reads the auto-tag setting from at the start of
    /// every job, or `nil` for an engine that never auto-tags.
    ///
    /// `nil` is the default. `AppViewModel.init` passes one for the app's own
    /// engine (#508 commit 8), so a real app encode reads this; the
    /// `meedya-convert` CLI, `APIServer`'s standalone engine, and any
    /// encoding pipeline all build their own `EncodingEngine` with no
    /// argument for this parameter, so it stays `nil` for them and they never
    /// auto-tag. An engine with a source and the setting OFF (the shipped
    /// default — see `AutoTagSettingsStore`'s header) behaves exactly like an
    /// engine with no source: only the on/off switch is read (the TMDB key is
    /// not even fetched), nothing is sent, nothing is published on
    /// `autoTagEvents`, and the FFmpeg arguments are identical.
    public let autoTagSettings: AutoTagSettingsSource?

    /// What each job's auto-tag lookup did, as it happens. See
    /// `AutoTagJobEvent`.
    ///
    /// - Buffers at most the NEWEST 64 events, dropping older ones, so an
    ///   engine nobody listens to (the command-line tool, the API server's
    ///   standalone engine, most tests) never piles events up in memory.
    /// - An `AsyncStream` has ONE reader: two loops reading it at once would
    ///   each see only some of the events. The app's `autoTagEventTask`
    ///   (`AppViewModel.init`, #508 commit 8) is that one reader.
    /// - Finished when the engine is released (`deinit`), so a reader's
    ///   `for await` loop ends instead of waiting forever.
    public let autoTagEvents: AsyncStream<AutoTagJobEvent>

    /// The writing end of `autoTagEvents`. `AsyncStream.Continuation` is
    /// safe to use from any thread, so it needs no lock.
    private let autoTagEventContinuation: AsyncStream<AutoTagJobEvent>.Continuation

    // MARK: - Initialiser

    /// Create a new encoding engine with default configuration.
    ///
    /// - Parameters:
    ///   - ffmpegPath: Optional user-specified FFmpeg path.
    ///   - ffprobePath: Optional user-specified FFprobe path.
    ///   - tempDirectory: Optional custom temp directory.
    ///   - featureGate: Feature gate instance (defaults to all-unlocked).
    ///   - autoTagSettings: Where to read the auto-tag setting from at the
    ///     start of each job (#508). Defaults to `nil` — never auto-tag.
    ///     Deliberately the LAST parameter and defaulted, so every existing
    ///     `EncodingEngine(…)` call compiles and behaves exactly as before.
    public init(
        ffmpegPath: String? = nil,
        ffprobePath: String? = nil,
        tempDirectory: URL? = nil,
        featureGate: FeatureGateProtocol = DefaultFeatureGate(),
        autoTagSettings: AutoTagSettingsSource? = nil
    ) {
        self.bundleManager = FFmpegBundleManager(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath)
        self.tempManager = TempFileManager(baseDirectory: tempDirectory)
        self.profileStore = EncodingProfileStore()
        self.queue = EncodingQueue()
        self.featureGate = featureGate
        self.hardwareDetector = HardwareEncoderDetector()
        self.doviTool = DoviToolWrapper()
        self.hlgTools = HlgToolsWrapper()
        self.subtitleTonemapper = SubtitleTonemapWrapper()
        self.autoTagSettings = autoTagSettings
        let (events, continuation) = AsyncStream<AutoTagJobEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.autoTagEvents = events
        self.autoTagEventContinuation = continuation
    }

    deinit {
        // Ends any reader's `for await` loop over `autoTagEvents`. Events
        // still in the buffer are delivered first; `finish()` only stops
        // new ones.
        autoTagEventContinuation.finish()
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
    /// This is the main encoding entry point. In order, it:
    /// 1. Records the job as in flight, so a Stop pressed before FFmpeg has
    ///    started is remembered rather than lost (see step 6).
    /// 2. Checks FFmpeg is configured, the input exists, the output folder
    ///    is writable and there is at least 1 GB free.
    /// 3. Creates a temp directory for intermediary files.
    /// 4. Probes the source (a failed probe is tolerated) and checks the
    ///    codec/container combination.
    /// 5. Auto-tagging (#508) — ONLY when this engine was given an
    ///    `autoTagSettings` source and the setting is on: looks the file up
    ///    and works out which tags it lacks. See "Auto-tagging" below.
    /// 6. Throws `CancellationError` if a stop was requested for this job,
    ///    BEFORE any FFmpeg pass has started.
    /// 7. Runs the Dolby Vision RPU extraction pass, when one is needed.
    /// 8. Adjusts the job from the probe (HDR tone mapping, PQ→HLG routing,
    ///    HLG signalling, HDR10 metadata), adds the looked-up tags from
    ///    step 5 to its output tags, and runs any subtitle tone-map passes.
    /// 9. Builds the FFmpeg arguments and runs the pass(es), reporting
    ///    progress.
    /// 10. Runs the Dolby Vision re-injection or DV-over-HLG passes, when
    ///    needed.
    /// 11. Writes a Kodi `.nfo` sidecar next to the output (#508 commit 7) —
    ///    ONLY when step 5's lookup identified a film AND the setting read in
    ///    step 5 asked for one (`AutoTagConfig.writeNFO`). See "The NFO
    ///    sidecar (step 11)" below. Runs last, and only once, so the output
    ///    it sits next to is guaranteed to already exist.
    /// The temp directory is removed on the way out, however it ends.
    ///
    /// **Auto-tagging (step 5).** The setting is read once, at the start of
    /// this job, so a change made mid-queue applies from the next job. The
    /// lookup's missing tags are added to `outputMetadata`, which the
    /// argument builder turns into `-metadata key=value` arguments; the
    /// file's own tags still travel by the builder's usual
    /// `-map_metadata 0`. Precedence, highest first:
    ///   1. the job's own `outputMetadata`;
    ///   2. the source file's own (non-blank) tags;
    ///   3. looked-up tags — which only ever fill a key both of the above
    ///      lack (`AutoTagMerge`, including aliases such as `date`/`year`).
    /// A lookup that is skipped, finds nothing, is not confident, fails or
    /// runs out of time NEVER fails the encode: the file is converted
    /// exactly as it would have been without auto-tagging. What happened is
    /// published on `autoTagEvents`. The app passes a settings source and
    /// logs those events as Activity Log lines (#508 commit 8), so a real app
    /// encode auto-tags whenever the Settings switch (commit 9) is on; the
    /// `meedya-convert` CLI and any encoding pipeline never do, because their
    /// `EncodingEngine` is built with no settings source at all.
    ///
    /// **The NFO sidecar (step 11).** `AutoTagNFOWriter.write` does the
    /// actual writing (see its own doc comment for the three rules: never
    /// overwrite, the output must exist first, never throw); this method
    /// only decides WHEN to call it and publishes what happened. It uses the
    /// SAME `AutoTagRequest` step 5 already read — never a second,
    /// independently-timed read of the setting — so a job that started with
    /// NFO writing on finishes with it on even if the setting were flipped
    /// mid-job, and a job that started with it off never writes one no
    /// matter what changes later. Skipped entirely (no write attempted, no
    /// event published) when a stop was requested for this job by the time
    /// this step runs: every FFmpeg pass has already finished successfully
    /// by this point (an error from any earlier step would have already
    /// thrown out of this method), so the ONE way the stop flag can still be
    /// set here is `stopEncoding()` marking it and killing the controller at
    /// almost the same moment the last pass was finishing anyway. Writing an
    /// extra file for a job the user just asked to stop is the wrong side to
    /// err on, and — mirroring how a lookup stopped mid-request publishes no
    /// `.lookup` event at all — nothing is published either, so a reader of
    /// `autoTagEvents` never sees an outcome for work that was deliberately
    /// never attempted.
    ///
    /// **Stopping.** `stopEncoding()` / `stopEncoding(jobID:)` reach a job
    /// in steps 1-6 through a stop flag rather than a running process: the
    /// lookup notices within about a quarter of a second, and step 6 throws
    /// before FFmpeg is ever launched. The step-6 check runs whether or not
    /// auto-tagging is on, so a Stop pressed during the source probe is
    /// honoured too; before #508 commit 6 such a Stop reached nothing and
    /// the encode ran to the end regardless.
    ///
    /// What this does NOT cover: a Stop that arrives after step 6 while no
    /// FFmpeg pass is registered — for example while the separate
    /// `subtitle_tonemap` tool runs in step 8, or in the moment between two
    /// passes — still reaches nothing, exactly as before #508. Nothing
    /// re-checks the flag after step 6.
    ///
    /// - Parameters:
    ///   - job: The encoding job configuration.
    ///   - onProgress: Callback for progress updates.
    /// - Throws: `EncodingEngineError` if encoding fails.
    ///   `CancellationError` if a stop was requested for this job before
    ///   FFmpeg started, or the calling task was cancelled during an
    ///   auto-tag lookup. (A stop that arrives while FFmpeg is running kills
    ///   the process exactly as before #508; that usually surfaces as
    ///   `EncodingEngineError.encodingFailed`, because the killed process
    ///   exits with a non-zero status.)
    public func encode(
        job: EncodingJobConfig,
        onProgress: @escaping @Sendable (FFmpegProgressInfo) -> Void = { _ in }
    ) async throws {
        // Registered FIRST, before anything that can take time, so a Stop
        // pressed at any point before FFmpeg starts is recorded (step 1).
        // The `defer` removes the registration and any stop flag however
        // this call ends — success, failure or cancellation — so a flag can
        // never outlive the run it was meant for.
        beginTrackingJob(job.id)
        defer { endTrackingJob(job.id) }

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

        // Auto-tagging (#508, step 5). Here, and not earlier or later,
        // because:
        //   * it needs the probe (film or music, the running time that
        //     scores a match, and the file's own tags that must not be
        //     overwritten);
        //   * a job that fails validation above costs no network request;
        //   * nothing has been launched yet, so stopping during the lookup
        //     costs nothing — in particular it is BEFORE the Dolby Vision
        //     extraction pass below, which is itself an FFmpeg run.
        // `tagsToAdd` is empty, and `identifiedFilm` is nil, whenever there is
        // nothing to add or nothing was identified (no settings source,
        // switched off, skipped, failed, …). `writeNFO` is this job's own
        // resolved setting, read once here — step 11 reuses it rather than
        // reading `autoTagSettings` a second time, so what was decided at the
        // start of the job is exactly what happens at the end of it.
        let autoTagResult = try await autoTagLookupIfSwitchedOn(job: job, sourceInfo: sourceInfo)

        // Step 6: the last point before any FFmpeg pass. Deliberately runs
        // whether or not a lookup ran (see the doc comment's "Stopping").
        if isStopRequested(jobID: job.id) {
            throw CancellationError()
        }

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
                jobID: job.id,
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

        var enrichedJob = job

        // Looked-up tags (#508) fill only keys the job doesn't set itself:
        // on a clash the job's own value wins. The runner already left out
        // every key the job or the source file carries (`AutoTagMerge`), so
        // this closure is a second line of defence for the job's tags, not
        // the main rule. The file's own tags are not in `outputMetadata` at
        // all — they reach the output through `-map_metadata 0` — which is
        // why the runner, not this merge, is what protects them.
        enrichedJob.outputMetadata.merge(autoTagResult.tagsToAdd) { jobValue, _ in jobValue }

        // Automatic HDR-to-SDR tone mapping trigger (Phase 3.9c / Issue #248)
        // When the source is HDR but the output codec or container cannot carry HDR,
        // automatically enable tone mapping to prevent washed-out colours.
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

        // -----------------------------------------------------------
        // Subtitle tone-mapping pre-processing (Issues #369 / #409)
        // -----------------------------------------------------------
        //
        // When the profile opts in (profile.subtitleTonemap != nil), the
        // source is HDR, AND subtitles are passing through, extract each
        // supported HDR subtitle stream and run subtitle_tonemap on it.
        // The pipeline returns one entry per successfully-processed stream;
        // we build a full per-stream action list that:
        //
        //   * .replaceWith(tonemappedFile) for every successfully-processed
        //     stream  → the encoder picks the SDR-coloured version from a
        //     separate -i input
        //   * .passthrough for every other subtitle stream  → unchanged
        //     stream-by-stream copy from the source
        //
        // Including passthrough entries for non-tonemapped streams is
        // important: once subtitleStreamActions is non-empty the builder
        // uses it EXCLUSIVELY, so omitting a stream here would silently
        // drop it from the output. The pipeline.run() helper returns
        // empty (no-op) when subtitleTonemap is nil, the source is SDR,
        // or no supported subtitle codec is present — leaving the
        // legacy subtitlePassthrough behaviour intact.
        if let sourceInfo,
           job.profile.subtitlePassthrough,
           job.profile.subtitleTonemap != nil {
            let tonemapped = await SubtitleTonemapPipeline.run(
                source: job.inputURL,
                sourceInfo: sourceInfo,
                config: job.profile.subtitleTonemap,
                wrapper: subtitleTonemapper,
                tempDir: tempDir,
                runFFmpeg: { args in
                    try await self.runFFmpegPass(
                        ffmpegPath: ffmpegPath,
                        arguments: args,
                        pass: nil,
                        multipassLogPath: nil,
                        sourceDuration: sourceDuration,
                        jobID: job.id,
                        onProgress: { _ in } // Silent extraction
                    )
                }
            )
            if !tonemapped.isEmpty {
                let resultByIndex = Dictionary(
                    uniqueKeysWithValues: tonemapped.map { ($0.streamIndex, $0) }
                )
                enrichedJob.subtitleStreamActions = sourceInfo.subtitleStreams.map { stream in
                    if let result = resultByIndex[stream.streamIndex] {
                        return .init(
                            streamIndex: stream.streamIndex,
                            action: .replaceWith(result.tonemappedFile)
                        )
                    }
                    return .init(streamIndex: stream.streamIndex, action: .passthrough)
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
                jobID: job.id,
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
                jobID: job.id,
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
                jobID: job.id,
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
                jobID: job.id,
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
                jobID: job.id,
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
                    jobID: job.id,
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
                    jobID: job.id,
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

        // Step 11 (#508 commit 7): the Kodi .nfo sidecar. Deliberately the
        // VERY LAST thing this method does — after the single/multi-pass
        // encode above AND both DV blocks — so `job.outputURL` is guaranteed
        // to already hold the finished file `AutoTagNFOWriter.write` needs to
        // sit next to. See this method's own doc comment, "The NFO sidecar
        // (step 11)", for the stop decision below.
        if let identifiedFilm = autoTagResult.identifiedFilm, autoTagResult.writeNFO {
            if isStopRequested(jobID: job.id) {
                // A stop landed for this job at almost the exact moment the
                // last pass finished anyway (every earlier throwing point
                // above would already have exited this method otherwise).
                // Deliberately no write and no event — see the doc comment.
            } else {
                let outcome = AutoTagNFOWriter.write(film: identifiedFilm, nextTo: job.outputURL)
                autoTagEventContinuation.yield(
                    AutoTagJobEvent(jobID: job.id, fileName: job.inputURL.lastPathComponent, kind: .nfo(outcome))
                )
            }
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

    /// Pause every encoding process currently in flight.
    ///
    /// With a single job running — the only case before Issue #286 — this
    /// is byte-identical to the previous single-controller behaviour.
    public func pauseEncoding() {
        for controller in currentControllers() {
            controller.pauseEncoding()
        }
    }

    /// Resume every paused encoding process.
    public func resumeEncoding() {
        for controller in currentControllers() {
            controller.resumeEncoding()
        }
    }

    /// Cancel/stop every encoding process currently in flight.
    ///
    /// Also records a stop for every job inside `encode` that has not
    /// started FFmpeg yet (#508 commit 6) — one being probed or auto-tagged —
    /// which then throws `CancellationError` before launching anything. How
    /// a RUNNING FFmpeg process is stopped is unchanged. With nothing in
    /// flight this still does nothing at all.
    public func stopEncoding() {
        lock.withLock {
            stopRequestedJobIDs.formUnion(inFlightJobIDs.keys)
        }
        for controller in currentControllers() {
            controller.stopEncoding()
        }
    }

    /// Pause only the pass belonging to `jobID`. A no-op when that job has
    /// no pass in flight.
    public func pauseEncoding(jobID: UUID) {
        controller(forJobID: jobID)?.pauseEncoding()
    }

    /// Resume only the pass belonging to `jobID`. A no-op when that job has
    /// no pass in flight.
    public func resumeEncoding(jobID: UUID) {
        controller(forJobID: jobID)?.resumeEncoding()
    }

    /// Stop only the job `jobID`: its FFmpeg pass if one is running, and —
    /// from #508 commit 6 — a stop flag if it is inside `encode` but has not
    /// started FFmpeg yet (see `stopEncoding()`). Other jobs are untouched.
    /// A no-op when that job is not in flight at all: no flag is recorded
    /// for a job that isn't running, so a stale stop can never cancel it
    /// when it does run later.
    public func stopEncoding(jobID: UUID) {
        lock.withLock {
            if inFlightJobIDs[jobID] != nil {
                stopRequestedJobIDs.insert(jobID)
            }
        }
        controller(forJobID: jobID)?.stopEncoding()
    }

    /// Whether at least one encoding process is currently running.
    public var isEncoding: Bool {
        currentControllers().contains { $0.isRunning }
    }

    /// The number of FFmpeg passes currently registered with the engine.
    ///
    /// Exposed for tests and diagnostics — the runner in `AppViewModel`
    /// tracks its own in-flight count and does not consult this.
    public var activeControllerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeControllers.count
    }

    // MARK: - Private Helpers

    /// Registers one `encode` call for `jobID` (see `inFlightJobIDs`).
    private func beginTrackingJob(_ jobID: UUID) {
        lock.withLock {
            inFlightJobIDs[jobID, default: 0] += 1
        }
    }

    /// Ends one `encode` call for `jobID`. When it was the last one for that
    /// id, the id AND its stop flag are removed, so neither outlives the run.
    private func endTrackingJob(_ jobID: UUID) {
        lock.withLock {
            let remaining = (inFlightJobIDs[jobID] ?? 1) - 1
            if remaining > 0 {
                inFlightJobIDs[jobID] = remaining
            } else {
                inFlightJobIDs.removeValue(forKey: jobID)
                stopRequestedJobIDs.remove(jobID)
            }
        }
    }

    /// Whether a stop has been requested for `jobID` since it started.
    /// Cheap and safe from any thread: the auto-tag runner polls it every
    /// quarter of a second from a background task.
    private func isStopRequested(jobID: UUID) -> Bool {
        lock.withLock { stopRequestedJobIDs.contains(jobID) }
    }

    /// What `autoTagLookupIfSwitchedOn` learned, beyond the tags it already
    /// resolved for `encode` to merge into `outputMetadata`. Kept as its own
    /// small type — rather than returning `AutoTagLookupReport` itself, or a
    /// bare tuple — so that `encode`'s step 11 (the NFO write) reads as "the
    /// two facts it actually needs", not "reach into a report meant for
    /// something else".
    private struct AutoTagStepResult {
        /// Tags to merge into the job's `outputMetadata`. Empty whenever
        /// there is nothing to add (see `autoTagLookupIfSwitchedOn`'s doc
        /// comment for every case that leaves this empty).
        let tagsToAdd: [String: String]

        /// The film step 5's lookup identified, if any — copied straight
        /// from `AutoTagLookupReport.identifiedFilm`. `nil` for a skip, a
        /// failure, no match, an ambiguous or below-threshold result, AND
        /// always `nil` for a music match (see that property's own doc
        /// comment in `AutoTagRunner.swift`). Step 11 only ever attempts an
        /// NFO write when this is non-`nil`.
        let identifiedFilm: MetadataResult?

        /// This job's resolved `AutoTagConfig.writeNFO`, read once alongside
        /// everything else in step 5. `false` whenever there was no request
        /// at all (no settings source, or switched off) — matching
        /// `tagsToAdd`/`identifiedFilm` being empty/`nil` in that case, so a
        /// caller never needs to check "was there even a request?" itself.
        let writeNFO: Bool
    }

    /// Step 5 of `encode`: runs the auto-tag lookup when this engine has a
    /// settings source and the setting is on, publishes what happened on
    /// `autoTagEvents`, and returns the tags to add (empty whenever nothing
    /// is to be added) together with the two facts step 11 (the NFO write)
    /// needs from this same, single settings read.
    ///
    /// - Throws: `CancellationError` only — when the job is stopped, or the
    ///   calling task cancelled, during the lookup. Nothing else a lookup
    ///   does can make this throw, so a lookup can never fail an encode.
    private func autoTagLookupIfSwitchedOn(
        job: EncodingJobConfig,
        sourceInfo: MediaFile?
    ) async throws -> AutoTagStepResult {
        // Read ONCE per job, now — never cached across jobs — so flipping
        // the setting mid-queue applies from the next job. `nil` means no
        // settings source or switched off: no events, no requests, and the
        // encode is exactly what it would have been without auto-tagging.
        // This same `request` is also where `writeNFO` below comes from —
        // step 11 never reads `autoTagSettings` a second time.
        guard let request = autoTagSettings?.currentRequest() else {
            return AutoTagStepResult(tagsToAdd: [:], identifiedFilm: nil, writeNFO: false)
        }

        let jobID = job.id
        let fileName = job.inputURL.lastPathComponent
        let events = autoTagEventContinuation

        let report: AutoTagLookupReport
        if let sourceInfo {
            do {
                report = try await AutoTagRunner.run(
                    request: request,
                    source: sourceInfo,
                    jobTags: job.outputMetadata,
                    shouldStop: { self.isStopRequested(jobID: jobID) },
                    onLookingUp: { provider in
                        events.yield(AutoTagJobEvent(jobID: jobID, fileName: fileName, kind: .lookingUp(provider)))
                    }
                )
            } catch is CancellationError {
                // A stop (or the task being cancelled). Passed on so the
                // job ends as stopped; no `.lookup` event is published.
                throw CancellationError()
            } catch {
                // Not expected: `AutoTagRunner.run` is documented to throw
                // only `CancellationError`, turning every other problem into
                // a report. Handled anyway because a tagging helper must
                // never be able to fail an encode. The error's own text is
                // deliberately NOT included: this path has no guarantee it
                // went through the TMDB key redaction, and a URL-bearing
                // error description could carry the key. Its type name
                // cannot.
                report = AutoTagLookupReport(
                    outcome: .failed(reason: "The lookup failed unexpectedly (\(type(of: error)))."),
                    provider: nil
                )
            }
        } else {
            // The probe failed (`encode` tolerates that and carries on), so
            // there is nothing to identify the file from.
            report = AutoTagLookupReport(
                outcome: .skipped(reason: AutoTagRunner.Reasons.emptyProbe),
                provider: nil
            )
        }

        events.yield(AutoTagJobEvent(jobID: jobID, fileName: fileName, kind: .lookup(report)))
        return AutoTagStepResult(
            tagsToAdd: report.metadataToAdd,
            identifiedFilm: report.identifiedFilm,
            writeNFO: request.config.writeNFO
        )
    }

    /// A lock-protected snapshot of every registered controller.
    ///
    /// Taken as a snapshot so the (potentially blocking) signal calls above
    /// happen with `lock` released — a controller's own `pauseEncoding()`
    /// takes its own lock, and holding both would invite a deadlock.
    private func currentControllers() -> [FFmpegProcessController] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeControllers.values)
    }

    /// The controller registered for `jobID`, if any.
    private func controller(forJobID jobID: UUID) -> FFmpegProcessController? {
        lock.lock()
        defer { lock.unlock() }
        return activeControllers[jobID]
    }

    /// Thread-safe registration of a job's active controller (avoids NSLock in async context).
    private nonisolated func setActiveController(
        _ controller: FFmpegProcessController?,
        forJobID jobID: UUID
    ) {
        lock.lock()
        if let controller {
            activeControllers[jobID] = controller
        } else {
            activeControllers.removeValue(forKey: jobID)
        }
        lock.unlock()
    }

    /// Run an arbitrary FFmpeg command with progress reporting.
    ///
    /// Used by the CLI manifest command and other tools that need to execute
    /// FFmpeg directly with custom arguments (e.g., variant encoding).
    ///
    /// - Parameter jobID: Key under which the pass registers its process
    ///   controller, so `pauseEncoding(jobID:)`/`stopEncoding(jobID:)` can
    ///   target it. Defaults to a fresh UUID, which keeps every existing
    ///   caller compiling and behaving exactly as before (the pass is still
    ///   reachable via the un-keyed `stopEncoding()`, which signals all).
    public func runFFmpeg(
        arguments: [String],
        jobID: UUID = UUID(),
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
            jobID: jobID,
            onProgress: onProgress
        )
    }

    /// Run a single FFmpeg pass (or the entire encode for single-pass).
    ///
    /// `jobID` scopes the pass's process controller so that concurrent jobs
    /// (Issue #286) cannot clear each other's registration on pass end.
    private func runFFmpegPass(
        ffmpegPath: String,
        arguments: [String],
        pass: Int?,
        multipassLogPath: String?,
        sourceDuration: TimeInterval?,
        jobID: UUID,
        onProgress: @escaping @Sendable (FFmpegProgressInfo) -> Void
    ) async throws {
        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        controller.sourceDuration = sourceDuration

        setActiveController(controller, forJobID: jobID)

        defer {
            // Remove only THIS job's entry — a sibling job's controller
            // must survive this pass ending (Issue #286).
            setActiveController(nil, forJobID: jobID)
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
