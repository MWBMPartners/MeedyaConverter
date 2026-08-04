// ============================================================================
// MeedyaConverter — EncodingBenchmarkTests (Issue #325 / real-execution wiring)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Pure (no ffmpeg execution) regression tests for `EncodingBenchmark`.
///
/// `BenchmarkView.runStandardBenchmarks()` was previously a stub that built
/// real FFmpeg arguments via `buildBenchmarkArguments` but then fabricated
/// a simulated fps/duration result instead of executing them. These tests
/// cover the pure argument-building, output-parsing, and result-computation
/// logic that the real execution wiring relies on — none of them spawn a
/// process, so they run in CI without requiring ffmpeg to be installed.
final class EncodingBenchmarkTests: XCTestCase {

    // MARK: - buildBenchmarkArguments

    func test_buildBenchmarkArguments_softwareEncoder_includesPresetAndDiscardsOutput() {
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .h264,
            preset: "medium",
            resolution: "1920x1080",
            duration: 10.0,
            hwAccel: false
        )

        XCTAssertEqual(args, [
            "-f", "lavfi",
            "-i", "testsrc2=duration=10:size=1920x1080:rate=30",
            "-c:v", "libx264",
            "-preset", "medium",
            "-f", "null", "-",
        ])
    }

    func test_buildBenchmarkArguments_h265_usesLibx265Encoder() {
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .h265,
            preset: "slow",
            resolution: "3840x2160",
            duration: 5.0,
            hwAccel: false
        )

        XCTAssertEqual(args, [
            "-f", "lavfi",
            "-i", "testsrc2=duration=5:size=3840x2160:rate=30",
            "-c:v", "libx265",
            "-preset", "slow",
            "-f", "null", "-",
        ])
    }

    func test_buildBenchmarkArguments_av1_usesLibsvtav1Encoder() {
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .av1,
            preset: "8",
            resolution: "1920x1080"
        )

        XCTAssertTrue(args.contains("libsvtav1"))
        XCTAssertTrue(args.contains("8"))
    }

    func test_buildBenchmarkArguments_hardwareAccelerated_omitsPresetFlag() {
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .h264,
            preset: "medium",
            resolution: "1920x1080",
            duration: 10.0,
            hwAccel: true
        )

        // VideoToolbox encoders don't support -preset.
        XCTAssertFalse(args.contains("-preset"))
        XCTAssertTrue(args.contains("h264_videotoolbox"))
    }

    func test_buildBenchmarkArguments_hardwareAccelerated_fallsBackToSoftwareWhenNoVideoToolboxEncoder() {
        // AV1 has no `videoToolboxEncoder` mapping (only h264/h265/prores do),
        // so hwAccel should fall back to the software encoder.
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .av1,
            preset: "8",
            resolution: "1920x1080",
            hwAccel: true
        )

        XCTAssertTrue(args.contains("libsvtav1"))
    }

    func test_buildBenchmarkArguments_invalidResolution_defaultsTo1080p() {
        let args = EncodingBenchmark.buildBenchmarkArguments(
            codec: .h264,
            preset: "medium",
            resolution: "not-a-resolution",
            duration: 10.0
        )

        XCTAssertTrue(args.contains { $0.contains("size=1920x1080") })
    }

    // MARK: - parseBenchmarkOutput

    /// A representative FFmpeg stderr tail from a completed `-f null -`
    /// benchmark encode (the format this method is designed to parse).
    private static let sampleStderrTail = """
        frame=  150 fps= 75 q=28.0 Lsize=       0kB time=00:00:05.00 bitrate=   0.0kbits/s speed=2.51x
        frame=  300 fps= 76 q=28.0 Lsize=       0kB time=00:00:10.00 bitrate=   0.0kbits/s speed=2.53x
        video:0kB audio:0kB subtitle:0kB other streams:0kB global headers:0kB muxing overhead: unknown
        """

    func test_parseBenchmarkOutput_extractsLastFpsAndTime() {
        let result = EncodingBenchmark.parseBenchmarkOutput(Self.sampleStderrTail)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fps, 76)
        XCTAssertEqual(result?.duration ?? -1, 10.0, accuracy: 0.001)
    }

    func test_parseBenchmarkOutput_noFpsLine_returnsNil() {
        let result = EncodingBenchmark.parseBenchmarkOutput("no progress information here")
        XCTAssertNil(result)
    }

    func test_parseBenchmarkOutput_fpsWithoutTime_defaultsDurationToZero() {
        let result = EncodingBenchmark.parseBenchmarkOutput("frame=100 fps=50 q=1.0")

        XCTAssertEqual(result?.fps, 50)
        XCTAssertEqual(result?.duration, 0)
    }

    // MARK: - makeResult

    func test_makeResult_computesFpsFromFramesAndEncodeTime() {
        let result = EncodingBenchmark.makeResult(
            codec: .h264,
            preset: "medium",
            resolution: "1920x1080",
            frames: 300,
            encodeTime: 5.0,
            hardwareAccelerated: false
        )

        XCTAssertEqual(result.fps, 60.0, accuracy: 0.001)
        XCTAssertEqual(result.duration, 5.0, accuracy: 0.001)
        XCTAssertEqual(result.codec, "h264")
        XCTAssertEqual(result.preset, "medium")
        XCTAssertEqual(result.resolution, "1920x1080")
        XCTAssertFalse(result.hardwareAccelerated)
    }

    func test_makeResult_zeroEncodeTime_avoidsDivideByZero() {
        let result = EncodingBenchmark.makeResult(
            codec: .h265,
            preset: "fast",
            resolution: "1920x1080",
            frames: 100,
            encodeTime: 0,
            hardwareAccelerated: false
        )

        XCTAssertEqual(result.fps, 0)
        XCTAssertEqual(result.duration, 0)
    }

    func test_makeResult_negativeEncodeTime_avoidsDivideByZero() {
        let result = EncodingBenchmark.makeResult(
            codec: .h265,
            preset: "fast",
            resolution: "1920x1080",
            frames: 100,
            encodeTime: -1,
            hardwareAccelerated: false
        )

        XCTAssertEqual(result.fps, 0)
    }

    func test_makeResult_roundTripsHardwareAcceleratedFlag() {
        let result = EncodingBenchmark.makeResult(
            codec: .h264,
            preset: "medium",
            resolution: "1920x1080",
            frames: 300,
            encodeTime: 2.0,
            hardwareAccelerated: true
        )

        XCTAssertTrue(result.hardwareAccelerated)
    }

    // MARK: - standardBenchmarks

    func test_standardBenchmarks_isNonEmptyAndCoversAllThreeCodecFamilies() {
        let benchmarks = EncodingBenchmark.standardBenchmarks

        XCTAssertFalse(benchmarks.isEmpty)
        XCTAssertTrue(benchmarks.contains { $0.codec == .h264 })
        XCTAssertTrue(benchmarks.contains { $0.codec == .h265 })
        XCTAssertTrue(benchmarks.contains { $0.codec == .av1 })
    }
}
