// ============================================================================
// MeedyaConverter — VideoStabilizer argument tests (#323)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import XCTest
@testable import ConverterEngine

/// Guards the two-pass vid.stab argument builders that `StabilizationView`
/// (#323) drives — they had no caller until the view was wired, so these pin
/// the filter/flag shape the executed passes depend on.
final class VideoStabilizerArgumentTests: XCTestCase {

    /// Value FFmpeg receives after the first `-vf`.
    private func vf(_ args: [String]) -> String? {
        guard let i = args.firstIndex(of: "-vf"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func hasPair(_ args: [String], _ f: String, _ v: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == f && args[i + 1] == v { return true }
        return false
    }

    // MARK: - Pass 1 (analysis)

    func test_analysis_buildsVidstabdetectToNull() {
        let args = VideoStabilizer.buildAnalysisArguments(
            inputPath: "/in.mov", transformsPath: "/tmp/x.trf", config: VideoStabilizer.medium)
        XCTAssertTrue(hasPair(args, "-i", "/in.mov"), "\(args)")
        let filter = vf(args)
        XCTAssertTrue(filter?.hasPrefix("vidstabdetect=") == true, "\(args)")
        XCTAssertTrue(filter?.contains("shakiness=5") == true)
        XCTAssertTrue(filter?.contains("accuracy=15") == true)
        XCTAssertTrue(filter?.contains("stepsize=6") == true)
        XCTAssertTrue(filter?.contains("result='/tmp/x.trf'") == true, "\(filter ?? "")")
        // Analysis writes no media — it discards to the null muxer.
        XCTAssertTrue(hasPair(args, "-f", "null"), "\(args)")
    }

    // MARK: - Pass 2 (transform)

    func test_stabilize_buildsVidstabtransformWithOutput() {
        let args = VideoStabilizer.buildStabilizeArguments(
            inputPath: "/in.mov", outputPath: "/out.mp4",
            transformsPath: "/tmp/x.trf", config: VideoStabilizer.medium)
        let filter = vf(args)
        XCTAssertTrue(filter?.contains("vidstabtransform=input='/tmp/x.trf'") == true, "\(filter ?? "")")
        XCTAssertTrue(filter?.contains("zoom=0.0") == true, "zoom uses %.1f: \(filter ?? "")")
        XCTAssertTrue(filter?.contains("optzoom=1") == true)
        XCTAssertTrue(filter?.contains("smoothing=10") == true)
        XCTAssertTrue(filter?.contains(",unsharp=") == true, "post-transform sharpen expected")
        XCTAssertTrue(hasPair(args, "-c:a", "copy"), "audio copied: \(args)")
        XCTAssertEqual(args.last, "/out.mp4")
    }

    // MARK: - Presets

    func test_presets_haveExpectedConfigs() {
        XCTAssertEqual([VideoStabilizer.light.shakiness, VideoStabilizer.light.accuracy,
                        VideoStabilizer.light.stepSize, VideoStabilizer.light.optzoom,
                        VideoStabilizer.light.smoothing], [3, 9, 6, 0, 5])
        XCTAssertEqual([VideoStabilizer.medium.shakiness, VideoStabilizer.medium.accuracy,
                        VideoStabilizer.medium.optzoom, VideoStabilizer.medium.smoothing], [5, 15, 1, 10])
        XCTAssertEqual([VideoStabilizer.heavy.shakiness, VideoStabilizer.heavy.stepSize,
                        VideoStabilizer.heavy.optzoom, VideoStabilizer.heavy.smoothing], [10, 4, 2, 30])
        XCTAssertEqual(VideoStabilizer.heavy.zoom, 5)
    }

    /// The init clamps out-of-range values so a bad UI value can't reach ffmpeg.
    func test_config_clampsOutOfRange() {
        let c = StabilizationConfig(shakiness: 20, accuracy: 99, stepSize: -3, zoom: 0, optzoom: 9, smoothing: 0)
        XCTAssertEqual(c.shakiness, 10)
        XCTAssertEqual(c.accuracy, 15)
        XCTAssertEqual(c.stepSize, 1)
        XCTAssertEqual(c.optzoom, 2)
        XCTAssertEqual(c.smoothing, 1)
    }
}
