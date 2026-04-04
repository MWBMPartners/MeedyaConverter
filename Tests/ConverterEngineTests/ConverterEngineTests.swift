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

    /// Verifies auto-chaptering is skipped when source already has chapters.
    func test_sceneDetector_shouldAutoChapter() {
        XCTAssertTrue(SceneDetector.shouldAutoChapter(existingChapterCount: 0))
        XCTAssertFalse(SceneDetector.shouldAutoChapter(existingChapterCount: 1))
        XCTAssertFalse(SceneDetector.shouldAutoChapter(existingChapterCount: 5))
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

    // -----------------------------------------------------------------
    // MARK: - Phase 7.3: Encoding Reports
    // -----------------------------------------------------------------

    /// Verifies EncodingReport compression ratio calculation.
    func test_encodingReport_compressionRatio() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 1_000_000_000, // 1 GB
            inputDuration: 3600,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 250_000_000 // 250 MB
        )
        XCTAssertEqual(report.compressionRatio, 4.0, accuracy: 0.01)
        XCTAssertEqual(report.sizeReductionPercent, 75.0, accuracy: 0.01)
    }

    /// Verifies EncodingReport plain text output.
    func test_encodingReport_plainText() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 500_000_000,
            inputDuration: 1800,
            inputFormat: "matroska",
            inputStreams: [
                StreamReport(type: "video", codec: "h265", bitrate: 5_000_000, resolution: "1920x1080"),
                StreamReport(type: "audio", codec: "aac", bitrate: 160_000, channels: 2),
            ],
            outputPath: "/tmp/output.mp4",
            outputFileSize: 200_000_000,
            outputFormat: "mp4",
            profileName: "webStandard"
        )
        let text = report.toPlainText()
        XCTAssertTrue(text.contains("ENCODING REPORT"))
        XCTAssertTrue(text.contains("source.mkv"))
        XCTAssertTrue(text.contains("output.mp4"))
        XCTAssertTrue(text.contains("COMPRESSION"))
        XCTAssertTrue(text.contains("webStandard"))
    }

    /// Verifies EncodingReport Markdown output.
    func test_encodingReport_markdown() {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 500_000_000,
            inputDuration: 1800,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 200_000_000
        )
        let md = report.toMarkdown()
        XCTAssertTrue(md.contains("# Encoding Report"))
        XCTAssertTrue(md.contains("| Property | Value |"))
        XCTAssertTrue(md.contains("Compression"))
    }

    /// Verifies EncodingReport JSON serialization.
    func test_encodingReport_json() throws {
        let report = EncodingReport(
            inputPath: "/tmp/source.mkv",
            inputFileSize: 100_000,
            inputDuration: 60,
            outputPath: "/tmp/output.mp4",
            outputFileSize: 50_000
        )
        let data = try report.toJSON()
        XCTAssertFalse(data.isEmpty)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("inputPath"))
        XCTAssertTrue(str.contains("outputFileSize"))
    }

    /// Verifies EncodingPerformance formatted time.
    func test_encodingPerformance_formattedTime() {
        let short = EncodingPerformance(totalTime: 45)
        XCTAssertEqual(short.formattedTime, "45s")

        let medium = EncodingPerformance(totalTime: 185)
        XCTAssertEqual(medium.formattedTime, "3m 5s")

        let long = EncodingPerformance(totalTime: 7325)
        XCTAssertEqual(long.formattedTime, "2h 2m 5s")
    }

    /// Verifies StreamReport construction.
    func test_streamReport_construction() {
        let stream = StreamReport(
            type: "video",
            codec: "h265",
            bitrate: 5_000_000,
            resolution: "3840x2160",
            frameRate: 23.976
        )
        XCTAssertEqual(stream.type, "video")
        XCTAssertEqual(stream.codec, "h265")
        XCTAssertEqual(stream.bitrate, 5_000_000)
        XCTAssertEqual(stream.resolution, "3840x2160")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.16: Content-Aware Encoding
    // -----------------------------------------------------------------

    /// Verifies content complexity CRF adjustments.
    func test_contentComplexity_crfAdjustment() {
        XCTAssertGreaterThan(ContentComplexity.veryLow.crfAdjustment, 0) // Less quality needed
        XCTAssertEqual(ContentComplexity.medium.crfAdjustment, 0) // Baseline
        XCTAssertLessThan(ContentComplexity.veryHigh.crfAdjustment, 0) // More quality needed
    }

    /// Verifies content complexity bitrate multipliers.
    func test_contentComplexity_bitrateMultiplier() {
        XCTAssertLessThan(ContentComplexity.veryLow.bitrateMultiplier, 1.0)
        XCTAssertEqual(ContentComplexity.medium.bitrateMultiplier, 1.0)
        XCTAssertGreaterThan(ContentComplexity.veryHigh.bitrateMultiplier, 1.0)
    }

    /// Verifies complexity classification from scores.
    func test_contentAnalyzer_classifyComplexity() {
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.05, spatialComplexity: 0.05),
            .veryLow
        )
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.5, spatialComplexity: 0.5),
            .medium
        )
        XCTAssertEqual(
            ContentAnalyzer.classifyComplexity(temporalComplexity: 0.9, spatialComplexity: 0.9),
            .veryHigh
        )
    }

    /// Verifies CRF adjustment clamping.
    func test_contentAnalyzer_adjustedCRF() {
        let config = ContentAwareConfig(minCRF: 16, maxCRF: 32, baselineCRF: 22)

        let simple = ContentAnalyzer.adjustedCRF(config: config, complexity: .veryLow)
        XCTAssertEqual(simple, 26) // 22 + 4

        let complex = ContentAnalyzer.adjustedCRF(config: config, complexity: .veryHigh)
        XCTAssertEqual(complex, 18) // 22 - 4

        // Test clamping
        let extreme = ContentAwareConfig(minCRF: 20, maxCRF: 24, baselineCRF: 22)
        XCTAssertEqual(ContentAnalyzer.adjustedCRF(config: extreme, complexity: .veryLow), 24)
        XCTAssertEqual(ContentAnalyzer.adjustedCRF(config: extreme, complexity: .veryHigh), 20)
    }

    /// Verifies content-aware encoder arguments for H.265.
    func test_contentAnalyzer_h265Arguments() {
        let config = ContentAwareConfig()
        let analysis = ContentAnalysisResult(
            overallComplexity: .high,
            contentType: .film
        )
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .h265
        )
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("-tune"))
        XCTAssertTrue(args.contains("film"))
    }

    /// Verifies content-aware encoder arguments for AV1 with film grain.
    func test_contentAnalyzer_av1FilmGrain() {
        let config = ContentAwareConfig(filmGrainSynthesis: true)
        let analysis = ContentAnalysisResult(
            segments: [
                SegmentAnalysis(startTime: 0, endTime: 10,
                    temporalComplexity: 0.5, spatialComplexity: 0.5, hasFilmGrain: true)
            ],
            overallComplexity: .medium
        )
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .av1
        )
        XCTAssertTrue(args.contains("-film-grain-denoise"))
    }

    /// Verifies disabled content-aware produces empty arguments.
    func test_contentAnalyzer_disabled() {
        let config = ContentAwareConfig(enabled: false)
        let analysis = ContentAnalysisResult()
        let args = ContentAnalyzer.buildEncoderArguments(
            config: config, analysis: analysis, codec: .h265
        )
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies ContentType encoder tunes.
    func test_contentType_encoderTune() {
        XCTAssertEqual(ContentType.film.encoderTune, "film")
        XCTAssertEqual(ContentType.animation.encoderTune, "animation")
        XCTAssertEqual(ContentType.screenContent.encoderTune, "stillimage")
        XCTAssertNil(ContentType.documentary.encoderTune)
    }

    /// Verifies ContentAnalysisResult computed properties.
    func test_contentAnalysisResult_averages() {
        let result = ContentAnalysisResult(
            segments: [
                SegmentAnalysis(startTime: 0, endTime: 5,
                    temporalComplexity: 0.2, spatialComplexity: 0.3),
                SegmentAnalysis(startTime: 5, endTime: 10,
                    temporalComplexity: 0.8, spatialComplexity: 0.7),
            ],
            overallComplexity: .medium
        )
        XCTAssertEqual(result.averageTemporalComplexity, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.averageSpatialComplexity, 0.5, accuracy: 0.01)
    }

    /// Verifies analysis arguments construction.
    func test_contentAnalyzer_analysisArguments() {
        let args = ContentAnalyzer.buildAnalysisArguments(inputPath: "/tmp/video.mp4")
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        let vf = args.first { $0.contains("signalstats") }
        XCTAssertNotNil(vf)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.10: Watch Folder
    // -----------------------------------------------------------------

    /// Verifies WatchFolderConfig default initialization.
    func test_watchFolderConfig_defaults() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")
        XCTAssertEqual(config.name, "Test")
        XCTAssertEqual(config.watchPath, "/tmp/watch")
        XCTAssertNil(config.outputPath)
        XCTAssertEqual(config.profileName, "webStandard")
        XCTAssertTrue(config.fileExtensions.isEmpty)
        XCTAssertFalse(config.recursive)
        XCTAssertEqual(config.postAction, .leaveInPlace)
        XCTAssertEqual(config.concurrencyLimit, 1)
        XCTAssertTrue(config.isActive)
    }

    /// Verifies effective output path defaults to sibling "output" folder.
    func test_watchFolderConfig_effectiveOutputPath() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")
        XCTAssertTrue(config.effectiveOutputPath.contains("output"))

        let custom = WatchFolderConfig(
            name: "Test", watchPath: "/tmp/watch", outputPath: "/tmp/encoded"
        )
        XCTAssertEqual(custom.effectiveOutputPath, "/tmp/encoded")
    }

    /// Verifies file extension filtering.
    func test_watchFolderConfig_shouldProcess() {
        let config = WatchFolderConfig(name: "Test", watchPath: "/tmp/watch")

        // Default extensions — accepts common media files
        XCTAssertTrue(config.shouldProcess(filename: "movie.mkv"))
        XCTAssertTrue(config.shouldProcess(filename: "audio.flac"))
        XCTAssertTrue(config.shouldProcess(filename: "video.mp4"))
        XCTAssertFalse(config.shouldProcess(filename: "readme.txt"))
        XCTAssertFalse(config.shouldProcess(filename: "image.png"))

        // Hidden files rejected
        XCTAssertFalse(config.shouldProcess(filename: ".DS_Store"))
        XCTAssertFalse(config.shouldProcess(filename: ".hidden.mp4"))

        // System files rejected
        XCTAssertFalse(config.shouldProcess(filename: "Thumbs.db"))
        XCTAssertFalse(config.shouldProcess(filename: "desktop.ini"))
    }

    /// Verifies custom extension filtering.
    func test_watchFolderConfig_customExtensions() {
        let config = WatchFolderConfig(
            name: "Test", watchPath: "/tmp/watch",
            fileExtensions: ["mkv", "avi"]
        )
        XCTAssertTrue(config.shouldProcess(filename: "movie.mkv"))
        XCTAssertTrue(config.shouldProcess(filename: "movie.avi"))
        XCTAssertFalse(config.shouldProcess(filename: "movie.mp4"))
    }

    /// Verifies PostProcessingAction raw values.
    func test_postProcessingAction_rawValues() {
        XCTAssertEqual(PostProcessingAction.leaveInPlace.rawValue, "leave")
        XCTAssertEqual(PostProcessingAction.moveToCompleted.rawValue, "move")
        XCTAssertEqual(PostProcessingAction.deleteSource.rawValue, "delete")
    }

    /// Verifies output path generation.
    func test_fileStabilityChecker_outputPath() {
        let config = WatchFolderConfig(
            name: "Test",
            watchPath: "/tmp/watch",
            outputPath: "/tmp/output"
        )
        let path = FileStabilityChecker.outputPath(
            for: "/tmp/watch/movie.mkv",
            config: config,
            outputExtension: "mp4"
        )
        XCTAssertTrue(path.contains("movie.mp4"))
        XCTAssertTrue(path.contains("/tmp/output"))
    }

    /// Verifies WatchFolderConfig JSON round-trip.
    func test_watchFolderStore_roundTrip() throws {
        let configs = [
            WatchFolderConfig(name: "Folder 1", watchPath: "/tmp/w1"),
            WatchFolderConfig(name: "Folder 2", watchPath: "/tmp/w2", recursive: true),
        ]
        let data = try WatchFolderStore.encode(configs: configs)
        let decoded = try WatchFolderStore.decode(from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Folder 1")
        XCTAssertEqual(decoded[1].recursive, true)
    }

    /// Verifies WatchFolderStatus construction.
    func test_watchFolderStatus_construction() {
        let status = WatchFolderStatus(
            configId: "abc",
            isMonitoring: true,
            filesProcessed: 5,
            filesQueued: 2,
            filesFailed: 1
        )
        XCTAssertEqual(status.configId, "abc")
        XCTAssertTrue(status.isMonitoring)
        XCTAssertEqual(status.filesProcessed, 5)
        XCTAssertEqual(status.filesQueued, 2)
        XCTAssertEqual(status.filesFailed, 1)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.15: AI Upscaling
    // -----------------------------------------------------------------

    /// Verifies UpscaleModel display names and scale factors.
    func test_upscaleModel_properties() {
        XCTAssertEqual(UpscaleModel.realESRGAN.displayName, "Real-ESRGAN (General)")
        XCTAssertEqual(UpscaleModel.realESRGANAnime.displayName, "Real-ESRGAN (Anime)")
        XCTAssertEqual(UpscaleModel.realESRGAN.defaultScaleFactor, 4)
        XCTAssertEqual(UpscaleModel.waifu2x.defaultScaleFactor, 2)
        XCTAssertTrue(UpscaleModel.realESRGAN.supportedScaleFactors.contains(4))
    }

    /// Verifies UpscaleModel CaseIterable.
    func test_upscaleModel_allCases() {
        XCTAssertEqual(UpscaleModel.allCases.count, 4)
    }

    /// Verifies Real-ESRGAN argument construction.
    func test_aiUpscaler_realESRGANArguments() {
        let config = UpscaleConfig(model: .realESRGAN, scaleFactor: 4, tileSize: 256)
        let args = AIUpscaler.buildRealESRGANArguments(
            config: config,
            inputPath: "/tmp/input.png",
            outputPath: "/tmp/output.png"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/input.png"))
        XCTAssertTrue(args.contains("-n"))
        XCTAssertTrue(args.contains("realesrgan-x4plus"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("4"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("256"))
    }

    /// Verifies output resolution calculation.
    func test_aiUpscaler_calculateOutputResolution() {
        let res = AIUpscaler.calculateOutputResolution(
            sourceWidth: 960, sourceHeight: 540, scaleFactor: 4
        )
        XCTAssertEqual(res.width, 3840)
        XCTAssertEqual(res.height, 2160)
    }

    /// Verifies resolution rounding to even numbers.
    func test_aiUpscaler_resolutionRounding() {
        let res = AIUpscaler.calculateOutputResolution(
            sourceWidth: 481, sourceHeight: 271, scaleFactor: 2
        )
        XCTAssertEqual(res.width % 2, 0)
        XCTAssertEqual(res.height % 2, 0)
    }

    /// Verifies traditional upscale filter fallback.
    func test_aiUpscaler_traditionalFilter() {
        let filter = AIUpscaler.buildTraditionalUpscaleFilter(
            targetWidth: 3840, targetHeight: 2160
        )
        XCTAssertTrue(filter.contains("scale=3840:2160"))
        XCTAssertTrue(filter.contains("lanczos"))
    }

    /// Verifies VRAM estimation.
    func test_aiUpscaler_estimateVRAM() {
        let vram = AIUpscaler.estimateVRAM(width: 1920, height: 1080, scaleFactor: 4)
        XCTAssertGreaterThan(vram, 0)

        // Smaller tile = less VRAM
        let vramTiled = AIUpscaler.estimateVRAM(
            width: 1920, height: 1080, scaleFactor: 4, tileSize: 256
        )
        XCTAssertLessThan(vramTiled, vram)
    }

    /// Verifies frame extraction arguments.
    func test_aiUpscaler_frameExtraction() {
        let args = AIUpscaler.buildFrameExtractionArguments(
            inputPath: "/tmp/video.mp4",
            outputPattern: "/tmp/frames/%06d.png"
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("-pix_fmt"))
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.17: DCP Creation
    // -----------------------------------------------------------------

    /// Verifies DCP resolution dimensions.
    func test_dcpResolution_dimensions() {
        XCTAssertEqual(DCPResolution.dci2K.width, 2048)
        XCTAssertEqual(DCPResolution.dci2K.height, 1080)
        XCTAssertEqual(DCPResolution.dci4K.width, 4096)
        XCTAssertEqual(DCPResolution.dci4K.height, 2160)
    }

    /// Verifies DCP aspect ratio dimensions.
    func test_dcpAspectRatio_dimensions() {
        let flat2K = DCPAspectRatio.flat.activeDimensions(for: .dci2K)
        XCTAssertEqual(flat2K.width, 1998)
        XCTAssertEqual(flat2K.height, 1080)

        let scope2K = DCPAspectRatio.scope.activeDimensions(for: .dci2K)
        XCTAssertEqual(scope2K.width, 2048)
        XCTAssertEqual(scope2K.height, 858)

        let flat4K = DCPAspectRatio.flat.activeDimensions(for: .dci4K)
        XCTAssertEqual(flat4K.width, 3996)
        XCTAssertEqual(flat4K.height, 2160)
    }

    /// Verifies DCP video encode arguments.
    func test_dcpGenerator_videoEncodeArguments() {
        let config = DCPConfig(title: "Test Film", outputDirectory: "/tmp/dcp")
        let args = DCPGenerator.buildVideoEncodeArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/dcp/video.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libopenjpeg"))
        XCTAssertTrue(args.contains("-pix_fmt"))
        XCTAssertTrue(args.contains("xyz12le"))
        XCTAssertTrue(args.contains("-an"))
    }

    /// Verifies DCP audio encode arguments.
    func test_dcpGenerator_audioEncodeArguments() {
        let config = DCPConfig(title: "Test", audioChannels: 6, outputDirectory: "/tmp/dcp")
        let args = DCPGenerator.buildAudioEncodeArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/dcp/audio.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("pcm_s24le"))
        XCTAssertTrue(args.contains("48000"))
        XCTAssertTrue(args.contains("6"))
        XCTAssertTrue(args.contains("-vn"))
    }

    /// Verifies DCP ASSETMAP generation.
    func test_dcpGenerator_assetMap() {
        let xml = DCPGenerator.generateAssetMap(
            dcpId: "dcp-uuid",
            cplId: "cpl-uuid",
            pklId: "pkl-uuid",
            videoFile: "video.mxf",
            audioFile: "audio.mxf"
        )
        XCTAssertTrue(xml.contains("AssetMap"))
        XCTAssertTrue(xml.contains("urn:uuid:dcp-uuid"))
        XCTAssertTrue(xml.contains("urn:uuid:cpl-uuid"))
        XCTAssertTrue(xml.contains("video.mxf"))
        XCTAssertTrue(xml.contains("audio.mxf"))
        XCTAssertTrue(xml.contains("MeedyaConverter"))
    }

    /// Verifies DCP CPL generation.
    func test_dcpGenerator_cpl() {
        let config = DCPConfig(
            title: "My Film",
            contentKind: .feature,
            outputDirectory: "/tmp/dcp"
        )
        let xml = DCPGenerator.generateCPL(
            config: config,
            cplId: "cpl-uuid",
            videoId: "vid-uuid",
            audioId: "aud-uuid",
            durationFrames: 172800
        )
        XCTAssertTrue(xml.contains("CompositionPlaylist"))
        XCTAssertTrue(xml.contains("My Film"))
        XCTAssertTrue(xml.contains("feature"))
        XCTAssertTrue(xml.contains("172800"))
    }

    /// Verifies DCP validation.
    func test_dcpGenerator_validation() {
        let good = DCPConfig(title: "Film", frameRate: 24, outputDirectory: "/tmp")
        XCTAssertTrue(DCPGenerator.validate(config: good).isEmpty)

        let badFps = DCPConfig(title: "Film", frameRate: 30, outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: badFps).isEmpty)

        let noTitle = DCPConfig(title: "", outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: noTitle).isEmpty)

        let encrypted = DCPConfig(title: "Film", encrypted: true, outputDirectory: "/tmp")
        XCTAssertFalse(DCPGenerator.validate(config: encrypted).isEmpty)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.18: Audio Fingerprinting
    // -----------------------------------------------------------------

    /// Verifies fingerprint argument construction.
    func test_audioFingerprinter_arguments() {
        let args = AudioFingerprinter.buildFingerprintArguments(
            inputPath: "/tmp/audio.flac",
            duration: 120
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/audio.flac"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("chromaprint"))
        XCTAssertTrue(args.contains("-t"))
    }

    /// Verifies fingerprint argument with stream selection.
    func test_audioFingerprinter_streamSelection() {
        let args = AudioFingerprinter.buildFingerprintArguments(
            inputPath: "/tmp/video.mkv",
            streamIndex: 2
        )
        XCTAssertTrue(args.contains("-map"))
        XCTAssertTrue(args.contains("0:a:2"))
    }

    /// Verifies AcoustID URL construction.
    func test_audioFingerprinter_acoustIDURL() {
        let url = AudioFingerprinter.buildAcoustIDLookupURL(
            fingerprint: "AQAA",
            duration: 180,
            apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("api.acoustid.org"))
        XCTAssertTrue(url.contains("client=test-key"))
        XCTAssertTrue(url.contains("duration=180"))
        XCTAssertTrue(url.contains("fingerprint=AQAA"))
    }

    /// Verifies fingerprint comparison.
    func test_audioFingerprinter_compareIdentical() {
        let fp: [UInt32] = [0xAABBCCDD, 0x11223344, 0x55667788]
        let result = AudioFingerprinter.compareFingerprints(fp, fp)
        XCTAssertEqual(result.similarity, 1.0, accuracy: 0.001)
        XCTAssertTrue(result.isDefiniteMatch)
    }

    /// Verifies fingerprint comparison with different data.
    func test_audioFingerprinter_compareDifferent() {
        let fp1: [UInt32] = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
        let fp2: [UInt32] = [0x00000000, 0x00000000, 0x00000000]
        let result = AudioFingerprinter.compareFingerprints(fp1, fp2)
        XCTAssertEqual(result.similarity, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isLikelyMatch)
    }

    /// Verifies FingerprintMatch confidence levels.
    func test_fingerprintMatch_confidence() {
        let high = FingerprintMatch(confidence: 0.95, title: "Song")
        XCTAssertTrue(high.isHighConfidence)

        let low = FingerprintMatch(confidence: 0.3)
        XCTAssertFalse(low.isHighConfidence)
    }

    /// Verifies fingerprint parsing from output.
    func test_audioFingerprinter_parseFingerprint() {
        let output = "FINGERPRINT=AQADtNQYhYkYnYmR"
        let fp = AudioFingerprinter.parseFingerprint(from: output)
        XCTAssertEqual(fp, "AQADtNQYhYkYnYmR")
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 7.6: Auto Metadata Tagging
    // -----------------------------------------------------------------

    /// Verifies audio title generation.
    func test_metadataTagger_audioTitle() {
        let title = MetadataTagger.generateAudioTitle(
            codec: "aac", channels: 2, language: "English"
        )
        XCTAssertEqual(title, "English Stereo AAC")

        let surround = MetadataTagger.generateAudioTitle(
            codec: "truehd", channels: 8, language: "English"
        )
        XCTAssertEqual(surround, "English 7.1 TrueHD")
    }

    /// Verifies subtitle title generation.
    func test_metadataTagger_subtitleTitle() {
        let normal = MetadataTagger.generateSubtitleTitle(language: "English")
        XCTAssertEqual(normal, "English")

        let forced = MetadataTagger.generateSubtitleTitle(language: "French", isForced: true)
        XCTAssertEqual(forced, "French (Forced)")

        let sdh = MetadataTagger.generateSubtitleTitle(language: "English", isSDH: true)
        XCTAssertEqual(sdh, "English SDH")
    }

    /// Verifies forced subtitle detection.
    func test_metadataTagger_forcedDetection() {
        // 10% of video duration = likely forced
        XCTAssertTrue(MetadataTagger.isLikelyForced(
            subtitleDuration: 180, videoDuration: 5400
        ))
        // 80% of video duration = full subtitles, not forced
        XCTAssertFalse(MetadataTagger.isLikelyForced(
            subtitleDuration: 4320, videoDuration: 5400
        ))
        // 0 duration = not forced
        XCTAssertFalse(MetadataTagger.isLikelyForced(
            subtitleDuration: 0, videoDuration: 5400
        ))
    }

    /// Verifies SDH subtitle detection.
    func test_metadataTagger_sdhDetection() {
        let sdhText = """
        [door slams]
        What are you doing here?
        [dramatic music]
        I came to say goodbye.
        [footsteps approaching]
        """
        XCTAssertTrue(MetadataTagger.isLikelySDH(sampleText: sdhText))

        let normalText = """
        What are you doing here?
        I came to say goodbye.
        We should talk about this.
        """
        XCTAssertFalse(MetadataTagger.isLikelySDH(sampleText: normalText))
    }

    /// Verifies metadata arguments generation.
    func test_metadataTagger_buildArguments() {
        let suggestions = [
            StreamTagSuggestion(
                streamIndex: 0,
                streamType: "audio",
                suggestedTitle: "English 5.1 AAC",
                suggestedLanguage: "eng",
                isDefault: true
            ),
            StreamTagSuggestion(
                streamIndex: 0,
                streamType: "subtitle",
                suggestedTitle: "English (Forced)",
                isForced: true
            ),
        ]
        let args = MetadataTagger.buildMetadataArguments(suggestions: suggestions)
        XCTAssertTrue(args.contains("title=English 5.1 AAC"))
        XCTAssertTrue(args.contains("language=eng"))
        let dispArg = args.first { $0.contains("default") }
        XCTAssertNotNil(dispArg)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 12: Cloud Integration
    // -----------------------------------------------------------------

    /// Verifies CloudProvider CaseIterable and display names.
    func test_cloudProvider_allCases() {
        XCTAssertEqual(CloudProvider.allCases.count, 11)
        XCTAssertEqual(CloudProvider.awsS3.displayName, "Amazon S3")
        XCTAssertEqual(CloudProvider.dropbox.displayName, "Dropbox")
        XCTAssertEqual(CloudProvider.sftp.displayName, "SFTP")
    }

    /// Verifies streaming provider detection.
    func test_cloudProvider_supportsStreaming() {
        XCTAssertTrue(CloudProvider.cloudflareStream.supportsStreaming)
        XCTAssertTrue(CloudProvider.mux.supportsStreaming)
        XCTAssertFalse(CloudProvider.awsS3.supportsStreaming)
        XCTAssertFalse(CloudProvider.dropbox.supportsStreaming)
    }

    /// Verifies OAuth provider detection.
    func test_cloudProvider_usesOAuth() {
        XCTAssertTrue(CloudProvider.googleDrive.usesOAuth)
        XCTAssertTrue(CloudProvider.dropbox.usesOAuth)
        XCTAssertFalse(CloudProvider.awsS3.usesOAuth)
        XCTAssertFalse(CloudProvider.sftp.usesOAuth)
    }

    /// Verifies CloudCredential configuration validation.
    func test_cloudCredential_isConfigured() {
        let s3 = CloudCredential(provider: .awsS3, apiKey: "key", secret: "secret", bucket: "bucket")
        XCTAssertTrue(s3.isConfigured)

        let s3Incomplete = CloudCredential(provider: .awsS3, apiKey: "key")
        XCTAssertFalse(s3Incomplete.isConfigured)

        let sftp = CloudCredential(provider: .sftp, endpoint: "host.com", username: "user")
        XCTAssertTrue(sftp.isConfigured)

        let sftpIncomplete = CloudCredential(provider: .sftp)
        XCTAssertFalse(sftpIncomplete.isConfigured)
    }

    /// Verifies token expiry detection.
    func test_cloudCredential_tokenExpiry() {
        let expired = CloudCredential(
            provider: .googleDrive,
            accessToken: "token",
            tokenExpiry: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let valid = CloudCredential(
            provider: .googleDrive,
            accessToken: "token",
            tokenExpiry: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(valid.isTokenExpired)
    }

    /// Verifies UploadProgress calculations.
    func test_uploadProgress_calculations() {
        let progress = UploadProgress(
            bytesUploaded: 500_000_000,
            totalBytes: 1_000_000_000,
            bytesPerSecond: 10_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
        XCTAssertNotNil(progress.estimatedTimeRemaining)
        XCTAssertEqual(progress.estimatedTimeRemaining!, 50.0, accuracy: 0.1)
    }

    /// Verifies content type detection.
    func test_uploadConfig_contentType() {
        XCTAssertEqual(UploadConfig.contentType(for: "movie.mp4"), "video/mp4")
        XCTAssertEqual(UploadConfig.contentType(for: "audio.flac"), "audio/flac")
        XCTAssertEqual(UploadConfig.contentType(for: "subs.vtt"), "text/vtt")
        XCTAssertEqual(UploadConfig.contentType(for: "unknown.xyz"), "application/octet-stream")
    }

    /// Verifies S3 endpoint URL construction.
    func test_s3Uploader_endpointURL() {
        let cred = CloudCredential(
            provider: .awsS3, region: "eu-west-1", bucket: "my-bucket"
        )
        let url = S3Uploader.buildEndpointURL(credential: cred, objectKey: "video/output.mp4")
        XCTAssertTrue(url.contains("s3.eu-west-1.amazonaws.com"))
        XCTAssertTrue(url.contains("my-bucket"))
        XCTAssertTrue(url.contains("video/output.mp4"))
    }

    /// Verifies S3 multipart threshold.
    func test_s3Uploader_shouldUseMultipart() {
        XCTAssertFalse(S3Uploader.shouldUseMultipart(fileSize: 50 * 1024 * 1024)) // 50 MB
        XCTAssertTrue(S3Uploader.shouldUseMultipart(fileSize: 200 * 1024 * 1024)) // 200 MB
    }

    /// Verifies S3 part count calculation.
    func test_s3Uploader_partCount() {
        let count = S3Uploader.calculatePartCount(
            fileSize: 100_000_000, // 100 MB
            partSize: 8 * 1024 * 1024 // 8 MB parts
        )
        XCTAssertEqual(count, 13) // ceil(100/8)
    }

    /// Verifies S3 credential validation.
    func test_s3Uploader_validate() {
        let valid = CloudCredential(provider: .awsS3, apiKey: "k", secret: "s", bucket: "b")
        XCTAssertTrue(S3Uploader.validate(credential: valid).isEmpty)

        let invalid = CloudCredential(provider: .awsS3)
        XCTAssertFalse(S3Uploader.validate(credential: invalid).isEmpty)
    }

    /// Verifies S3 upload headers.
    func test_s3Uploader_headers() {
        let headers = S3Uploader.buildUploadHeaders(
            contentType: "video/mp4",
            contentLength: 1_000_000,
            metadata: ["title": "Test Video"]
        )
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "1000000")
        XCTAssertEqual(headers["x-amz-meta-title"], "Test Video")
    }

    /// Verifies SFTP SCP arguments.
    func test_sftpUploader_scpArguments() {
        let cred = CloudCredential(
            provider: .sftp, endpoint: "server.com", username: "user", port: 2222
        )
        let args = SFTPUploader.buildSCPArguments(
            credential: cred,
            localPath: "/tmp/video.mp4",
            remotePath: "/uploads/video.mp4"
        )
        XCTAssertTrue(args.contains("-P"))
        XCTAssertTrue(args.contains("2222"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("user@server.com:/uploads/video.mp4"))
    }

    /// Verifies SFTP batch commands.
    func test_sftpUploader_batch() {
        let batch = SFTPUploader.buildSFTPBatch(
            localPath: "/tmp/file.mp4",
            remotePath: "/uploads/file.mp4",
            createDirectory: true
        )
        XCTAssertTrue(batch.contains("-mkdir /uploads"))
        XCTAssertTrue(batch.contains("put /tmp/file.mp4 /uploads/file.mp4"))
        XCTAssertTrue(batch.contains("quit"))
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 15: Media Metadata Lookup
    // -----------------------------------------------------------------

    /// Verifies MetadataSource CaseIterable and properties.
    func test_metadataSource_allCases() {
        XCTAssertEqual(MetadataSource.allCases.count, 7)
        XCTAssertEqual(MetadataSource.tmdb.displayName, "The Movie Database (TMDB)")
        XCTAssertFalse(MetadataSource.musicBrainz.requiresAPIKey)
        XCTAssertTrue(MetadataSource.tmdb.requiresAPIKey)
    }

    /// Verifies TMDB movie search URL construction.
    func test_tmdbClient_movieSearchURL() {
        let url = TMDBClient.buildMovieSearchURL(
            query: "Inception", year: 2010, apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("api.themoviedb.org/3/search/movie"))
        XCTAssertTrue(url.contains("api_key=test-key"))
        XCTAssertTrue(url.contains("query=Inception"))
        XCTAssertTrue(url.contains("year=2010"))
    }

    /// Verifies TMDB TV search URL construction.
    func test_tmdbClient_tvSearchURL() {
        let url = TMDBClient.buildTVSearchURL(
            query: "Breaking Bad", apiKey: "test-key"
        )
        XCTAssertTrue(url.contains("search/tv"))
        XCTAssertTrue(url.contains("Breaking"))
    }

    /// Verifies TMDB poster URL construction.
    func test_tmdbClient_posterURL() {
        let url = TMDBClient.posterURL(path: "/abc123.jpg")
        XCTAssertEqual(url, "https://image.tmdb.org/t/p/w500/abc123.jpg")
    }

    /// Verifies MusicBrainz recording search URL.
    func test_musicBrainzClient_recordingSearch() {
        let url = MusicBrainzClient.buildRecordingSearchURL(
            title: "Bohemian Rhapsody", artist: "Queen"
        )
        XCTAssertTrue(url.contains("musicbrainz.org/ws/2/recording"))
        XCTAssertTrue(url.contains("fmt=json"))
        XCTAssertTrue(url.contains("Bohemian"))
    }

    /// Verifies MusicBrainz User-Agent.
    func test_musicBrainzClient_userAgent() {
        XCTAssertTrue(MusicBrainzClient.userAgent.contains("MeedyaConverter"))
    }

    /// Verifies OpenSubtitles search URL.
    func test_openSubtitlesClient_searchURL() {
        let url = OpenSubtitlesClient.buildSearchURL(
            query: "Inception", language: "en", apiKey: "test"
        )
        XCTAssertTrue(url.contains("opensubtitles.com"))
        XCTAssertTrue(url.contains("query=Inception"))
        XCTAssertTrue(url.contains("languages=en"))
    }

    /// Verifies OpenSubtitles headers.
    func test_openSubtitlesClient_headers() {
        let headers = OpenSubtitlesClient.buildHeaders(apiKey: "mykey")
        XCTAssertEqual(headers["Api-Key"], "mykey")
        XCTAssertNotNil(headers["User-Agent"])
    }

    /// Verifies filename parser — TV show pattern.
    func test_filenameParser_tvShow() {
        let result = FilenameParser.parse(filename: "Breaking.Bad.S03E07.720p.BluRay.mkv")
        XCTAssertEqual(result.mediaType, .tvEpisode)
        XCTAssertEqual(result.title, "Breaking Bad")
        XCTAssertEqual(result.season, 3)
        XCTAssertEqual(result.episode, 7)
    }

    /// Verifies filename parser — movie pattern.
    func test_filenameParser_movie() {
        let result = FilenameParser.parse(filename: "Inception (2010).mkv")
        XCTAssertEqual(result.mediaType, .movie)
        XCTAssertEqual(result.title, "Inception")
        XCTAssertEqual(result.year, 2010)
    }

    /// Verifies filename parser — music pattern.
    func test_filenameParser_music() {
        let result = FilenameParser.parse(filename: "Queen - Bohemian Rhapsody.flac")
        XCTAssertEqual(result.mediaType, .music)
        XCTAssertEqual(result.artist, "Queen")
        XCTAssertTrue(result.title.contains("Bohemian Rhapsody"))
    }

    /// Verifies filename parser — fallback.
    func test_filenameParser_fallback() {
        let result = FilenameParser.parse(filename: "random_video_file.mp4")
        XCTAssertEqual(result.mediaType, .movie)
        XCTAssertTrue(result.title.contains("random"))
    }

    /// Verifies MetadataResult construction.
    func test_metadataResult_construction() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            genres: ["Sci-Fi", "Action"],
            score: 8.4,
            runtimeMinutes: 148,
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        XCTAssertEqual(result.source, .tmdb)
        XCTAssertEqual(result.title, "Inception")
        XCTAssertEqual(result.year, 2010)
        XCTAssertEqual(result.genres.count, 2)
        XCTAssertEqual(result.confidence, 0.95)
    }

    // -----------------------------------------------------------------
    // MARK: - Phase 17: Image Conversion
    // -----------------------------------------------------------------

    /// Verifies ImageFormat CaseIterable.
    func test_imageFormat_allCases() {
        XCTAssertEqual(ImageFormat.allCases.count, 12)
    }

    /// Verifies ImageFormat file extensions.
    func test_imageFormat_fileExtensions() {
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.webp.fileExtension, "webp")
        XCTAssertEqual(ImageFormat.avif.fileExtension, "avif")
        XCTAssertEqual(ImageFormat.jpegXL.fileExtension, "jxl")
    }

    /// Verifies ImageFormat display names.
    func test_imageFormat_displayNames() {
        XCTAssertEqual(ImageFormat.jpeg.displayName, "JPEG")
        XCTAssertEqual(ImageFormat.heif.displayName, "HEIF/HEIC")
        XCTAssertEqual(ImageFormat.exr.displayName, "OpenEXR")
        XCTAssertEqual(ImageFormat.jpegXL.displayName, "JPEG XL")
    }

    /// Verifies ImageFormat FFmpeg encoder names.
    func test_imageFormat_encoders() {
        XCTAssertEqual(ImageFormat.jpeg.ffmpegEncoder, "mjpeg")
        XCTAssertEqual(ImageFormat.png.ffmpegEncoder, "png")
        XCTAssertEqual(ImageFormat.webp.ffmpegEncoder, "libwebp")
        XCTAssertEqual(ImageFormat.avif.ffmpegEncoder, "libaom-av1")
        XCTAssertNil(ImageFormat.heif.ffmpegEncoder) // Requires external tool
    }

    /// Verifies ImageFormat capability flags.
    func test_imageFormat_capabilities() {
        // Lossless
        XCTAssertTrue(ImageFormat.png.supportsLossless)
        XCTAssertTrue(ImageFormat.webp.supportsLossless)
        XCTAssertFalse(ImageFormat.jpeg.supportsLossless)

        // Alpha
        XCTAssertTrue(ImageFormat.png.supportsAlpha)
        XCTAssertTrue(ImageFormat.webp.supportsAlpha)
        XCTAssertFalse(ImageFormat.jpeg.supportsAlpha)

        // HDR
        XCTAssertTrue(ImageFormat.avif.supportsHDR)
        XCTAssertTrue(ImageFormat.exr.supportsHDR)
        XCTAssertFalse(ImageFormat.jpeg.supportsHDR)

        // Animation
        XCTAssertTrue(ImageFormat.gif.supportsAnimation)
        XCTAssertTrue(ImageFormat.webp.supportsAnimation)
        XCTAssertFalse(ImageFormat.jpeg.supportsAnimation)
    }

    /// Verifies format detection from file extension.
    func test_imageFormat_fromExtension() {
        XCTAssertEqual(ImageFormat.from(extension: "jpg"), .jpeg)
        XCTAssertEqual(ImageFormat.from(extension: "JPEG"), .jpeg)
        XCTAssertEqual(ImageFormat.from(extension: "png"), .png)
        XCTAssertEqual(ImageFormat.from(extension: "webp"), .webp)
        XCTAssertEqual(ImageFormat.from(extension: "heic"), .heif)
        XCTAssertEqual(ImageFormat.from(extension: "tif"), .tiff)
        XCTAssertNil(ImageFormat.from(extension: "mp4"))
    }

    /// Verifies ImageQuality presets.
    func test_imageQuality_presets() {
        XCTAssertEqual(ImageQuality.low.quality, 50)
        XCTAssertEqual(ImageQuality.medium.quality, 75)
        XCTAssertEqual(ImageQuality.high.quality, 90)
        XCTAssertEqual(ImageQuality.maximum.quality, 100)
        XCTAssertTrue(ImageQuality.losslessPreset.lossless)
    }

    /// Verifies ImageQuality clamping.
    func test_imageQuality_clamping() {
        let clamped = ImageQuality(quality: 200, effort: -5)
        XCTAssertEqual(clamped.quality, 100)
        XCTAssertEqual(clamped.effort, 0)
    }

    /// Verifies basic image conversion arguments.
    func test_imageConverter_basicConversion() {
        let config = ImageConvertConfig(outputFormat: .webp)
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/photo.webp",
            config: config
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/photo.jpg"))
        XCTAssertTrue(args.contains("-c:v"))
        XCTAssertTrue(args.contains("libwebp"))
        XCTAssertTrue(args.contains("/tmp/photo.webp"))
    }

    /// Verifies image resize with fit mode.
    func test_imageConverter_resizeFit() {
        let config = ImageConvertConfig(
            outputFormat: .jpeg,
            width: 800,
            height: 600,
            resizeMode: .fit
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/big.png",
            outputPath: "/tmp/small.jpg",
            config: config
        )
        let vf = args.first { $0.contains("scale=") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("force_original_aspect_ratio=decrease") ?? false)
    }

    /// Verifies image resize with fill mode.
    func test_imageConverter_resizeFill() {
        let config = ImageConvertConfig(
            outputFormat: .jpeg,
            width: 800,
            height: 600,
            resizeMode: .fill
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/big.png",
            outputPath: "/tmp/small.jpg",
            config: config
        )
        let vf = args.first { $0.contains("scale=") }
        XCTAssertNotNil(vf)
        XCTAssertTrue(vf?.contains("crop=800:600") ?? false)
    }

    /// Verifies metadata stripping.
    func test_imageConverter_stripMetadata() {
        let config = ImageConvertConfig(outputFormat: .jpeg, stripMetadata: true)
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/clean.jpg",
            config: config
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies lossless WebP arguments.
    func test_imageConverter_losslessWebP() {
        let config = ImageConvertConfig(
            outputFormat: .webp,
            quality: .losslessPreset
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.png",
            outputPath: "/tmp/photo.webp",
            config: config
        )
        XCTAssertTrue(args.contains("-lossless"))
        XCTAssertTrue(args.contains("1"))
    }

    /// Verifies thumbnail extraction arguments.
    func test_imageConverter_thumbnail() {
        let args = ImageConverter.buildThumbnailArguments(
            inputPath: "/tmp/video.mp4",
            outputPath: "/tmp/thumb.jpg",
            timestamp: 30.0,
            width: 320
        )
        XCTAssertTrue(args.contains("-ss"))
        XCTAssertTrue(args.contains("30.00"))
        XCTAssertTrue(args.contains("-frames:v"))
        XCTAssertTrue(args.contains("1"))
        let vf = args.first { $0.contains("scale=") }
        XCTAssertTrue(vf?.contains("320") ?? false)
    }

    /// Verifies image file detection.
    func test_imageConverter_isImageFile() {
        XCTAssertTrue(ImageConverter.isImageFile("photo.jpg"))
        XCTAssertTrue(ImageConverter.isImageFile("image.PNG"))
        XCTAssertTrue(ImageConverter.isImageFile("art.webp"))
        XCTAssertFalse(ImageConverter.isImageFile("video.mp4"))
        XCTAssertFalse(ImageConverter.isImageFile("document.pdf"))
    }

    /// Verifies format recommendation.
    func test_imageConverter_recommendFormat() {
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAlpha: false, preferSmallSize: false),
            .jpeg
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAlpha: true, preferSmallSize: true),
            .webp
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsHDR: true),
            .avif
        )
        XCTAssertEqual(
            ImageConverter.recommendFormat(needsAnimation: true, preferSmallSize: true),
            .webp
        )
    }

    /// Verifies AVIF quality arguments.
    func test_imageConverter_avifQuality() {
        let config = ImageConvertConfig(
            outputFormat: .avif,
            quality: ImageQuality(quality: 80)
        )
        let args = ImageConverter.buildConvertArguments(
            inputPath: "/tmp/photo.jpg",
            outputPath: "/tmp/photo.avif",
            config: config
        )
        XCTAssertTrue(args.contains("-crf"))
        XCTAssertTrue(args.contains("-still-picture"))
        XCTAssertTrue(args.contains("libaom-av1"))
    }

    // =========================================================================
    // MARK: - Phase 8: Disc Reading — DiscModels
    // =========================================================================

    /// Verifies DiscType enum properties.
    func test_discType_properties() {
        XCTAssertEqual(DiscType.audioCd.displayName, "Audio CD")
        XCTAssertTrue(DiscType.audioCd.hasAudio)
        XCTAssertFalse(DiscType.audioCd.hasVideo)

        XCTAssertEqual(DiscType.dvdVideo.displayName, "DVD-Video")
        XCTAssertTrue(DiscType.dvdVideo.hasVideo)
        XCTAssertFalse(DiscType.dvdVideo.hasAudio)

        XCTAssertEqual(DiscType.bluray.displayName, "Blu-ray")
        XCTAssertTrue(DiscType.bluray.hasVideo)

        XCTAssertEqual(DiscType.sacd.displayName, "Super Audio CD")
        XCTAssertTrue(DiscType.sacd.hasAudio)
    }

    /// Verifies disc capacity values.
    func test_discType_capacity() {
        XCTAssertEqual(DiscType.audioCd.maxCapacityBytes, 737_280_000)
        XCTAssertTrue(DiscType.dvdVideo.maxCapacityBytes > 8_000_000_000)
        XCTAssertTrue(DiscType.bluray.maxCapacityBytes > 50_000_000_000)
        XCTAssertTrue(DiscType.uhdBluray.maxCapacityBytes > 100_000_000_000 - 1)
    }

    /// Verifies DiscInfo initialization.
    func test_discInfo_init() {
        let info = DiscInfo(
            discType: .dvdVideo,
            label: "MY_MOVIE",
            titleCount: 5,
            totalDuration: 7200,
            isProtected: true,
            protectionType: "CSS",
            regionCode: 1
        )
        XCTAssertEqual(info.discType, .dvdVideo)
        XCTAssertEqual(info.label, "MY_MOVIE")
        XCTAssertEqual(info.titleCount, 5)
        XCTAssertTrue(info.isProtected)
        XCTAssertEqual(info.protectionType, "CSS")
    }

    /// Verifies DiscTrack constants.
    func test_discTrack_constants() {
        XCTAssertEqual(DiscTrack.sectorSize, 2352)
        XCTAssertEqual(DiscTrack.sectorsPerSecond, 75)
    }

    /// Verifies DiscTitle initialization.
    func test_discTitle_init() {
        let title = DiscTitle(
            number: 1,
            duration: 7200,
            chapterCount: 25,
            audioStreams: [
                DiscAudioStream(index: 0, language: "eng", codec: "AC-3", channels: 6),
            ],
            videoWidth: 720,
            videoHeight: 480,
            isMainFeature: true
        )
        XCTAssertEqual(title.number, 1)
        XCTAssertEqual(title.chapterCount, 25)
        XCTAssertTrue(title.isMainFeature)
        XCTAssertEqual(title.audioStreams.count, 1)
        XCTAssertEqual(title.audioStreams[0].channels, 6)
    }

    /// Verifies DriveCapability read/write checks.
    func test_driveCapability_canRead() {
        let drive = DriveCapability(
            devicePath: "/dev/sr0",
            canReadCD: true,
            canReadDVD: true,
            canReadBluray: true,
            canReadUHDBluray: false,
            canWriteCD: true,
            canWriteDVD: true
        )
        XCTAssertTrue(drive.canRead(.audioCd))
        XCTAssertTrue(drive.canRead(.dvdVideo))
        XCTAssertTrue(drive.canRead(.bluray))
        XCTAssertFalse(drive.canRead(.uhdBluray))
        XCTAssertTrue(drive.canWrite(.audioCd))
        XCTAssertTrue(drive.canWrite(.dvdVideo))
        XCTAssertFalse(drive.canWrite(.bluray))
        XCTAssertFalse(drive.canWrite(.uhdBluray))
    }

    /// Verifies DiscRipConfig defaults.
    func test_discRipConfig_defaults() {
        let config = DiscRipConfig(
            sourcePath: "/dev/sr0",
            outputDirectory: "/tmp/rip"
        )
        XCTAssertTrue(config.decryptIfNeeded)
        XCTAssertTrue(config.paranoiaMode)
        XCTAssertTrue(config.mainFeatureOnly)
        XCTAssertEqual(config.retryCount, 20)
    }

    /// Verifies RipProgress calculations.
    func test_ripProgress_fraction() {
        let progress = RipProgress(
            bytesRead: 500_000_000,
            totalBytes: 1_000_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
    }

    // =========================================================================
    // MARK: - Phase 8: Audio CD Reader
    // =========================================================================

    /// Verifies cdparanoia single track rip arguments.
    func test_audioCDReader_ripTrackArguments() {
        let args = AudioCDReader.buildRipTrackArguments(
            devicePath: "/dev/sr0",
            trackNumber: 3,
            outputPath: "/tmp/track03.wav",
            paranoia: .full,
            readSpeed: 8
        )
        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("/dev/sr0"))
        XCTAssertTrue(args.contains("3"))
        XCTAssertTrue(args.contains("/tmp/track03.wav"))
        XCTAssertTrue(args.contains("-S"))
        XCTAssertTrue(args.contains("8"))
    }

    /// Verifies cdparanoia batch rip arguments.
    func test_audioCDReader_ripAllArguments() {
        let args = AudioCDReader.buildRipAllArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/rip"
        )
        XCTAssertTrue(args.contains("-B"))
        XCTAssertTrue(args.contains("-O"))
        XCTAssertTrue(args.contains("/tmp/rip"))
    }

    /// Verifies FFmpeg encoding arguments for FLAC.
    func test_audioCDReader_encodeFlac() {
        let args = AudioCDReader.buildEncodeArguments(
            inputPath: "/tmp/track01.wav",
            outputPath: "/tmp/track01.flac",
            format: .flac,
            metadata: ["title": "Test Track", "artist": "Test Artist"]
        )
        XCTAssertTrue(args.contains("flac"))
        XCTAssertTrue(args.contains("-compression_level"))
        XCTAssertTrue(args.contains("-metadata"))
    }

    /// Verifies FFmpeg encoding arguments for lossy MP3.
    func test_audioCDReader_encodeMp3() {
        let args = AudioCDReader.buildEncodeArguments(
            inputPath: "/tmp/track01.wav",
            outputPath: "/tmp/track01.mp3",
            format: .mp3,
            bitrate: 320
        )
        XCTAssertTrue(args.contains("libmp3lame"))
        XCTAssertTrue(args.contains("320k"))
    }

    /// Verifies CDDB disc ID calculation.
    func test_audioCDReader_cddbDiscId() {
        let tracks = [
            DiscTrack(number: 1, startSector: 0, sectorCount: 15000),
            DiscTrack(number: 2, startSector: 15000, sectorCount: 18000),
            DiscTrack(number: 3, startSector: 33000, sectorCount: 20000),
        ]
        let discId = AudioCDReader.calculateCDDBDiscId(
            tracks: tracks,
            leadOutSector: 53000
        )
        XCTAssertEqual(discId.count, 8) // 8-char hex string
        XCTAssertFalse(discId.isEmpty)
    }

    /// Verifies MusicBrainz TOC construction.
    func test_audioCDReader_musicBrainzTOC() {
        let toc = AudioCDReader.buildMusicBrainzTOC(
            firstTrack: 1,
            lastTrack: 10,
            leadOutOffset: 200000,
            trackOffsets: [150, 18000, 36000]
        )
        XCTAssertTrue(toc.contains("1+10+200000"))
        XCTAssertTrue(toc.contains("150"))
    }

    /// Verifies MusicBrainz lookup URL.
    func test_audioCDReader_musicBrainzURL() {
        let url = AudioCDReader.buildMusicBrainzLookupURL(toc: "1+10+200000+150")
        XCTAssertTrue(url.contains("musicbrainz.org"))
        XCTAssertTrue(url.contains("toc="))
    }

    /// Verifies AccurateRip disc ID calculation.
    func test_audioCDReader_accurateRipIds() {
        let offsets = [150, 18000, 36000]
        let (id1, id2) = AudioCDReader.calculateAccurateRipDiscIds(
            trackOffsets: offsets,
            leadOutOffset: 200000
        )
        XCTAssertTrue(id1 > 0)
        XCTAssertTrue(id2 > 0)
    }

    /// Verifies track duration calculation.
    func test_audioCDReader_trackDuration() {
        let duration = AudioCDReader.trackDuration(
            startSector: 0,
            nextStartSector: 33075 // 441 seconds at 75 sectors/sec
        )
        XCTAssertEqual(duration, 441.0, accuracy: 0.01)
    }

    /// Verifies output filename generation.
    func test_audioCDReader_outputFilename() {
        let name = AudioCDReader.buildOutputFilename(
            trackNumber: 3,
            title: "My Song",
            artist: "My Artist",
            format: .flac
        )
        XCTAssertEqual(name, "03 - My Artist - My Song.flac")

        let nameNoMeta = AudioCDReader.buildOutputFilename(
            trackNumber: 1,
            format: .wav
        )
        XCTAssertEqual(nameNoMeta, "01.wav")
    }

    /// Verifies CDDAFormat properties.
    func test_cddaFormat_properties() {
        XCTAssertTrue(CDDAFormat.flac.isLossless)
        XCTAssertTrue(CDDAFormat.wav.isLossless)
        XCTAssertFalse(CDDAFormat.mp3.isLossless)
        XCTAssertFalse(CDDAFormat.aacLC.isLossless)
        XCTAssertEqual(CDDAFormat.flac.fileExtension, "flac")
        XCTAssertEqual(CDDAFormat.alac.fileExtension, "m4a")
    }

    /// Verifies CDParanoiaMode flags.
    func test_paranoiaMode_flags() {
        XCTAssertEqual(CDParanoiaMode.disabled.paranoiaFlags, "--disable-paranoia")
        XCTAssertEqual(CDParanoiaMode.full.paranoiaFlags, "--never-skip=40")
    }

    // =========================================================================
    // MARK: - Phase 8: DVD Reader
    // =========================================================================

    /// Verifies FFmpeg DVD rip arguments.
    func test_dvdReader_ripArguments() {
        let args = DVDReader.buildRipArguments(
            devicePath: "/dev/sr0",
            titleNumber: 1,
            outputPath: "/tmp/movie.mkv"
        )
        XCTAssertTrue(args.contains("-dvd-device"))
        XCTAssertTrue(args.contains("/dev/sr0"))
        XCTAssertTrue(args.contains("dvd://1"))
        XCTAssertTrue(args.contains("copy"))
        XCTAssertTrue(args.contains("/tmp/movie.mkv"))
    }

    /// Verifies DVD rip with specific streams.
    func test_dvdReader_ripWithStreams() {
        let args = DVDReader.buildRipArguments(
            devicePath: "/dev/sr0",
            titleNumber: 1,
            outputPath: "/tmp/movie.mkv",
            audioStreams: [0, 1],
            subtitleStreams: [0]
        )
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("0:a:1"))
        XCTAssertTrue(args.contains("0:s:0"))
    }

    /// Verifies VOB concatenation arguments.
    func test_dvdReader_vobConcat() {
        let args = DVDReader.buildVOBConcatArguments(
            vobFiles: ["/mnt/dvd/VTS_01_1.VOB", "/mnt/dvd/VTS_01_2.VOB"],
            outputPath: "/tmp/title.vob"
        )
        XCTAssertTrue(args.contains("-i"))
        let concatArg = args.first { $0.hasPrefix("concat:") }
        XCTAssertNotNil(concatArg)
        XCTAssertTrue(concatArg?.contains("|") == true)
    }

    /// Verifies lsdvd arguments.
    func test_dvdReader_lsdvdArguments() {
        let args = DVDReader.buildLsdvdArguments(devicePath: "/dev/sr0")
        XCTAssertTrue(args.contains("-a"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("-c"))
        XCTAssertTrue(args.contains("-Oj"))
    }

    /// Verifies dvdbackup arguments.
    func test_dvdReader_backupArguments() {
        let args = DVDReader.buildDVDBackupArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/dvd",
            titleNumber: 1
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("1"))

        let mirrorArgs = DVDReader.buildDVDBackupArguments(
            devicePath: "/dev/sr0",
            outputDir: "/tmp/dvd"
        )
        XCTAssertTrue(mirrorArgs.contains("-M"))
    }

    /// Verifies VOB filename generation.
    func test_dvdReader_expectedVOBFiles() {
        let files = DVDReader.expectedVOBFiles(titleSetNumber: 1, partCount: 3)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0], "VTS_01_1.VOB")
        XCTAssertEqual(files[1], "VTS_01_2.VOB")
        XCTAssertEqual(files[2], "VTS_01_3.VOB")
    }

    /// Verifies VIDEO_TS path construction.
    func test_dvdReader_videoTSPath() {
        let path = DVDReader.videoTSPath(from: "/mnt/dvd")
        XCTAssertTrue(path.hasSuffix("VIDEO_TS"))
    }

    /// Verifies IFO file path construction.
    func test_dvdReader_ifoFilePath() {
        let vmg = DVDReader.ifoFilePath(videoTSDir: "/mnt/dvd/VIDEO_TS", titleSetNumber: 0)
        XCTAssertTrue(vmg.hasSuffix("VIDEO_TS.IFO"))

        let vts = DVDReader.ifoFilePath(videoTSDir: "/mnt/dvd/VIDEO_TS", titleSetNumber: 1)
        XCTAssertTrue(vts.hasSuffix("VTS_01_0.IFO"))
    }

    /// Verifies DVD region check.
    func test_dvdReader_regionCheck() {
        // Region 1 disc: bit 0 = 0 (allowed), bits 1-7 = 1 (blocked)
        let regionMask: UInt8 = 0xFE
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: regionMask, region: 1))
        XCTAssertFalse(DVDReader.isRegionAllowed(regionMask: regionMask, region: 2))

        // Region-free: all bits 0
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: 0x00, region: 1))
        XCTAssertTrue(DVDReader.isRegionAllowed(regionMask: 0x00, region: 4))
    }

    /// Verifies DVD structure properties.
    func test_dvdStructure_regions() {
        let structure = DVDStructure(regionMask: 0xFE) // Region 1 only
        XCTAssertEqual(structure.regions, [1])

        let regionFree = DVDStructure(regionMask: 0x00)
        XCTAssertEqual(regionFree.regions.count, 8)
    }

    /// Verifies main feature detection.
    func test_dvdReader_mainFeatureDetection() {
        let titles = [
            DiscTitle(number: 1, duration: 120),    // 2 min (menu)
            DiscTitle(number: 2, duration: 7200),   // 2 hours (main)
            DiscTitle(number: 3, duration: 600),    // 10 min (extras)
        ]
        let main = DVDReader.detectMainFeature(titles: titles)
        XCTAssertEqual(main?.number, 2)
    }

    // =========================================================================
    // MARK: - Phase 8: Blu-ray Reader
    // =========================================================================

    /// Verifies FFmpeg Blu-ray rip arguments.
    func test_blurayReader_ripArguments() {
        let args = BlurayReader.buildRipArguments(
            devicePath: "/dev/sr0",
            playlistNumber: 800,
            outputPath: "/tmp/movie.mkv"
        )
        XCTAssertTrue(args.contains("-playlist"))
        XCTAssertTrue(args.contains("800"))
        XCTAssertTrue(args.contains("bluray:/dev/sr0"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies Blu-ray rip with stream selection.
    func test_blurayReader_ripWithStreams() {
        let args = BlurayReader.buildRipArguments(
            devicePath: "/dev/sr0",
            playlistNumber: 800,
            outputPath: "/tmp/movie.mkv",
            audioStreams: [0, 2],
            subtitleStreams: [0]
        )
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("0:a:2"))
        XCTAssertTrue(args.contains("0:s:0"))
    }

    /// Verifies M2TS rip arguments.
    func test_blurayReader_m2tsRip() {
        let args = BlurayReader.buildM2TSRipArguments(
            m2tsPath: "/mnt/bd/BDMV/STREAM/00001.m2ts",
            outputPath: "/tmp/clip.mkv"
        )
        XCTAssertTrue(args.contains("00001.m2ts"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies BDMV path construction.
    func test_blurayReader_bdmvPaths() {
        let paths = BlurayReader.bdmvPaths(from: "/mnt/bd")
        XCTAssertTrue(paths["stream"]?.contains("STREAM") == true)
        XCTAssertTrue(paths["playlist"]?.contains("PLAYLIST") == true)
        XCTAssertTrue(paths["clipinf"]?.contains("CLIPINF") == true)
    }

    /// Verifies MPLS file path construction.
    func test_blurayReader_mplsFilePath() {
        let path = BlurayReader.mplsFilePath(basePath: "/mnt/bd", playlistNumber: 800)
        XCTAssertTrue(path.hasSuffix("00800.mpls"))
        XCTAssertTrue(path.contains("PLAYLIST"))
    }

    /// Verifies M2TS file path construction.
    func test_blurayReader_m2tsFilePath() {
        let path = BlurayReader.m2tsFilePath(basePath: "/mnt/bd", clipNumber: 1)
        XCTAssertTrue(path.hasSuffix("00001.m2ts"))
        XCTAssertTrue(path.contains("STREAM"))
    }

    /// Verifies main feature detection for Blu-ray.
    func test_blurayReader_mainFeatureDetection() {
        let playlists = [
            BlurayPlaylist(number: 1, duration: 30),       // Menu
            BlurayPlaylist(number: 800, duration: 7800),   // Main feature
            BlurayPlaylist(number: 801, duration: 900),    // Extra
        ]
        let main = BlurayReader.detectMainFeature(playlists: playlists)
        XCTAssertEqual(main?.number, 800)
    }

    /// Verifies HDR10 preservation arguments.
    func test_blurayReader_hdr10Arguments() {
        let args = BlurayReader.buildHDR10PreservationArguments()
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies BlurayVideoStream UHD detection.
    func test_blurayVideoStream_isUHD() {
        let uhd = BlurayVideoStream(width: 3840, height: 2160)
        XCTAssertTrue(uhd.isUHD)

        let hd = BlurayVideoStream(width: 1920, height: 1080)
        XCTAssertFalse(hd.isUHD)
    }

    /// Verifies BlurayProtection canDecrypt logic.
    func test_blurayProtection_canDecrypt() {
        let withKeys = BlurayProtection(hasAACS: true, hasKeyFile: true)
        XCTAssertTrue(withKeys.canDecrypt)

        let noKeys = BlurayProtection(hasAACS: true, hasKeyFile: false)
        XCTAssertFalse(noKeys.canDecrypt)

        let aacs2 = BlurayProtection(hasAACS2: true, hasKeyFile: true)
        XCTAssertFalse(aacs2.canDecrypt)

        let noProtection = BlurayProtection()
        XCTAssertTrue(noProtection.canDecrypt)
    }

    /// Verifies UHD and HDR detection helpers.
    func test_blurayReader_uhdAndHdrDetection() {
        let streams = [
            BlurayVideoStream(width: 3840, height: 2160, isHDR: true, hdrFormat: "HDR10"),
        ]
        XCTAssertTrue(BlurayReader.isUHDDisc(videoStreams: streams))
        XCTAssertTrue(BlurayReader.hasHDRContent(videoStreams: streams))

        let sdStreams = [BlurayVideoStream(width: 1920, height: 1080)]
        XCTAssertFalse(BlurayReader.isUHDDisc(videoStreams: sdStreams))
        XCTAssertFalse(BlurayReader.hasHDRContent(videoStreams: sdStreams))
    }

    // =========================================================================
    // MARK: - Phase 9: Disc Authoring
    // =========================================================================

    /// Verifies DiscAuthorFormat properties.
    func test_discAuthorFormat_properties() {
        XCTAssertEqual(DiscAuthorFormat.dvdVideo.displayName, "DVD-Video")
        XCTAssertEqual(DiscAuthorFormat.audioCd.displayName, "Audio CD")
        XCTAssertTrue(DiscAuthorFormat.dvdVideo.defaultCapacityBytes > 4_000_000_000)
    }

    /// Verifies DiscCapacity values.
    func test_discCapacity_values() {
        XCTAssertTrue(DiscCapacity.dvd5.capacityBytes > 4_700_000_000)
        XCTAssertTrue(DiscCapacity.dvd9.capacityBytes > 8_500_000_000)
        XCTAssertTrue(DiscCapacity.bd25.capacityBytes > 25_000_000_000)
        XCTAssertTrue(DiscCapacity.bd50.capacityBytes > 50_000_000_000)
    }

    /// Verifies dvdauthor arguments.
    func test_discAuthor_dvdAuthorArguments() {
        let args = DiscAuthor.buildDVDAuthorArguments(
            xmlConfigPath: "/tmp/dvdauthor.xml",
            outputDir: "/tmp/dvd_out"
        )
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("/tmp/dvd_out"))
        XCTAssertTrue(args.contains("-x"))
        XCTAssertTrue(args.contains("/tmp/dvdauthor.xml"))
    }

    /// Verifies dvdauthor XML generation.
    func test_discAuthor_dvdAuthorXML() {
        let config = AuthoringConfig(
            format: .dvdVideo,
            volumeLabel: "MY_DVD",
            outputDirectory: "/tmp/dvd_out",
            videoStandard: .ntsc
        )
        let xml = DiscAuthor.generateDVDAuthorXML(
            config: config,
            vobFiles: ["/tmp/title1.mpg", "/tmp/title2.mpg"]
        )
        XCTAssertTrue(xml.contains("<dvdauthor"))
        XCTAssertTrue(xml.contains("ntsc"))
        XCTAssertTrue(xml.contains("title1.mpg"))
        XCTAssertTrue(xml.contains("title2.mpg"))
    }

    /// Verifies DVD encode arguments.
    func test_discAuthor_dvdEncodeArguments() {
        let args = DiscAuthor.buildDVDEncodeArguments(
            inputPath: "/tmp/movie.mp4",
            outputPath: "/tmp/movie.mpg",
            standard: .pal,
            bitrate: 8000
        )
        XCTAssertTrue(args.contains("mpeg2video"))
        XCTAssertTrue(args.contains("8000k"))
        XCTAssertTrue(args.contains("720:576"))
        XCTAssertTrue(args.contains("ac3"))
        XCTAssertTrue(args.contains("dvd"))
    }

    /// Verifies Audio CD preparation arguments.
    func test_discAuthor_audioCDPrepare() {
        let args = DiscAuthor.buildAudioCDPrepareArguments(
            inputPath: "/tmp/song.mp3",
            outputPath: "/tmp/song.wav"
        )
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertTrue(args.contains("44100"))
        XCTAssertTrue(args.contains("2"))
    }

    /// Verifies tsMuxeR meta file generation.
    func test_discAuthor_tsMuxeRMeta() {
        let meta = DiscAuthor.generateTsMuxeRMeta(
            videoPath: "/tmp/video.264",
            audioPaths: ["/tmp/audio.ac3", "/tmp/audio.dts"],
            subtitlePaths: ["/tmp/subs.sup"],
            outputDir: "/tmp/bdmv"
        )
        XCTAssertTrue(meta.contains("MUXOPT"))
        XCTAssertTrue(meta.contains("V_MPEG4"))
        XCTAssertTrue(meta.contains("A_AC3"))
        XCTAssertTrue(meta.contains("A_DTS"))
        XCTAssertTrue(meta.contains("S_HDMV/PGS"))
    }

    /// Verifies genisoimage arguments.
    func test_discAuthor_genisoimageArguments() {
        let config = AuthoringConfig(
            format: .dvdVideo,
            volumeLabel: "TEST_DVD"
        )
        let args = DiscAuthor.buildGenisoimageArguments(
            config: config,
            sourceDir: "/tmp/dvd_struct",
            outputPath: "/tmp/movie.iso"
        )
        XCTAssertTrue(args.contains("-V"))
        XCTAssertTrue(args.contains("TEST_DVD"))
        XCTAssertTrue(args.contains("-dvd-video"))
        XCTAssertTrue(args.contains("-udf"))
        XCTAssertTrue(args.contains("-o"))
    }

    /// Verifies capacity validation.
    func test_discAuthor_capacityValidation() {
        // Fits on DVD-5
        let fitResult = DiscAuthor.validateCapacity(
            totalSizeBytes: 3_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(fitResult.fits)
        XCTAssertTrue(fitResult.remainingBytes > 0)
        XCTAssertTrue(fitResult.usedPercent < 100)

        // Doesn't fit on DVD-5
        let overResult = DiscAuthor.validateCapacity(
            totalSizeBytes: 6_000_000_000,
            capacity: .dvd5
        )
        XCTAssertFalse(overResult.fits)
        XCTAssertTrue(overResult.remainingBytes < 0)
        XCTAssertTrue(overResult.usedPercent > 100)
    }

    /// Verifies capacity validation summary.
    func test_capacityValidation_summary() {
        let fit = DiscAuthor.validateCapacity(
            totalSizeBytes: 2_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(fit.summary.contains("fits"))

        let over = DiscAuthor.validateCapacity(
            totalSizeBytes: 6_000_000_000,
            capacity: .dvd5
        )
        XCTAssertTrue(over.summary.contains("exceeds"))
    }

    // =========================================================================
    // MARK: - Phase 9: Disc Burner
    // =========================================================================

    /// Verifies audio CD burn arguments.
    func test_discBurner_audioCDBurn() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "",
            speed: .multiplier(8),
            ejectAfterBurn: true,
            format: .audioCd
        )
        let args = DiscBurner.buildAudioCDBurnArguments(
            config: config,
            wavFiles: ["/tmp/track01.wav", "/tmp/track02.wav"]
        )
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("speed=8"))
        XCTAssertTrue(args.contains("-audio"))
        XCTAssertTrue(args.contains("-dao"))
        XCTAssertTrue(args.contains("-eject"))
        XCTAssertTrue(args.contains("/tmp/track01.wav"))
        XCTAssertTrue(args.contains("/tmp/track02.wav"))
    }

    /// Verifies data disc burn arguments.
    func test_discBurner_dataDiscBurn() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/movie.iso",
            simulate: true
        )
        let args = DiscBurner.buildDataDiscBurnArguments(config: config)
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("-dummy"))
        XCTAssertTrue(args.contains("/tmp/movie.iso"))
    }

    /// Verifies disc blanking arguments.
    func test_discBurner_blankArguments() {
        let args = DiscBurner.buildBlankArguments(
            devicePath: "/dev/sr0",
            blankType: "fast"
        )
        XCTAssertTrue(args.contains("dev=/dev/sr0"))
        XCTAssertTrue(args.contains("blank=fast"))
    }

    /// Verifies growisofs arguments.
    func test_discBurner_growisofsArguments() {
        let config = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/movie.iso",
            speed: .multiplier(4),
            format: .dvdVideo
        )
        let args = DiscBurner.buildGrowisofsArguments(config: config)
        XCTAssertTrue(args.contains("-speed=4"))
        XCTAssertTrue(args.contains("-dvd-compat"))
        let zArg = args.first { $0.hasPrefix("-Z") }
        XCTAssertNil(zArg) // -Z is in separate element
        XCTAssertTrue(args.contains("-Z"))
    }

    /// Verifies hdiutil burn arguments.
    func test_discBurner_hdiutilBurn() {
        let args = DiscBurner.buildHdiutilBurnArguments(
            isoPath: "/tmp/movie.iso",
            verify: true
        )
        XCTAssertTrue(args.contains("burn"))
        XCTAssertTrue(args.contains("/tmp/movie.iso"))
        XCTAssertTrue(args.contains("-verifyburn"))
    }

    /// Verifies burn configuration validation.
    func test_discBurner_validation() {
        let emptyConfig = BurnConfig(devicePath: "", sourcePath: "")
        let errors = DiscBurner.validate(config: emptyConfig)
        XCTAssertEqual(errors.count, 2)

        let validConfig = BurnConfig(
            devicePath: "/dev/sr0",
            sourcePath: "/tmp/disc.iso"
        )
        let noErrors = DiscBurner.validate(config: validConfig)
        XCTAssertTrue(noErrors.isEmpty)
    }

    /// Verifies BurnSpeed cdrecord values.
    func test_burnSpeed_cdrecordValue() {
        XCTAssertEqual(BurnSpeed.auto.cdrecordValue, "0")
        XCTAssertEqual(BurnSpeed.multiplier(16).cdrecordValue, "16")
        XCTAssertEqual(BurnSpeed.maximum.cdrecordValue, "99")
    }

    /// Verifies BurnPhase display names.
    func test_burnPhase_displayNames() {
        XCTAssertEqual(BurnPhase.writing.displayName, "Writing data")
        XCTAssertEqual(BurnPhase.verifying.displayName, "Verifying burn")
        XCTAssertEqual(BurnPhase.fixating.displayName, "Fixating disc")
    }

    /// Verifies BurnProgress calculations.
    func test_burnProgress_fraction() {
        let progress = BurnProgress(
            phase: .writing,
            bytesWritten: 2_000_000_000,
            totalBytes: 4_000_000_000
        )
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.percentage, 50)
    }

    /// Verifies eject arguments.
    func test_discBurner_ejectArguments() {
        let args = DiscBurner.buildEjectArguments(devicePath: "/dev/sr0")
        XCTAssertEqual(args, ["/dev/sr0"])
    }

    /// Verifies DVDVideoStandard properties.
    func test_dvdVideoStandard_properties() {
        XCTAssertEqual(DVDVideoStandard.ntsc.frameRate, 29.97)
        XCTAssertEqual(DVDVideoStandard.pal.frameRate, 25.0)

        let ntscRes = DVDVideoStandard.ntsc.resolution
        XCTAssertEqual(ntscRes.width, 720)
        XCTAssertEqual(ntscRes.height, 480)

        let palRes = DVDVideoStandard.pal.resolution
        XCTAssertEqual(palRes.width, 720)
        XCTAssertEqual(palRes.height, 576)
    }

    /// Verifies DiscImageFormat properties.
    func test_discImageFormat_properties() {
        XCTAssertEqual(DiscImageFormat.iso.displayName, "ISO 9660")
        XCTAssertEqual(DiscImageFormat.bin.displayName, "BIN/CUE")
        XCTAssertEqual(DiscImageFormat.iso.fileExtension, "iso")
    }

    // =========================================================================
    // MARK: - Phase 10-11: Platform Support
    // =========================================================================

    /// Verifies Platform enum.
    func test_platform_enum() {
        XCTAssertEqual(Platform.macOS.displayName, "macOS")
        XCTAssertEqual(Platform.windows.displayName, "Windows")
        XCTAssertEqual(Platform.linux.displayName, "Linux")

        // Current platform should be one of the cases
        let current = Platform.current
        XCTAssertTrue(Platform.allCases.contains(current))
    }

    /// Verifies Architecture enum.
    func test_architecture_enum() {
        XCTAssertEqual(Architecture.arm64.displayName, "ARM64 (Apple Silicon / ARM)")
        XCTAssertEqual(Architecture.x86_64.displayName, "x86-64 (Intel/AMD)")

        let current = Architecture.current
        XCTAssertTrue(Architecture.allCases.contains(current))
    }

    /// Verifies PlatformPaths binary names.
    func test_platformPaths_binaryNames() {
        // On current platform (macOS in dev), these should not be .exe
        #if os(Windows)
        XCTAssertTrue(PlatformPaths.ffmpegBinaryName.hasSuffix(".exe"))
        XCTAssertTrue(PlatformPaths.ffprobeBinaryName.hasSuffix(".exe"))
        XCTAssertEqual(PlatformPaths.pathSeparator, ";")
        #else
        XCTAssertEqual(PlatformPaths.ffmpegBinaryName, "ffmpeg")
        XCTAssertEqual(PlatformPaths.ffprobeBinaryName, "ffprobe")
        XCTAssertEqual(PlatformPaths.pathSeparator, ":")
        XCTAssertEqual(PlatformPaths.fileSeparator, "/")
        #endif
    }

    /// Verifies FFmpeg search paths are non-empty.
    func test_platformPaths_searchPaths() {
        let paths = PlatformPaths.ffmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
    }

    /// Verifies Windows-specific search paths contain expected locations.
    func test_platformPaths_windowsSearchPaths() {
        let paths = PlatformPaths.windowsFFmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
        // Should contain common Windows FFmpeg locations
        XCTAssertTrue(paths.contains { $0.contains("FFmpeg") || $0.contains("MeedyaConverter") })
    }

    /// Verifies Linux-specific search paths contain expected locations.
    func test_platformPaths_linuxSearchPaths() {
        let paths = PlatformPaths.linuxFFmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
        XCTAssertTrue(paths.contains("/usr/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains("/snap/bin"))
    }

    /// Verifies application data directories are non-empty.
    func test_platformPaths_directories() {
        XCTAssertFalse(PlatformPaths.applicationDataDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.configDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.cacheDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.logDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.tempDirectory.isEmpty)
    }

    /// Verifies PlatformCapabilities.
    func test_platformCapabilities() {
        let apis = PlatformCapabilities.availableHardwareAPIs
        XCTAssertFalse(apis.isEmpty)

        XCTAssertTrue(PlatformCapabilities.hasNativeGUI)
        XCTAssertFalse(PlatformCapabilities.nativeUIFramework.isEmpty)
        XCTAssertTrue(PlatformCapabilities.supportsOpticalDisc)
        XCTAssertFalse(PlatformCapabilities.packageManagers.isEmpty)
    }

    // =========================================================================
    // MARK: - Phase 10: Windows Platform
    // =========================================================================

    /// Verifies WindowsInstallerType properties.
    func test_windowsInstallerType() {
        XCTAssertEqual(WindowsInstallerType.msi.displayName, "Windows Installer (MSI)")
        XCTAssertEqual(WindowsInstallerType.msix.displayName, "MSIX Package")
    }

    /// Verifies WindowsDriveInfo device path construction.
    func test_windowsDriveInfo_devicePath() {
        let drive = WindowsDriveInfo(driveLetter: "D", driveType: .cdrom, isReady: true)
        XCTAssertTrue(drive.devicePath.contains("D"))
        XCTAssertTrue(drive.driveType.isOptical)
    }

    /// Verifies WindowsDriveType properties.
    func test_windowsDriveType() {
        XCTAssertTrue(WindowsDriveType.cdrom.isOptical)
        XCTAssertFalse(WindowsDriveType.fixed.isOptical)
        XCTAssertFalse(WindowsDriveType.removable.isOptical)
        XCTAssertEqual(WindowsDriveType.cdrom.displayName, "CD-ROM / Optical")
    }

    /// Verifies NVENC argument builder.
    func test_windowsPlatform_nvencArguments() {
        let args = WindowsPlatform.buildNVENCArguments(
            codec: "h264_nvenc",
            preset: "p7",
            cq: 20,
            gpuIndex: 0
        )
        XCTAssertTrue(args.contains("h264_nvenc"))
        XCTAssertTrue(args.contains("p7"))
        XCTAssertTrue(args.contains("20"))
        XCTAssertTrue(args.contains("-gpu"))
        XCTAssertTrue(args.contains("hq"))
        XCTAssertTrue(args.contains("vbr"))
    }

    /// Verifies QSV argument builder.
    func test_windowsPlatform_qsvArguments() {
        let args = WindowsPlatform.buildQSVArguments(
            codec: "hevc_qsv",
            preset: "veryslow",
            globalQuality: 18
        )
        XCTAssertTrue(args.contains("hevc_qsv"))
        XCTAssertTrue(args.contains("-init_hw_device"))
        XCTAssertTrue(args.contains("-global_quality"))
        XCTAssertTrue(args.contains("18"))
    }

    /// Verifies AMF argument builder.
    func test_windowsPlatform_amfArguments() {
        let args = WindowsPlatform.buildAMFArguments(
            codec: "hevc_amf",
            quality: "quality",
            cq: 20
        )
        XCTAssertTrue(args.contains("hevc_amf"))
        XCTAssertTrue(args.contains("quality"))
        XCTAssertTrue(args.contains("cqp"))
    }

    /// Verifies D3D11VA decode arguments.
    func test_windowsPlatform_d3d11vaArguments() {
        let args = WindowsPlatform.buildD3D11VADecodeArguments()
        XCTAssertTrue(args.contains("d3d11va"))
        XCTAssertTrue(args.contains("d3d11"))
    }

    /// Verifies DXVA2 decode arguments.
    func test_windowsPlatform_dxva2Arguments() {
        let args = WindowsPlatform.buildDXVA2DecodeArguments()
        XCTAssertTrue(args.contains("dxva2"))
    }

    /// Verifies IMAPI burn script generation.
    func test_windowsPlatform_imapiBurnScript() {
        let script = WindowsPlatform.buildIMAPIBurnScript(
            isoPath: "C:\\temp\\movie.iso",
            driveLetter: "D",
            speed: 8
        )
        XCTAssertTrue(script.contains("IMAPI2"))
        XCTAssertTrue(script.contains("movie.iso"))
        XCTAssertTrue(script.contains("MeedyaConverter"))
    }

    /// Verifies WiX component generation.
    func test_windowsPlatform_wixComponent() {
        let xml = WindowsPlatform.generateWiXComponent(
            filePath: "C:\\build\\ffmpeg.exe",
            componentId: "FFmpegExe"
        )
        XCTAssertTrue(xml.contains("<Component"))
        XCTAssertTrue(xml.contains("FFmpegExe"))
        XCTAssertTrue(xml.contains("ffmpeg.exe"))
    }

    /// Verifies media file extensions are populated.
    func test_windowsPlatform_fileAssociations() {
        XCTAssertFalse(WindowsPlatform.mediaFileExtensions.isEmpty)
        XCTAssertEqual(WindowsPlatform.mediaFileExtensions[".mp4"], "video/mp4")
        XCTAssertEqual(WindowsPlatform.mediaFileExtensions[".flac"], "audio/flac")
    }

    /// Verifies TaskbarProgressState values.
    func test_windowsPlatform_taskbarState() {
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.noProgress.rawValue, 0)
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.normal.rawValue, 2)
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.error.rawValue, 4)
    }

    // =========================================================================
    // MARK: - Phase 11: Linux Platform
    // =========================================================================

    /// Verifies LinuxDistro properties.
    func test_linuxDistro_properties() {
        XCTAssertEqual(LinuxDistro.ubuntu.displayName, "Ubuntu")
        XCTAssertEqual(LinuxDistro.ubuntu.packageManager, "apt")
        XCTAssertEqual(LinuxDistro.fedora.packageManager, "dnf")
        XCTAssertEqual(LinuxDistro.arch.packageManager, "pacman")
    }

    /// Verifies FFmpeg package names per distro.
    func test_linuxDistro_ffmpegPackage() {
        XCTAssertEqual(LinuxDistro.ubuntu.ffmpegPackageName, "ffmpeg")
        XCTAssertTrue(LinuxDistro.fedora.ffmpegPackageName.contains("ffmpeg"))
    }

    /// Verifies install commands.
    func test_linuxDistro_installCommand() {
        XCTAssertTrue(LinuxDistro.ubuntu.ffmpegInstallCommand.contains("apt"))
        XCTAssertTrue(LinuxDistro.fedora.ffmpegInstallCommand.contains("dnf"))
        XCTAssertTrue(LinuxDistro.arch.ffmpegInstallCommand.contains("pacman"))
    }

    /// Verifies LinuxDesktopEnvironment detection.
    func test_linuxDesktopEnvironment_detect() {
        let de = LinuxDesktopEnvironment.detect()
        // On macOS/non-Linux, this should return headless or unknown
        XCTAssertNotNil(de)
    }

    /// Verifies LinuxPackageFormat properties.
    func test_linuxPackageFormat_properties() {
        XCTAssertTrue(LinuxPackageFormat.flatpak.isSandboxed)
        XCTAssertTrue(LinuxPackageFormat.snap.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.deb.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.rpm.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.appImage.isSandboxed)
    }

    /// Verifies recommended package format per distro.
    func test_linuxPackageFormat_recommended() {
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .ubuntu), .deb)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .debian), .deb)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .fedora), .rpm)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .unknown), .appImage)
    }

    /// Verifies VAAPI encode arguments.
    func test_linuxPlatform_vaapiEncodeArguments() {
        let args = LinuxPlatform.buildVAAPIEncodeArguments(
            codec: "h264_vaapi",
            devicePath: "/dev/dri/renderD128",
            quality: 20
        )
        XCTAssertTrue(args.contains("-vaapi_device"))
        XCTAssertTrue(args.contains("/dev/dri/renderD128"))
        XCTAssertTrue(args.contains("h264_vaapi"))
        XCTAssertTrue(args.contains("hwupload"))
        XCTAssertTrue(args.contains("20"))
    }

    /// Verifies VAAPI decode arguments.
    func test_linuxPlatform_vaapiDecodeArguments() {
        let args = LinuxPlatform.buildVAAPIDecodeArguments()
        XCTAssertTrue(args.contains("vaapi"))
        XCTAssertTrue(args.contains("/dev/dri/renderD128"))
    }

    /// Verifies V4L2 encode arguments for Raspberry Pi.
    func test_linuxPlatform_v4l2EncodeArguments() {
        let args = LinuxPlatform.buildV4L2EncodeArguments(
            codec: "h264_v4l2m2m",
            bitrate: 3000
        )
        XCTAssertTrue(args.contains("h264_v4l2m2m"))
        XCTAssertTrue(args.contains("3000k"))
    }

    /// Verifies Raspberry Pi memory-conscious settings.
    func test_linuxPlatform_rpiEncodingArgs() {
        let lowRam = LinuxPlatform.buildRPiEncodingArgs(availableRAM_MB: 1024)
        XCTAssertTrue(lowRam.contains("2")) // 2 threads
        XCTAssertTrue(lowRam.contains("-rc-lookahead"))

        let highRam = LinuxPlatform.buildRPiEncodingArgs(availableRAM_MB: 8192)
        XCTAssertTrue(highRam.contains("4")) // 4 threads
    }

    /// Verifies vainfo arguments.
    func test_linuxPlatform_vainfoArguments() {
        let args = LinuxPlatform.buildVainfoArguments(devicePath: "/dev/dri/renderD128")
        XCTAssertTrue(args.contains("--display"))
        XCTAssertTrue(args.contains("drm"))
    }

    /// Verifies desktop entry generation.
    func test_linuxPlatform_desktopEntry() {
        let entry = LinuxPlatform.generateDesktopEntry(
            execPath: "/usr/bin/meedya-convert",
            iconPath: "/usr/share/icons/meedyaconverter.png"
        )
        XCTAssertTrue(entry.contains("[Desktop Entry]"))
        XCTAssertTrue(entry.contains("MeedyaConverter"))
        XCTAssertTrue(entry.contains("AudioVideo"))
        XCTAssertTrue(entry.contains("/usr/bin/meedya-convert"))
    }

    /// Verifies udev rules generation.
    func test_linuxPlatform_udevRules() {
        let rules = LinuxPlatform.generateOpticalDiscUdevRules()
        XCTAssertTrue(rules.contains("SUBSYSTEM"))
        XCTAssertTrue(rules.contains("cdrom"))
        XCTAssertTrue(rules.contains("sr[0-9]*"))
    }

    /// Verifies udevadm arguments.
    func test_linuxPlatform_udevadmArguments() {
        let args = LinuxPlatform.buildUdevadmInfoArguments(devicePath: "/dev/sr0")
        XCTAssertTrue(args.contains("info"))
        XCTAssertTrue(args.contains { $0.contains("/dev/sr0") })
    }

    /// Verifies Flatpak permissions.
    func test_linuxPlatform_flatpakPermissions() {
        XCTAssertFalse(LinuxPlatform.flatpakPermissions.isEmpty)
        XCTAssertTrue(LinuxPlatform.flatpakPermissions.contains("--filesystem=home"))
        XCTAssertTrue(LinuxPlatform.flatpakPermissions.contains("--device=all"))
    }

    /// Verifies Snap plugs.
    func test_linuxPlatform_snapPlugs() {
        XCTAssertFalse(LinuxPlatform.snapPlugs.isEmpty)
        XCTAssertTrue(LinuxPlatform.snapPlugs.contains("home"))
        XCTAssertTrue(LinuxPlatform.snapPlugs.contains("removable-media"))
    }

    /// Verifies AppRun script generation.
    func test_linuxPlatform_appRunScript() {
        let script = LinuxPlatform.generateAppRunScript()
        XCTAssertTrue(script.contains("#!/bin/bash"))
        XCTAssertTrue(script.contains("meedya-convert"))
        XCTAssertTrue(script.contains("LD_LIBRARY_PATH"))
    }

    /// Verifies build dependencies lists.
    func test_linuxPlatform_buildDependencies() {
        XCTAssertFalse(LinuxPlatform.debianBuildDependencies.isEmpty)
        XCTAssertTrue(LinuxPlatform.debianBuildDependencies.contains("ffmpeg"))
        XCTAssertTrue(LinuxPlatform.debianBuildDependencies.contains("libgtk-4-dev"))

        XCTAssertFalse(LinuxPlatform.fedoraBuildDependencies.isEmpty)
        XCTAssertTrue(LinuxPlatform.fedoraBuildDependencies.contains("gtk4-devel"))
    }

    /// Verifies VAAPI device paths are defined.
    func test_linuxPlatform_devicePaths() {
        XCTAssertFalse(LinuxPlatform.vaapiDevicePaths.isEmpty)
        XCTAssertTrue(LinuxPlatform.vaapiDevicePaths.contains("/dev/dri/renderD128"))

        XCTAssertFalse(LinuxPlatform.v4l2DevicePaths.isEmpty)
        XCTAssertFalse(LinuxPlatform.opticalDriveDevices.isEmpty)
        XCTAssertTrue(LinuxPlatform.opticalDriveDevices.contains("/dev/sr0"))
    }

    /// Verifies WindowsInstallConfig defaults.
    func test_windowsInstallConfig_defaults() {
        let config = WindowsInstallConfig()
        XCTAssertEqual(config.appName, "MeedyaConverter")
        XCTAssertTrue(config.startMenuShortcut)
        XCTAssertTrue(config.fileAssociations)
        XCTAssertEqual(config.installerType, .msix)
    }

    // =========================================================================
    // MARK: - Phase 3.26: Color Space Conversion & HDR Tone Mapping
    // =========================================================================

    /// Verifies ColorPrimaries properties.
    func test_colorPrimaries_properties() {
        XCTAssertEqual(ColorPrimaries.bt709.displayName, "BT.709 (HD)")
        XCTAssertEqual(ColorPrimaries.bt2020.displayName, "BT.2020 (UHD)")
        XCTAssertTrue(ColorPrimaries.bt2020.isWideGamut)
        XCTAssertTrue(ColorPrimaries.dciP3.isWideGamut)
        XCTAssertFalse(ColorPrimaries.bt709.isWideGamut)
        XCTAssertFalse(ColorPrimaries.bt601NTSC.isWideGamut)
    }

    /// Verifies TransferFunction properties.
    func test_transferFunction_properties() {
        XCTAssertTrue(TransferFunction.pq.isHDR)
        XCTAssertTrue(TransferFunction.hlg.isHDR)
        XCTAssertFalse(TransferFunction.bt709.isHDR)
        XCTAssertFalse(TransferFunction.srgb.isHDR)
        XCTAssertEqual(TransferFunction.pq.displayName, "PQ / ST 2084 (HDR10)")
    }

    /// Verifies ToneMapAlgorithm enum.
    func test_toneMapAlgorithm() {
        XCTAssertEqual(ToneMapAlgorithm.hable.rawValue, "hable")
        XCTAssertEqual(ToneMapAlgorithm.reinhard.rawValue, "reinhard")
        XCTAssertFalse(ToneMapAlgorithm.hable.description.isEmpty)
    }

    /// Verifies HDR to SDR tone map filter.
    func test_colorSpaceConverter_toneMapFilter() {
        let config = ToneMapConfig(algorithm: .hable, peakBrightness: 1000, desaturation: 0.0)
        let filter = ColorSpaceConverter.buildToneMapFilter(config: config)
        XCTAssertTrue(filter.contains("zscale=t=linear"))
        XCTAssertTrue(filter.contains("gbrpf32le"))
        XCTAssertTrue(filter.contains("tonemap=hable"))
        XCTAssertTrue(filter.contains("bt709"))
        XCTAssertTrue(filter.contains("yuv420p"))
    }

    /// Verifies 10-bit SDR output option.
    func test_colorSpaceConverter_10bitSDR() {
        let config = ToneMapConfig(algorithm: .mobius, use10BitSDR: true)
        let filter = ColorSpaceConverter.buildToneMapFilter(config: config)
        XCTAssertTrue(filter.contains("yuv420p10le"))
    }

    /// Verifies HDR to SDR FFmpeg arguments.
    func test_colorSpaceConverter_hdrToSDRArguments() {
        let args = ColorSpaceConverter.buildHDRtoSDRArguments(
            inputPath: "/tmp/hdr.mkv",
            outputPath: "/tmp/sdr.mkv"
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt709"))
    }

    /// Verifies general color space conversion filter.
    func test_colorSpaceConverter_colorSpaceFilter() {
        let config = ColorSpaceConfig(
            targetPrimaries: .bt709,
            targetTransfer: .bt709,
            targetMatrix: .bt709
        )
        let filter = ColorSpaceConverter.buildColorSpaceFilter(config: config)
        XCTAssertTrue(filter.contains("zscale="))
        XCTAssertTrue(filter.contains("p=709"))
        XCTAssertTrue(filter.contains("t=709"))
    }

    /// Verifies HLG to SDR filter.
    func test_colorSpaceConverter_hlgToSDR() {
        let filter = ColorSpaceConverter.buildHLGtoSDRFilter()
        XCTAssertTrue(filter.contains("zscale=t=linear"))
        XCTAssertTrue(filter.contains("tonemap="))
        XCTAssertTrue(filter.contains("bt709"))
    }

    /// Verifies HDR metadata arguments.
    func test_colorSpaceConverter_hdrMetadata() {
        var metadata = HDRMetadata(maxCLL: 1000, maxFALL: 400)
        metadata.masteringDisplayMaxLuminance = 1000.0
        metadata.masteringDisplayMinLuminance = 0.005
        let args = ColorSpaceConverter.buildHDRMetadataArguments(metadata: metadata)
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
        XCTAssertTrue(args.contains("-master_display"))
    }

    /// Verifies strip HDR metadata arguments.
    func test_colorSpaceConverter_stripHDR() {
        let args = ColorSpaceConverter.buildStripHDRMetadataArguments()
        XCTAssertTrue(args.contains("bt709"))
        XCTAssertEqual(args.count, 6)
    }

    /// Verifies DoVi to HDR10 arguments.
    func test_colorSpaceConverter_doviToHDR10() {
        let args = ColorSpaceConverter.buildDoViToHDR10Arguments(
            inputPath: "/tmp/dv.hevc",
            outputPath: "/tmp/hdr10.hevc"
        )
        XCTAssertTrue(args.contains("remove"))
        XCTAssertTrue(args.contains("-i"))
    }

    /// Verifies conversion detection helpers.
    func test_colorSpaceConverter_needsConversion() {
        XCTAssertTrue(ColorSpaceConverter.needsConversion(
            sourcePrimaries: .bt2020, targetPrimaries: .bt709,
            sourceTransfer: .pq, targetTransfer: .bt709
        ))
        XCTAssertFalse(ColorSpaceConverter.needsConversion(
            sourcePrimaries: .bt709, targetPrimaries: .bt709,
            sourceTransfer: .bt709, targetTransfer: .bt709
        ))
    }

    /// Verifies tone mapping detection.
    func test_colorSpaceConverter_needsToneMapping() {
        XCTAssertTrue(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .pq, targetTransfer: .bt709
        ))
        XCTAssertTrue(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .hlg, targetTransfer: .bt709
        ))
        XCTAssertFalse(ColorSpaceConverter.needsToneMapping(
            sourceTransfer: .bt709, targetTransfer: .bt709
        ))
    }

    /// Verifies recommended primaries by resolution.
    func test_colorSpaceConverter_recommendedPrimaries() {
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 2160), .bt2020)
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 1080), .bt709)
        XCTAssertEqual(ColorSpaceConverter.recommendedPrimaries(forHeight: 480), .bt601NTSC)
    }

    /// Verifies HDRMetadata peak brightness defaults.
    func test_hdrMetadata_peakBrightness() {
        let empty = HDRMetadata()
        XCTAssertEqual(empty.peakBrightness, 1000)

        let withCLL = HDRMetadata(maxCLL: 4000)
        XCTAssertEqual(withCLL.peakBrightness, 4000)
    }

    // =========================================================================
    // MARK: - Phase 3.23: Extended Video Codecs
    // =========================================================================

    /// Verifies ExtendedVideoCodecType properties.
    func test_extendedVideoCodec_properties() {
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.canEncode)
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.isLossless)
        XCTAssertTrue(ExtendedVideoCodecType.cineform.canEncode)
        XCTAssertFalse(ExtendedVideoCodecType.vc1.canEncode)
        XCTAssertFalse(ExtendedVideoCodecType.wmv9.canEncode)
        XCTAssertTrue(ExtendedVideoCodecType.jpeg2000.canEncode)
    }

    /// Verifies extended codec display names.
    func test_extendedVideoCodec_displayNames() {
        XCTAssertEqual(ExtendedVideoCodecType.ffv1.displayName, "FFV1 (Archival Lossless)")
        XCTAssertEqual(ExtendedVideoCodecType.cineform.displayName, "GoPro CineForm")
        XCTAssertEqual(ExtendedVideoCodecType.jpeg2000.displayName, "JPEG 2000")
    }

    /// Verifies FFmpeg encoder/decoder names.
    func test_extendedVideoCodec_ffmpegNames() {
        XCTAssertEqual(ExtendedVideoCodecType.ffv1.ffmpegEncoder, "ffv1")
        XCTAssertEqual(ExtendedVideoCodecType.cineform.ffmpegEncoder, "cfhd")
        XCTAssertNil(ExtendedVideoCodecType.vc1.ffmpegEncoder)
        XCTAssertEqual(ExtendedVideoCodecType.vc1.ffmpegDecoder, "vc1")
    }

    /// Verifies compatible containers.
    func test_extendedVideoCodec_containers() {
        XCTAssertTrue(ExtendedVideoCodecType.ffv1.compatibleContainers.contains("mkv"))
        XCTAssertTrue(ExtendedVideoCodecType.jpeg2000.compatibleContainers.contains("mxf"))
        XCTAssertTrue(ExtendedVideoCodecType.cineform.compatibleContainers.contains("avi"))
    }

    /// Verifies FFV1 encoding arguments.
    func test_extendedVideoCodecBuilder_ffv1() {
        let config = FFV1Config(version: 3, sliceCount: 8, sliceCRC: true)
        let args = ExtendedVideoCodecBuilder.buildFFV1EncodeArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/archive.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("ffv1"))
        XCTAssertTrue(args.contains("-level"))
        XCTAssertTrue(args.contains("3"))
        XCTAssertTrue(args.contains("-slices"))
        XCTAssertTrue(args.contains("8"))
        XCTAssertTrue(args.contains("-slicecrc"))
    }

    /// Verifies CineForm encoding arguments.
    func test_extendedVideoCodecBuilder_cineform() {
        let args = ExtendedVideoCodecBuilder.buildCineFormEncodeArguments(
            inputPath: "/tmp/source.mov",
            outputPath: "/tmp/edit.avi",
            quality: 8
        )
        XCTAssertTrue(args.contains("cfhd"))
        XCTAssertTrue(args.contains("-quality"))
        XCTAssertTrue(args.contains("8"))
    }

    /// Verifies JPEG 2000 encoding arguments.
    func test_extendedVideoCodecBuilder_jpeg2000() {
        let config = JPEG2000Config(cinemaProfile: .cinema2K)
        let args = ExtendedVideoCodecBuilder.buildJPEG2000EncodeArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/dcp.mxf",
            config: config
        )
        XCTAssertTrue(args.contains("libopenjpeg"))
        XCTAssertTrue(args.contains("-cinema_mode"))
        XCTAssertTrue(args.contains("cinema2k"))
    }

    /// Verifies JPEG2000CinemaProfile properties.
    func test_jpeg2000CinemaProfile() {
        XCTAssertEqual(JPEG2000CinemaProfile.cinema2K.maxBitrateMbps, 250)
        XCTAssertEqual(JPEG2000CinemaProfile.cinema4K.maxBitrateMbps, 500)

        let res2K = JPEG2000CinemaProfile.cinema2K.resolution
        XCTAssertEqual(res2K.width, 2048)
        XCTAssertEqual(res2K.height, 1080)
    }

    /// Verifies passthrough arguments.
    func test_extendedVideoCodecBuilder_passthrough() {
        let args = ExtendedVideoCodecBuilder.buildPassthroughArguments(
            inputPath: "/tmp/source.mkv",
            outputPath: "/tmp/output.mkv"
        )
        XCTAssertTrue(args.contains("copy"))
    }

    // =========================================================================
    // MARK: - Phase 3.24: Extended Containers
    // =========================================================================

    /// Verifies ExtendedContainerFormat properties.
    func test_extendedContainer_properties() {
        XCTAssertEqual(ExtendedContainerFormat.mxf.fileExtension, "mxf")
        XCTAssertEqual(ExtendedContainerFormat.avi.fileExtension, "avi")
        XCTAssertEqual(ExtendedContainerFormat.mpegTS.fileExtension, "ts")
        XCTAssertEqual(ExtendedContainerFormat.threeGP.fileExtension, "3gp")
    }

    /// Verifies container display names.
    func test_extendedContainer_displayNames() {
        XCTAssertTrue(ExtendedContainerFormat.mxf.displayName.contains("MXF"))
        XCTAssertTrue(ExtendedContainerFormat.avi.displayName.contains("AVI"))
        XCTAssertTrue(ExtendedContainerFormat.flv.displayName.contains("FLV"))
    }

    /// Verifies FFmpeg muxer/demuxer names.
    func test_extendedContainer_ffmpegNames() {
        XCTAssertEqual(ExtendedContainerFormat.mpegTS.ffmpegMuxer, "mpegts")
        XCTAssertEqual(ExtendedContainerFormat.avi.ffmpegMuxer, "avi")
        XCTAssertEqual(ExtendedContainerFormat.ogg.ffmpegMuxer, "ogg")
    }

    /// Verifies container codec compatibility.
    func test_extendedContainer_codecCompatibility() {
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("h264", with: .mpegTS))
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("h264", with: .flv))
        XCTAssertFalse(ExtendedContainerBuilder.isVideoCodecCompatible("hevc", with: .avi))
        XCTAssertTrue(ExtendedContainerBuilder.isVideoCodecCompatible("anything", with: .nut))
    }

    /// Verifies audio codec compatibility.
    func test_extendedContainer_audioCompatibility() {
        XCTAssertTrue(ExtendedContainerBuilder.isAudioCodecCompatible("aac", with: .mpegTS))
        XCTAssertTrue(ExtendedContainerBuilder.isAudioCodecCompatible("vorbis", with: .ogg))
        XCTAssertFalse(ExtendedContainerBuilder.isAudioCodecCompatible("flac", with: .flv))
    }

    /// Verifies MPEG-TS arguments.
    func test_extendedContainerBuilder_mpegTS() {
        let args = ExtendedContainerBuilder.buildMPEGTSArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.ts",
            serviceName: "MeedyaConverter"
        )
        XCTAssertTrue(args.contains("mpegts"))
        XCTAssertTrue(args.contains("resend_headers"))
        XCTAssertTrue(args.contains { $0.contains("MeedyaConverter") })
    }

    /// Verifies MXF arguments.
    func test_extendedContainerBuilder_mxf() {
        let args = ExtendedContainerBuilder.buildMXFArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.mxf"
        )
        XCTAssertTrue(args.contains("mpeg2video"))
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertTrue(args.contains("mxf"))
    }

    /// Verifies 3GP arguments.
    func test_extendedContainerBuilder_3gp() {
        let args = ExtendedContainerBuilder.build3GPArguments(
            inputPath: "/tmp/source.mp4",
            outputPath: "/tmp/output.3gp"
        )
        XCTAssertTrue(args.contains("3gp"))
        XCTAssertTrue(args.contains("h264"))
        XCTAssertTrue(args.contains("aac"))
    }

    /// Verifies recommended audio codec.
    func test_extendedContainerBuilder_recommendAudioCodec() {
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .mxf), "pcm_s16le")
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .ogg), "libvorbis")
        XCTAssertEqual(ExtendedContainerBuilder.recommendAudioCodec(for: .flv), "aac")
    }

    /// Verifies container feature flags.
    func test_extendedContainer_features() {
        XCTAssertTrue(ExtendedContainerFormat.ogg.supportsChapters)
        XCTAssertFalse(ExtendedContainerFormat.flv.supportsChapters)
        XCTAssertTrue(ExtendedContainerFormat.mpegTS.supportsSubtitles)
        XCTAssertNotNil(ExtendedContainerFormat.avi.maxFileSize)
    }

    // =========================================================================
    // MARK: - Phase 7: Stereo 3D Conversion
    // =========================================================================

    /// Verifies Stereo3DLayout properties.
    func test_stereo3DLayout_properties() {
        XCTAssertEqual(Stereo3DLayout.sideBySide.displayName, "Side-by-Side (Full)")
        XCTAssertTrue(Stereo3DLayout.sideBySideHalf.isHalfResolution)
        XCTAssertTrue(Stereo3DLayout.topBottomHalf.isHalfResolution)
        XCTAssertFalse(Stereo3DLayout.sideBySide.isHalfResolution)
    }

    /// Verifies Stereo3DOutput properties.
    func test_stereo3DOutput_properties() {
        XCTAssertEqual(Stereo3DOutput.mvHevc.displayName, "MV-HEVC (Spatial Video)")
        XCTAssertFalse(Stereo3DOutput.mvHevc.compatiblePlatforms.isEmpty)
        XCTAssertTrue(Stereo3DOutput.mvHevc.compatiblePlatforms.contains("Apple Vision Pro"))
    }

    /// Verifies left eye crop filter for SBS.
    func test_stereo3DConverter_leftEyeCropSBS() {
        let crop = Stereo3DConverter.buildLeftEyeCropFilter(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:0"))
    }

    /// Verifies right eye crop filter for SBS.
    func test_stereo3DConverter_rightEyeCropSBS() {
        let crop = Stereo3DConverter.buildRightEyeCropFilter(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:1920:0"))
    }

    /// Verifies left eye crop filter for TB.
    func test_stereo3DConverter_leftEyeCropTB() {
        let crop = Stereo3DConverter.buildLeftEyeCropFilter(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:0"))
    }

    /// Verifies right eye crop filter for TB.
    func test_stereo3DConverter_rightEyeCropTB() {
        let crop = Stereo3DConverter.buildRightEyeCropFilter(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertTrue(crop.contains("crop=1920:1080:0:1080"))
    }

    /// Verifies MV-HEVC conversion arguments.
    func test_stereo3DConverter_mvHevcArguments() {
        let config = Stereo3DConfig(
            inputLayout: .sideBySide,
            outputFormat: .mvHevc
        )
        let args = Stereo3DConverter.buildMVHEVCArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/spatial.mov",
            config: config,
            frameWidth: 3840,
            frameHeight: 1080
        )
        XCTAssertTrue(args.contains("hevc_videotoolbox"))
        XCTAssertTrue(args.contains("-filter_complex"))
        XCTAssertTrue(args.contains("[left]"))
        XCTAssertTrue(args.contains("[right]"))
        XCTAssertTrue(args.contains("hvc1"))
    }

    /// Verifies stereo 3D format conversion arguments.
    func test_stereo3DConverter_formatConversion() {
        let config = Stereo3DConfig(
            inputLayout: .sideBySide,
            outputFormat: .topBottom
        )
        let args = Stereo3DConverter.buildStereo3DConvertArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/tb.mkv",
            config: config
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains { $0.contains("stereo3d=") })
    }

    /// Verifies eye extraction arguments.
    func test_stereo3DConverter_eyeExtraction() {
        let args = Stereo3DConverter.buildEyeExtractionArguments(
            inputPath: "/tmp/sbs.mkv",
            outputPath: "/tmp/left.mkv",
            layout: .sideBySide,
            eye: "left",
            frameWidth: 3840,
            frameHeight: 1080
        )
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains { $0.contains("crop=") })
    }

    /// Verifies per-eye resolution calculation.
    func test_stereo3DConverter_perEyeResolution() {
        let sbsRes = Stereo3DConverter.perEyeResolution(
            frameWidth: 3840, frameHeight: 1080, layout: .sideBySide
        )
        XCTAssertEqual(sbsRes.width, 1920)
        XCTAssertEqual(sbsRes.height, 1080)

        let tbRes = Stereo3DConverter.perEyeResolution(
            frameWidth: 1920, frameHeight: 2160, layout: .topBottom
        )
        XCTAssertEqual(tbRes.width, 1920)
        XCTAssertEqual(tbRes.height, 1080)
    }

    /// Verifies stereo layout detection from dimensions.
    func test_stereo3DConverter_detectLayout() {
        // Very wide = SBS
        let sbs = Stereo3DConverter.detectStereoLayout(frameWidth: 3840, frameHeight: 1080)
        XCTAssertEqual(sbs, .sideBySideHalf)

        // Very tall = TB
        let tb = Stereo3DConverter.detectStereoLayout(frameWidth: 1920, frameHeight: 2880)
        XCTAssertEqual(tb, .topBottomHalf)

        // Normal aspect ratio = nil (2D)
        let normal = Stereo3DConverter.detectStereoLayout(frameWidth: 1920, frameHeight: 1080)
        XCTAssertNil(normal)
    }

    /// Verifies Stereo3DConfig defaults.
    func test_stereo3DConfig_defaults() {
        let config = Stereo3DConfig()
        XCTAssertEqual(config.inputLayout, .sideBySide)
        XCTAssertEqual(config.outputFormat, .mvHevc)
        XCTAssertFalse(config.swapEyes)
        XCTAssertTrue(config.preserveHDR)
    }

    // =========================================================================
    // MARK: - Phase 5: Surround Upmixing
    // =========================================================================

    /// Verifies UpmixAlgorithm properties.
    func test_upmixAlgorithm_properties() {
        XCTAssertTrue(UpmixAlgorithm.proLogicII.isMatrixDecode)
        XCTAssertTrue(UpmixAlgorithm.dtsNeo6.isMatrixDecode)
        XCTAssertFalse(UpmixAlgorithm.virtualSurround.isMatrixDecode)
        XCTAssertEqual(UpmixAlgorithm.proLogicII.displayName, "Dolby Pro Logic II Decode")
    }

    /// Verifies UpmixTarget properties.
    func test_upmixTarget_properties() {
        XCTAssertEqual(UpmixTarget.surround51.channelCount, 6)
        XCTAssertEqual(UpmixTarget.surround71.channelCount, 8)
        XCTAssertEqual(UpmixTarget.surround51.ffmpegLayout, "5.1")
    }

    /// Verifies virtual surround 5.1 filter.
    func test_surroundUpmixer_virtual51() {
        let filter = SurroundUpmixer.buildVirtualSurround51Filter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("FL="))
        XCTAssertTrue(filter.contains("LFE="))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies virtual surround 7.1 filter.
    func test_surroundUpmixer_virtual71() {
        let filter = SurroundUpmixer.buildVirtualSurround71Filter()
        XCTAssertTrue(filter.contains("pan=7.1"))
        XCTAssertTrue(filter.contains("SL="))
        XCTAssertTrue(filter.contains("SR="))
    }

    /// Verifies Pro Logic II decode filter.
    func test_surroundUpmixer_proLogicII() {
        let filter = SurroundUpmixer.buildProLogicIIDecodeFilter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("0.707"))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies DTS Neo:6 decode filter.
    func test_surroundUpmixer_dtsNeo6() {
        let filter = SurroundUpmixer.buildDTSNeo6DecodeFilter()
        XCTAssertTrue(filter.contains("pan=5.1"))
        XCTAssertTrue(filter.contains("lowpass"))
    }

    /// Verifies upmix arguments.
    func test_surroundUpmixer_arguments() {
        let config = UpmixConfig(algorithm: .virtualSurround, target: .surround51)
        let args = SurroundUpmixer.buildUpmixArguments(
            inputPath: "/tmp/stereo.flac",
            outputPath: "/tmp/surround.m4a",
            config: config,
            audioCodec: "aac",
            bitrate: 384
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("384k"))
    }

    /// Verifies downmix filter.
    func test_surroundUpmixer_downmix() {
        let filter = SurroundUpmixer.buildDownmixFilter(sourceLayout: "5.1")
        XCTAssertTrue(filter.contains("pan=stereo"))
        XCTAssertTrue(filter.contains("FC"))
    }

    /// Verifies downmix arguments.
    func test_surroundUpmixer_downmixArguments() {
        let args = SurroundUpmixer.buildDownmixArguments(
            inputPath: "/tmp/surround.mkv",
            outputPath: "/tmp/stereo.mkv"
        )
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("2"))
    }

    /// Verifies UpmixConfig defaults.
    func test_upmixConfig_defaults() {
        let config = UpmixConfig()
        XCTAssertEqual(config.algorithm, .virtualSurround)
        XCTAssertEqual(config.target, .surround51)
        XCTAssertEqual(config.lfeCrossover, 120)
        XCTAssertEqual(config.surroundDelayMs, 20)
    }

    // =========================================================================
    // MARK: - Phase 3.25: Extended Subtitle Formats
    // =========================================================================

    /// Verifies ExtendedSubtitleFormat properties.
    func test_extendedSubtitle_properties() {
        XCTAssertEqual(ExtendedSubtitleFormat.ebuSTL.fileExtension, "stl")
        XCTAssertEqual(ExtendedSubtitleFormat.scc.fileExtension, "scc")
        XCTAssertEqual(ExtendedSubtitleFormat.pgs.fileExtension, "sup")
        XCTAssertTrue(ExtendedSubtitleFormat.pgs.isBitmap)
        XCTAssertTrue(ExtendedSubtitleFormat.vobsub.isBitmap)
        XCTAssertTrue(ExtendedSubtitleFormat.ebuSTL.isText)
        XCTAssertTrue(ExtendedSubtitleFormat.scc.isText)
    }

    /// Verifies subtitle display names.
    func test_extendedSubtitle_displayNames() {
        XCTAssertTrue(ExtendedSubtitleFormat.ebuSTL.displayName.contains("EBU"))
        XCTAssertTrue(ExtendedSubtitleFormat.scc.displayName.contains("SCC"))
        XCTAssertTrue(ExtendedSubtitleFormat.ttml.displayName.contains("TTML"))
    }

    /// Verifies subtitle conversion paths.
    func test_subtitleConversionPath_canConvert() {
        // Text-to-text: yes
        XCTAssertTrue(SubtitleConversionPath.canConvert(from: .ebuSTL, to: .scc))
        XCTAssertTrue(SubtitleConversionPath.canConvert(from: .scc, to: .ttml))

        // Bitmap-to-text: no (needs OCR)
        XCTAssertFalse(SubtitleConversionPath.canConvert(from: .pgs, to: .scc))
        XCTAssertTrue(SubtitleConversionPath.needsOCR(from: .pgs, to: .scc))

        // Text-to-bitmap: no
        XCTAssertFalse(SubtitleConversionPath.canConvert(from: .scc, to: .pgs))
    }

    /// Verifies subtitle extraction arguments.
    func test_extendedSubtitleBuilder_extract() {
        let args = ExtendedSubtitleBuilder.buildExtractArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/subs.srt",
            streamIndex: 1
        )
        XCTAssertTrue(args.contains("0:s:1"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies SCC embed arguments.
    func test_extendedSubtitleBuilder_sccEmbed() {
        let args = ExtendedSubtitleBuilder.buildSCCEmbedArguments(
            inputPath: "/tmp/movie.mp4",
            sccPath: "/tmp/captions.scc",
            outputPath: "/tmp/output.mp4"
        )
        XCTAssertTrue(args.contains("/tmp/captions.scc"))
        XCTAssertTrue(args.contains("mov_text"))
    }

    /// Verifies teletext extraction arguments.
    func test_extendedSubtitleBuilder_teletext() {
        let args = ExtendedSubtitleBuilder.buildTeletextExtractArguments(
            inputPath: "/tmp/broadcast.ts",
            outputPath: "/tmp/subs.srt",
            teletextPage: 888
        )
        XCTAssertTrue(args.contains("-txt_page"))
        XCTAssertTrue(args.contains("888"))
        XCTAssertTrue(args.contains("srt"))
    }

    /// Verifies burn-in filter.
    func test_extendedSubtitleBuilder_burnIn() {
        let filter = ExtendedSubtitleBuilder.buildBurnInFilter(streamIndex: 0)
        XCTAssertTrue(filter.contains("subtitles"))
    }

    /// Verifies bitmap overlay filter.
    func test_extendedSubtitleBuilder_bitmapOverlay() {
        let filter = ExtendedSubtitleBuilder.buildBitmapOverlayFilter(streamIndex: 1)
        XCTAssertTrue(filter.contains("overlay"))
        XCTAssertTrue(filter.contains("[0:s:1]"))
    }

    // =========================================================================
    // MARK: - Phase 3.21-22: Extended Audio Codecs
    // =========================================================================

    /// Verifies ExtendedAudioCodecType properties.
    func test_extendedAudioCodec_properties() {
        XCTAssertTrue(ExtendedAudioCodecType.dtsxIMAX.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.iamf.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.mp3surround.isImmersive)
        XCTAssertFalse(ExtendedAudioCodecType.amrNB.isImmersive)
        XCTAssertTrue(ExtendedAudioCodecType.wmaLossless.isLossless)
        XCTAssertTrue(ExtendedAudioCodecType.mp3hd.isLossless)
    }

    /// Verifies encode/decode capabilities.
    func test_extendedAudioCodec_capabilities() {
        XCTAssertTrue(ExtendedAudioCodecType.amrNB.canEncode)
        XCTAssertTrue(ExtendedAudioCodecType.amrNB.canDecode)
        XCTAssertTrue(ExtendedAudioCodecType.speex.canEncode)
        XCTAssertFalse(ExtendedAudioCodecType.dtsxIMAX.canEncode)
        XCTAssertTrue(ExtendedAudioCodecType.dtsxIMAX.canDecode)
        XCTAssertFalse(ExtendedAudioCodecType.iamf.canDecode)
    }

    /// Verifies channel counts.
    func test_extendedAudioCodec_channels() {
        XCTAssertEqual(ExtendedAudioCodecType.amrNB.maxChannels, 1)
        XCTAssertEqual(ExtendedAudioCodecType.mp3surround.maxChannels, 6)
        XCTAssertEqual(ExtendedAudioCodecType.dtsxIMAX.maxChannels, 32)
    }

    /// Verifies AMR-NB encoding arguments.
    func test_extendedAudioCodecBuilder_amrNB() {
        let args = ExtendedAudioCodecBuilder.buildAMRNBEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.amr"
        )
        XCTAssertTrue(args.contains("libopencore_amrnb"))
        XCTAssertTrue(args.contains("8000"))
        XCTAssertTrue(args.contains("1"))
    }

    /// Verifies AMR-WB encoding arguments.
    func test_extendedAudioCodecBuilder_amrWB() {
        let args = ExtendedAudioCodecBuilder.buildAMRWBEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.3gp"
        )
        XCTAssertTrue(args.contains("libvo_amrwbenc"))
        XCTAssertTrue(args.contains("16000"))
    }

    /// Verifies Speex encoding arguments.
    func test_extendedAudioCodecBuilder_speex() {
        let args = ExtendedAudioCodecBuilder.buildSpeexEncodeArguments(
            inputPath: "/tmp/voice.wav",
            outputPath: "/tmp/voice.ogg"
        )
        XCTAssertTrue(args.contains("libspeex"))
        XCTAssertTrue(args.contains("16000"))
    }

    /// Verifies DTS:X passthrough arguments.
    func test_extendedAudioCodecBuilder_dtsxPassthrough() {
        let args = ExtendedAudioCodecBuilder.buildDTSXPassthroughArguments(
            inputPath: "/tmp/imax.mkv",
            outputPath: "/tmp/output.mkv"
        )
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies extended codec detection.
    func test_extendedAudioCodecBuilder_detect() {
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("wmapro"), .wmaPro)
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("amrnb"), .amrNB)
        XCTAssertEqual(ExtendedAudioCodecBuilder.detectExtendedCodec("speex"), .speex)
        XCTAssertNil(ExtendedAudioCodecBuilder.detectExtendedCodec("aac"))
    }

    /// Verifies transcode arguments.
    func test_extendedAudioCodecBuilder_transcode() {
        let args = ExtendedAudioCodecBuilder.buildTranscodeArguments(
            inputPath: "/tmp/wma.wmv",
            outputPath: "/tmp/output.m4a",
            targetCodec: "aac",
            bitrate: 256,
            channels: 2
        )
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("256k"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("2"))
    }

    // MARK: - Phase 12: Cloud Providers Tests

    // MARK: Google Drive

    /// Verifies Google Drive simple upload URL construction.
    func test_googleDriveUploader_simpleUploadURL() {
        let url = GoogleDriveUploader.buildSimpleUploadURL(accessToken: "ya29.test")
        XCTAssertTrue(url.contains("googleapis.com/upload/drive/v3/files"))
        XCTAssertTrue(url.contains("uploadType=media"))
    }

    /// Verifies Google Drive resumable upload URL construction.
    func test_googleDriveUploader_resumableUploadURL() {
        let url = GoogleDriveUploader.buildResumableUploadURL()
        XCTAssertTrue(url.contains("uploadType=resumable"))
    }

    /// Verifies Google Drive upload headers include authorization and content type.
    func test_googleDriveUploader_uploadHeaders() {
        let headers = GoogleDriveUploader.buildUploadHeaders(
            accessToken: "ya29.test",
            contentType: "video/mp4",
            contentLength: 1024
        )
        XCTAssertEqual(headers["Authorization"], "Bearer ya29.test")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "1024")
    }

    /// Verifies Google Drive upload headers omit content-length when nil.
    func test_googleDriveUploader_uploadHeaders_noLength() {
        let headers = GoogleDriveUploader.buildUploadHeaders(
            accessToken: "tok",
            contentType: "video/mp4"
        )
        XCTAssertNil(headers["Content-Length"])
    }

    /// Verifies Google Drive upload metadata JSON with folder.
    func test_googleDriveUploader_uploadMetadata_withFolder() {
        let json = GoogleDriveUploader.buildUploadMetadata(
            filename: "movie.mp4",
            mimeType: "video/mp4",
            folderId: "folder123"
        )
        XCTAssertTrue(json.contains("\"name\":\"movie.mp4\""))
        XCTAssertTrue(json.contains("\"mimeType\":\"video/mp4\""))
        XCTAssertTrue(json.contains("\"parents\":[\"folder123\"]"))
    }

    /// Verifies Google Drive upload metadata JSON without folder.
    func test_googleDriveUploader_uploadMetadata_noFolder() {
        let json = GoogleDriveUploader.buildUploadMetadata(
            filename: "test.mov",
            mimeType: "video/quicktime"
        )
        XCTAssertFalse(json.contains("parents"))
    }

    /// Verifies Google Drive folder creation body.
    func test_googleDriveUploader_createFolderBody() {
        let json = GoogleDriveUploader.buildCreateFolderBody(
            folderName: "Exports",
            parentId: "root123"
        )
        XCTAssertTrue(json.contains("\"name\":\"Exports\""))
        XCTAssertTrue(json.contains("application/vnd.google-apps.folder"))
        XCTAssertTrue(json.contains("\"parents\":[\"root123\"]"))
    }

    /// Verifies Google Drive upload size constants.
    func test_googleDriveUploader_constants() {
        XCTAssertEqual(GoogleDriveUploader.simpleUploadMaxBytes, 5 * 1024 * 1024)
        XCTAssertEqual(GoogleDriveUploader.resumableChunkSize, 5 * 1024 * 1024)
    }

    // MARK: Dropbox

    /// Verifies Dropbox upload URLs.
    func test_dropboxUploader_urls() {
        XCTAssertTrue(DropboxUploader.uploadURL.contains("content.dropboxapi.com"))
        XCTAssertTrue(DropboxUploader.sessionStartURL.contains("upload_session/start"))
        XCTAssertTrue(DropboxUploader.sessionAppendURL.contains("upload_session/append_v2"))
        XCTAssertTrue(DropboxUploader.sessionFinishURL.contains("upload_session/finish"))
    }

    /// Verifies Dropbox upload headers with overwrite mode.
    func test_dropboxUploader_uploadHeaders_overwrite() {
        let headers = DropboxUploader.buildUploadHeaders(
            accessToken: "dbx_tok",
            dropboxPath: "/Videos/movie.mp4",
            overwrite: true
        )
        XCTAssertEqual(headers["Authorization"], "Bearer dbx_tok")
        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"mode\":\"overwrite\""))
        XCTAssertTrue(apiArg.contains("/Videos/movie.mp4"))
    }

    /// Verifies Dropbox upload headers default to add mode.
    func test_dropboxUploader_uploadHeaders_addMode() {
        let headers = DropboxUploader.buildUploadHeaders(
            accessToken: "tok",
            dropboxPath: "/test.mp4"
        )
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"mode\":\"add\""))
        XCTAssertTrue(apiArg.contains("\"autorename\":true"))
    }

    /// Verifies Dropbox session start headers.
    func test_dropboxUploader_sessionStartHeaders() {
        let headers = DropboxUploader.buildSessionStartHeaders(accessToken: "dbx_tok")
        XCTAssertEqual(headers["Authorization"], "Bearer dbx_tok")
        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
    }

    /// Verifies Dropbox session finish headers include cursor and commit.
    func test_dropboxUploader_sessionFinishHeaders() {
        let headers = DropboxUploader.buildSessionFinishHeaders(
            accessToken: "dbx_tok",
            sessionId: "sess_abc123",
            offset: 8388608,
            dropboxPath: "/Videos/large.mp4"
        )
        let apiArg = headers["Dropbox-API-Arg"]!
        XCTAssertTrue(apiArg.contains("\"session_id\":\"sess_abc123\""))
        XCTAssertTrue(apiArg.contains("\"offset\":8388608"))
        XCTAssertTrue(apiArg.contains("/Videos/large.mp4"))
    }

    /// Verifies Dropbox size constants.
    func test_dropboxUploader_constants() {
        XCTAssertEqual(DropboxUploader.singleUploadMaxBytes, 150 * 1024 * 1024)
        XCTAssertEqual(DropboxUploader.sessionChunkSize, 8 * 1024 * 1024)
    }

    // MARK: Azure Blob

    /// Verifies Azure Blob URL construction.
    func test_azureBlobUploader_buildBlobURL() {
        let url = AzureBlobUploader.buildBlobURL(
            accountName: "myaccount",
            containerName: "videos",
            blobName: "movie.mp4"
        )
        XCTAssertEqual(url, "https://myaccount.blob.core.windows.net/videos/movie.mp4")
    }

    /// Verifies Azure Blob upload headers.
    func test_azureBlobUploader_uploadHeaders() {
        let headers = AzureBlobUploader.buildUploadHeaders(
            sasToken: "sv=2023-11-03&sig=abc",
            contentType: "video/mp4",
            contentLength: 5000000
        )
        XCTAssertEqual(headers["x-ms-blob-type"], "BlockBlob")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(headers["Content-Length"], "5000000")
        XCTAssertEqual(headers["x-ms-version"], "2023-11-03")
    }

    /// Verifies Azure Blob authenticated URL with SAS token.
    func test_azureBlobUploader_authenticatedURL() {
        let url = AzureBlobUploader.buildAuthenticatedURL(
            blobURL: "https://acct.blob.core.windows.net/c/b.mp4",
            sasToken: "sv=2023&sig=xyz"
        )
        XCTAssertEqual(url, "https://acct.blob.core.windows.net/c/b.mp4?sv=2023&sig=xyz")
    }

    /// Verifies Azure Blob block list XML generation.
    func test_azureBlobUploader_blockListXML() {
        let xml = AzureBlobUploader.buildBlockListXML(blockIds: ["YmxvY2sx", "YmxvY2sy"])
        XCTAssertTrue(xml.contains("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<BlockList>"))
        XCTAssertTrue(xml.contains("<Latest>YmxvY2sx</Latest>"))
        XCTAssertTrue(xml.contains("<Latest>YmxvY2sy</Latest>"))
        XCTAssertTrue(xml.contains("</BlockList>"))
    }

    /// Verifies Azure Blob size constants.
    func test_azureBlobUploader_constants() {
        XCTAssertEqual(AzureBlobUploader.maxBlockSize, 100 * 1024 * 1024)
        XCTAssertEqual(AzureBlobUploader.defaultBlockSize, 4 * 1024 * 1024)
    }

    // MARK: OneDrive

    /// Verifies OneDrive simple upload URL.
    func test_oneDriveUploader_simpleUploadURL() {
        let url = OneDriveUploader.buildSimpleUploadURL(drivePath: "/Videos/movie.mp4")
        XCTAssertTrue(url.contains("graph.microsoft.com/v1.0"))
        XCTAssertTrue(url.contains("/me/drive/root:/Videos/movie.mp4:/content"))
    }

    /// Verifies OneDrive create session URL.
    func test_oneDriveUploader_createSessionURL() {
        let url = OneDriveUploader.buildCreateSessionURL(drivePath: "/Videos/movie.mp4")
        XCTAssertTrue(url.contains("/createUploadSession"))
        XCTAssertTrue(url.contains("/Videos/movie.mp4"))
    }

    /// Verifies OneDrive upload headers.
    func test_oneDriveUploader_uploadHeaders() {
        let headers = OneDriveUploader.buildUploadHeaders(
            accessToken: "ey_msft_token",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["Authorization"], "Bearer ey_msft_token")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
    }

    /// Verifies OneDrive session body with custom conflict behavior.
    func test_oneDriveUploader_sessionBody() {
        let body = OneDriveUploader.buildSessionBody(conflictBehavior: "replace")
        XCTAssertTrue(body.contains("\"@microsoft.graph.conflictBehavior\":\"replace\""))
    }

    /// Verifies OneDrive session body defaults to rename.
    func test_oneDriveUploader_sessionBody_defaultRename() {
        let body = OneDriveUploader.buildSessionBody()
        XCTAssertTrue(body.contains("\"rename\""))
    }

    /// Verifies OneDrive size constants.
    func test_oneDriveUploader_constants() {
        XCTAssertEqual(OneDriveUploader.simpleUploadMaxBytes, 4 * 1024 * 1024)
        XCTAssertEqual(OneDriveUploader.fragmentSize, 10 * 1024 * 1024)
    }

    // MARK: Cloudflare Stream

    /// Verifies Cloudflare Stream direct upload URL.
    func test_cloudflareStreamUploader_directUploadURL() {
        let url = CloudflareStreamUploader.buildDirectUploadURL(accountId: "acc_123")
        XCTAssertTrue(url.contains("api.cloudflare.com/client/v4"))
        XCTAssertTrue(url.contains("accounts/acc_123/stream/direct_upload"))
    }

    /// Verifies Cloudflare Stream TUS upload URL.
    func test_cloudflareStreamUploader_tusUploadURL() {
        let url = CloudflareStreamUploader.buildTUSUploadURL(accountId: "acc_456")
        XCTAssertTrue(url.contains("accounts/acc_456/stream"))
        XCTAssertFalse(url.contains("direct_upload"))
    }

    /// Verifies Cloudflare Stream upload headers include TUS protocol headers.
    func test_cloudflareStreamUploader_uploadHeaders() {
        let headers = CloudflareStreamUploader.buildUploadHeaders(
            apiToken: "cf_token",
            contentLength: 50_000_000
        )
        XCTAssertEqual(headers["Authorization"], "Bearer cf_token")
        XCTAssertEqual(headers["Tus-Resumable"], "1.0.0")
        XCTAssertEqual(headers["Upload-Length"], "50000000")
        XCTAssertEqual(headers["Content-Length"], "50000000")
    }

    /// Verifies Cloudflare Stream upload metadata encoding.
    func test_cloudflareStreamUploader_uploadMetadata() {
        let metadata = CloudflareStreamUploader.buildUploadMetadata(
            name: "My Video",
            requireSignedURLs: true
        )
        XCTAssertTrue(metadata.contains("name "))
        XCTAssertTrue(metadata.contains("requiresignedurls "))
    }

    /// Verifies Cloudflare Stream metadata without signed URLs.
    func test_cloudflareStreamUploader_uploadMetadata_noSigned() {
        let metadata = CloudflareStreamUploader.buildUploadMetadata(name: "Test")
        XCTAssertTrue(metadata.contains("name "))
        XCTAssertFalse(metadata.contains("requiresignedurls"))
    }

    // MARK: FTP

    /// Verifies FTP curl upload arguments with FTPS.
    func test_ftpUploader_curlArguments_ftps() {
        let args = FTPUploader.buildCurlUploadArguments(
            localPath: "/tmp/video.mp4",
            ftpURL: "ftp://server.com/uploads/video.mp4",
            username: "user",
            password: "pass",
            useFTPS: true
        )
        XCTAssertTrue(args.contains("-T"))
        XCTAssertTrue(args.contains("/tmp/video.mp4"))
        XCTAssertTrue(args.contains("-u"))
        XCTAssertTrue(args.contains("user:pass"))
        XCTAssertTrue(args.contains("--ssl-reqd"))
        XCTAssertTrue(args.contains("--ftp-create-dirs"))
        XCTAssertTrue(args.contains("ftp://server.com/uploads/video.mp4"))
    }

    /// Verifies FTP curl upload arguments without FTPS.
    func test_ftpUploader_curlArguments_noFTPS() {
        let args = FTPUploader.buildCurlUploadArguments(
            localPath: "/tmp/file.mp4",
            ftpURL: "ftp://server.com/file.mp4",
            username: "u",
            password: "p",
            useFTPS: false
        )
        XCTAssertFalse(args.contains("--ssl-reqd"))
        XCTAssertTrue(args.contains("--progress-bar"))
    }

    /// Verifies lftp command string construction.
    func test_ftpUploader_lftpCommand() {
        let cmd = FTPUploader.buildLftpCommand(
            localPath: "/tmp/video.mp4",
            remotePath: "/uploads/video.mp4",
            host: "ftp.example.com",
            username: "user",
            password: "pass",
            useFTPS: true
        )
        XCTAssertTrue(cmd.contains("open ftps://"))
        XCTAssertTrue(cmd.contains("user:pass@ftp.example.com"))
        XCTAssertTrue(cmd.contains("put /tmp/video.mp4 -o /uploads/video.mp4"))
        XCTAssertTrue(cmd.contains("&& bye"))
    }

    /// Verifies lftp command with plain FTP.
    func test_ftpUploader_lftpCommand_plainFTP() {
        let cmd = FTPUploader.buildLftpCommand(
            localPath: "/tmp/f.mp4",
            remotePath: "/f.mp4",
            host: "ftp.test.com",
            username: "u",
            password: "p",
            useFTPS: false
        )
        XCTAssertTrue(cmd.contains("open ftp://"))
        XCTAssertFalse(cmd.contains("ftps://"))
    }

    // MARK: APIKeyConfig

    /// Verifies APIKeyConfig initialization and validity.
    func test_apiKeyConfig_isValid() {
        let config = APIKeyConfig(
            provider: .googleDrive,
            apiKey: "ya29.test_key"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.provider, .googleDrive)
        XCTAssertEqual(config.apiKey, "ya29.test_key")
        XCTAssertNil(config.secretKey)
        XCTAssertNil(config.refreshToken)
    }

    /// Verifies APIKeyConfig with empty key is invalid.
    func test_apiKeyConfig_emptyKey_isInvalid() {
        let config = APIKeyConfig(
            provider: .dropbox,
            apiKey: ""
        )
        XCTAssertFalse(config.isValid)
    }

    /// Verifies APIKeyConfig token expiry detection.
    func test_apiKeyConfig_tokenExpired() {
        let expired = APIKeyConfig(
            provider: .oneDrive,
            apiKey: "token",
            tokenExpiresAt: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let valid = APIKeyConfig(
            provider: .oneDrive,
            apiKey: "token",
            tokenExpiresAt: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(valid.isTokenExpired)
    }

    /// Verifies APIKeyConfig without expiry is not expired.
    func test_apiKeyConfig_noExpiry_notExpired() {
        let config = APIKeyConfig(
            provider: .azureBlob,
            apiKey: "key"
        )
        XCTAssertFalse(config.isTokenExpired)
    }

    /// Verifies APIKeyConfig with all optional fields.
    func test_apiKeyConfig_fullInit() {
        let config = APIKeyConfig(
            provider: .awsS3,
            apiKey: "AKIAIOSFODNN7EXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            refreshToken: nil,
            tokenExpiresAt: nil,
            region: "us-east-1",
            customEndpoint: "https://s3.us-east-1.amazonaws.com",
            label: "Production S3"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.secretKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(config.region, "us-east-1")
        XCTAssertEqual(config.customEndpoint, "https://s3.us-east-1.amazonaws.com")
        XCTAssertEqual(config.label, "Production S3")
    }

    // MARK: - Phase 12: Extended Cloud Providers Tests

    // MARK: CloudFront

    /// Verifies CloudFront invalidation URL construction.
    func test_cloudFrontDistribution_invalidationURL() {
        let url = CloudFrontDistribution.buildInvalidationURL(distributionId: "E1A2B3C4D5")
        XCTAssertTrue(url.contains("cloudfront.amazonaws.com"))
        XCTAssertTrue(url.contains("E1A2B3C4D5/invalidation"))
    }

    /// Verifies CloudFront invalidation body XML.
    func test_cloudFrontDistribution_invalidationBody() {
        let body = CloudFrontDistribution.buildInvalidationBody(
            paths: ["/videos/*", "/thumbnails/*"],
            callerReference: "ref-123"
        )
        XCTAssertTrue(body.contains("<Quantity>2</Quantity>"))
        XCTAssertTrue(body.contains("<Path>/videos/*</Path>"))
        XCTAssertTrue(body.contains("<Path>/thumbnails/*</Path>"))
        XCTAssertTrue(body.contains("<CallerReference>ref-123</CallerReference>"))
    }

    /// Verifies CloudFront distribution URL.
    func test_cloudFrontDistribution_distributionURL() {
        let url = CloudFrontDistribution.buildDistributionURL(
            distributionDomain: "d12345.cloudfront.net",
            objectKey: "videos/movie.mp4"
        )
        XCTAssertEqual(url, "https://d12345.cloudfront.net/videos/movie.mp4")
    }

    // MARK: SharePoint

    /// Verifies SharePoint upload URL construction.
    func test_sharePointUploader_uploadURL() {
        let url = SharePointUploader.buildUploadURL(
            siteId: "site-abc",
            driveId: "drive-123",
            itemPath: "/Videos/movie.mp4"
        )
        XCTAssertTrue(url.contains("graph.microsoft.com/v1.0"))
        XCTAssertTrue(url.contains("sites/site-abc"))
        XCTAssertTrue(url.contains("drives/drive-123"))
        XCTAssertTrue(url.contains("/Videos/movie.mp4:/content"))
    }

    /// Verifies SharePoint upload session URL.
    func test_sharePointUploader_sessionURL() {
        let url = SharePointUploader.buildCreateSessionURL(
            siteId: "site-abc",
            driveId: "drive-123",
            itemPath: "/Videos/large.mp4"
        )
        XCTAssertTrue(url.contains("/createUploadSession"))
    }

    /// Verifies SharePoint upload headers.
    func test_sharePointUploader_headers() {
        let headers = SharePointUploader.buildUploadHeaders(
            accessToken: "eyJ_token",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["Authorization"], "Bearer eyJ_token")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
    }

    /// Verifies SharePoint constants.
    func test_sharePointUploader_constants() {
        XCTAssertEqual(SharePointUploader.simpleUploadMaxBytes, 4 * 1024 * 1024)
        XCTAssertEqual(SharePointUploader.fragmentSize, 10 * 1024 * 1024)
    }

    // MARK: iCloud Drive

    /// Verifies iCloud Drive container path construction.
    func test_iCloudDriveUploader_containerPath() {
        let path = ICloudDriveUploader.buildContainerPath(containerId: "iCloud.com.mwbm.MeedyaConverter")
        XCTAssertTrue(path.contains("Mobile Documents"))
        XCTAssertTrue(path.contains("iCloud.com.mwbm.MeedyaConverter"))
    }

    /// Verifies iCloud Drive document path.
    func test_iCloudDriveUploader_documentPath() {
        let path = ICloudDriveUploader.buildDocumentPath(
            containerId: "iCloud.com.mwbm.MeedyaConverter",
            relativePath: "Exports/movie.mp4"
        )
        XCTAssertTrue(path.contains("Documents/Exports/movie.mp4"))
    }

    /// Verifies default container ID.
    func test_iCloudDriveUploader_defaultContainerId() {
        XCTAssertEqual(ICloudDriveUploader.defaultContainerId, "iCloud.com.mwbm.MeedyaConverter")
    }

    // MARK: Mega

    /// Verifies Mega command URL construction.
    func test_megaUploader_commandURL() {
        let url = MegaUploader.buildCommandURL(sequenceNumber: 42)
        XCTAssertTrue(url.contains("g.api.mega.co.nz/cs"))
        XCTAssertTrue(url.contains("id=42"))
    }

    /// Verifies Mega upload request command.
    func test_megaUploader_uploadRequest() {
        let cmd = MegaUploader.buildUploadRequestCommand(fileSize: 50_000_000)
        XCTAssertTrue(cmd.contains("\"a\":\"u\""))
        XCTAssertTrue(cmd.contains("\"s\":50000000"))
    }

    /// Verifies Mega chunk size progression.
    func test_megaUploader_chunkSizes() {
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 0), 128 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 1), 256 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 2), 512 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 3), 1024 * 1024)
        XCTAssertEqual(MegaUploader.chunkSize(forChunkIndex: 10), 1024 * 1024)
    }

    // MARK: Mux

    /// Verifies Mux direct upload URL.
    func test_muxUploader_directUploadURL() {
        let url = MuxUploader.buildCreateDirectUploadURL()
        XCTAssertTrue(url.contains("api.mux.com/video/v1/uploads"))
    }

    /// Verifies Mux asset URL.
    func test_muxUploader_assetURL() {
        let url = MuxUploader.buildAssetURL(assetId: "asset_abc123")
        XCTAssertTrue(url.contains("video/v1/assets/asset_abc123"))
    }

    /// Verifies Mux headers with Basic auth.
    func test_muxUploader_headers() {
        let headers = MuxUploader.buildHeaders(
            tokenId: "tok_id",
            tokenSecret: "tok_secret"
        )
        XCTAssertTrue(headers["Authorization"]!.hasPrefix("Basic "))
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    /// Verifies Mux playback URL construction.
    func test_muxUploader_playbackURL() {
        let url = MuxUploader.buildPlaybackURL(playbackId: "play_abc")
        XCTAssertEqual(url, "https://stream.mux.com/play_abc.m3u8")
    }

    /// Verifies Mux thumbnail URL.
    func test_muxUploader_thumbnailURL() {
        let url = MuxUploader.buildThumbnailURL(playbackId: "play_abc", width: 320, time: 5.0)
        XCTAssertTrue(url.contains("image.mux.com/play_abc"))
        XCTAssertTrue(url.contains("width=320"))
        XCTAssertTrue(url.contains("time=5.0"))
    }

    /// Verifies Mux direct upload body.
    func test_muxUploader_directUploadBody() {
        let body = MuxUploader.buildDirectUploadBody(
            corsOrigin: "https://app.example.com",
            playbackPolicy: "signed",
            mp4Support: true
        )
        XCTAssertTrue(body.contains("https://app.example.com"))
        XCTAssertTrue(body.contains("\"signed\""))
        XCTAssertTrue(body.contains("mp4_support"))
    }

    // MARK: Akamai

    /// Verifies Akamai NetStorage upload URL.
    func test_akamaiNetStorageUploader_uploadURL() {
        let url = AkamaiNetStorageUploader.buildUploadURL(
            hostname: "example-nsu.akamaihd.net",
            cpCode: "123456",
            remotePath: "videos/movie.mp4"
        )
        XCTAssertEqual(url, "https://example-nsu.akamaihd.net/123456/videos/movie.mp4")
    }

    /// Verifies Akamai action header.
    func test_akamaiNetStorageUploader_actionHeader() {
        let header = AkamaiNetStorageUploader.buildActionHeader(action: "upload", version: 1)
        XCTAssertEqual(header, "version=1&action=upload")
    }

    /// Verifies Akamai upload headers.
    func test_akamaiNetStorageUploader_headers() {
        let headers = AkamaiNetStorageUploader.buildUploadHeaders(
            authData: "5, 0.0.0.0, 0.0.0.0, 1234, nonce, key",
            authSign: "hmac_signature",
            action: "version=1&action=upload",
            contentType: "video/mp4"
        )
        XCTAssertEqual(headers["X-Akamai-ACS-Auth-Data"], "5, 0.0.0.0, 0.0.0.0, 1234, nonce, key")
        XCTAssertEqual(headers["X-Akamai-ACS-Auth-Sign"], "hmac_signature")
        XCTAssertEqual(headers["X-Akamai-ACS-Action"], "version=1&action=upload")
    }

    // MARK: Backblaze B2

    /// Verifies Backblaze B2 authorization header.
    func test_backblazeB2Uploader_authHeader() {
        let header = BackblazeB2Uploader.buildAuthorizationHeader(
            keyId: "app_key_id",
            applicationKey: "app_key"
        )
        XCTAssertTrue(header.hasPrefix("Basic "))
    }

    /// Verifies Backblaze B2 upload headers.
    func test_backblazeB2Uploader_uploadHeaders() {
        let headers = BackblazeB2Uploader.buildUploadHeaders(
            authorizationToken: "auth_tok",
            filename: "video.mp4",
            contentType: "video/mp4",
            sha1: "abc123"
        )
        XCTAssertEqual(headers["Authorization"], "auth_tok")
        XCTAssertEqual(headers["X-Bz-Content-Sha1"], "abc123")
        XCTAssertNotNil(headers["X-Bz-File-Name"])
    }

    /// Verifies Backblaze B2 constants.
    func test_backblazeB2Uploader_constants() {
        XCTAssertEqual(BackblazeB2Uploader.minimumPartSize, 5 * 1024 * 1024)
        XCTAssertEqual(BackblazeB2Uploader.recommendedPartSize, 100 * 1024 * 1024)
    }

    // MARK: - Phase 14: Metadata Providers Tests

    // MARK: TheTVDB

    /// Verifies TheTVDB login URL and body.
    func test_theTVDBClient_login() {
        let url = TheTVDBClient.buildLoginURL()
        XCTAssertTrue(url.contains("api4.thetvdb.com/v4/login"))

        let body = TheTVDBClient.buildLoginBody(apiKey: "my_api_key")
        XCTAssertTrue(body.contains("\"apikey\":\"my_api_key\""))
    }

    /// Verifies TheTVDB search URL.
    func test_theTVDBClient_searchURL() {
        let url = TheTVDBClient.buildSearchURL(query: "Breaking Bad", year: 2008)
        XCTAssertTrue(url.contains("search?query=Breaking"))
        XCTAssertTrue(url.contains("type=series"))
        XCTAssertTrue(url.contains("year=2008"))
    }

    /// Verifies TheTVDB series details URL.
    func test_theTVDBClient_seriesURL() {
        let url = TheTVDBClient.buildSeriesURL(seriesId: 81189)
        XCTAssertTrue(url.contains("series/81189/extended"))
    }

    /// Verifies TheTVDB episodes URL.
    func test_theTVDBClient_episodesURL() {
        let url = TheTVDBClient.buildEpisodesURL(seriesId: 81189, seasonNumber: 3)
        XCTAssertTrue(url.contains("series/81189/episodes"))
        XCTAssertTrue(url.contains("season=3"))
    }

    /// Verifies TheTVDB headers.
    func test_theTVDBClient_headers() {
        let headers = TheTVDBClient.buildHeaders(bearerToken: "jwt_token")
        XCTAssertEqual(headers["Authorization"], "Bearer jwt_token")
        XCTAssertEqual(headers["Accept"], "application/json")
    }

    // MARK: OMDb

    /// Verifies OMDb search URL.
    func test_omdbClient_searchURL() {
        let url = OMDbClient.buildSearchURL(
            title: "Inception",
            year: 2010,
            type: "movie",
            apiKey: "abc123"
        )
        XCTAssertTrue(url.contains("s=Inception"))
        XCTAssertTrue(url.contains("y=2010"))
        XCTAssertTrue(url.contains("type=movie"))
        XCTAssertTrue(url.contains("apikey=abc123"))
    }

    /// Verifies OMDb IMDB lookup URL.
    func test_omdbClient_imdbLookupURL() {
        let url = OMDbClient.buildIMDBLookupURL(
            imdbId: "tt1375666",
            apiKey: "abc123"
        )
        XCTAssertTrue(url.contains("i=tt1375666"))
        XCTAssertTrue(url.contains("plot=full"))
    }

    /// Verifies OMDb season URL.
    func test_omdbClient_seasonURL() {
        let url = OMDbClient.buildSeasonURL(
            imdbId: "tt0903747",
            season: 5,
            apiKey: "key"
        )
        XCTAssertTrue(url.contains("i=tt0903747"))
        XCTAssertTrue(url.contains("Season=5"))
    }

    // MARK: Discogs

    /// Verifies Discogs headers.
    func test_discogsClient_headers() {
        let headers = DiscogsClient.buildHeaders(personalAccessToken: "my_token")
        XCTAssertEqual(headers["Authorization"], "Discogs token=my_token")
        XCTAssertEqual(headers["User-Agent"], "MeedyaConverter/1.0")
    }

    /// Verifies Discogs search URL.
    func test_discogsClient_searchURL() {
        let url = DiscogsClient.buildSearchURL(query: "Dark Side of the Moon", type: "master")
        XCTAssertTrue(url.contains("database/search"))
        XCTAssertTrue(url.contains("type=master"))
    }

    /// Verifies Discogs release URL.
    func test_discogsClient_releaseURL() {
        let url = DiscogsClient.buildReleaseURL(releaseId: 249504)
        XCTAssertEqual(url, "https://api.discogs.com/releases/249504")
    }

    /// Verifies Discogs barcode search.
    func test_discogsClient_barcodeSearch() {
        let url = DiscogsClient.buildBarcodeSearchURL(barcode: "0724349691704")
        XCTAssertTrue(url.contains("barcode=0724349691704"))
        XCTAssertTrue(url.contains("type=release"))
    }

    // MARK: FanArt.tv

    /// Verifies FanArt.tv movie artwork URL.
    func test_fanArtTVClient_movieArtworkURL() {
        let url = FanArtTVClient.buildMovieArtworkURL(tmdbId: 27205, apiKey: "fa_key")
        XCTAssertTrue(url.contains("movies/27205"))
        XCTAssertTrue(url.contains("api_key=fa_key"))
    }

    /// Verifies FanArt.tv TV artwork URL.
    func test_fanArtTVClient_tvArtworkURL() {
        let url = FanArtTVClient.buildTVArtworkURL(tvdbId: 81189, apiKey: "fa_key")
        XCTAssertTrue(url.contains("tv/81189"))
    }

    /// Verifies FanArt.tv music artwork URL.
    func test_fanArtTVClient_musicArtworkURL() {
        let url = FanArtTVClient.buildMusicArtworkURL(
            musicBrainzId: "65f4f0c5-ef9e-490c-aee3-909e7ae6b2ab",
            apiKey: "fa_key"
        )
        XCTAssertTrue(url.contains("music/65f4f0c5"))
    }

    /// Verifies FanArt.tv artwork types.
    func test_fanArtTVClient_artworkTypes() {
        XCTAssertTrue(FanArtTVClient.movieArtworkTypes.contains("movieposter"))
        XCTAssertTrue(FanArtTVClient.tvArtworkTypes.contains("tvposter"))
    }

    // MARK: AcoustID

    /// Verifies AcoustID lookup URL.
    func test_acoustIDClient_lookupURL() {
        let url = AcoustIDClient.buildLookupURL(
            fingerprint: "AQADtF...fingerprint",
            duration: 240,
            apiKey: "acoust_key"
        )
        XCTAssertTrue(url.contains("api.acoustid.org/v2/lookup"))
        XCTAssertTrue(url.contains("duration=240"))
        XCTAssertTrue(url.contains("client=acoust_key"))
        XCTAssertTrue(url.contains("meta=recordings"))
    }

    /// Verifies fpcalc arguments.
    func test_acoustIDClient_fpcalcArguments() {
        let args = AcoustIDClient.buildFpcalcArguments(inputPath: "/tmp/song.flac", maxDuration: 60)
        XCTAssertTrue(args.contains("-json"))
        XCTAssertTrue(args.contains("-length"))
        XCTAssertTrue(args.contains("60"))
        XCTAssertTrue(args.contains("/tmp/song.flac"))
    }

    /// Verifies FFmpeg fingerprint arguments.
    func test_acoustIDClient_ffmpegFingerprint() {
        let args = AcoustIDClient.buildFFmpegFingerprintArguments(inputPath: "/tmp/song.mp3")
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("chromaprint"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("1"))
    }

    // MARK: MeedyaDB

    /// Verifies MeedyaDB search URL.
    func test_meedyaDBClient_searchURL() {
        let url = MeedyaDBClient.buildSearchURL(query: "Inception", mediaType: "movie")
        XCTAssertTrue(url.contains("api.meedya.tv/v1/search"))
        XCTAssertTrue(url.contains("type=movie"))
    }

    /// Verifies MeedyaDB match URL.
    func test_meedyaDBClient_matchURL() {
        let url = MeedyaDBClient.buildMatchURL(filename: "Inception.2010.1080p.BluRay.mkv")
        XCTAssertTrue(url.contains("match?filename="))
    }

    /// Verifies MeedyaDB headers.
    func test_meedyaDBClient_headers() {
        let headers = MeedyaDBClient.buildHeaders(apiKey: "mdb_key")
        XCTAssertEqual(headers["X-API-Key"], "mdb_key")
    }

    // MARK: MediaServerTagging

    /// Verifies Plex movie filename generation.
    func test_mediaServerTagging_plexMovieFilename() {
        let name = MediaServerTagging.buildPlexMovieFilename(
            title: "Inception",
            year: 2010,
            extension_: "mkv"
        )
        XCTAssertEqual(name, "Inception (2010).mkv")
    }

    /// Verifies Plex episode filename generation.
    func test_mediaServerTagging_plexEpisodeFilename() {
        let name = MediaServerTagging.buildPlexEpisodeFilename(
            showTitle: "Breaking Bad",
            season: 5,
            episode: 16,
            episodeTitle: "Felina",
            extension_: "mkv"
        )
        XCTAssertEqual(name, "Breaking Bad - S05E16 - Felina.mkv")
    }

    /// Verifies Plex episode filename without episode title.
    func test_mediaServerTagging_plexEpisodeFilename_noTitle() {
        let name = MediaServerTagging.buildPlexEpisodeFilename(
            showTitle: "Lost",
            season: 1,
            episode: 1,
            extension_: "mp4"
        )
        XCTAssertEqual(name, "Lost - S01E01.mp4")
    }

    /// Verifies Kodi movie NFO generation.
    func test_mediaServerTagging_kodiMovieNFO() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            overview: "A mind-bending thriller",
            genres: ["Sci-Fi", "Action"],
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        let nfo = MediaServerTagging.buildKodiMovieNFO(result: result)
        XCTAssertTrue(nfo.contains("<movie>"))
        XCTAssertTrue(nfo.contains("<title>Inception</title>"))
        XCTAssertTrue(nfo.contains("<year>2010</year>"))
        XCTAssertTrue(nfo.contains("<genre>Sci-Fi</genre>"))
        XCTAssertTrue(nfo.contains("<director>Christopher Nolan</director>"))
        XCTAssertTrue(nfo.contains("uniqueid type=\"tmdb\""))
    }

    /// Verifies Kodi episode NFO generation.
    func test_mediaServerTagging_kodiEpisodeNFO() {
        let result = MetadataResult(
            source: .tvdb,
            externalId: "12345",
            title: "Pilot",
            season: 1,
            episode: 1,
            confidence: 0.9
        )
        let nfo = MediaServerTagging.buildKodiEpisodeNFO(result: result)
        XCTAssertTrue(nfo.contains("<episodedetails>"))
        XCTAssertTrue(nfo.contains("<season>1</season>"))
        XCTAssertTrue(nfo.contains("<episode>1</episode>"))
    }

    /// Verifies FFmpeg metadata arguments from MetadataResult.
    func test_mediaServerTagging_ffmpegMetadata() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            genres: ["Sci-Fi"],
            directors: ["Christopher Nolan"],
            confidence: 0.95
        )
        let args = MediaServerTagging.buildFFmpegMetadataArguments(result: result)
        XCTAssertTrue(args.contains("title=Inception"))
        XCTAssertTrue(args.contains("year=2010"))
        XCTAssertTrue(args.contains("genre=Sci-Fi"))
        XCTAssertTrue(args.contains("director=Christopher Nolan"))
    }

    // MARK: - Phase 2/3: Metadata Passthrough Tests

    // MARK: MetadataPassthroughMode

    /// Verifies metadata passthrough mode display names.
    func test_metadataPassthroughMode_displayNames() {
        XCTAssertEqual(MetadataPassthroughMode.copyAll.displayName, "Copy All Metadata")
        XCTAssertEqual(MetadataPassthroughMode.strip.displayName, "Strip All Metadata")
    }

    /// Verifies chapter passthrough mode display names.
    func test_chapterPassthroughMode_displayNames() {
        XCTAssertEqual(ChapterPassthroughMode.copy.displayName, "Preserve Chapters")
        XCTAssertEqual(ChapterPassthroughMode.strip.displayName, "Remove Chapters")
    }

    // MARK: MetadataPassthroughBuilder

    /// Verifies copyAll metadata arguments.
    func test_metadataPassthroughBuilder_copyAll() {
        let args = MetadataPassthroughBuilder.buildMetadataArguments(
            config: MetadataPassthroughConfig(mode: .copyAll)
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies strip metadata arguments.
    func test_metadataPassthroughBuilder_strip() {
        let args = MetadataPassthroughBuilder.buildMetadataArguments(
            config: MetadataPassthroughConfig(mode: .strip)
        )
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies custom metadata strip arguments.
    func test_metadataPassthroughBuilder_custom() {
        let config = MetadataPassthroughConfig(
            mode: .custom,
            stripKeys: ["comment", "encoder"]
        )
        let args = MetadataPassthroughBuilder.buildMetadataArguments(config: config)
        XCTAssertTrue(args.contains("comment="))
        XCTAssertTrue(args.contains("encoder="))
    }

    /// Verifies chapter copy arguments.
    func test_metadataPassthroughBuilder_chapterCopy() {
        let args = MetadataPassthroughBuilder.buildChapterArguments(mode: .copy)
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies chapter strip arguments.
    func test_metadataPassthroughBuilder_chapterStrip() {
        let args = MetadataPassthroughBuilder.buildChapterArguments(mode: .strip)
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("-1"))
    }

    /// Verifies aspect ratio override arguments.
    func test_metadataPassthroughBuilder_aspectRatioOverride() {
        let args = MetadataPassthroughBuilder.buildAspectRatioArguments(
            mode: .override_,
            customRatio: "16:9"
        )
        XCTAssertTrue(args.contains("-aspect"))
        XCTAssertTrue(args.contains("16:9"))
    }

    /// Verifies aspect ratio preserve returns no arguments.
    func test_metadataPassthroughBuilder_aspectRatioPreserve() {
        let args = MetadataPassthroughBuilder.buildAspectRatioArguments(mode: .preserve)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies disposition reset arguments.
    func test_metadataPassthroughBuilder_dispositionReset() {
        let args = MetadataPassthroughBuilder.buildDispositionArguments(
            copyDispositions: false,
            streamIndex: 1
        )
        XCTAssertTrue(args.contains("-disposition:1"))
        XCTAssertTrue(args.contains("0"))
    }

    /// Verifies set default stream arguments.
    func test_metadataPassthroughBuilder_setDefault() {
        let args = MetadataPassthroughBuilder.buildSetDefaultStream(streamSpecifier: "a:0")
        XCTAssertTrue(args.contains("-disposition:a:0"))
        XCTAssertTrue(args.contains("default"))
    }

    /// Verifies color description preservation arguments.
    func test_metadataPassthroughBuilder_colorDescription() {
        let args = MetadataPassthroughBuilder.buildColorDescriptionArguments(
            colorPrimaries: "bt2020",
            transferCharacteristics: "smpte2084",
            colorMatrix: "bt2020nc"
        )
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("smpte2084"))
        XCTAssertTrue(args.contains("-colorspace"))
        XCTAssertTrue(args.contains("bt2020nc"))
    }

    /// Verifies full argument builder combines all config.
    func test_metadataPassthroughBuilder_allArguments() {
        let config = MetadataPassthroughConfig(
            mode: .copyAll,
            chapterMode: .copy,
            aspectRatioMode: .override_,
            customAspectRatio: "2.35:1",
            preserveCodecMetadata: true,
            copyDispositions: true
        )
        let args = MetadataPassthroughBuilder.buildAllArguments(config: config)
        XCTAssertTrue(args.contains("-map_metadata"))
        XCTAssertTrue(args.contains("-map_chapters"))
        XCTAssertTrue(args.contains("-aspect"))
        XCTAssertTrue(args.contains("2.35:1"))
    }

    /// Verifies AFD preservation arguments.
    func test_metadataPassthroughBuilder_afdPreservation() {
        let args = MetadataPassthroughBuilder.buildAFDPreservationArguments(preserveAFD: true)
        XCTAssertTrue(args.contains("-copy_unknown"))

        let empty = MetadataPassthroughBuilder.buildAFDPreservationArguments(preserveAFD: false)
        XCTAssertTrue(empty.isEmpty)
    }

    /// Verifies codec metadata bitexact strip.
    func test_metadataPassthroughBuilder_codecMetadata() {
        let strip = MetadataPassthroughBuilder.buildCodecMetadataArguments(preserve: false)
        XCTAssertTrue(strip.contains("-bitexact"))

        let preserve = MetadataPassthroughBuilder.buildCodecMetadataArguments(preserve: true)
        XCTAssertTrue(preserve.isEmpty)
    }

    /// Verifies default MetadataPassthroughConfig.
    func test_metadataPassthroughConfig_defaults() {
        let config = MetadataPassthroughConfig()
        XCTAssertEqual(config.mode, .copyAll)
        XCTAssertEqual(config.chapterMode, .copy)
        XCTAssertEqual(config.aspectRatioMode, .preserve)
        XCTAssertTrue(config.preserveCodecMetadata)
        XCTAssertTrue(config.copyDispositions)
    }

    /// Verifies MediaServer enum.
    func test_mediaServer_displayNames() {
        XCTAssertEqual(MediaServerTagging.MediaServer.plex.displayName, "Plex")
        XCTAssertEqual(MediaServerTagging.MediaServer.jellyfin.displayName, "Jellyfin")
        XCTAssertEqual(MediaServerTagging.MediaServer.emby.displayName, "Emby")
        XCTAssertEqual(MediaServerTagging.MediaServer.kodi.displayName, "Kodi")
    }

    // MARK: - Phase 3: HDR Policy Engine Tests

    // MARK: HDRFormat

    /// Verifies HDR format properties.
    func test_hdrFormat_properties() {
        XCTAssertTrue(HDRFormat.hdr10.isHDR)
        XCTAssertTrue(HDRFormat.hdr10.isPQ)
        XCTAssertFalse(HDRFormat.hdr10.isHLG)
        XCTAssertFalse(HDRFormat.hdr10.hasDynamicMetadata)

        XCTAssertTrue(HDRFormat.hlg.isHDR)
        XCTAssertTrue(HDRFormat.hlg.isHLG)
        XCTAssertFalse(HDRFormat.hlg.isPQ)

        XCTAssertTrue(HDRFormat.dolbyVision.hasDynamicMetadata)
        XCTAssertTrue(HDRFormat.hdr10Plus.hasDynamicMetadata)

        XCTAssertFalse(HDRFormat.sdr.isHDR)
    }

    /// Verifies HDR format display names.
    func test_hdrFormat_displayNames() {
        XCTAssertEqual(HDRFormat.hdr10.displayName, "HDR10")
        XCTAssertEqual(HDRFormat.dolbyVision.displayName, "Dolby Vision")
        XCTAssertEqual(HDRFormat.hlg.displayName, "HLG")
    }

    // MARK: HDRCompatibility

    /// Verifies H.265 HDR compatibility.
    func test_hdrPolicyEngine_compatibility_h265() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libx265", container: "mkv")
        XCTAssertTrue(compat.supportsHDR10)
        XCTAssertTrue(compat.supportsHLG)
        XCTAssertTrue(compat.supportsDolbyVision)
        XCTAssertTrue(compat.supportsHDR10Plus)
        XCTAssertTrue(compat.supports10Bit)
    }

    /// Verifies H.264 does not support HDR.
    func test_hdrPolicyEngine_compatibility_h264() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libx264", container: "mp4")
        XCTAssertFalse(compat.supportsHDR10)
        XCTAssertFalse(compat.supportsHLG)
        XCTAssertFalse(compat.supportsDolbyVision)
        XCTAssertFalse(compat.supportsAnyHDR)
    }

    /// Verifies AV1 HDR compatibility.
    func test_hdrPolicyEngine_compatibility_av1() {
        let compat = HDRPolicyEngine.compatibility(videoCodec: "libsvtav1", container: "webm")
        XCTAssertTrue(compat.supportsHDR10)
        XCTAssertTrue(compat.supportsHLG)
        XCTAssertFalse(compat.supportsDolbyVision)
    }

    // MARK: HDRPolicyEngine Actions

    /// Verifies SDR source gets passthrough action.
    func test_hdrPolicyEngine_sdrSource_passthrough() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .sdr,
            videoCodec: "libx264",
            container: "mp4"
        )
        XCTAssertEqual(action, .passthrough)
    }

    /// Verifies HDR10 → H.264 triggers tone map.
    func test_hdrPolicyEngine_hdr10ToH264_toneMap() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx264",
            container: "mp4"
        )
        XCTAssertEqual(action, .toneMapToSDR)
    }

    /// Verifies HDR10 → H.265 preserves.
    func test_hdrPolicyEngine_hdr10ToH265_preserve() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx265",
            container: "mkv"
        )
        XCTAssertEqual(action, .preserve)
    }

    /// Verifies DV → VP9 strips dynamic metadata.
    func test_hdrPolicyEngine_dvToVP9_stripDynamic() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .dolbyVision,
            videoCodec: "libvpx-vp9",
            container: "mkv"
        )
        // VP9 supports HDR10 but not DV
        XCTAssertEqual(action, .stripDynamicMetadata)
    }

    /// Verifies user preference overrides auto-detection.
    func test_hdrPolicyEngine_userPreference() {
        let action = HDRPolicyEngine.recommendAction(
            sourceFormat: .hdr10,
            videoCodec: "libx265",
            container: "mkv",
            userPreference: .toneMapToSDR
        )
        XCTAssertEqual(action, .toneMapToSDR)
    }

    /// Verifies preserve arguments for HLG.
    func test_hdrPolicyEngine_preserveArguments_hlg() {
        let args = HDRPolicyEngine.buildPreserveArguments(sourceFormat: .hlg)
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
    }

    /// Verifies preserve arguments for HDR10.
    func test_hdrPolicyEngine_preserveArguments_hdr10() {
        let args = HDRPolicyEngine.buildPreserveArguments(sourceFormat: .hdr10)
        XCTAssertTrue(args.contains("smpte2084"))
    }

    /// Verifies tone map arguments include filter.
    func test_hdrPolicyEngine_buildArguments_toneMap() {
        let args = HDRPolicyEngine.buildArguments(action: .toneMapToSDR, sourceFormat: .hdr10)
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("-color_primaries"))
        XCTAssertTrue(args.contains("bt709"))
    }

    /// Verifies passthrough returns empty arguments.
    func test_hdrPolicyEngine_buildArguments_passthrough() {
        let args = HDRPolicyEngine.buildArguments(action: .passthrough, sourceFormat: .sdr)
        XCTAssertTrue(args.isEmpty)
    }

    // MARK: HDR Detection

    /// Verifies HDR format detection from stream metadata.
    func test_hdrPolicyEngine_detectFormat_pq() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "smpte2084",
            colorPrimaries: "bt2020"
        )
        XCTAssertEqual(fmt, .hdr10)
    }

    /// Verifies HLG detection.
    func test_hdrPolicyEngine_detectFormat_hlg() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "arib-std-b67",
            colorPrimaries: "bt2020"
        )
        XCTAssertEqual(fmt, .hlg)
    }

    /// Verifies Dolby Vision detection from side data.
    func test_hdrPolicyEngine_detectFormat_dv() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "smpte2084",
            colorPrimaries: "bt2020",
            sideDataList: ["Dolby Vision configuration"]
        )
        XCTAssertEqual(fmt, .dolbyVisionHDR10)
    }

    /// Verifies SDR detection.
    func test_hdrPolicyEngine_detectFormat_sdr() {
        let fmt = HDRPolicyEngine.detectFormat(
            colorTransfer: "bt709",
            colorPrimaries: "bt709"
        )
        XCTAssertEqual(fmt, .sdr)
    }

    /// Verifies recommended pixel format for HDR.
    func test_hdrPolicyEngine_recommendedPixelFormat() {
        let fmt = HDRPolicyEngine.recommendedPixelFormat(action: .preserve, currentPixelFormat: "yuv420p")
        XCTAssertEqual(fmt, "yuv420p10le")

        let noChange = HDRPolicyEngine.recommendedPixelFormat(action: .preserve, currentPixelFormat: "yuv420p10le")
        XCTAssertNil(noChange)

        let sdr = HDRPolicyEngine.recommendedPixelFormat(action: .toneMapToSDR, currentPixelFormat: nil)
        XCTAssertEqual(sdr, "yuv420p")
    }

    // MARK: HLGMetadataPreserver

    /// Verifies HLG preservation arguments.
    func test_hlgMetadataPreserver_preservationArguments() {
        let args = HLGMetadataPreserver.buildPreservationArguments()
        XCTAssertTrue(args.contains("-color_trc"))
        XCTAssertTrue(args.contains("arib-std-b67"))
        XCTAssertTrue(args.contains("bt2020"))
        XCTAssertTrue(args.contains("-color_range"))
        XCTAssertTrue(args.contains("tv"))
    }

    /// Verifies HLG preservation with CLL/FALL.
    func test_hlgMetadataPreserver_withCLL() {
        let args = HLGMetadataPreserver.buildPreservationArguments(maxCLL: 1000, maxFALL: 400)
        XCTAssertTrue(args.contains("-max_cll"))
        XCTAssertTrue(args.contains("1000,400"))
    }

    /// Verifies HLG pixel format upgrade.
    func test_hlgMetadataPreserver_pixelFormat() {
        let upgrade = HLGMetadataPreserver.buildPixelFormatArguments(sourcePixelFormat: "yuv420p")
        XCTAssertTrue(upgrade.contains("yuv420p10le"))

        let keep = HLGMetadataPreserver.buildPixelFormatArguments(sourcePixelFormat: "yuv420p10le")
        XCTAssertTrue(keep.contains("yuv420p10le"))
    }

    /// Verifies HLG encoder capability check.
    func test_hlgMetadataPreserver_encoderCapable() {
        XCTAssertTrue(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "libx265"))
        XCTAssertTrue(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "hevc_videotoolbox"))
        XCTAssertFalse(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "libx264"))
        XCTAssertFalse(HLGMetadataPreserver.isEncoderHLGCapable(encoder: "mpeg2video"))
    }

    // MARK: - Phase 1: MediaInfo Tests

    /// Verifies MediaInfo full report arguments.
    func test_mediaInfoBuilder_fullReport() {
        let args = MediaInfoBuilder.buildFullReportArguments(inputPath: "/tmp/video.mkv")
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(args.contains("/tmp/video.mkv"))
    }

    /// Verifies MediaInfo JSON output arguments.
    func test_mediaInfoBuilder_jsonOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .json
        )
        XCTAssertTrue(args.contains("--Output=JSON"))
    }

    /// Verifies MediaInfo XML output arguments.
    func test_mediaInfoBuilder_xmlOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .xml
        )
        XCTAssertTrue(args.contains("--Output=XML"))
    }

    /// Verifies MediaInfo PBCore output arguments.
    func test_mediaInfoBuilder_pbcoreOutput() {
        let args = MediaInfoBuilder.buildFormattedArguments(
            inputPath: "/tmp/video.mkv",
            format: .pbcore
        )
        XCTAssertTrue(args.contains("--Output=PBCore2"))
    }

    /// Verifies MediaInfo field query arguments.
    func test_mediaInfoBuilder_fieldQuery() {
        let args = MediaInfoBuilder.buildFieldQueryArguments(
            inputPath: "/tmp/video.mkv",
            section: .video,
            field: "HDR_Format"
        )
        XCTAssertTrue(args.first?.contains("Video") ?? false)
        XCTAssertTrue(args.first?.contains("HDR_Format") ?? false)
    }

    /// Verifies MediaInfo HDR analysis arguments.
    func test_mediaInfoBuilder_hdrAnalysis() {
        let args = MediaInfoBuilder.buildHDRAnalysisArguments(inputPath: "/tmp/hdr.mkv")
        XCTAssertTrue(args.first?.contains("HDR_Format") ?? false)
        XCTAssertTrue(args.first?.contains("MaxCLL") ?? false)
        XCTAssertTrue(args.first?.contains("MasteringDisplay_Luminance") ?? false)
    }

    /// Verifies MediaInfo dual analysis arguments.
    func test_mediaInfoBuilder_dualAnalysis() {
        let (ffprobe, mediaInfo) = MediaInfoBuilder.buildDualAnalysisArguments(
            inputPath: "/tmp/video.mkv"
        )
        XCTAssertTrue(ffprobe.contains("-show_streams"))
        XCTAssertTrue(mediaInfo.contains("--Output=JSON"))
    }

    /// Verifies MediaInfo HDR format parsing.
    func test_mediaInfoBuilder_parseHDRFormat() {
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("Dolby Vision, Version 1.0, Profile 8.1"),
            .dolbyVision
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("SMPTE ST 2086, HDR10 compatible"),
            .hdr10
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("SMPTE ST 2094 App 4, HDR10+ Profile A"),
            .hdr10Plus
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat("HLG"),
            .hlg
        )
        XCTAssertEqual(
            MediaInfoBuilder.parseHDRFormat(nil),
            .sdr
        )
    }

    /// Verifies DV profile parsing.
    func test_mediaInfoBuilder_parseDVProfile() {
        XCTAssertEqual(MediaInfoBuilder.parseDolbyVisionProfile("Profile 8.1"), 8)
        XCTAssertNil(MediaInfoBuilder.parseDolbyVisionProfile(nil))
    }

    /// Verifies MediaInfo search paths exist.
    func test_mediaInfoBuilder_searchPaths() {
        let paths = MediaInfoBuilder.searchPaths()
        XCTAssertFalse(paths.isEmpty)
    }

    // MARK: - Phase 5: Matrix Encoding Tests

    // MARK: MatrixEncoding

    /// Verifies matrix encoding properties.
    func test_matrixEncoding_properties() {
        XCTAssertTrue(MatrixEncoding.dolbyProLogicII.isDecodable)
        XCTAssertEqual(MatrixEncoding.dolbyProLogicII.maxDecodeChannels, 6)
        XCTAssertEqual(MatrixEncoding.dolbyProLogicIIx.maxDecodeChannels, 8)
        XCTAssertFalse(MatrixEncoding.none.isDecodable)
        XCTAssertEqual(MatrixEncoding.none.maxDecodeChannels, 2)
    }

    /// Verifies matrix encoding display names.
    func test_matrixEncoding_displayNames() {
        XCTAssertEqual(MatrixEncoding.dolbyProLogicII.displayName, "Dolby Pro Logic II")
        XCTAssertEqual(MatrixEncoding.dtsNeo6.displayName, "DTS Neo:6")
        XCTAssertEqual(MatrixEncoding.none.displayName, "None")
    }

    // MARK: MatrixEncodingPreserver

    /// Verifies matrix encoding detection from metadata.
    func test_matrixEncodingPreserver_detect() {
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("Dolby Pro Logic II Movie"),
            .dolbyProLogicII
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("DTS Neo:6"),
            .dtsNeo6
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata("Dolby Surround"),
            .dolbySurround
        )
        XCTAssertEqual(
            MatrixEncodingPreserver.detectFromMetadata(nil),
            .none
        )
    }

    /// Verifies matrix encoding detection arguments.
    func test_matrixEncodingPreserver_detectionArgs() {
        let args = MatrixEncodingPreserver.buildDetectionArguments(
            inputPath: "/tmp/audio.m4a",
            streamIndex: 1,
            duration: 15
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("astats=metadata=1:reset=1"))
        XCTAssertTrue(args.contains("0:a:1"))
    }

    /// Verifies matrix preservation arguments.
    func test_matrixEncodingPreserver_preservation() {
        let args = MatrixEncodingPreserver.buildPreservationArguments(
            encoding: .dolbyProLogicII,
            streamIndex: 0
        )
        XCTAssertTrue(args.contains("ENCODING=Dolby Pro Logic II"))
        XCTAssertTrue(args.contains("DOWNMIX_TYPE=Dolby Pro Logic II"))
    }

    /// Verifies no preservation for .none encoding.
    func test_matrixEncodingPreserver_preservation_none() {
        let args = MatrixEncodingPreserver.buildPreservationArguments(encoding: .none)
        XCTAssertTrue(args.isEmpty)
    }

    /// Verifies Pro Logic II decode filter.
    func test_matrixEncodingPreserver_decodeFilter_plII() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .dolbyProLogicII)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=5.1"))
    }

    /// Verifies Dolby Surround decode filter.
    func test_matrixEncodingPreserver_decodeFilter_surround() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .dolbySurround)
        XCTAssertNotNil(filter)
        XCTAssertTrue(filter!.contains("pan=5.1"))
    }

    /// Verifies non-decodable encoding returns nil filter.
    func test_matrixEncodingPreserver_decodeFilter_none() {
        let filter = MatrixEncodingPreserver.buildDecodeFilter(encoding: .none)
        XCTAssertNil(filter)
    }

    /// Verifies full transcode arguments with decode.
    func test_matrixEncodingPreserver_transcodeArgs() {
        let args = MatrixEncodingPreserver.buildTranscodeArguments(
            encoding: .dolbyProLogicII,
            decode: true,
            targetChannels: 6
        )
        XCTAssertTrue(args.contains("-af"))
        XCTAssertTrue(args.contains("-ac"))
        XCTAssertTrue(args.contains("6"))
        XCTAssertTrue(args.contains { $0.contains("ENCODING") })
    }

    // MARK: - Phase 5: Teletext Tests

    // MARK: TeletextExtractor

    /// Verifies teletext extraction arguments.
    func test_teletextExtractor_extractArguments() {
        let args = TeletextExtractor.buildExtractArguments(
            inputPath: "/tmp/broadcast.ts",
            outputPath: "/tmp/subs.srt",
            page: 888
        )
        XCTAssertTrue(args.contains("-txt_page"))
        XCTAssertTrue(args.contains("888"))
        XCTAssertTrue(args.contains("-c:s"))
        XCTAssertTrue(args.contains("srt"))
    }

    /// Verifies teletext detect arguments.
    func test_teletextExtractor_detectArguments() {
        let args = TeletextExtractor.buildDetectArguments(inputPath: "/tmp/broadcast.ts")
        XCTAssertTrue(args.contains("-select_streams"))
        XCTAssertTrue(args.contains("s"))
        XCTAssertTrue(args.contains("-show_entries"))
    }

    /// Verifies teletext to DVB conversion.
    func test_teletextExtractor_convertToDVB() {
        let args = TeletextExtractor.buildConvertToDVBArguments(
            inputPath: "/tmp/teletext.ts",
            outputPath: "/tmp/dvb.ts"
        )
        XCTAssertTrue(args.contains("-c:s"))
        XCTAssertTrue(args.contains("dvbsub"))
    }

    /// Verifies country page lookup.
    func test_teletextExtractor_pageForCountry() {
        XCTAssertEqual(TeletextExtractor.pageForCountry("uk"), 888)
        XCTAssertEqual(TeletextExtractor.pageForCountry("de"), 150)
        XCTAssertEqual(TeletextExtractor.pageForCountry("it"), 777)
        XCTAssertEqual(TeletextExtractor.pageForCountry("unknown"), 888)
    }

    /// Verifies subtitle page dictionary completeness.
    func test_teletextExtractor_subtitlePages() {
        XCTAssertFalse(TeletextExtractor.subtitlePages.isEmpty)
        XCTAssertNotNil(TeletextExtractor.subtitlePages["default"])
    }

    /// Verifies teletext codec names.
    func test_teletextExtractor_codecNames() {
        XCTAssertTrue(TeletextExtractor.teletextCodecNames.contains("dvb_teletext"))
    }

    // MARK: - Phase 13: Tool Bundle Manifest Tests

    /// Verifies default manifest has all expected tools.
    func test_toolBundleManifest_defaultManifest() {
        let manifest = ToolBundleManifest.defaultManifest
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.tools.count, 4)
        XCTAssertNotNil(manifest.tool(id: "dovi_tool"))
        XCTAssertNotNil(manifest.tool(id: "hlg_tools"))
        XCTAssertNotNil(manifest.tool(id: "mediainfo"))
        XCTAssertNotNil(manifest.tool(id: "fpcalc"))
    }

    /// Verifies tool lookup by binary name.
    func test_toolBundleManifest_lookupByBinaryName() {
        let manifest = ToolBundleManifest.defaultManifest
        XCTAssertEqual(manifest.tool(binaryName: "pq2hlg")?.id, "hlg_tools")
        XCTAssertEqual(manifest.tool(binaryName: "dovi_tool")?.id, "dovi_tool")
    }

    /// Verifies version comparison.
    func test_toolBundleManifest_versionComparison() {
        XCTAssertTrue(ToolBundleManifest.isUpdateAvailable(installed: "2.1.0", latest: "2.1.2"))
        XCTAssertTrue(ToolBundleManifest.isUpdateAvailable(installed: "1.9.9", latest: "2.0.0"))
        XCTAssertFalse(ToolBundleManifest.isUpdateAvailable(installed: "2.1.2", latest: "2.1.2"))
        XCTAssertFalse(ToolBundleManifest.isUpdateAvailable(installed: "3.0.0", latest: "2.1.2"))
    }

    /// Verifies GitHub release URL builder.
    func test_toolBundleManifest_releaseURL() {
        let tool = ToolBundleManifest.defaultManifest.tool(id: "dovi_tool")!
        let url = ToolBundleManifest.buildLatestReleaseURL(tool: tool)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.contains("api.github.com/repos"))
        XCTAssertTrue(url!.contains("quietvoid/dovi_tool"))
    }

    /// Verifies manifest JSON serialization.
    func test_toolBundleManifest_jsonRoundTrip() throws {
        let manifest = ToolBundleManifest.defaultManifest
        let data = try manifest.toJSON()
        let decoded = try ToolBundleManifest.fromJSON(data)
        XCTAssertEqual(decoded.tools.count, manifest.tools.count)
        XCTAssertEqual(decoded.schemaVersion, manifest.schemaVersion)
    }

    /// Verifies bundled binary path construction.
    func test_toolBundleManifest_bundledBinaryPath() {
        let tool = BundledTool(
            id: "test",
            name: "Test Tool",
            version: "1.0",
            sourceURL: "https://github.com/example/test",
            lastUpdated: "2026-01-01",
            binaryName: "testtool",
            description: "A test tool",
            license: "MIT"
        )
        let path = ToolBundleManifest.bundledBinaryPath(tool: tool, bundlePath: "/app")
        XCTAssertTrue(path.contains("testtool"))
    }

    // MARK: - Phase 14: Auto Tagger Tests

    /// Verifies auto-tag source properties.
    func test_autoTagSource_properties() {
        XCTAssertFalse(AutoTagSource.filename.requiresNetwork)
        XCTAssertFalse(AutoTagSource.existingMetadata.requiresNetwork)
        XCTAssertTrue(AutoTagSource.tmdb.requiresNetwork)
        XCTAssertTrue(AutoTagSource.tmdb.requiresAPIKey)
        XCTAssertFalse(AutoTagSource.musicBrainz.requiresAPIKey)
    }

    /// Verifies auto-tag config defaults.
    func test_autoTagConfig_defaults() {
        let config = AutoTagConfig()
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.minimumConfidence, 0.7)
        XCTAssertTrue(config.embedArtwork)
        XCTAssertFalse(config.writeNFO)
        XCTAssertEqual(config.namingTemplate, .plex)
    }

    /// Verifies output filename generation for movies.
    func test_autoTagger_generateFilename_movie() {
        let result = MetadataResult(
            source: .tmdb,
            externalId: "27205",
            title: "Inception",
            year: 2010,
            confidence: 0.95
        )
        let filename = AutoTagger.generateOutputFilename(
            result: result,
            template: .plex,
            extension_: "mkv"
        )
        XCTAssertEqual(filename, "Inception (2010).mkv")
    }

    /// Verifies output filename generation for TV episodes.
    func test_autoTagger_generateFilename_tv() {
        let result = MetadataResult(
            source: .tvdb,
            externalId: "123",
            title: "Breaking Bad",
            season: 5,
            episode: 16,
            confidence: 0.9
        )
        let filename = AutoTagger.generateOutputFilename(
            result: result,
            template: .plex,
            extension_: "mp4"
        )
        XCTAssertTrue(filename.contains("S05E16"))
    }

    /// Verifies NFO path generation.
    func test_autoTagger_nfoPath() {
        let path = AutoTagger.generateNFOPath(
            outputPath: "/output/Inception (2010).mkv",
            mediaType: .movie
        )
        XCTAssertEqual(path, "/output/Inception (2010).nfo")
    }

    /// Verifies lookup order determination.
    func test_autoTagger_lookupOrder() {
        let query = MetadataSearchQuery(mediaType: .movie, title: "Inception")
        let config = AutoTagConfig(sources: [.filename, .tmdb, .tvdb, .musicBrainz])
        let order = AutoTagger.determineLookupOrder(query: query, config: config)
        XCTAssertTrue(order.contains(.tmdb))
        XCTAssertFalse(order.contains(.musicBrainz))
    }

    /// Verifies confidence threshold check.
    func test_autoTagger_meetsThreshold() {
        let config = AutoTagConfig(minimumConfidence: 0.7)
        let good = MetadataResult(source: .tmdb, externalId: "1", title: "Test", confidence: 0.9)
        let bad = MetadataResult(source: .tmdb, externalId: "2", title: "Test", confidence: 0.3)
        XCTAssertTrue(AutoTagger.meetsThreshold(result: good, config: config))
        XCTAssertFalse(AutoTagger.meetsThreshold(result: bad, config: config))
    }

    /// Verifies filename sanitisation.
    func test_autoTagger_sanitiseFilename() {
        XCTAssertEqual(AutoTagger.sanitiseFilename("Movie: The Sequel"), "Movie The Sequel")
        XCTAssertEqual(AutoTagger.sanitiseFilename("File<>Name"), "FileName")
        XCTAssertEqual(AutoTagger.sanitiseFilename("trailing..."), "trailing")
    }

    /// Verifies artwork embedding arguments.
    func test_autoTagger_artworkArguments() {
        let args = AutoTagger.buildArtworkArguments(artworkPath: "/tmp/poster.jpg")
        XCTAssertTrue(args.contains("/tmp/poster.jpg"))
        XCTAssertTrue(args.contains("attached_pic"))
    }

    // MARK: - Phase 3: TrueHD in MP4 Tests

    /// Verifies TrueHD mux arguments.
    func test_trueHDMP4Muxer_muxArguments() {
        let args = TrueHDMP4Muxer.buildMuxArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/movie.mp4",
            fallbackCodec: "aac",
            fallbackBitrate: 256
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("aac"))
        XCTAssertTrue(args.contains("256k"))
        XCTAssertTrue(args.contains("default"))
    }

    /// Verifies TrueHD remux arguments.
    func test_trueHDMP4Muxer_remuxArguments() {
        let args = TrueHDMP4Muxer.buildRemuxArguments(
            inputPath: "/tmp/in.mkv",
            outputPath: "/tmp/out.mp4"
        )
        XCTAssertTrue(args.contains("-strict"))
        XCTAssertTrue(args.contains("unofficial"))
        XCTAssertTrue(args.contains("copy"))
    }

    /// Verifies AC-3 core extraction arguments.
    func test_trueHDMP4Muxer_ac3Extract() {
        let args = TrueHDMP4Muxer.buildAC3CoreExtractArguments(
            inputPath: "/tmp/movie.mkv",
            outputPath: "/tmp/ac3.ac3"
        )
        XCTAssertTrue(args.contains("ac3"))
        XCTAssertTrue(args.contains("640k"))
    }

    /// Verifies TrueHD validation with fallback track.
    func test_trueHDMP4Muxer_validate_withFallback() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["aac", "truehd"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    /// Verifies TrueHD validation without fallback.
    func test_trueHDMP4Muxer_validate_noFallback() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["truehd"],
            audioDefaults: [true]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings[0].contains("fallback"))
    }

    /// Verifies TrueHD validation with default TrueHD.
    func test_trueHDMP4Muxer_validate_trueHDDefault() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["truehd", "aac"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.contains { $0.contains("default") })
    }

    /// Verifies container support levels.
    func test_trueHDMP4Muxer_containerSupport() {
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "mkv"), .native)
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "mp4"), .unofficial)
        XCTAssertEqual(TrueHDMP4Muxer.trueHDSupport(container: "webm"), .unsupported)
    }

    /// Verifies no warnings for non-TrueHD content.
    func test_trueHDMP4Muxer_validate_noTrueHD() {
        let warnings = TrueHDMP4Muxer.validate(
            audioCodecs: ["aac", "ac3"],
            audioDefaults: [true, false]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - Phase 12: API Key Manager Tests

    /// Verifies API key provider properties.
    func test_apiKeyProvider_properties() {
        XCTAssertEqual(APIKeyProvider.tmdb.category, .metadata)
        XCTAssertEqual(APIKeyProvider.awsS3.category, .cloudStorage)
        XCTAssertTrue(APIKeyProvider.googleDrive.usesOAuth)
        XCTAssertFalse(APIKeyProvider.tmdb.usesOAuth)
    }

    /// Verifies API key provider registration URLs.
    func test_apiKeyProvider_registrationURLs() {
        XCTAssertNotNil(APIKeyProvider.tmdb.registrationURL)
        XCTAssertNotNil(APIKeyProvider.acoustID.registrationURL)
        XCTAssertTrue(APIKeyProvider.tmdb.registrationURL!.contains("themoviedb"))
    }

    /// Verifies stored API key validity.
    func test_storedAPIKey_validity() {
        let valid = StoredAPIKey(provider: .tmdb, apiKey: "abc123")
        XCTAssertTrue(valid.isValid)

        let empty = StoredAPIKey(provider: .tmdb, apiKey: "")
        XCTAssertFalse(empty.isValid)

        let awsNoSecret = StoredAPIKey(provider: .awsS3, apiKey: "AKID")
        XCTAssertFalse(awsNoSecret.isValid)

        let awsFull = StoredAPIKey(provider: .awsS3, apiKey: "AKID", secretKey: "secret")
        XCTAssertTrue(awsFull.isValid)
    }

    /// Verifies stored API key token expiry.
    func test_storedAPIKey_tokenExpiry() {
        let expired = StoredAPIKey(
            provider: .googleDrive,
            apiKey: "key",
            accessToken: "tok",
            tokenExpiry: Date(timeIntervalSinceNow: -3600)
        )
        XCTAssertTrue(expired.isTokenExpired)

        let fresh = StoredAPIKey(
            provider: .googleDrive,
            apiKey: "key",
            accessToken: "tok",
            tokenExpiry: Date(timeIntervalSinceNow: 3600)
        )
        XCTAssertFalse(fresh.isTokenExpired)
    }

    /// Verifies API key category display names.
    func test_apiKeyCategory_displayNames() {
        XCTAssertEqual(APIKeyCategory.cloudStorage.displayName, "Cloud Storage & Delivery")
        XCTAssertEqual(APIKeyCategory.metadata.displayName, "Metadata Providers")
    }

    /// Verifies naming template display names.
    func test_namingTemplate_displayNames() {
        XCTAssertEqual(NamingTemplate.plex.displayName, "Plex")
        XCTAssertEqual(NamingTemplate.kodi.displayName, "Kodi")
        XCTAssertEqual(NamingTemplate.simple.displayName, "Simple")
    }
}
