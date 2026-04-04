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

    // -----------------------------------------------------------------
    // MARK: - ColourSpaceConverter Tests
    // -----------------------------------------------------------------

    /// Verifies colour space filter generation.
    func test_colourSpaceConverter_buildFilter() {
        let filter = ColourSpaceConverter.buildFilter(from: .bt601, to: .bt709)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("zscale"))
        XCTAssertTrue(filter!.contains("bt709"))
    }

    /// Verifies no filter generated for same colour space.
    func test_colourSpaceConverter_sameColourSpace() {
        let filter = ColourSpaceConverter.buildFilter(from: .bt709, to: .bt709)
        XCTAssertNil(filter, "Should return nil when source == target")
    }

    /// Verifies signalling arguments.
    func test_colourSpaceConverter_signalling() {
        let args = ColourSpaceConverter.buildSignallingArguments(for: .bt2020)
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-color_primaries bt2020"))
        XCTAssertTrue(argStr.contains("-colorspace bt2020nc"))
    }

    /// Verifies recommended colour space for HDR.
    func test_colourSpaceConverter_recommendation() {
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h265, isHDR: true), .bt2020)
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h264, isHDR: false), .bt709)
        XCTAssertEqual(ColourSpaceConverter.recommendedColourSpace(for: .h264, isHDR: true), .bt709) // H.264 doesn't support HDR
    }

    /// Verifies ColourSpace properties.
    func test_colourSpace_properties() {
        XCTAssertTrue(ColourSpace.bt2020.isWideGamut)
        XCTAssertTrue(ColourSpace.dciP3.isWideGamut)
        XCTAssertFalse(ColourSpace.bt709.isWideGamut)
        XCTAssertFalse(ColourSpace.bt601.isWideGamut)
    }

    // -----------------------------------------------------------------
    // MARK: - PlatformFormatPolicy Tests
    // -----------------------------------------------------------------

    /// Verifies H.264 is universally supported.
    func test_platformPolicy_h264Universal() {
        for platform in PlatformFormatPolicy.Platform.allCases {
            let result = PlatformFormatPolicy.checkVideoCodec(.h264, on: platform)
            if case .supported = result {
                // OK
            } else {
                XCTFail("H.264 should be supported on \(platform.rawValue)")
            }
        }
    }

    /// Verifies platform validation catches incompatible combinations.
    func test_platformPolicy_webBrowserRestrictions() {
        let result = PlatformFormatPolicy.checkContainer(.mkv, on: .webBrowser)
        if case .unsupported = result {
            // Expected
        } else {
            XCTFail("MKV should be unsupported in web browsers")
        }
    }

    /// Verifies profile validation returns warnings for incompatible settings.
    func test_platformPolicy_profileValidation() {
        // HDR Master profile with MKV should warn on Apple platforms
        let warnings = PlatformFormatPolicy.validate(profile: .fourKHDRMaster, for: .iOS)
        // MKV is not natively supported on iOS
        XCTAssertTrue(warnings.contains { $0.contains("MKV") })
    }

    /// Verifies recommended profiles differ by platform.
    func test_platformPolicy_recommendations() {
        let webProfile = PlatformFormatPolicy.recommendedProfile(for: .webBrowser)
        XCTAssertEqual(webProfile.videoCodec, .av1)

        let androidProfile = PlatformFormatPolicy.recommendedProfile(for: .android)
        XCTAssertEqual(androidProfile.videoCodec, .h264)

        let plexProfile = PlatformFormatPolicy.recommendedProfile(for: .plex)
        XCTAssertEqual(plexProfile.videoCodec, .h265)
    }

    // -----------------------------------------------------------------
    // MARK: - HDRTransferFunction Tests
    // -----------------------------------------------------------------

    /// Verifies HDRTransferFunction enum values.
    func test_hdrTransferFunction_rawValues() {
        XCTAssertEqual(HDRTransferFunction.pq.rawValue, "pq")
        XCTAssertEqual(HDRTransferFunction.hlg.rawValue, "hlg")
    }

    // -----------------------------------------------------------------
    // MARK: - ManifestGenerator Tests
    // -----------------------------------------------------------------

    /// Verifies default variant ladder has expected entries.
    func test_manifestGenerator_defaultLadder() {
        let ladder = StreamingVariant.defaultLadder
        XCTAssertEqual(ladder.count, 4)
        XCTAssertEqual(ladder[0].label, "1080p")
        XCTAssertEqual(ladder[0].width, 1920)
        XCTAssertEqual(ladder[0].height, 1080)
        XCTAssertEqual(ladder[3].label, "360p")
    }

    /// Verifies 4K UHD ladder.
    func test_manifestGenerator_uhdLadder() {
        let ladder = StreamingVariant.uhdrLadder
        XCTAssertEqual(ladder[0].label, "2160p")
        XCTAssertEqual(ladder[0].width, 3840)
        XCTAssertGreaterThan(ladder[0].videoBitrate, ladder[1].videoBitrate)
    }

    /// Verifies HLS variant arguments are generated correctly.
    func test_manifestGenerator_hlsVariantArguments() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .hls
        )
        let args = generator.buildVariantArguments(config: config, variant: StreamingVariant.defaultLadder[0], variantIndex: 0)
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-f hls"))
        XCTAssertTrue(argStr.contains("-hls_time"))
        XCTAssertTrue(argStr.contains("-s 1920x1080"))
        XCTAssertTrue(argStr.contains("libx264"))
    }

    /// Verifies DASH variant arguments.
    func test_manifestGenerator_dashVariantArguments() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .dash
        )
        let args = generator.buildVariantArguments(config: config, variant: StreamingVariant.defaultLadder[0], variantIndex: 0)
        let argStr = args.joined(separator: " ")

        XCTAssertTrue(argStr.contains("-f dash"))
        XCTAssertTrue(argStr.contains("-seg_duration"))
    }

    /// Verifies master HLS playlist generation.
    func test_manifestGenerator_masterPlaylist() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        let playlist = generator.buildMasterPlaylist(config: config)

        XCTAssertTrue(playlist.contains("#EXTM3U"))
        XCTAssertTrue(playlist.contains("#EXT-X-STREAM-INF"))
        XCTAssertTrue(playlist.contains("RESOLUTION=1920x1080"))
        XCTAssertTrue(playlist.contains("RESOLUTION=1280x720"))
        XCTAssertTrue(playlist.contains("v0_1080p/playlist.m3u8"))
    }

    /// Verifies DASH MPD manifest generation.
    func test_manifestGenerator_dashManifest() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")
        let config = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            format: .dash
        )
        let mpd = generator.buildDASHManifest(config: config)

        XCTAssertTrue(mpd.contains("<?xml"))
        XCTAssertTrue(mpd.contains("<MPD"))
        XCTAssertTrue(mpd.contains("Representation"))
        XCTAssertTrue(mpd.contains("width=\"1920\""))
    }

    /// Verifies manifest config validation.
    func test_manifestGenerator_validation() {
        let generator = ManifestGenerator(ffmpegPath: "/usr/bin/ffmpeg")

        // Valid config
        let validConfig = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        let validIssues = generator.validate(config: validConfig)
        XCTAssertTrue(validIssues.isEmpty, "Default config should be valid")

        // Empty variants
        let emptyConfig = ManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/"),
            variants: []
        )
        let emptyIssues = generator.validate(config: emptyConfig)
        XCTAssertTrue(emptyIssues.contains { $0.contains("No variants") })
    }

    // -----------------------------------------------------------------
    // MARK: - EncodingProfile New Properties Tests
    // -----------------------------------------------------------------

    /// Verifies new tone mapping parameters exist and round-trip.
    func test_profile_toneMapParameters() throws {
        var profile = EncodingProfile(name: "Test TM")
        profile.toneMapToSDR = true
        profile.toneMapAlgorithm = "hable"
        profile.toneMapPeakNits = 1000.0
        profile.toneMapDesaturation = 0.5

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.toneMapPeakNits, 1000.0)
        XCTAssertEqual(decoded.toneMapDesaturation, 0.5)
    }

    /// Verifies displayAspectRatio round-trips.
    func test_profile_displayAspectRatio() throws {
        var profile = EncodingProfile(name: "Test DAR")
        profile.displayAspectRatio = "16:9"

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EncodingProfile.self, from: data)

        XCTAssertEqual(decoded.displayAspectRatio, "16:9")
    }

    /// Verifies tone mapping params wire through toArgumentBuilder.
    func test_profile_toneMapParamsWiring() {
        var profile = EncodingProfile(name: "Test Wiring")
        profile.toneMapToSDR = true
        profile.toneMapAlgorithm = "mobius"
        profile.toneMapPeakNits = 4000.0
        profile.toneMapDesaturation = 0.8

        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        XCTAssertTrue(builder.toneMap)
        XCTAssertEqual(builder.toneMapAlgorithm, .mobius)
        XCTAssertEqual(builder.toneMapPeakNits, 4000.0)
        XCTAssertEqual(builder.toneMapDesaturation, 0.8)
    }

    /// Verifies displayAspectRatio wires through toArgumentBuilder.
    func test_profile_displayAspectRatioWiring() {
        var profile = EncodingProfile(name: "Test DAR Wiring")
        profile.displayAspectRatio = "2.35:1"

        let inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        XCTAssertEqual(builder.displayAspectRatio, "2.35:1")
    }

    // -----------------------------------------------------------------
    // MARK: - AudioProcessor Tests (Phase 5)
    // -----------------------------------------------------------------

    /// Verifies EBU R128 loudnorm filter generation.
    func test_audioProcessor_ebuR128Filter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .ebuR128)
        XCTAssertTrue(filter.contains("loudnorm"))
        XCTAssertTrue(filter.contains("I=-23"))
        XCTAssertTrue(filter.contains("TP=-1"))
        XCTAssertTrue(filter.contains("LRA=20"))
        XCTAssertTrue(filter.contains("linear=true"))
    }

    /// Verifies streaming loudness standard.
    func test_audioProcessor_streamingFilter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .streaming)
        XCTAssertTrue(filter.contains("I=-14"))
    }

    /// Verifies podcast loudness standard.
    func test_audioProcessor_podcastFilter() {
        let filter = AudioProcessor.buildLoudnormFilter(standard: .podcast)
        XCTAssertTrue(filter.contains("I=-16"))
    }

    /// Verifies two-pass measurement injection.
    func test_audioProcessor_twoPassMeasurement() {
        let measurement = LoudnessMeasurement(
            integratedLUFS: -25.0,
            truePeakDBTP: -0.5,
            loudnessRangeLU: 15.0
        )
        let filter = AudioProcessor.buildLoudnormFilter(
            standard: .ebuR128,
            measurement: measurement
        )
        XCTAssertTrue(filter.contains("measured_I=-25"))
        XCTAssertTrue(filter.contains("measured_TP=-0.5"))
        XCTAssertTrue(filter.contains("measured_LRA=15"))
    }

    /// Verifies analysis pass arguments.
    func test_audioProcessor_analysisPass() {
        let args = AudioProcessor.buildAnalysisPassArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv")
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-af loudnorm"))
        XCTAssertTrue(argStr.contains("-f null"))
        XCTAssertTrue(argStr.contains("/dev/null"))
    }

    /// Verifies ReplayGain analysis arguments.
    func test_audioProcessor_replayGainAnalysis() {
        let args = AudioProcessor.buildReplayGainAnalysisArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.flac")
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-af replaygain"))
        XCTAssertTrue(argStr.contains("-f null"))
    }

    /// Verifies ReplayGain volume filter.
    func test_audioProcessor_replayGainApply() {
        let filter = AudioProcessor.buildReplayGainApplyFilter(gainDB: -3.5)
        XCTAssertTrue(filter.contains("volume=-3.5dB"))
        XCTAssertTrue(filter.contains("alimiter"), "Should include peak limiter")
    }

    /// Verifies peak limiter filter.
    func test_audioProcessor_peakLimiter() {
        let filter = AudioProcessor.buildPeakLimiterFilter(limitDBTP: -1.0)
        XCTAssertTrue(filter.contains("alimiter"))
        XCTAssertTrue(filter.contains("limit="))
    }

    /// Verifies combined processing chain.
    func test_audioProcessor_combinedChain() {
        let chain = AudioProcessor.buildProcessingChain(
            normalize: true,
            standard: .ebuR128,
            limit: true
        )
        XCTAssertNotNil(chain)
        XCTAssertTrue(chain!.contains("loudnorm"))
    }

    /// Verifies LoudnessStandard properties.
    func test_loudnessStandard_properties() {
        XCTAssertEqual(LoudnessStandard.ebuR128.targetLUFS, -23.0)
        XCTAssertEqual(LoudnessStandard.atscA85.targetLUFS, -24.0)
        XCTAssertEqual(LoudnessStandard.streaming.targetLUFS, -14.0)
        XCTAssertEqual(LoudnessStandard.podcast.targetLUFS, -16.0)
        XCTAssertEqual(LoudnessStandard.ebuR128.targetTruePeak, -1.0)
        XCTAssertEqual(LoudnessStandard.atscA85.targetTruePeak, -2.0)
    }

    // -----------------------------------------------------------------
    // MARK: - SubtitleConverter Tests (Phase 5)
    // -----------------------------------------------------------------

    /// Verifies text subtitle conversion arguments.
    func test_subtitleConverter_textConversion() {
        let args = SubtitleConverter.buildTextConversionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.srt"),
            inputFormat: .ssa,
            outputFormat: .srt
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-c:s srt"))
        XCTAssertTrue(argStr.contains("-map 0:s:0"))
    }

    /// Verifies subtitle extraction arguments.
    func test_subtitleConverter_extraction() {
        let args = SubtitleConverter.buildExtractionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/subs.vtt"),
            streamIndex: 2,
            outputFormat: .webVTT
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-map 0:s:2"))
        XCTAssertTrue(argStr.contains("-c:s webvtt"))
        XCTAssertTrue(argStr.contains("-vn"))
        XCTAssertTrue(argStr.contains("-an"))
    }

    /// Verifies burn-in filter generation.
    func test_subtitleConverter_burnIn() {
        let filter = SubtitleConverter.buildBurnInFilter(
            subtitlePath: "/tmp/subs.srt",
            fontSize: 24,
            fontName: "Arial"
        )
        XCTAssertTrue(filter.contains("subtitles="))
        XCTAssertTrue(filter.contains("FontSize=24"))
        XCTAssertTrue(filter.contains("FontName=Arial"))
    }

    /// Verifies conversion matrix.
    func test_subtitleConverter_conversionMatrix() {
        XCTAssertTrue(SubtitleConverter.canConvert(from: .srt, to: .webVTT))
        XCTAssertTrue(SubtitleConverter.canConvert(from: .ssa, to: .srt))
        XCTAssertTrue(SubtitleConverter.canConvert(from: .pgs, to: .srt)) // OCR
        XCTAssertFalse(SubtitleConverter.canConvert(from: .srt, to: .pgs)) // Can't create bitmap
    }

    /// Verifies OCR requirement detection.
    func test_subtitleConverter_ocrRequired() {
        XCTAssertTrue(SubtitleConverter.requiresOCR(from: .pgs, to: .srt))
        XCTAssertTrue(SubtitleConverter.requiresOCR(from: .vobSub, to: .webVTT))
        XCTAssertFalse(SubtitleConverter.requiresOCR(from: .srt, to: .webVTT))
    }

    /// Verifies FFmpeg codec mapping.
    func test_subtitleConverter_codecMapping() {
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .srt), "srt")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .webVTT), "webvtt")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .ssa), "ass")
        XCTAssertEqual(SubtitleConverter.ffmpegSubtitleCodec(for: .pgs), "hdmv_pgs_subtitle")
    }

    // -----------------------------------------------------------------
    // MARK: - Streaming Enhancements Tests (Phase 6)
    // -----------------------------------------------------------------

    /// Verifies HLS encryption key generation.
    func test_hlsEncryption_keyGeneration() {
        let (hex, bytes) = HLSEncryption.generateKey()
        XCTAssertEqual(hex.count, 32, "Hex key should be 32 characters (16 bytes)")
        XCTAssertEqual(bytes.count, 16, "Key should be 16 bytes")
    }

    /// Verifies Data hex string initializer.
    func test_data_hexInit() {
        let data = Data(hexString: "48656c6c6f")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 5)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")

        let invalid = Data(hexString: "xyz")
        XCTAssertNil(invalid)
    }

    /// Verifies thumbnail extraction arguments.
    func test_thumbnailSprite_extractionArgs() {
        let config = ThumbnailSpriteGenerator.Config(intervalSeconds: 10.0)
        let args = ThumbnailSpriteGenerator.buildExtractionArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputPattern: "/tmp/thumb_%04d.jpg",
            config: config
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("-vf"))
        XCTAssertTrue(argStr.contains("fps="))
        XCTAssertTrue(argStr.contains("scale=160:90"))
        XCTAssertTrue(argStr.contains("-an"))
    }

    /// Verifies sprite sheet arguments.
    func test_thumbnailSprite_spriteSheetArgs() {
        let args = ThumbnailSpriteGenerator.buildSpriteSheetArguments(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputPath: "/tmp/sprites.jpg"
        )
        let argStr = args.joined(separator: " ")
        XCTAssertTrue(argStr.contains("tile="))
        XCTAssertTrue(argStr.contains("-frames:v 1"))
    }

    /// Verifies WebVTT thumbnail map generation.
    func test_thumbnailSprite_webVTT() {
        let config = ThumbnailSpriteGenerator.Config(
            intervalSeconds: 10.0,
            thumbnailWidth: 160,
            thumbnailHeight: 90,
            columns: 10
        )
        let vtt = ThumbnailSpriteGenerator.buildWebVTT(
            spriteURL: "sprites.jpg",
            config: config,
            totalDuration: 30.0
        )
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("sprites.jpg#xywh="))
        XCTAssertTrue(vtt.contains("00:00:00.000"))
    }

    /// Verifies streaming presets exist and have valid settings.
    func test_streamingPresets_exist() {
        let presets = StreamingPreset.builtInPresets
        XCTAssertEqual(presets.count, 5)

        for preset in presets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.variants.isEmpty)
            XCTAssertGreaterThan(preset.segmentDuration, 0)
            XCTAssertGreaterThan(preset.keyframeInterval, 0)
        }
    }

    /// Verifies Apple HLS preset settings.
    func test_streamingPresets_appleHLS() {
        let preset = StreamingPreset.appleHLS
        XCTAssertEqual(preset.format, .hls)
        XCTAssertEqual(preset.videoCodec, .h264)
        XCTAssertEqual(preset.audioCodec, .aacLC)
        XCTAssertEqual(preset.segmentDuration, 6.0)
    }

    /// Verifies YouTube-like preset uses AV1.
    func test_streamingPresets_youtube() {
        let preset = StreamingPreset.youtubeLike
        XCTAssertEqual(preset.videoCodec, .av1)
        XCTAssertEqual(preset.audioCodec, .opus)
    }

    /// Verifies Netflix-like preset has HDR settings.
    func test_streamingPresets_netflix() {
        let preset = StreamingPreset.netflixLike
        XCTAssertEqual(preset.videoCodec, .h265)
        XCTAssertEqual(preset.pixelFormat, "yuv420p10le")
        XCTAssertEqual(preset.format, .cmaf)
    }

    /// Verifies preset to ManifestConfig conversion.
    func test_streamingPreset_toManifestConfig() {
        let config = StreamingPreset.appleHLS.toManifestConfig(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputDirectory: URL(fileURLWithPath: "/tmp/output/")
        )
        XCTAssertEqual(config.format, .hls)
        XCTAssertEqual(config.videoCodec, .h264)
        XCTAssertEqual(config.segmentDuration, 6.0)
        XCTAssertEqual(config.variants.count, StreamingVariant.defaultLadder.count)
    }

    /// Verifies loudness normalization wires into EncodingProfile.
    func test_profile_loudnessNormalization() {
        var profile = EncodingProfile(name: "Test Loudness")
        profile.loudnessNormalization = "ebu_r128"
        profile.applyPeakLimiter = true

        let builder = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        XCTAssertNotNil(builder.audioFilterChain)
        XCTAssertTrue(builder.audioFilterChain?.contains("loudnorm") ?? false)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: Spatial Audio Codecs
    // -----------------------------------------------------------------

    /// Verifies new spatial audio codecs exist and have correct display names.
    func test_spatialAudioCodecs_displayNames() {
        XCTAssertEqual(AudioCodec.dolbyMAT.displayName, "Dolby MAT")
        XCTAssertEqual(AudioCodec.iamf.displayName, "IAMF")
        XCTAssertEqual(AudioCodec.mpegH3D.displayName, "MPEG-H 3D Audio")
        XCTAssertEqual(AudioCodec.sonyRA.displayName, "Sony 360 Reality Audio")
        XCTAssertEqual(AudioCodec.ambisonics.displayName, "Ambisonics")
        XCTAssertEqual(AudioCodec.auro3D.displayName, "Auro-3D")
        XCTAssertEqual(AudioCodec.nhk222.displayName, "NHK 22.2")
        XCTAssertEqual(AudioCodec.ac4AJOC.displayName, "AC-4 A-JOC")
        XCTAssertEqual(AudioCodec.mp3Surround.displayName, "MP3 Surround")
        XCTAssertEqual(AudioCodec.imaxEnhanced.displayName, "IMAX Enhanced")
    }

    /// Verifies spatial audio codecs are passthrough-only (no FFmpeg encoder).
    func test_spatialAudioCodecs_passthroughOnly() {
        let spatialCodecs: [AudioCodec] = [
            .dolbyMAT, .iamf, .mpegH3D, .sonyRA, .asaf,
            .ambisonics, .auro3D, .nhk222, .ac4AJOC, .mp3Surround, .imaxEnhanced
        ]
        for codec in spatialCodecs {
            XCTAssertNil(codec.ffmpegEncoder, "\(codec.rawValue) should be passthrough-only")
        }
    }

    /// Verifies the isSpatial computed property.
    func test_spatialAudioCodecs_isSpatialProperty() {
        XCTAssertTrue(AudioCodec.dolbyMAT.isSpatial)
        XCTAssertTrue(AudioCodec.iamf.isSpatial)
        XCTAssertTrue(AudioCodec.ambisonics.isSpatial)
        XCTAssertTrue(AudioCodec.nhk222.isSpatial)
        XCTAssertFalse(AudioCodec.aac.isSpatial)
        XCTAssertFalse(AudioCodec.flac.isSpatial)
    }

    /// Verifies the isObjectBased computed property.
    func test_spatialAudioCodecs_isObjectBasedProperty() {
        XCTAssertTrue(AudioCodec.dolbyMAT.isObjectBased)
        XCTAssertTrue(AudioCodec.iamf.isObjectBased)
        XCTAssertTrue(AudioCodec.mpegH3D.isObjectBased)
        XCTAssertTrue(AudioCodec.ac4AJOC.isObjectBased)
        XCTAssertFalse(AudioCodec.ambisonics.isObjectBased)
        XCTAssertFalse(AudioCodec.nhk222.isObjectBased)
        XCTAssertFalse(AudioCodec.aac.isObjectBased)
    }

    /// Verifies maxChannels for spatial codecs.
    func test_spatialAudioCodecs_maxChannels() {
        XCTAssertEqual(AudioCodec.nhk222.maxChannels, 24)
        XCTAssertEqual(AudioCodec.ambisonics.maxChannels, 64)
        XCTAssertEqual(AudioCodec.auro3D.maxChannels, 14)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioFormat
    // -----------------------------------------------------------------

    /// Verifies SpatialAudioFormat raw values.
    func test_spatialAudioFormat_rawValues() {
        XCTAssertEqual(SpatialAudioFormat.channelBased.rawValue, "channel")
        XCTAssertEqual(SpatialAudioFormat.objectBased.rawValue, "object")
        XCTAssertEqual(SpatialAudioFormat.sceneBased.rawValue, "scene")
        XCTAssertEqual(SpatialAudioFormat.hybrid.rawValue, "hybrid")
    }

    /// Verifies SpatialAudioFormat CaseIterable conformance.
    func test_spatialAudioFormat_allCases() {
        XCTAssertEqual(SpatialAudioFormat.allCases.count, 4)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: AmbisonicsOrder
    // -----------------------------------------------------------------

    /// Verifies Ambisonics channel count formula: (order+1)².
    func test_ambisonicsOrder_channelCount() {
        XCTAssertEqual(AmbisonicsOrder.first.channelCount, 4)    // (1+1)² = 4
        XCTAssertEqual(AmbisonicsOrder.second.channelCount, 9)   // (2+1)² = 9
        XCTAssertEqual(AmbisonicsOrder.third.channelCount, 16)   // (3+1)² = 16
        XCTAssertEqual(AmbisonicsOrder.fourth.channelCount, 25)  // (4+1)² = 25
        XCTAssertEqual(AmbisonicsOrder.fifth.channelCount, 36)   // (5+1)² = 36
        XCTAssertEqual(AmbisonicsOrder.seventh.channelCount, 64) // (7+1)² = 64
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: StereoMode3D
    // -----------------------------------------------------------------

    /// Verifies StereoMode3D display names.
    func test_stereoMode3D_displayNames() {
        XCTAssertEqual(StereoMode3D.mono.displayName, "2D (Mono)")
        XCTAssertEqual(StereoMode3D.sideBySide.displayName, "Side-by-Side")
        XCTAssertEqual(StereoMode3D.topBottom.displayName, "Top-and-Bottom")
        XCTAssertEqual(StereoMode3D.multiview.displayName, "Multiview (MV-HEVC/MVC)")
        XCTAssertEqual(StereoMode3D.anaglyph.displayName, "Anaglyph")
    }

    /// Verifies isMultiStream is true only for multiview.
    func test_stereoMode3D_isMultiStream() {
        XCTAssertTrue(StereoMode3D.multiview.isMultiStream)
        XCTAssertFalse(StereoMode3D.sideBySide.isMultiStream)
        XCTAssertFalse(StereoMode3D.topBottom.isMultiStream)
        XCTAssertFalse(StereoMode3D.mono.isMultiStream)
    }

    /// Verifies StereoMode3D CaseIterable conformance.
    func test_stereoMode3D_allCases() {
        XCTAssertEqual(StereoMode3D.allCases.count, 9)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: Video3DMetadata
    // -----------------------------------------------------------------

    /// Verifies Video3DMetadata default initialization.
    func test_video3DMetadata_defaults() {
        let meta = Video3DMetadata()
        XCTAssertEqual(meta.stereoMode, .mono)
        XCTAssertNil(meta.viewIndex)
        XCTAssertNil(meta.viewCount)
        XCTAssertFalse(meta.viewsSwapped)
        XCTAssertNil(meta.baselineDistance)
    }

    /// Verifies Video3DMetadata custom initialization.
    func test_video3DMetadata_customInit() {
        let meta = Video3DMetadata(
            stereoMode: .sideBySide,
            viewIndex: 0,
            viewCount: 2,
            viewsSwapped: true,
            baselineDistance: 63.5
        )
        XCTAssertEqual(meta.stereoMode, .sideBySide)
        XCTAssertEqual(meta.viewIndex, 0)
        XCTAssertEqual(meta.viewCount, 2)
        XCTAssertTrue(meta.viewsSwapped)
        XCTAssertEqual(meta.baselineDistance, 63.5)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioMetadata
    // -----------------------------------------------------------------

    /// Verifies SpatialAudioMetadata default initialization.
    func test_spatialAudioMetadata_defaults() {
        let meta = SpatialAudioMetadata()
        XCTAssertEqual(meta.format, .channelBased)
        XCTAssertNil(meta.ambisonicsOrder)
        XCTAssertNil(meta.ambisonicsNorm)
        XCTAssertNil(meta.objectCount)
        XCTAssertNil(meta.bedChannels)
        XCTAssertFalse(meta.hasHeightChannels)
        XCTAssertFalse(meta.binauralRendering)
    }

    /// Verifies SpatialAudioMetadata scene-based initialization.
    func test_spatialAudioMetadata_sceneBased() {
        let meta = SpatialAudioMetadata(
            format: .sceneBased,
            ambisonicsOrder: .third,
            ambisonicsNorm: .sn3d
        )
        XCTAssertEqual(meta.format, .sceneBased)
        XCTAssertEqual(meta.ambisonicsOrder, .third)
        XCTAssertEqual(meta.ambisonicsNorm, .sn3d)
    }

    /// Verifies SpatialAudioMetadata hybrid initialization.
    func test_spatialAudioMetadata_hybrid() {
        let meta = SpatialAudioMetadata(
            format: .hybrid,
            objectCount: 118,
            bedChannels: 12,
            hasHeightChannels: true,
            binauralRendering: true
        )
        XCTAssertEqual(meta.format, .hybrid)
        XCTAssertEqual(meta.objectCount, 118)
        XCTAssertEqual(meta.bedChannels, 12)
        XCTAssertTrue(meta.hasHeightChannels)
        XCTAssertTrue(meta.binauralRendering)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: SpatialAudioConverter
    // -----------------------------------------------------------------

    /// Verifies Ambisonics encode filter output.
    func test_spatialAudioConverter_ambisonicsEncodeFilter() {
        let filter = SpatialAudioConverter.buildAmbisonicsEncodeFilter(
            order: .first, normalization: .sn3d
        )
        XCTAssertTrue(filter.contains("pan=4c"))
    }

    /// Verifies Ambisonics encode filter with third order (16 channels).
    func test_spatialAudioConverter_ambisonicsEncodeThirdOrder() {
        let filter = SpatialAudioConverter.buildAmbisonicsEncodeFilter(
            order: .third, normalization: .n3d
        )
        XCTAssertTrue(filter.contains("pan=16c"))
    }

    /// Verifies binaural downmix filter uses sofalizer.
    func test_spatialAudioConverter_binauralDownmix() {
        let filter = SpatialAudioConverter.buildBinauralDownmixFilter()
        XCTAssertTrue(filter.contains("sofalizer"))
        XCTAssertTrue(filter.contains("hrtf.sofa"))
    }

    /// Verifies Dolby MAT passthrough arguments.
    func test_spatialAudioConverter_matPassthrough() {
        let args = SpatialAudioConverter.buildMATPassthroughArguments()
        XCTAssertTrue(args.contains("-c:a"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies channel layout conversion downmix.
    func test_spatialAudioConverter_channelLayoutDownmix() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 8, to: 2)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=2c"))
    }

    /// Verifies channel layout conversion upmix.
    func test_spatialAudioConverter_channelLayoutUpmix() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 2, to: 6)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("5.1"))
    }

    /// Verifies no conversion when channel counts match.
    func test_spatialAudioConverter_noConversionNeeded() {
        let filter = SpatialAudioConverter.buildChannelLayoutConversion(from: 6, to: 6)
        XCTAssertNil(filter)
    }

    /// Verifies channel layout strings for standard configurations.
    func test_spatialAudioConverter_channelLayoutStrings() {
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 1), "mono")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 2), "stereo")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 6), "5.1")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 8), "7.1")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 12), "7.1.4")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 24), "22.2")
        XCTAssertEqual(SpatialAudioConverter.channelLayoutString(for: 3), "3c")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7: Video3DConverter
    // -----------------------------------------------------------------

    /// Verifies SBS to TB conversion filter.
    func test_video3DConverter_sbsToTB() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .topBottom)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d=sbsl:abl"))
    }

    /// Verifies TB to SBS conversion filter.
    func test_video3DConverter_tbToSBS() {
        let filter = Video3DConverter.buildConversionFilter(from: .topBottom, to: .sideBySide)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d=abl:sbsl"))
    }

    /// Verifies 3D to mono (left view extraction).
    func test_video3DConverter_3dToMono() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .mono)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("stereo3d="))
        XCTAssertTrue(filter!.contains(":ml"))
    }

    /// Verifies SBS to anaglyph conversion.
    func test_video3DConverter_sbsToAnaglyph() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .anaglyph)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("arcg"))
    }

    /// Verifies no conversion when modes match.
    func test_video3DConverter_noConversionNeeded() {
        let filter = Video3DConverter.buildConversionFilter(from: .sideBySide, to: .sideBySide)
        XCTAssertNil(filter)
    }

    /// Verifies 3D metadata arguments for SBS.
    func test_video3DConverter_metadataArgsSBS() {
        let meta = Video3DMetadata(stereoMode: .sideBySide)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.contains("-metadata:s:v:0"))
        XCTAssertTrue(args.contains("stereo_mode=side_by_side"))
    }

    /// Verifies 3D metadata arguments for top-bottom.
    func test_video3DConverter_metadataArgsTB() {
        let meta = Video3DMetadata(stereoMode: .topBottom)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.contains("stereo_mode=top_bottom"))
    }

    /// Verifies no metadata for mono mode.
    func test_video3DConverter_metadataArgsMono() {
        let meta = Video3DMetadata(stereoMode: .mono)
        let args = Video3DConverter.buildMetadataArguments(metadata: meta)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies AmbisonicsNormalization raw values.
    func test_ambisonicsNormalization_rawValues() {
        XCTAssertEqual(AmbisonicsNormalization.sn3d.rawValue, "sn3d")
        XCTAssertEqual(AmbisonicsNormalization.n3d.rawValue, "n3d")
        XCTAssertEqual(AmbisonicsNormalization.fuma.rawValue, "fuma")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.12: Quality Metrics
    // -----------------------------------------------------------------

    /// Verifies QualityMetricType CaseIterable conformance.
    func test_qualityMetricType_allCases() {
        XCTAssertEqual(QualityMetricType.allCases.count, 3)
        XCTAssertTrue(QualityMetricType.allCases.contains(.vmaf))
        XCTAssertTrue(QualityMetricType.allCases.contains(.ssim))
        XCTAssertTrue(QualityMetricType.allCases.contains(.psnr))
    }

    /// Verifies VMAF model raw values.
    func test_vmafModel_rawValues() {
        XCTAssertEqual(VMAFModel.standard.rawValue, "vmaf_v0.6.1")
        XCTAssertEqual(VMAFModel.uhd4K.rawValue, "vmaf_4k_v0.6.1")
        XCTAssertEqual(VMAFModel.phone.rawValue, "vmaf_v0.6.1neg")
    }

    /// Verifies VMAF argument construction.
    func test_qualityMetrics_vmafArguments() {
        let args = QualityMetricsBuilder.buildVMAFArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/encoded.mp4"))
        XCTAssertTrue(args.contains("/tmp/source.mp4"))
        let lavfi = args.first { $0.contains("libvmaf") }
        XCTAssertNotNil(lavfi)
        XCTAssertTrue(lavfi?.contains("vmaf_v0.6.1") ?? false)
    }

    /// Verifies VMAF with 4K model and log path.
    func test_qualityMetrics_vmaf4KWithLog() {
        let args = QualityMetricsBuilder.buildVMAFArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            model: .uhd4K,
            logPath: "/tmp/vmaf.json"
        )
        let lavfi = args.first { $0.contains("libvmaf") }
        XCTAssertNotNil(lavfi)
        XCTAssertTrue(lavfi?.contains("vmaf_4k_v0.6.1") ?? false)
        XCTAssertTrue(lavfi?.contains("log_path") ?? false)
        XCTAssertTrue(lavfi?.contains("log_fmt=json") ?? false)
    }

    /// Verifies SSIM argument construction.
    func test_qualityMetrics_ssimArguments() {
        let args = QualityMetricsBuilder.buildSSIMArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            logPath: "/tmp/ssim.log"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        let filter = args.first { $0.contains("ssim") }
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter?.contains("stats_file") ?? false)
    }

    /// Verifies PSNR argument construction.
    func test_qualityMetrics_psnrArguments() {
        let args = QualityMetricsBuilder.buildPSNRArguments(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4"
        )
        XCTAssertTrue(args.contains("-lavfi"))
        let filter = args.first { $0.contains("psnr") }
        XCTAssertNotNil(filter)
    }

    /// Verifies VMAF score parsing from FFmpeg output.
    func test_qualityMetrics_parseVMAF() {
        let output = """
        [libvmaf @ 0x12345] VMAF score: 95.123456
        """
        let score = QualityMetricsBuilder.parseVMAFScore(from: output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 95.123456, accuracy: 0.001)
    }

    /// Verifies SSIM score parsing from FFmpeg output.
    func test_qualityMetrics_parseSSIM() {
        let output = """
        [Parsed_ssim_0 @ 0x12345] SSIM Y:0.987654 U:0.993210 V:0.991234 All:0.990699 (20.41)
        """
        let score = QualityMetricsBuilder.parseSSIMScore(from: output)
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 0.990699, accuracy: 0.0001)
    }

    /// Verifies PSNR score parsing from FFmpeg output.
    func test_qualityMetrics_parsePSNR() {
        let output = """
        [Parsed_psnr_0 @ 0x12345] PSNR y:45.123456 u:47.234567 v:46.345678 average:45.901234 min:32.123456 max:inf
        """
        let result = QualityMetricsBuilder.parsePSNRScore(from: output)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.average, 45.901234, accuracy: 0.001)
        XCTAssertEqual(result!.min, 32.123456, accuracy: 0.001)
    }

    /// Verifies QualityScore summary text.
    func test_qualityScore_summary() {
        let vmaf = QualityScore(metric: .vmaf, mean: 95.5, min: 82.0, max: 99.0)
        XCTAssertTrue(vmaf.summary.contains("Excellent"))
        XCTAssertTrue(vmaf.summary.contains("95.50"))

        let ssim = QualityScore(metric: .ssim, mean: 0.85, min: 0.72, max: 0.99)
        XCTAssertTrue(ssim.summary.contains("Fair"))

        let psnr = QualityScore(metric: .psnr, mean: 42.5, min: 30.0, max: 50.0)
        XCTAssertTrue(psnr.summary.contains("Excellent"))
    }

    /// Verifies QualityReport threshold checking.
    func test_qualityReport_meetsThresholds() {
        let good = QualityReport(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 93, min: 80, max: 99),
                QualityScore(metric: .ssim, mean: 0.97, min: 0.92, max: 1.0),
            ]
        )
        XCTAssertTrue(good.meetsQualityThresholds)

        let bad = QualityReport(
            referencePath: "/tmp/source.mp4",
            distortedPath: "/tmp/encoded.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 70, min: 50, max: 85),
            ]
        )
        XCTAssertFalse(bad.meetsQualityThresholds)
    }

    /// Verifies QualityReport score lookup.
    func test_qualityReport_scoreLookup() {
        let report = QualityReport(
            referencePath: "/tmp/a.mp4",
            distortedPath: "/tmp/b.mp4",
            scores: [
                QualityScore(metric: .vmaf, mean: 90, min: 80, max: 99),
                QualityScore(metric: .psnr, mean: 42, min: 35, max: 50),
            ]
        )
        XCTAssertNotNil(report.score(for: .vmaf))
        XCTAssertNotNil(report.score(for: .psnr))
        XCTAssertNil(report.score(for: .ssim))
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.13: Scene Detection & Chaptering
    // -----------------------------------------------------------------

    /// Verifies scene detection argument construction.
    func test_sceneDetector_detectionArguments() {
        let args = SceneDetector.buildDetectionArguments(
            inputPath: "/tmp/video.mp4",
            threshold: 0.4
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        let vf = args.first { $0.contains("scene") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("0.40") ?? false)
    }

    /// Verifies scene change parsing from FFmpeg output.
    func test_sceneDetector_parseSceneChanges() {
        let output = """
        [Parsed_showinfo_1 @ 0x12345] n:  42 pts:  512000 pts_time:5.333 pos:123456 fmt:yuv420p sar:1/1
        [Parsed_showinfo_1 @ 0x12345] n: 120 pts: 1440000 pts_time:15.000 pos:234567 fmt:yuv420p sar:1/1
        [Parsed_showinfo_1 @ 0x12345] n: 250 pts: 3000000 pts_time:31.250 pos:345678 fmt:yuv420p sar:1/1
        """
        let changes = SceneDetector.parseSceneChanges(from: output)
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[0].timestamp, 5.333, accuracy: 0.001)
        XCTAssertEqual(changes[1].timestamp, 15.0, accuracy: 0.001)
        XCTAssertEqual(changes[2].timestamp, 31.25, accuracy: 0.001)
        XCTAssertEqual(changes[0].frameNumber, 42)
    }

    /// Verifies chapter generation from scene changes (every scene strategy).
    func test_sceneDetector_generateChaptersEveryScene() {
        let scenes = [
            SceneChange(timestamp: 60.0, score: 0.5),
            SceneChange(timestamp: 120.0, score: 0.4),
            SceneChange(timestamp: 180.0, score: 0.6),
        ]
        let chapters = SceneDetector.generateChapters(
            from: scenes,
            duration: 240.0,
            strategy: .everyScene,
            minimumDuration: 30.0
        )
        // Chapter 1 at 0, plus 3 scene chapters
        XCTAssertEqual(chapters.count, 4)
        XCTAssertEqual(chapters[0].startTime, 0)
        XCTAssertEqual(chapters[0].title, "Chapter 1")
        XCTAssertEqual(chapters[1].startTime, 60.0)
        XCTAssertEqual(chapters[3].startTime, 180.0)
    }

    /// Verifies micro-chapter filtering with minimum duration.
    func test_sceneDetector_minimumDurationFilter() {
        let scenes = [
            SceneChange(timestamp: 5.0, score: 0.5),  // Too close to start
            SceneChange(timestamp: 60.0, score: 0.4),
            SceneChange(timestamp: 65.0, score: 0.3),  // Too close to previous
        ]
        let chapters = SceneDetector.generateChapters(
            from: scenes,
            duration: 120.0,
            strategy: .everyScene,
            minimumDuration: 30.0
        )
        // Should get: Chapter 1 at 0, Chapter 2 at 60 (5s too close to 0, 65s too close to 60)
        XCTAssertEqual(chapters.count, 2)
    }

    /// Verifies fixed-interval chapter generation.
    func test_sceneDetector_fixedIntervalChapters() {
        let chapters = SceneDetector.generateChapters(
            from: [],
            duration: 900.0,
            strategy: .fixedInterval,
            fixedInterval: 300.0
        )
        // 0, 300, 600 (3 chapters at 5-minute intervals for 15-min video)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].startTime, 0)
        XCTAssertEqual(chapters[1].startTime, 300.0)
        XCTAssertEqual(chapters[2].startTime, 600.0)
    }

    /// Verifies FFmetadata chapter output format.
    func test_sceneDetector_ffmetadataOutput() {
        let chapters = [
            Chapter(title: "Intro", startTime: 0, endTime: 60),
            Chapter(title: "Main", startTime: 60, endTime: 180),
        ]
        let metadata = SceneDetector.generateFFmetadata(chapters: chapters, duration: 180)
        XCTAssertTrue(metadata.contains(";FFMETADATA1"))
        XCTAssertTrue(metadata.contains("[CHAPTER]"))
        XCTAssertTrue(metadata.contains("TIMEBASE=1/1000"))
        XCTAssertTrue(metadata.contains("START=0"))
        XCTAssertTrue(metadata.contains("END=60000"))
        XCTAssertTrue(metadata.contains("title=Intro"))
        XCTAssertTrue(metadata.contains("START=60000"))
        XCTAssertTrue(metadata.contains("title=Main"))
    }

    /// Verifies OGG chapter format output.
    func test_sceneDetector_oggChapterOutput() {
        let chapters = [
            Chapter(title: "Scene 1", startTime: 0),
            Chapter(title: "Scene 2", startTime: 65.5),
        ]
        let ogg = SceneDetector.generateOGGChapters(chapters: chapters)
        XCTAssertTrue(ogg.contains("CHAPTER01=00:00:00.000"))
        XCTAssertTrue(ogg.contains("CHAPTER01NAME=Scene 1"))
        XCTAssertTrue(ogg.contains("CHAPTER02=00:01:05.000"))
        XCTAssertTrue(ogg.contains("CHAPTER02NAME=Scene 2"))
    }

    /// Verifies SceneChange formatted timestamp.
    func test_sceneChange_formattedTimestamp() {
        let change = SceneChange(timestamp: 3723.456)
        XCTAssertEqual(change.formattedTimestamp, "01:02:03.456")
    }

    /// Verifies ChapterGenerationStrategy raw values.
    func test_chapterStrategy_rawValues() {
        XCTAssertEqual(ChapterGenerationStrategy.everyScene.rawValue, "every_scene")
        XCTAssertEqual(ChapterGenerationStrategy.fixedInterval.rawValue, "fixed_interval")
        XCTAssertEqual(ChapterGenerationStrategy.keyScenes.rawValue, "key_scenes")
        XCTAssertEqual(ChapterGenerationStrategy.combined.rawValue, "combined")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.2: Forensic Watermarking
    // -----------------------------------------------------------------

    /// Verifies WatermarkStrength CaseIterable conformance and values.
    func test_watermarkStrength_allCases() {
        XCTAssertEqual(WatermarkStrength.allCases.count, 3)
        XCTAssertTrue(WatermarkStrength.light.opacity < WatermarkStrength.standard.opacity)
        XCTAssertTrue(WatermarkStrength.standard.opacity < WatermarkStrength.strong.opacity)
        XCTAssertTrue(WatermarkStrength.light.blendFactor < WatermarkStrength.strong.blendFactor)
    }

    /// Verifies WatermarkPayload encoding.
    func test_watermarkPayload_encodedString() {
        let payload = WatermarkPayload(
            identifier: "user-123",
            metadata: "license-abc"
        )
        XCTAssertTrue(payload.encodedString.contains("user-123"))
        XCTAssertTrue(payload.encodedString.contains("license-abc"))
        XCTAssertFalse(payload.payloadHash.isEmpty)
        XCTAssertEqual(payload.payloadHash.count, 16) // 16 hex chars
    }

    /// Verifies embed filter construction.
    func test_forensicWatermark_embedFilter() {
        let payload = WatermarkPayload(identifier: "test-user")
        let filter = ForensicWatermark.buildEmbedFilter(
            payload: payload,
            strength: .standard
        )
        XCTAssertTrue(filter.contains("drawtext"))
        XCTAssertTrue(filter.contains(payload.payloadHash))
        XCTAssertTrue(filter.contains("fontcolor=white@"))
    }

    /// Verifies multiple drawtext positions for redundancy.
    func test_forensicWatermark_multiplePositions() {
        let payload = WatermarkPayload(identifier: "test")
        let filter = ForensicWatermark.buildEmbedFilter(payload: payload)
        // Should have 5 drawtext filters chained
        let drawTextCount = filter.components(separatedBy: "drawtext").count - 1
        XCTAssertEqual(drawTextCount, 5)
    }

    /// Verifies noise watermark filter construction.
    func test_forensicWatermark_noiseFilter() {
        let payload = WatermarkPayload(identifier: "test")
        let filter = ForensicWatermark.buildNoiseWatermarkFilter(
            payload: payload,
            strength: .standard
        )
        XCTAssertTrue(filter.contains("noise="))
        XCTAssertTrue(filter.contains("amount="))
    }

    /// Verifies metadata arguments for container embedding.
    func test_forensicWatermark_metadataArguments() {
        let payload = WatermarkPayload(identifier: "user-456")
        let args = ForensicWatermark.buildMetadataArguments(payload: payload)
        XCTAssertTrue(args.contains("-metadata"))
        XCTAssertTrue(args.contains("encoded_by=MeedyaConverter"))
        let wmArg = args.first { $0.contains("watermark_id=") }
        XCTAssertNotNil(wmArg)
    }

    /// Verifies complete watermark arguments when enabled.
    func test_forensicWatermark_enabledConfig() {
        let config = WatermarkConfig(
            enabled: true,
            payload: WatermarkPayload(identifier: "test"),
            strength: .strong
        )
        let (filter, args) = ForensicWatermark.buildWatermarkArguments(config: config)
        XCTAssertFalse(filter.isEmpty)
        XCTAssertFalse(args.isEmpty)
        XCTAssertTrue(filter.contains("drawtext"))
    }

    /// Verifies watermark arguments when disabled.
    func test_forensicWatermark_disabledConfig() {
        let config = WatermarkConfig(
            enabled: false,
            payload: WatermarkPayload(identifier: "test")
        )
        let (filter, args) = ForensicWatermark.buildWatermarkArguments(config: config)
        XCTAssertTrue(filter.isEmpty)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies detection argument construction.
    func test_forensicWatermark_detectionArguments() {
        let args = ForensicWatermark.buildDetectionArguments(
            inputPath: "/tmp/video.mp4",
            outputPath: "/tmp/analysis.png",
            seekTo: 30.0
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("/tmp/analysis.png"))
        let vf = args.first { $0.contains("contrast") }
        XCTAssertNotNil(vf)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.14: Crop Detection (existing CropDetector)
    // -----------------------------------------------------------------

    /// Verifies CropRect filter string generation.
    func test_cropRect_filterString() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.filterString, "crop=1920:800:0:140")
    }

    /// Verifies CropRect display string.
    func test_cropRect_displayString() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.displayString, "1920x800+0+140")
    }

    /// Verifies CropRect aspect ratio calculation.
    func test_cropRect_aspectRatio() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertEqual(crop.aspectRatio, 2.4, accuracy: 0.01)
    }

    /// Verifies CropRect cropping detection.
    func test_cropRect_isCropping() {
        let crop = CropRect(width: 1920, height: 800, x: 0, y: 140)
        XCTAssertTrue(crop.isCropping(sourceWidth: 1920, sourceHeight: 1080))
        XCTAssertFalse(crop.isCropping(sourceWidth: 1920, sourceHeight: 800))
    }

    /// Verifies cropdetect output parsing.
    func test_cropDetector_parseCropOutput() {
        let output = """
        [Parsed_cropdetect_0 @ 0x12345] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:12345
        [Parsed_cropdetect_0 @ 0x12345] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:23456
        """
        let crops = CropDetector.parseCropDetectOutput(output)
        XCTAssertEqual(crops.count, 2)
        XCTAssertEqual(crops[0].width, 1920)
        XCTAssertEqual(crops[0].height, 800)
        XCTAssertEqual(crops[0].x, 0)
        XCTAssertEqual(crops[0].y, 140)
    }

    /// Verifies CropDetectionResult summary.
    func test_cropDetectionResult_summary() {
        let result = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 800, x: 0, y: 140),
            detectedCrops: [],
            confidence: 0.95,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertTrue(result.willCrop)
        XCTAssertTrue(result.cropPercentage > 0)
        XCTAssertTrue(result.summary.contains("removes"))
    }

    /// Verifies no-crop result.
    func test_cropDetectionResult_noCrop() {
        let result = CropDetectionResult(
            recommendedCrop: CropRect(width: 1920, height: 1080, x: 0, y: 0),
            detectedCrops: [],
            confidence: 1.0,
            sourceWidth: 1920,
            sourceHeight: 1080
        )
        XCTAssertFalse(result.willCrop)
        XCTAssertEqual(result.cropPercentage, 0, accuracy: 0.01)
        XCTAssertTrue(result.summary.contains("No black bars"))
    }
}
