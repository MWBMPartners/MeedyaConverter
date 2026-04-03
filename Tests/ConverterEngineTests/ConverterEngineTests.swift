// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Unit tests for the `ConverterEngine` library module.
//
// This test file verifies the foundational elements of the engine:
//   - The module imports correctly (linking sanity check).
//   - The version string is well-formed and non-empty.
//   - The build identifier contains the version string.
//   - Placeholder types (`EncodingJob`, `EncodingResult`, `MediaFile`) can
//     be instantiated — confirming their public visibility and Sendable
//     conformance.
//
// As the engine grows, additional test files should be added for each
// subsystem:
//   - `EncodingProfileTests.swift`   — Profile parsing and validation.
//   - `FFmpegArgumentTests.swift`    — FFmpeg argument-string construction.
//   - `ManifestGeneratorTests.swift`  — HLS/DASH manifest output correctness.
//   - `MediaProbeTests.swift`         — Probe result deserialization.
//   - `SubtitleConverterTests.swift`  — SRT/VTT/ASS format conversion.
//
// ### Test Naming Convention
// Tests follow the pattern `test_<unit>_<scenario>_<expectedBehaviour>`:
//   - `test_version_isNonEmpty` — The version string must not be empty.
//   - `test_buildIdentifier_containsVersion` — The build ID embeds the
//     version string.
//
// ### Fixtures
// Once media-file tests are added, sample files should be placed in
// `Tests/ConverterEngineTests/Fixtures/` and loaded via
// `Bundle.module.url(forResource:withExtension:)`.
// ---------------------------------------------------------------------------

import XCTest

// ---------------------------------------------------------------------------
// Importing the module under test.
//
// The `@testable` attribute is intentionally NOT used here. All assertions
// target the *public* API surface of ConverterEngine. Using `@testable`
// would bypass access control and could mask visibility issues — we want
// to catch those regressions in CI.
//
// If a future test needs access to internal helpers (e.g., to verify
// FFmpeg argument builders), create a separate test file that uses
// `@testable import ConverterEngine` and document the rationale.
// ---------------------------------------------------------------------------
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - ConverterEngineTests
// ---------------------------------------------------------------------------
/// Tests for the top-level `ConverterEngine` struct and its associated types.
///
/// These tests serve a dual purpose:
/// 1. **Build verification** — They confirm that the ConverterEngine module
///    compiles, links, and can be imported from a test target. A failure
///    here usually indicates a Package.swift misconfiguration.
/// 2. **API contract** — They lock in the expected shape of the public API
///    so that accidental breaking changes are caught by CI.
// ---------------------------------------------------------------------------
final class ConverterEngineTests: XCTestCase {

    // ---------------------------------------------------------------------
    // MARK: - Version Tests
    // ---------------------------------------------------------------------

    /// Verifies that the engine exposes a non-empty version string.
    ///
    /// An empty version would break the CLI's `--version` flag and the
    /// GUI's "About" window. This test guards against accidentally clearing
    /// the constant during a refactor.
    func test_version_isNonEmpty() {
        // The version constant must contain at least one character.
        XCTAssertFalse(
            ConverterEngine.version.isEmpty,
            "ConverterEngine.version must not be an empty string."
        )
    }

