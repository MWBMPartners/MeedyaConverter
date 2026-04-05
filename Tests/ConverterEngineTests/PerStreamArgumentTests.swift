// ============================================================================
// MeedyaConverter — PerStreamArgumentTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

final class PerStreamArgumentTests: XCTestCase {

    // MARK: - Helpers

    /// Create a builder pre-configured with dummy input/output URLs.
    private func makeBuilder() -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        return builder
    }

    /// Assert that two consecutive elements appear in the argument array.
    private func assertConsecutive(
        _ args: [String],
        flag: String,
        value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let idx = args.firstIndex(of: flag) else {
            XCTFail("Expected flag \"\(flag)\" not found in args: \(args)", file: file, line: line)
            return
        }
        let nextIdx = args.index(after: idx)
        guard nextIdx < args.endIndex else {
            XCTFail("Flag \"\(flag)\" found at end of args with no following value", file: file, line: line)
            return
        }
        XCTAssertEqual(
            args[nextIdx], value,
            "Expected \"\(value)\" after \"\(flag)\", got \"\(args[nextIdx])\"",
            file: file, line: line
        )
    }

    // MARK: - 1. Per-Stream Audio Codec Overrides

    func testPerStreamAudioCodecOverrides() {
        var builder = makeBuilder()
        builder.perStreamAudioCodec[0] = .aacLC
        builder.perStreamAudioCodec[1] = .flac
        let args = builder.build()

        assertConsecutive(args, flag: "-c:a:0", value: "aac")
        assertConsecutive(args, flag: "-c:a:1", value: "flac")
    }

    // MARK: - 2. Per-Stream Audio Bitrate

    func testPerStreamAudioBitrate() {
        var builder = makeBuilder()
        builder.perStreamAudioCodec[0] = .aacLC
        builder.perStreamAudioBitrate[0] = 160_000
        let args = builder.build()

        assertConsecutive(args, flag: "-b:a:0", value: "160k")
    }

    // MARK: - 3. Per-Stream Video Codec Overrides

    func testPerStreamVideoCodecOverrides() {
        var builder = makeBuilder()
        builder.perStreamVideoCodec[0] = .h264
        let args = builder.build()

        assertConsecutive(args, flag: "-c:v:0", value: "libx264")
    }

    // MARK: - 4. Per-Stream Video Passthrough

    func testPerStreamVideoPassthrough() {
        var builder = makeBuilder()
        builder.perStreamVideoPassthrough[0] = true
        let args = builder.build()

        assertConsecutive(args, flag: "-c:v:0", value: "copy")
    }

    // MARK: - 5. Mixed Passthrough and Encode

    func testMixedPassthroughAndEncode() {
        var builder = makeBuilder()
        builder.perStreamVideoPassthrough[0] = true
        builder.perStreamVideoCodec[1] = .h265
        let args = builder.build()

        assertConsecutive(args, flag: "-c:v:0", value: "copy")
        assertConsecutive(args, flag: "-c:v:1", value: "libx265")
    }

    // MARK: - 6. Per-Stream Video Bitrate

    func testPerStreamVideoBitrate() {
        var builder = makeBuilder()
        builder.perStreamVideoCodec[0] = .h264
        builder.perStreamVideoBitrate[0] = 5_000_000
        let args = builder.build()

        assertConsecutive(args, flag: "-b:v:0", value: "5M")
    }

    // MARK: - 7. Per-Stream CRF Applied Globally

    func testPerStreamCRFAppliedGlobally() {
        var builder = makeBuilder()
        builder.perStreamVideoCodec[0] = .h265
        builder.perStreamVideoCRF[0] = 18
        let args = builder.build()

        // CRF is a global encoder option, not per-stream
        assertConsecutive(args, flag: "-crf", value: "18")
        XCTAssertFalse(args.contains("-crf:v:0"), "CRF should not use per-stream specifier")
    }

    // MARK: - 8. Per-Stream Preset Applied Globally

    func testPerStreamPresetAppliedGlobally() {
        var builder = makeBuilder()
        builder.perStreamVideoCodec[0] = .h265
        builder.perStreamVideoPreset[0] = "slow"
        let args = builder.build()

        // Preset is a global encoder option, not per-stream
        assertConsecutive(args, flag: "-preset", value: "slow")
        XCTAssertFalse(args.contains("-preset:v:0"), "Preset should not use per-stream specifier")
    }

    // MARK: - 9. PerStreamSettings Model — hasOverrides

    func testHasOverridesReturnsFalseWhenEmpty() {
        let settings = PerStreamSettings()
        XCTAssertFalse(settings.hasOverrides, "Empty PerStreamSettings should report no overrides")
    }

    func testHasOverridesReturnsTrueWhenVideoPopulated() {
        let settings = PerStreamSettings(
            videoOverrides: [0: VideoStreamOverride(codec: .h264)]
        )
        XCTAssertTrue(settings.hasOverrides, "PerStreamSettings with video overrides should report hasOverrides")
    }

    func testHasOverridesReturnsTrueWhenAudioPopulated() {
        let settings = PerStreamSettings(
            audioOverrides: [0: AudioStreamOverride(codec: .flac)]
        )
        XCTAssertTrue(settings.hasOverrides, "PerStreamSettings with audio overrides should report hasOverrides")
    }

    func testHasOverridesReturnsTrueWhenSubtitlePopulated() {
        let settings = PerStreamSettings(
            subtitleOverrides: [0: SubtitleStreamOverride()]
        )
        XCTAssertTrue(settings.hasOverrides, "PerStreamSettings with subtitle overrides should report hasOverrides")
    }

    // MARK: - 10. EncodingProfile with perStreamSettings via toArgumentBuilder

    func testEncodingProfileAppliesPerStreamOverrides() {
        let perStream = PerStreamSettings(
            videoOverrides: [
                0: VideoStreamOverride(passthrough: true),
                1: VideoStreamOverride(codec: .h265, crf: 20, preset: "slow"),
            ],
            audioOverrides: [
                0: AudioStreamOverride(codec: .aacLC, bitrate: 192_000),
                1: AudioStreamOverride(codec: .flac),
            ]
        )

        let profile = EncodingProfile(
            name: "Test Profile",
            perStreamSettings: perStream,
            containerFormat: .mkv
        )

        let builder = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv")
        )

        // Verify per-stream video overrides were applied to builder
        XCTAssertEqual(builder.perStreamVideoPassthrough[0], true)
        XCTAssertEqual(builder.perStreamVideoCodec[1], .h265)
        XCTAssertEqual(builder.perStreamVideoCRF[1], 20)
        XCTAssertEqual(builder.perStreamVideoPreset[1], "slow")

        // Verify per-stream audio overrides were applied to builder
        XCTAssertEqual(builder.perStreamAudioCodec[0], .aacLC)
        XCTAssertEqual(builder.perStreamAudioBitrate[0], 192_000)
        XCTAssertEqual(builder.perStreamAudioCodec[1], .flac)

        // Verify the built arguments contain expected flags
        let args = builder.build()
        assertConsecutive(args, flag: "-c:v:0", value: "copy")
        assertConsecutive(args, flag: "-c:v:1", value: "libx265")
        assertConsecutive(args, flag: "-c:a:0", value: "aac")
        assertConsecutive(args, flag: "-c:a:1", value: "flac")
        assertConsecutive(args, flag: "-b:a:0", value: "192k")
    }

    // MARK: - 11. Empty Overrides Fall Through to Global

    func testEmptyOverridesFallThroughToGlobalPassthrough() {
        var builder = makeBuilder()
        // No per-stream overrides — perStreamVideoCodec is empty
        builder.videoPassthrough = true
        let args = builder.build()

        // Global passthrough should produce -c:v copy
        assertConsecutive(args, flag: "-c:v", value: "copy")
        // No per-stream specifiers should be present
        XCTAssertFalse(args.contains("-c:v:0"), "No per-stream flag expected when overrides are empty")
    }

    func testEmptyOverridesFallThroughToGlobalCodec() {
        var builder = makeBuilder()
        // No per-stream overrides
        builder.videoCodec = .h264
        builder.videoCRF = 23
        let args = builder.build()

        // Global codec should produce -c:v libx264
        assertConsecutive(args, flag: "-c:v", value: "libx264")
        assertConsecutive(args, flag: "-crf", value: "23")
    }

    // MARK: - PerStreamSettings Codable Round-Trip

    func testPerStreamSettingsCodableRoundTrip() throws {
        let original = PerStreamSettings(
            videoOverrides: [
                0: VideoStreamOverride(codec: .h264, passthrough: false, crf: 22, bitrate: 5_000_000, preset: "medium"),
                1: VideoStreamOverride(passthrough: true),
            ],
            audioOverrides: [
                0: AudioStreamOverride(codec: .aacLC, bitrate: 160_000, sampleRate: 48000, channels: 2),
                1: AudioStreamOverride(codec: .flac),
            ],
            subtitleOverrides: [
                0: SubtitleStreamOverride(include: true, passthrough: true),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PerStreamSettings.self, from: data)

        XCTAssertEqual(original, decoded, "PerStreamSettings should survive JSON round-trip unchanged")
    }

    func testVideoStreamOverrideCodableRoundTrip() throws {
        let original = VideoStreamOverride(
            codec: .h265, passthrough: false, crf: 18, qp: nil,
            bitrate: 10_000_000, maxBitrate: 15_000_000, preset: "slow",
            width: 1920, height: 1080, frameRate: 23.976
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoStreamOverride.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testAudioStreamOverrideCodableRoundTrip() throws {
        let original = AudioStreamOverride(
            codec: .eac3, passthrough: false, bitrate: 640_000,
            sampleRate: 48000, channels: 6, channelLayout: "5.1"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioStreamOverride.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
