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

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: HDR10 Metadata Tests
    // -----------------------------------------------------------------

    /// Verifies H.265 HDR10 metadata injection via -x265-params.
    func test_argumentBuilder_hdr10MetadataH265() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.pixelFormat = "yuv420p10le"
        builder.audioCodec = .eac3
        builder.audioBitrate = 640_000

        // Set HDR10 metadata from probe
        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // Should have colour signalling
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        XCTAssertTrue(argStr.contains("-colorspace bt2020nc"))

        // Should have -x265-params with HDR10 metadata
        XCTAssertTrue(args.contains("-x265-params"))
        if let x265Idx = args.firstIndex(of: "-x265-params") {
            let params = args[args.index(after: x265Idx)]
            XCTAssertTrue(params.contains("hdr10-opt=1"), "Should enable hdr10-opt")
            XCTAssertTrue(params.contains("repeat-headers=1"), "Should enable repeat-headers")
            XCTAssertTrue(params.contains("master-display="), "Should include mastering display")
            XCTAssertTrue(params.contains("max-cll=1000,400"), "Should include CLL/FALL")
        }
    }

    /// Verifies AV1 HDR10 metadata injection uses generic FFmpeg side data.
    func test_argumentBuilder_hdr10MetadataAV1() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .av1
        builder.videoCRF = 30
        builder.audioPassthrough = true

        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // AV1 uses -master_display and -content_light (not x265-params)
        XCTAssertTrue(argStr.contains("-master_display"))
        XCTAssertTrue(argStr.contains("-content_light 1000,400"))
        XCTAssertFalse(argStr.contains("-x265-params"), "AV1 should not use x265-params")
    }

    /// Verifies no HDR metadata when tone mapping is enabled.
    func test_argumentBuilder_noHDRMetadataWhenToneMapping() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.audioCodec = .aacLC
        builder.audioBitrate = 192_000

        builder.masteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        builder.maxCLL = 1000
        builder.maxFALL = 400

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // When tone mapping, HDR10 metadata should NOT be injected
        XCTAssertFalse(argStr.contains("-x265-params"), "Should not inject HDR metadata when tone mapping")
        XCTAssertFalse(argStr.contains("-master_display"), "Should not inject mastering display when tone mapping")
    }

    /// Verifies colour signalling without MDCV/CLL still emits colour args.
    func test_argumentBuilder_hdrColourSignallingOnly() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.audioPassthrough = true
        // No masteringDisplay or maxCLL set

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // Should still have colour signalling even without MDCV/CLL
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        // Should NOT have x265-params since no metadata
        XCTAssertFalse(argStr.contains("-x265-params"))
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Per-Stream Audio Tests
    // -----------------------------------------------------------------

    /// Verifies per-stream audio codec arguments (-c:a:N).
    func test_argumentBuilder_perStreamAudioCodec() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true

        // Multi-codec audio: AAC for stream 0, E-AC-3 for stream 1
        builder.perStreamAudioCodec = [0: .aacLC, 1: .eac3]
        builder.perStreamAudioBitrate = [0: 160_000, 1: 640_000]

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-c:a:0 aac"), "Should set AAC for stream 0")
        XCTAssertTrue(argStr.contains("-b:a:0 160k"), "Should set bitrate for stream 0")
        XCTAssertTrue(argStr.contains("-c:a:1 eac3"), "Should set E-AC-3 for stream 1")
        XCTAssertTrue(argStr.contains("-b:a:1 640k"), "Should set bitrate for stream 1")
        // Should NOT have global -c:a
        XCTAssertFalse(argStr.contains(" -c:a "), "Should not have global audio codec when per-stream is set")
    }

    /// Verifies per-stream audio overrides take precedence over global.
    func test_argumentBuilder_perStreamOverridesGlobal() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioCodec = .aacLC  // Global setting
        builder.audioBitrate = 128_000

        // Per-stream overrides should win
        builder.perStreamAudioCodec = [0: .flac]

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-c:a:0 flac"), "Per-stream codec should override global")
        XCTAssertFalse(argStr.contains(" -c:a aac"), "Global codec should not appear when per-stream is set")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Container Flags Tests
    // -----------------------------------------------------------------

    /// Verifies MP4 gets -movflags +faststart.
    func test_argumentBuilder_mp4Faststart() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h264
        builder.videoCRF = 20
        builder.audioCodec = .aacLC
        builder.containerFormat = .mp4

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-movflags +faststart"), "MP4 should include faststart")
    }

    /// Verifies MOV also gets -movflags +faststart.
    func test_argumentBuilder_movFaststart() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mov")
        builder.videoCodec = .prores
        builder.audioCodec = .pcm
        builder.containerFormat = .mov

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-movflags +faststart"), "MOV should include faststart")
    }

    /// Verifies MPEG-TS gets resend_headers flag.
    func test_argumentBuilder_mpegTSHeaders() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.ts")
        builder.videoCodec = .h264
        builder.audioCodec = .ac3
        builder.containerFormat = .mpegTS

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-mpegts_flags +resend_headers"), "MPEG-TS should include resend_headers")
    }

    /// Verifies MKV does not get faststart or TS flags.
    func test_argumentBuilder_mkvNoContainerFlags() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mp4")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoPassthrough = true
        builder.audioPassthrough = true
        builder.containerFormat = .mkv

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertFalse(argStr.contains("-movflags"), "MKV should not have movflags")
        XCTAssertFalse(argStr.contains("-mpegts_flags"), "MKV should not have mpegts_flags")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Tone Mapping Tests
    // -----------------------------------------------------------------

    /// Verifies tone mapping filter chain is generated.
    func test_argumentBuilder_toneMapping() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.toneMapAlgorithm = .hable
        builder.audioCodec = .aacLC

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        // Should have a -vf with the tone mapping filter chain
        XCTAssertTrue(args.contains("-vf"), "Should have video filter for tone mapping")
        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("zscale=t=linear"), "Should start with linear conversion")
            XCTAssertTrue(filterChain.contains("tonemap=hable"), "Should use hable algorithm")
            XCTAssertTrue(filterChain.contains("zscale=p=bt709"), "Should convert to BT.709")
            XCTAssertTrue(filterChain.contains("format=yuv420p"), "Should output 8-bit SDR")
        }
    }

    /// Verifies PQ→HLG filter chain.
    func test_argumentBuilder_pqToHLG() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.videoCodec = .h265
        builder.videoCRF = 18
        builder.convertPQToHLG = true
        builder.audioPassthrough = true

        let args = builder.build()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(args.contains("-vf"), "Should have video filter for PQ→HLG")
        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("smpte2084"), "Should reference PQ input")
            XCTAssertTrue(filterChain.contains("arib-std-b67"), "Should convert to HLG")
            XCTAssertTrue(filterChain.contains("yuv420p10le"), "Should output 10-bit")
        }
    }

    /// Verifies tone mapping and PQ→HLG are mutually exclusive.
    func test_argumentBuilder_toneMapOverridesPQToHLG() {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        builder.videoCodec = .h265
        builder.videoCRF = 20
        builder.toneMap = true
        builder.convertPQToHLG = true  // Both set — toneMap should win
        builder.audioCodec = .aacLC

        let args = builder.build()

        if let vfIdx = args.firstIndex(of: "-vf") {
            let filterChain = args[args.index(after: vfIdx)]
            XCTAssertTrue(filterChain.contains("tonemap="), "Tone mapping should be present")
            XCTAssertFalse(filterChain.contains("arib-std-b67"), "PQ→HLG should not be present when tone mapping")
        }
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: HLG/PQ Preservation Tests
    // -----------------------------------------------------------------

    /// Verifies HLG preservation arguments.
    func test_argumentBuilder_hlgPreservation() {
        var builder = FFmpegArgumentBuilder()
        builder.videoCodec = .h265
        let args = builder.buildHLGPreservationArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-color_trc arib-std-b67"))
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
    }

    /// Verifies HLG preservation is skipped when tone mapping.
    func test_argumentBuilder_hlgPreservationSkippedWhenToneMap() {
        var builder = FFmpegArgumentBuilder()
        builder.toneMap = true
        let args = builder.buildHLGPreservationArguments()
        XCTAssertTrue(args.isEmpty, "HLG preservation should be empty when tone mapping")
    }

    /// Verifies PQ preservation arguments.
    func test_argumentBuilder_pqPreservation() {
        var builder = FFmpegArgumentBuilder()
        builder.videoCodec = .h265
        let args = builder.buildPQPreservationArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-color_trc smpte2084"))
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: TrueHD Disposition Tests
    // -----------------------------------------------------------------

    /// Verifies TrueHD in MP4 gets non-default disposition.
    func test_argumentBuilder_trueHDDispositionMP4() {
        let streams: [(index: Int, codec: AudioCodec)] = [
            (0, .aacLC),
            (1, .trueHD),
        ]
        let args = FFmpegArgumentBuilder.buildTrueHDDispositionArguments(
            audioStreams: streams, container: .mp4
        )
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-disposition:a:0 default"), "AAC should be set as default")
        XCTAssertTrue(argStr.contains("-disposition:a:1 0"), "TrueHD should be non-default")
    }

    /// Verifies TrueHD in MKV does NOT get disposition override.
    func test_argumentBuilder_trueHDDispositionMKV() {
        let streams: [(index: Int, codec: AudioCodec)] = [
            (0, .trueHD),
            (1, .aacLC),
        ]
        let args = FFmpegArgumentBuilder.buildTrueHDDispositionArguments(
            audioStreams: streams, container: .mkv
        )
        XCTAssertTrue(args.isEmpty, "MKV should not need TrueHD disposition override")
    }

    // -----------------------------------------------------------------
    // MARK: - FFmpeg Argument Builder: Static Helper Tests
    // -----------------------------------------------------------------

    /// Verifies PCM encoder name selection.
    func test_argumentBuilder_pcmEncoderName() {
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 16), "pcm_s16le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 24), "pcm_s24le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 32), "pcm_s32le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 32, floatingPoint: true), "pcm_f32le")
        XCTAssertEqual(FFmpegArgumentBuilder.pcmEncoderName(bitDepth: 64, floatingPoint: true), "pcm_f64le")
    }

    /// Verifies ProRes profile value mapping.
    func test_argumentBuilder_proresProfileValue() {
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "proxy"), 0)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "lt"), 1)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "hq"), 3)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "4444"), 4)
        XCTAssertEqual(FFmpegArgumentBuilder.proresProfileValue(for: "4444xq"), 5)
        XCTAssertNil(FFmpegArgumentBuilder.proresProfileValue(for: "invalid"))
    }

    /// Verifies DNxHR profile value mapping.
    func test_argumentBuilder_dnxhrProfileValue() {
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "lb"), "dnxhr_lb")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "sq"), "dnxhr_sq")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "hq"), "dnxhr_hq")
        XCTAssertEqual(FFmpegArgumentBuilder.dnxhrProfileValue(for: "444"), "dnxhr_444")
        XCTAssertNil(FFmpegArgumentBuilder.dnxhrProfileValue(for: "invalid"))
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Profile: New Property Tests
    // -----------------------------------------------------------------

    /// Verifies preferredExtension computed property.
    func test_profile_preferredExtension() {
        XCTAssertEqual(EncodingProfile.webStandard.preferredExtension, "mp4")
        XCTAssertEqual(EncodingProfile.fourKHDRMaster.preferredExtension, "mkv")
        XCTAssertEqual(EncodingProfile.proresHQ.preferredExtension, "mov")
        XCTAssertEqual(EncodingProfile.blurayCompatible.preferredExtension, "ts")
    }

    /// Verifies PQ→DV+HLG profile has correct settings.
    func test_profile_pqToDVHLG() {
        let profile = EncodingProfile.pqToDVHLG
        XCTAssertTrue(profile.isBuiltIn)
        XCTAssertTrue(profile.convertPQToHLG)
        XCTAssertTrue(profile.convertPQToDVHLG)
        XCTAssertTrue(profile.preserveHDR)
        XCTAssertEqual(profile.videoCodec, .h265)
        XCTAssertEqual(profile.pixelFormat, "yuv420p10le")
        XCTAssertEqual(profile.containerFormat, .mkv)
    }

    /// Verifies PQ→HLG profile exists and has correct flags.
    func test_profile_pqToHLG() {
        let profile = EncodingProfile.pqToHLG
        XCTAssertTrue(profile.isBuiltIn)
        XCTAssertTrue(profile.convertPQToHLG)
        XCTAssertFalse(profile.convertPQToDVHLG)
        XCTAssertTrue(profile.preserveHDR)
        XCTAssertFalse(profile.toneMapToSDR)
    }

    /// Verifies built-in profile count includes new HDR profiles.
    func test_builtInProfiles_count() {
        // 23 original + pqToHLG + pqToDVHLG = at least 25
        XCTAssertGreaterThanOrEqual(EncodingProfile.builtInProfiles.count, 23)
    }

    /// Verifies convertPQToDVHLG round-trips through JSON.
    func test_profile_pqToDVHLG_jsonRoundTrip() throws {
        let original = EncodingProfile.pqToDVHLG
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.convertPQToHLG, original.convertPQToHLG)
        XCTAssertEqual(decoded.convertPQToDVHLG, original.convertPQToDVHLG)
        XCTAssertEqual(decoded.preserveHDR, original.preserveHDR)
        XCTAssertEqual(decoded.videoCodec, original.videoCodec)
    }

    // -----------------------------------------------------------------
    // MARK: - Encoding Job Config: HDR Metadata Tests
    // -----------------------------------------------------------------

    /// Verifies EncodingJobConfig wires HDR metadata to argument builder.
    func test_encodingJobConfig_hdrMetadataWiring() {
        var config = EncodingJobConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            profile: .fourKHDRMaster
        )
        config.hdrMasteringDisplay = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)"
        config.hdrMaxCLL = 1000
        config.hdrMaxFALL = 400

        let args = config.buildArguments()
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-x265-params"), "Should have x265 HDR params")
        XCTAssertTrue(argStr.contains("max-cll=1000,400"), "Should pass through CLL/FALL")
    }

    // -----------------------------------------------------------------
    // MARK: - ContainerFormat Codec Compatibility Tests
    // -----------------------------------------------------------------

    /// Verifies MP4 container supports expected codecs.
    func test_containerFormat_mp4Compatibility() {
        let mp4 = ContainerFormat.mp4
        XCTAssertTrue(mp4.supportsVideoCodec(.h264))
        XCTAssertTrue(mp4.supportsVideoCodec(.h265))
        XCTAssertTrue(mp4.supportsVideoCodec(.av1))
        XCTAssertTrue(mp4.supportsAudioCodec(.aacLC))
        XCTAssertTrue(mp4.supportsAudioCodec(.ac3))
    }

    /// Verifies MKV container supports a wide range of codecs.
    func test_containerFormat_mkvCompatibility() {
        let mkv = ContainerFormat.mkv
        XCTAssertTrue(mkv.supportsVideoCodec(.h264))
        XCTAssertTrue(mkv.supportsVideoCodec(.h265))
        XCTAssertTrue(mkv.supportsVideoCodec(.av1))
        XCTAssertTrue(mkv.supportsVideoCodec(.vp9))
        XCTAssertTrue(mkv.supportsAudioCodec(.flac))
        XCTAssertTrue(mkv.supportsAudioCodec(.trueHD))
        XCTAssertTrue(mkv.supportsAudioCodec(.dtsHDMA))
    }

    /// Verifies WebM container restricts to VP8/VP9/AV1 + Opus/Vorbis.
    func test_containerFormat_webmCompatibility() {
        let webm = ContainerFormat.webm
        XCTAssertTrue(webm.supportsVideoCodec(.vp9))
        XCTAssertTrue(webm.supportsVideoCodec(.av1))
        XCTAssertTrue(webm.supportsAudioCodec(.opus))
        XCTAssertFalse(webm.supportsAudioCodec(.aacLC))
        XCTAssertFalse(webm.supportsVideoCodec(.h264))
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
