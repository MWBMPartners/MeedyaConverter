// ============================================================================
// MeedyaConverter — PerStreamArgumentTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Per-stream settings are keyed by SOURCE stream number (the `#N` the
/// per-stream settings view shows) and placed on the output stream each source
/// stream becomes (issue #530). Every builder here therefore knows the source's
/// streams — `layout` below — and the keys are whole-file numbers:
///
///   video #0, video #1, audio #2, audio #3, subtitle #4, subtitle #5
///
/// Before #530 these tests keyed everything 0 and 1 with no source list and
/// expected `-c:a:0`, `-c:a:1` … That only held because the builder treated
/// the keys as output positions, while the app stored whole-file numbers — so
/// in a real file the override landed on the wrong track. With the layout,
/// audio #2 is output audio 0 and audio #3 is output audio 1, which is what
/// the expectations below now say.
final class PerStreamArgumentTests: XCTestCase {

    // MARK: - Helpers

    /// The source file every test uses (see the class comment).
    private let layout = streamLayout(.video, .video, .audio, .audio, .subtitle, .subtitle)

    /// Create a builder pre-configured with dummy input/output URLs and the
    /// source layout above.
    private func makeBuilder() -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = URL(fileURLWithPath: "/tmp/input.mkv")
        builder.outputURL = URL(fileURLWithPath: "/tmp/output.mkv")
        builder.sourceStreams = layout
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
        builder.perStreamAudioCodec[2] = .aacLC   // source #2 → output audio 0
        builder.perStreamAudioCodec[3] = .flac    // source #3 → output audio 1
        let args = builder.build()