    /// Verifies that the version string follows semantic versioning format.
    ///
    /// While we do not enforce the full semver grammar here (pre-release
    /// tags, build metadata, etc.), we check for the basic `X.Y.Z` shape
    /// with at least two dot-separated components.
    func test_version_followsSemanticVersioning() {
        // Split on "." and verify we get at least major.minor.patch.
        let components = ConverterEngine.version.split(separator: ".")
        XCTAssertGreaterThanOrEqual(
            components.count, 3,
            "Version '\(ConverterEngine.version)' should have at least three dot-separated components (major.minor.patch)."
        )

        // Each component should be a valid integer.
        for component in components {
            XCTAssertNotNil(
                Int(component),
                "Version component '\(component)' in '\(ConverterEngine.version)' must be a valid integer."
            )
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Build Identifier Tests
    // ---------------------------------------------------------------------

    /// Verifies that the build identifier contains the version string.
    ///
    /// The build identifier is used in log preambles and user-agent headers.
    /// It must embed the version so that log analysis tools can correlate
    /// output with a specific engine release.
    func test_buildIdentifier_containsVersion() {
        XCTAssertTrue(
            ConverterEngine.buildIdentifier.contains(ConverterEngine.version),
            "Build identifier '\(ConverterEngine.buildIdentifier)' must contain the version string '\(ConverterEngine.version)'."
        )
    }

    /// Verifies that the build identifier starts with the module name.
    ///
    /// Convention: `"ModuleName/X.Y.Z"`. This test locks in the prefix.
    func test_buildIdentifier_startsWithModuleName() {
        XCTAssertTrue(
            ConverterEngine.buildIdentifier.hasPrefix("ConverterEngine/"),
            "Build identifier must start with 'ConverterEngine/' but got '\(ConverterEngine.buildIdentifier)'."
        )
    }

    // ---------------------------------------------------------------------
    // MARK: - Initialization Tests
    // ---------------------------------------------------------------------

    /// Verifies that a `ConverterEngine` instance can be created.
    ///
    /// This is a basic instantiation check. Once the initializer accepts
    /// a `Configuration` parameter, this test will be expanded to verify
    /// default configuration values.
    func test_init_succeeds() {
        let engine = ConverterEngine()
        // If we reach this point, the initializer did not trap or throw.
        // Verify the type is as expected by checking the static version
        // (which is accessible on the type, not the instance).
        _ = engine  // Silence unused variable warning.
        XCTAssertFalse(ConverterEngine.version.isEmpty)
    }

    // ---------------------------------------------------------------------
    // MARK: - Placeholder Type Tests
    // ---------------------------------------------------------------------
    // These tests verify that the placeholder types defined alongside
    // `EncodingBackend` are publicly accessible and can be instantiated.
    // They will be expanded significantly once the types gain real
    // properties and validation logic.
    // ---------------------------------------------------------------------

    /// Verifies that `EncodingJob` can be instantiated and has a non-nil ID.
    ///
    /// `EncodingJob` conforms to `Identifiable` — the `id` property must
    /// be populated automatically on creation.
    func test_encodingJob_hasUniqueID() {
        let job1 = EncodingJob()
        let job2 = EncodingJob()

        // Each job should receive a distinct UUID.
        XCTAssertNotEqual(
            job1.id, job2.id,
            "Two independently created EncodingJob instances must have distinct IDs."
        )
    }

    /// Verifies that `EncodingResult` can be instantiated.
    ///
    /// This is a minimal existence check — expanded tests will verify
    /// output metrics once the type gains properties.
    func test_encodingResult_canBeCreated() {
        let result = EncodingResult()
        // If we reach here, the type is publicly visible and constructible.
        _ = result
    }

    /// Verifies that `MediaFile` can be instantiated with required properties.
    func test_mediaFile_canBeCreated() {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let file = MediaFile(fileURL: url)
        XCTAssertEqual(file.fileName, "test.mkv")
        XCTAssertTrue(file.streams.isEmpty)
        XCTAssertFalse(file.hasVideo)
        XCTAssertFalse(file.hasAudio)
    }

    /// Verifies MediaFile stream filtering works correctly.
    func test_mediaFile_streamFiltering() {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let videoStream = MediaStream(streamIndex: 0, streamType: .video, codecName: "hevc")
        let audioStream = MediaStream(streamIndex: 1, streamType: .audio, codecName: "aac")
        let subStream = MediaStream(streamIndex: 2, streamType: .subtitle, codecName: "srt")
        let file = MediaFile(fileURL: url, streams: [videoStream, audioStream, subStream])

        XCTAssertEqual(file.videoStreams.count, 1)
        XCTAssertEqual(file.audioStreams.count, 1)
        XCTAssertEqual(file.subtitleStreams.count, 1)
        XCTAssertTrue(file.hasVideo)
        XCTAssertTrue(file.hasAudio)
        XCTAssertFalse(file.isAudioOnly)
    }

    /// Verifies ContainerFormat file extension lookup works.
    func test_containerFormat_fromExtension() {
        XCTAssertEqual(ContainerFormat.from(fileExtension: "mkv"), .mkv)
        XCTAssertEqual(ContainerFormat.from(fileExtension: "mp4"), .mp4)
        XCTAssertEqual(ContainerFormat.from(fileExtension: "ts"), .mpegTS)
        XCTAssertNil(ContainerFormat.from(fileExtension: "xyz"))
    }

    /// Verifies VideoCodec properties are consistent.
    func test_videoCodec_properties() {
        XCTAssertTrue(VideoCodec.h265.supportsHDR)
        XCTAssertFalse(VideoCodec.h264.supportsHDR)
        XCTAssertTrue(VideoCodec.h264.canEncode)
        XCTAssertFalse(VideoCodec.av2.isEncoderStable)
        XCTAssertNotNil(VideoCodec.h264.ffmpegEncoder)
    }

    /// Verifies AudioCodec properties are consistent.
    func test_audioCodec_properties() {
        XCTAssertTrue(AudioCodec.flac.isLossless)
        XCTAssertFalse(AudioCodec.aacLC.isLossless)
        XCTAssertEqual(AudioCodec.ac3.maxChannels, 6) // 5.1
        XCTAssertEqual(AudioCodec.eac3.maxChannels, 8) // 7.1
        XCTAssertTrue(AudioCodec.aacLC.supportsVBR)
        XCTAssertFalse(AudioCodec.ac3.supportsVBR)
    }

    /// Verifies SubtitleFormat bitmap detection.
    func test_subtitleFormat_bitmapDetection() {
        XCTAssertTrue(SubtitleFormat.pgs.isBitmap)
        XCTAssertTrue(SubtitleFormat.vobSub.isBitmap)
        XCTAssertFalse(SubtitleFormat.srt.isBitmap)
        XCTAssertTrue(SubtitleFormat.srt.isText)
    }

    // -----------------------------------------------------------------
    // MARK: - Feature Gating Tests
    // -----------------------------------------------------------------

    /// Verifies that DefaultFeatureGate unlocks all features at Studio tier.
    func test_featureGate_studioUnlocksAll() {
        let gate = DefaultFeatureGate(tier: .studio)
        XCTAssertTrue(gate.isAvailable(.basicEncoding))
        XCTAssertTrue(gate.isAvailable(.hdrProcessing))
        XCTAssertTrue(gate.isAvailable(.discRipping))
        XCTAssertTrue(gate.isAvailable(.aiFeatures))
    }

    /// Verifies that free tier gates pro and studio features.
    func test_featureGate_freeGatesProFeatures() {
        let gate = DefaultFeatureGate(tier: .free)
        XCTAssertTrue(gate.isAvailable(.basicEncoding)) // Free feature
        XCTAssertFalse(gate.isAvailable(.hdrProcessing)) // Pro feature
        XCTAssertFalse(gate.isAvailable(.discRipping)) // Studio feature
    }

    /// Verifies tier comparison works correctly.
    func test_productTier_comparison() {
        XCTAssertTrue(ProductTier.free < ProductTier.pro)
        XCTAssertTrue(ProductTier.pro < ProductTier.studio)
        XCTAssertFalse(ProductTier.studio < ProductTier.pro)
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder Tests
    // -----------------------------------------------------------------

    /// Verifies basic argument building with H.265/AAC.
    func test_argumentBuilder_basicH265() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 22
        builder.audioCodec = .aacLC
        builder.audioBitrate = 160_000

        let args = builder.build()

        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("libx265"))
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("22"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("160k"))
    }

    /// Verifies passthrough arguments.
    func test_argumentBuilder_passthrough() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioPassthrough = true

        let args = builder.build()

        // Should contain "-c:v copy" and "-c:a copy"
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-c:v copy"))
        XCTAssertTrue(argStr.contains("-c:a copy"))
        // Should NOT contain any codec-specific args
        XCTAssertFalse(argStr.contains("libx26"))
    }

