// ============================================================================
// MeedyaConverter — LoudnessReporterTests (Issue #433)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Pure (no ffmpeg execution) regression tests for `LoudnessReporter`.
///
/// `capturedStderrSample` below is a real FFmpeg 8.1.2 stderr capture from
/// running `LoudnessReporter.buildAnalysisArguments(inputPath:)` against a
/// 3-second, 1kHz test tone (`ffmpeg -f lavfi -i "sine=frequency=1000:
/// duration=3" -c:a aac`) through `FFmpegProcessController`. It anchors the
/// parsing logic against real-world output rather than a hand-rolled
/// approximation, without requiring ffmpeg to be present in CI.
///
/// Wired up for Issue #433 (LoudnessReportView.runAnalysis() was previously
/// a stub that never ran an analysis).
final class LoudnessReporterTests: XCTestCase {

    // MARK: - Fixtures

    /// Captured real `ffmpeg` stderr output from a `loudnorm=print_format=json`
    /// measurement pass (see file doc comment for provenance).
    private static let capturedStderrSample = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'tone.m4a':
          Metadata:
            major_brand     : M4A
            minor_version   : 512
            compatible_brands: M4A isomiso2
            encoder         : Lavf62.12.102
          Duration: 00:00:03.00, start: 0.000000, bitrate: 73 kb/s
          Stream #0:0[0x1](und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, mono, fltp, 69 kb/s (default)
            Metadata:
              handler_name    : SoundHandler
        Stream mapping:
          Stream #0:0 -> #0:0 (aac (native) -> pcm_s16le (native))
        Output #0, null, to 'pipe:':
          Metadata:
            major_brand     : M4A
            minor_version   : 512
            compatible_brands: M4A isomiso2
            encoder         : Lavf62.12.102
          Stream #0:0(und): Audio: pcm_s16le, 192000 Hz, mono, s16, 3072 kb/s (default)
            Metadata:
              encoder         : Lavc62.28.102 pcm_s16le
              handler_name    : SoundHandler
        [Parsed_loudnorm_0 @ 0xa72c35680]
        {
        \t"input_i" : "-21.13",
        \t"input_tp" : "-16.54",
        \t"input_lra" : "0.00",
        \t"input_thresh" : "-31.13",
        \t"output_i" : "-24.00",
        \t"output_tp" : "-19.43",
        \t"output_lra" : "0.00",
        \t"output_thresh" : "-34.00",
        \t"normalization_type" : "dynamic",
        \t"target_offset" : "0.00"
        }
        [out#0/null @ 0xa72c34f00] video:0KiB audio:1132KiB subtitle:0KiB other streams:0KiB global headers:0KiB muxing overhead: unknown
        size=N/A time=00:00:03.10 bitrate=N/A speed=  86x elapsed=0:00:00.03
        """

    // MARK: - buildAnalysisArguments

    func test_buildAnalysisArguments_includesLoudnormMeasurementPass() {
        let args = LoudnessReporter.buildAnalysisArguments(inputPath: "/tmp/input.mov")

        XCTAssertEqual(args, [
            "-i", "/tmp/input.mov",
            "-af", "loudnorm=print_format=json",
            "-f", "null",
            "-",
        ])
    }

    // MARK: - parseAnalysisOutput

    func test_parseAnalysisOutput_realFFmpegStderr_parsesExpectedValues() throws {
        let report = try XCTUnwrap(
            LoudnessReporter.parseAnalysisOutput(Self.capturedStderrSample)
        )

        XCTAssertEqual(report.integratedLUFS, -21.13, accuracy: 0.001)
        XCTAssertEqual(report.truePeakDBTP, -16.54, accuracy: 0.001)
        XCTAssertEqual(report.loudnessRange, 0.00, accuracy: 0.001)
        XCTAssertEqual(report.shortTermMax, -31.13, accuracy: 0.001) // input_thresh
        XCTAssertEqual(report.momentaryMax, 0.00, accuracy: 0.001) // target_offset

        // Compliance is left for checkCompliance() to determine.
        XCTAssertFalse(report.compliant)
        XCTAssertEqual(report.standard, "")
        XCTAssertEqual(report.fileName, "")
    }

    func test_parseAnalysisOutput_noJSONBlock_returnsNil() {
        let output = "Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'tone.m4a':\nno json here at all\n"
        XCTAssertNil(LoudnessReporter.parseAnalysisOutput(output))
    }

    func test_parseAnalysisOutput_jsonMissingRequiredField_returnsNil() {
        let output = """
            [Parsed_loudnorm_0 @ 0x0]
            {
            \t"input_tp" : "-16.54",
            \t"input_lra" : "0.00"
            }
            """
        // Missing "input_i" — integrated loudness is mandatory.
        XCTAssertNil(LoudnessReporter.parseAnalysisOutput(output))
    }

    func test_parseAnalysisOutput_missingOptionalFields_fallsBackToIntegrated() throws {
        let output = """
            [Parsed_loudnorm_0 @ 0x0]
            {
            \t"input_i" : "-23.00",
            \t"input_tp" : "-2.00",
            \t"input_lra" : "5.50"
            }
            """
        let report = try XCTUnwrap(LoudnessReporter.parseAnalysisOutput(output))

        // input_thresh / target_offset absent — both fall back to integratedLUFS.
        XCTAssertEqual(report.shortTermMax, report.integratedLUFS)
        XCTAssertEqual(report.momentaryMax, report.integratedLUFS)
    }

    func test_parseAnalysisOutput_malformedJSON_returnsNil() {
        let output = """
            [Parsed_loudnorm_0 @ 0x0]
            { this is not valid json }
            """
        XCTAssertNil(LoudnessReporter.parseAnalysisOutput(output))
    }

    // MARK: - checkCompliance

    func test_checkCompliance_ebur128_realFFmpegSample_isNonCompliant() throws {
        // A plain 1kHz sine tone is not loudness-normalised to the -23 LUFS
        // EBU R128 target, so the real captured sample should correctly
        // fail compliance — this is the exact end-to-end verdict produced
        // when LoudnessReportView analyses a real file.
        let report = try XCTUnwrap(
            LoudnessReporter.parseAnalysisOutput(Self.capturedStderrSample)
        )
        XCTAssertFalse(LoudnessReporter.checkCompliance(report: report, standard: .ebur128))
    }

    func test_checkCompliance_ebur128_withinToleranceAndUnderPeakLimit_isCompliant() {
        let report = LoudnessReport(
            integratedLUFS: -23.5,   // within +/-1 LU of -23 target
            truePeakDBTP: -1.5,      // under the -1 dBTP limit
            loudnessRange: 8.0,
            shortTermMax: -20.0,
            momentaryMax: -18.0,
            compliant: false,
            standard: "",
            fileName: "test.wav"
        )
        XCTAssertTrue(LoudnessReporter.checkCompliance(report: report, standard: .ebur128))
    }

    func test_checkCompliance_ebur128_exceedsToleranceOnLUFS_isNonCompliant() {
        let report = LoudnessReport(
            integratedLUFS: -21.13,  // 1.87 LU off target, tolerance is 1.0
            truePeakDBTP: -16.54,
            loudnessRange: 0.0,
            shortTermMax: -31.13,
            momentaryMax: 0.0,
            compliant: false,
            standard: "",
            fileName: "test.wav"
        )
        XCTAssertFalse(LoudnessReporter.checkCompliance(report: report, standard: .ebur128))
    }

    func test_checkCompliance_truePeakExceedsLimit_isNonCompliantEvenIfLUFSMatches() {
        let report = LoudnessReport(
            integratedLUFS: -23.0,   // exactly on target
            truePeakDBTP: -0.2,      // over the -1 dBTP limit
            loudnessRange: 8.0,
            shortTermMax: -20.0,
            momentaryMax: -18.0,
            compliant: false,
            standard: "",
            fileName: "test.wav"
        )
        XCTAssertFalse(LoudnessReporter.checkCompliance(report: report, standard: .ebur128))
    }

    func test_checkCompliance_nonEBUStandard_usesTighterTolerance() {
        // Streaming target is -14 LUFS / -1 dBTP with a +/-0.5 LU tolerance
        // (vs. EBU R128's +/-1 LU).
        let justOutside = LoudnessReport(
            integratedLUFS: -14.6,   // 0.6 LU off target — fails 0.5 tolerance
            truePeakDBTP: -1.5,
            loudnessRange: 6.0,
            shortTermMax: -13.0,
            momentaryMax: -12.0,
            compliant: false,
            standard: "",
            fileName: "test.wav"
        )
        XCTAssertFalse(LoudnessReporter.checkCompliance(report: justOutside, standard: .streaming))

        let withinTolerance = LoudnessReport(
            integratedLUFS: -14.3,   // 0.3 LU off target — passes 0.5 tolerance
            truePeakDBTP: -1.5,
            loudnessRange: 6.0,
            shortTermMax: -13.0,
            momentaryMax: -12.0,
            compliant: false,
            standard: "",
            fileName: "test.wav"
        )
        XCTAssertTrue(LoudnessReporter.checkCompliance(report: withinTolerance, standard: .streaming))
    }
}