        assertConsecutive(args, flag: "-c:a:0", value: "aac")
        assertConsecutive(args, flag: "-c:a:1", value: "flac")
    }

    // MARK: - 2. Per-Stream Audio Bitrate

    func testPerStreamAudioBitrate() {
        var builder = makeBuilder()
        builder.perStreamAudioCodec[2] = .aacLC
        builder.perStreamAudioBitrate[2] = 160_000
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
        // Keys are source stream numbers in `layout` (see the class comment).
        let perStream = PerStreamSettings(
            videoOverrides: [
                0: VideoStreamOverride(passthrough: true),
                1: VideoStreamOverride(codec: .h265, crf: 20, preset: "slow"),
            ],
            audioOverrides: [
                2: AudioStreamOverride(codec: .aacLC, bitrate: 192_000),
                3: AudioStreamOverride(codec: .flac)
            ],
            subtitleOverrides: [
                4: SubtitleStreamOverride(include: true, passthrough: true),
                5: SubtitleStreamOverride(include: false, passthrough: true)
            ]
        )

        let profile = EncodingProfile(
            name: "Test Profile",
            subtitlePassthrough: true,
            perStreamSettings: perStream,
            containerFormat: .mkv
        )

        var builder = profile.toArgumentBuilder(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv")
        )
        builder.sourceStreams = layout

        // Verify per-stream video overrides were applied to builder
        XCTAssertEqual(builder.perStreamVideoPassthrough[0], true)
        XCTAssertEqual(builder.perStreamVideoCodec[1], .h265)
        XCTAssertEqual(builder.perStreamVideoCRF[1], 20)
        XCTAssertEqual(builder.perStreamVideoPreset[1], "slow")

        // Verify per-stream audio overrides were applied to builder
        XCTAssertEqual(builder.perStreamAudioCodec[2], .aacLC)
        XCTAssertEqual(builder.perStreamAudioBitrate[2], 192_000)
        XCTAssertEqual(builder.perStreamAudioCodec[3], .flac)

        // Verify per-stream subtitle overrides were applied to builder
        XCTAssertEqual(builder.perStreamSubtitleInclude[4], true)
        XCTAssertEqual(builder.perStreamSubtitleInclude[5], false)
        XCTAssertEqual(builder.perStreamSubtitlePassthrough[4], true)
        XCTAssertEqual(builder.perStreamSubtitlePassthrough[5], true)

        // Verify the built arguments contain expected flags
        let args = builder.build()
        assertConsecutive(args, flag: "-c:v:0", value: "copy")
        assertConsecutive(args, flag: "-c:v:1", value: "libx265")
        assertConsecutive(args, flag: "-c:a:0", value: "aac")
        assertConsecutive(args, flag: "-c:a:1", value: "flac")
        assertConsecutive(args, flag: "-b:a:0", value: "192k")
        assertConsecutive(args, flag: "-c:s:0", value: "copy")

        // Source #5's include:false override removes it from the output:
        // with a source list the mapping is explicit, so #5 is simply never
        // mapped (the old legacy path wrote a negative `-map -0:s:1`).
        let mapped = zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
        XCTAssertEqual(mapped, ["0:0", "0:1", "0:2", "0:3", "0:4"], "\(args)")
        // Excluded streams get no redundant per-stream codec option —
        // there is no matching output stream left to apply it to.
        XCTAssertFalse(args.contains("-c:s:1"), "Excluded stream #5 should not get a subtitle codec option")
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

    // MARK: - 12. Per-Stream Subtitle Overrides (Issue #41)

    func testPerStreamSubtitleExclusionMapping() {
        var builder = makeBuilder()
        builder.subtitlePassthrough = true
        builder.perStreamSubtitleInclude[5] = false
        let args = builder.build()

        let mapped = zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
        // Every other stream is still mapped (explicitly, by whole-file
        // number); subtitle #5 is not.
        XCTAssertEqual(mapped, ["0:0", "0:1", "0:2", "0:3", "0:4"], "\(args)")
    }

    func testPerStreamSubtitleExclusionAppliesUnderMapAllStreams() {
        var builder = makeBuilder()
        builder.mapAllStreams = true
        builder.perStreamSubtitleInclude[4] = false
        let args = builder.build()

        let mapped = zip(args, args.dropFirst()).filter { $0.0 == "-map" }.map(\.1)
        XCTAssertEqual(mapped, ["0:0", "0:1", "0:2", "0:3", "0:5"],
                       "Subtitle #4 should still be excluded under mapAllStreams: \(args)")
    }

    func testPerStreamSubtitlePassthroughForcesCopy() {
        var builder = makeBuilder()
        builder.subtitlePassthrough = true
        builder.perStreamSubtitlePassthrough[4] = true   // source #4 → output subtitle 0
        let args = builder.build()

        assertConsecutive(args, flag: "-c:s:0", value: "copy")
    }

    /// Without the source's streams, per-stream settings cannot be matched to
    /// output tracks. They are left out and reported (the engine then refuses
    /// the job) — never written with the whole-file number as if it were a
    /// type-counted one (#530).
    func testPerStreamSettingsWithoutSourceStreamsAreReportedNotGuessed() {
        var builder = makeBuilder()
        builder.sourceStreams = nil
        builder.perStreamAudioCodec[2] = .flac
        builder.perStreamSubtitleInclude[4] = false
        let args = builder.build()

        XCTAssertFalse(args.contains { $0.hasPrefix("-c:a:") }, "\(args)")
        XCTAssertFalse(args.contains { $0.hasPrefix("-0:") }, "\(args)")
        let problems = builder.streamSelectionProblems()
        XCTAssertEqual(problems.count, 1, "\(problems)")
        XCTAssertTrue(problems[0].contains("audio codec (stream #2)"), problems[0])
        XCTAssertTrue(problems[0].contains("subtitle removal (stream #4)"), problems[0])
    }

    func testEmptyPerStreamSubtitleOverridesNoExclusion() {
        var builder = makeBuilder()
        builder.subtitlePassthrough = true
        let args = builder.build()

        XCTAssertFalse(
            args.contains { $0.hasPrefix("-0:s:") },
            "No exclusion maps expected when perStreamSubtitleInclude is empty: \(args)"
        )
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