    /// Verifies hardware encoding arguments for VideoToolbox.
    func test_argumentBuilder_hardwareEncoding() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.useHardwareEncoding = true
        builder.videoCRF = 25

        let args = builder.build()

        XCTAssertTrue(args.contains("hevc_videotoolbox"))
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Profile Tests
    // -----------------------------------------------------------------

    /// Verifies built-in profiles exist and have valid settings.
    func test_builtInProfiles_exist() {
        let profiles = EncodingProfile.builtInProfiles
        XCTAssertGreaterThanOrEqual(profiles.count, 7)

        // All built-in profiles should be marked as built-in
        for profile in profiles {
            XCTAssertTrue(profile.isBuiltIn, "\(profile.name) should be marked as built-in")
        }
    }

    /// Verifies profile-to-argument conversion works.
    func test_profile_toArgumentBuilder() {
        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = EncodingProfile.webStandard.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)
        let args = builder.build()

        XCTAssertTrue(args.contains("libx264"))
        XCTAssertTrue(args.contains("-crf"))
    }

    /// Verifies profile JSON serialisation round-trip.
    func test_profile_jsonRoundTrip() throws {
        let original = EncodingProfile.webHighQuality
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EncodingProfile.self, from: data)

        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.videoCodec, decoded.videoCodec)
        XCTAssertEqual(original.videoCRF, decoded.videoCRF)
        XCTAssertEqual(original.audioCodec, decoded.audioCodec)
        XCTAssertEqual(original.containerFormat, decoded.containerFormat)
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Queue Tests
    // -----------------------------------------------------------------

    /// Verifies job queue add and count.
    func test_encodingQueue_addJob() {
        let queue = EncodingQueue()
        let config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            profile: .webStandard
        )

        let jobState = queue.addJob(config)

        XCTAssertEqual(queue.totalCount, 1)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(jobState.status, .queued)
    }

    /// Verifies job queue priority ordering.
    func test_encodingQueue_priorityOrdering() {
        let queue = EncodingQueue()
        let lowPriority = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/low.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/low.mp4"),
            profile: .webStandard,
            priority: 0
        )
        let highPriority = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/high.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/high.mp4"),
            profile: .webStandard,
            priority: 10
        )

        queue.addJob(lowPriority)
        queue.addJob(highPriority)

        // High priority job should be first
        let next = queue.nextPendingJob()
        XCTAssertEqual(next?.config.priority, 10)
    }

    // -----------------------------------------------------------------
    // MARK: - Temp File Manager Tests
    // -----------------------------------------------------------------

    /// Verifies temp directory creation and cleanup.
    func test_tempManager_createAndCleanup() throws {
        let tempManager = TempFileManager()
        let jobID = UUID()

        let dir = try tempManager.createJobDirectory(for: jobID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // Subdirectories should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("demux").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("multipass").path))

        // Cleanup should remove the directory
        tempManager.cleanupJob(jobID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    /// Verifies disk space check returns a reasonable value.
    func test_tempManager_availableSpace() throws {
        let tempManager = TempFileManager()
        let space = try tempManager.availableSpace()
        XCTAssertGreaterThan(space, 0, "Available space should be > 0")
    }

    // -----------------------------------------------------------------
    // MARK: - HDR Format Detection Tests
    // -----------------------------------------------------------------

    /// Verifies HDR detection in video streams.
    func test_mediaStream_hdrDetection() {
        let hdrStream = MediaStream(
            streamIndex: 0,
            streamType: .video,
            hdrFormats: [.hdr10, .dolbyVision]
        )
        let sdrStream = MediaStream(streamIndex: 1, streamType: .video)

        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let file = MediaFile(fileURL: url, streams: [hdrStream, sdrStream])

        XCTAssertTrue(file.hasHDR)
        XCTAssertTrue(file.hasDolbyVision)
        XCTAssertFalse(file.hasHLG)
    }

    // -----------------------------------------------------------------
    // MARK: - Channel Layout Tests
    // -----------------------------------------------------------------

    /// Verifies channel layout properties.
    func test_channelLayout_properties() {
        let stereo = ChannelLayout(channelCount: 2, layoutName: "stereo")
        XCTAssertFalse(stereo.isSurround)
        XCTAssertTrue(stereo.canUpmix)
        XCTAssertEqual(stereo.displayName, "Stereo (2.0)")

        let surround = ChannelLayout(channelCount: 6, layoutName: "5.1")
        XCTAssertTrue(surround.isSurround)
        XCTAssertEqual(surround.displayName, "5.1 Surround")

        let mono = ChannelLayout(channelCount: 1)
        XCTAssertFalse(mono.canUpmix) // Mono should not offer upmix
    }
}
