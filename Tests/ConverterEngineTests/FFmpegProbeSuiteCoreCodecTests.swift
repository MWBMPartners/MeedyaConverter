// ============================================================================
// MeedyaConverter — FFmpegProbeSuiteCoreCodecTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// End-to-end coverage of the #372 adoption slice: `FFmpegProbe.analyze`
/// must tag audio streams with `MediaStream.suiteCoreCodecDescriptor` via
/// `SuiteCoreCodecClassifier`, using its default (no `SUITE_CORE`)
/// built-in fallback table.
///
/// `parseProbeOutput`/`parseStream` are `private`, so — following the
/// fixture-script pattern established in `FFmpegProbeWatchdogTests` — we
/// drive the real, public `analyze(url:)` entry point with a fake
/// `ffprobe` binary (a shell script) that prints crafted JSON to stdout.
/// `analyze` only requires that `url` exists on disk (its file-exists
/// pre-check), so the fixture script's own path doubles as the "media
/// file" URL.
final class FFmpegProbeSuiteCoreCodecTests: XCTestCase {

    // MARK: - Fixture helpers

    private var fixturesToCleanUp: [String] = []

    override func tearDown() {
        for path in fixturesToCleanUp {
            try? FileManager.default.removeItem(atPath: path)
        }
        fixturesToCleanUp.removeAll()
        super.tearDown()
    }

    /// Writes `json` to a temp file and a companion shell script that
    /// `cat`s it — this stands in for `ffprobe -show_streams -show_format
    /// -print_format json ...`. Returns the executable script's path.
    private func makeFFprobeFixture(json: String) throws -> String {
        let jsonPath = NSTemporaryDirectory() + "ffprobe-fixture-\(UUID().uuidString).json"
        try json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
        fixturesToCleanUp.append(jsonPath)

        let scriptPath = NSTemporaryDirectory() + "ffprobe-fixture-\(UUID().uuidString).sh"
        let script = "#!/bin/sh\ncat \"\(jsonPath)\"\n"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        fixturesToCleanUp.append(scriptPath)

        return scriptPath
    }

    // MARK: - Tests

    /// A TrueHD 7.1.4 (Atmos bed) stream and a plain AAC stereo stream in
    /// the same file: the probe must classify the former as lossless +
    /// spatial and the latter as neither, entirely through the default
    /// (no `SUITE_CORE`) fallback table.
    func test_analyze_classifiesLosslessSpatialAndLossyStereoAudioStreams() async throws {
        let json = """
        {
            "streams": [
                {
                    "index": 1,
                    "codec_name": "truehd",
                    "codec_long_name": "TrueHD",
                    "codec_type": "audio",
                    "sample_rate": "48000",
                    "channels": 12,
                    "channel_layout": "7.1.4",
                    "sample_fmt": "s32p",
                    "bits_per_raw_sample": "24"
                },
                {
                    "index": 2,
                    "codec_name": "aac",
                    "codec_long_name": "AAC (Advanced Audio Coding)",
                    "codec_type": "audio",
                    "sample_rate": "48000",
                    "channels": 2,
                    "channel_layout": "stereo",
                    "sample_fmt": "fltp"
                }
            ],
            "format": {
                "format_name": "matroska,webm",
                "duration": "120.500000"
            }
        }
        """
        let scriptPath = try makeFFprobeFixture(json: json)
        let probe = FFmpegProbe(ffprobePath: scriptPath)

        let mediaFile = try await probe.analyze(url: URL(fileURLWithPath: scriptPath))
        let audioStreams = mediaFile.audioStreams
        XCTAssertEqual(audioStreams.count, 2)

        let truehd = try XCTUnwrap(audioStreams.first { $0.codecName == "truehd" })
        XCTAssertEqual(truehd.suiteCoreCodecDescriptor?.isLossless, true)
        XCTAssertEqual(truehd.suiteCoreCodecDescriptor?.isSpatial, true)
        XCTAssertEqual(truehd.isLosslessAudio, true)
        XCTAssertEqual(truehd.isSpatialAudio, true)

        let aac = try XCTUnwrap(audioStreams.first { $0.codecName == "aac" })
        XCTAssertEqual(aac.suiteCoreCodecDescriptor?.isLossless, false)
        XCTAssertEqual(aac.suiteCoreCodecDescriptor?.isSpatial, false)
        XCTAssertEqual(aac.isLosslessAudio, false)
        XCTAssertEqual(aac.isSpatialAudio, false)

        // Existing #374-owned `AudioCodec` mapping and channel layout
        // parsing must be unaffected by the new field's addition.
        XCTAssertEqual(truehd.audioCodec, .trueHD)
        XCTAssertEqual(truehd.channelLayout?.layoutName, "7.1.4")
        XCTAssertEqual(aac.audioCodec, .aacLC)
        XCTAssertEqual(aac.channelLayout?.channelCount, 2)
    }

    /// A video stream must never receive a `suiteCoreCodecDescriptor` —
    /// classification is audio-only.
    func test_analyze_videoStreamsNeverGetSuiteCoreCodecDescriptor() async throws {
        let json = """
        {
            "streams": [
                {
                    "index": 0,
                    "codec_name": "hevc",
                    "codec_type": "video",
                    "width": 1920,
                    "height": 1080
                }
            ],
            "format": {
                "format_name": "mov,mp4,m4a,3gp,3g2,mj2"
            }
        }
        """
        let scriptPath = try makeFFprobeFixture(json: json)
        let probe = FFmpegProbe(ffprobePath: scriptPath)

        let mediaFile = try await probe.analyze(url: URL(fileURLWithPath: scriptPath))
        let video = try XCTUnwrap(mediaFile.videoStreams.first)
        XCTAssertNil(video.suiteCoreCodecDescriptor)
        XCTAssertNil(video.isLosslessAudio)
        XCTAssertNil(video.isSpatialAudio)
    }
}
