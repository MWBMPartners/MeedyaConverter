// ============================================================================
// MeedyaConverter — QualityCheckerTests (roadmap #8, Issue #445)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `QualityChecker` (Issue #344 / #445) previously had ZERO test coverage.
// This file covers the two new real detectors added for roadmap #8
// (`corruptFrames`, `levelCompliance`) plus a couple of regression guards on
// `runAllChecks`'s `.notImplemented` reporting for the checks that are
// still genuinely unimplemented (`audioSync`, `formatConformance`).
//
// `QualityChecker` is a pure, process-free utility — every method here is
// an argument builder or an output parser, never a process launch — so all
// tests run entirely against public API (`import ConverterEngine`, no
// `@testable`) with representative FFmpeg stderr/loudness strings, matching
// `LoudnessReporterTests.swift`'s house style. The `corruptFrames` stderr
// samples below are hand-written to match FFmpeg's documented `-v error`
// log-line shape (unlike `LoudnessReporterTests.capturedStderrSample`,
// which is a verbatim real-`ffmpeg` capture) — no `ffmpeg` binary is
// available in this environment to capture a genuine corrupt-frame decode
// session, and no real corrupt media fixture exists in this repo to feed
// it. The `levelCompliance` samples reuse the exact same
// `loudnorm=print_format=json` JSON shape `LoudnessReporterTests` verified
// against real `ffmpeg` output, since `parseLevelComplianceOutput` is a
// thin adapter over `LoudnessReporter.parseAnalysisOutput`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class QualityCheckerTests: XCTestCase {

    // MARK: - buildCorruptFrameDetectionArgs

    func test_buildCorruptFrameDetectionArgs_usesVErrorAndNullSink() {
        let args = QualityChecker.buildCorruptFrameDetectionArgs(inputPath: "/tmp/input.mp4")

        XCTAssertEqual(args, [
            "-v", "error",
            "-i", "/tmp/input.mp4",
            "-f", "null",
            "-",
        ])
    }

    // MARK: - buildLevelComplianceArgs

    func test_buildLevelComplianceArgs_matchesLoudnessReporterAnalysisArguments() {
        // `levelCompliance` must reuse LoudnessReporter's measurement
        // command byte-for-byte, not a second hand-rolled invocation.
        let inputPath = "/tmp/level-compliance-input.mov"
        XCTAssertEqual(
            QualityChecker.buildLevelComplianceArgs(inputPath: inputPath),
            LoudnessReporter.buildAnalysisArguments(inputPath: inputPath)
        )
    }

    // MARK: - parseCorruptFrameOutput

    func test_parseCorruptFrameOutput_emptyOutput_returnsSinglePassingResult() {
        let results = QualityChecker.parseCorruptFrameOutput("")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].check, .corruptFrames)
        XCTAssertEqual(results[0].status, .passed)
    }

    func test_parseCorruptFrameOutput_whitespaceOnlyOutput_returnsPassingResult() {
        let results = QualityChecker.parseCorruptFrameOutput("\n\n   \n\t\n")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .passed)
    }

    func test_parseCorruptFrameOutput_decodeErrorLines_returnsOneFailedResultPerLine() {
        // Representative `-v error` decode-error lines (FFmpeg's real
        // documented shape at error verbosity — see the file overview for
        // why these are hand-written rather than a captured sample).
        let output = """
            [h264 @ 0x600002a0c1a0] error while decoding MB 34 5, bytestream -5
            [h264 @ 0x600002a0c1a0] concealing 187 DC, 187 AC, 187 MV errors in P frame
            [NULL @ 0x600002a0c8b0] Invalid NAL unit size (-1 > 3).
            """

        let results = QualityChecker.parseCorruptFrameOutput(output)

        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertEqual(result.check, .corruptFrames)
            XCTAssertEqual(result.status, .failed)
            XCTAssertEqual(result.severity, "error")
        }
        XCTAssertTrue(results[0].details.contains("error while decoding MB 34 5"))
        XCTAssertTrue(results[1].details.contains("concealing 187 DC"))
        XCTAssertTrue(results[2].details.contains("Invalid NAL unit size"))
    }

    // MARK: - normalizationStandard(forLoudnessStandard:)

    func test_normalizationStandard_mapsKnownLabels() {
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "EBU R128"), .ebur128)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "ATSC A/85"), .atscA85)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "ITU-R BS.1770"), .ituBS1770)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "Podcast"), .podcast)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "Streaming"), .streaming)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "Cinema"), .cinema)
    }

    func test_normalizationStandard_nilOrUnrecognised_fallsBackToEBUR128() {
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: nil), .ebur128)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: "not a real standard"), .ebur128)
        XCTAssertEqual(QualityChecker.normalizationStandard(forLoudnessStandard: ""), .ebur128)
    }

    // MARK: - parseLevelComplianceOutput

    /// Real `loudnorm=print_format=json` JSON shape (see
    /// `LoudnessReporterTests.capturedStderrSample`), with values that sit
    /// well inside EBU R128's tolerance (target -23 LUFS ± 1 LU, true peak
    /// ≤ -1 dBTP).
    private static let compliantStderrSample = """
        [Parsed_loudnorm_0 @ 0xa72c35680]
        {
        \t"input_i" : "-23.20",
        \t"input_tp" : "-1.50",
        \t"input_lra" : "4.10",
        \t"input_thresh" : "-33.30",
        \t"output_i" : "-23.00",
        \t"output_tp" : "-2.00",
        \t"output_lra" : "4.00",
        \t"output_thresh" : "-33.00",
        \t"normalization_type" : "dynamic",
        \t"target_offset" : "0.20"
        }
        """

    /// Same JSON shape, but integrated loudness is far outside EBU R128's
    /// tolerance.
    private static let nonCompliantStderrSample = """
        [Parsed_loudnorm_0 @ 0xa72c35680]
        {
        \t"input_i" : "-16.00",
        \t"input_tp" : "-0.50",
        \t"input_lra" : "6.00",
        \t"input_thresh" : "-26.00",
        \t"output_i" : "-23.00",
        \t"output_tp" : "-2.00",
        \t"output_lra" : "4.00",
        \t"output_thresh" : "-33.00",
        \t"normalization_type" : "dynamic",
        \t"target_offset" : "0.00"
        }
        """

    func test_parseLevelComplianceOutput_compliantSample_returnsPassed() {
        let results = QualityChecker.parseLevelComplianceOutput(
            Self.compliantStderrSample,
            standard: .ebur128
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].check, .levelCompliance)
        XCTAssertEqual(results[0].status, .passed)
        XCTAssertEqual(results[0].severity, "info")
        XCTAssertTrue(results[0].details.contains("-23.2"))
    }

    func test_parseLevelComplianceOutput_nonCompliantSample_returnsFailed() {
        let results = QualityChecker.parseLevelComplianceOutput(
            Self.nonCompliantStderrSample,
            standard: .ebur128
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].check, .levelCompliance)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].severity, "warning")
    }

    func test_parseLevelComplianceOutput_unparsableOutput_returnsFailedNeverPassed() {
        // A real analysis failure (unexpected FFmpeg output shape) must be
        // reported honestly as `.failed`, never `.notImplemented` (the
        // check genuinely ran) and never `.passed` (never fabricate
        // success on a parse failure).
        let results = QualityChecker.parseLevelComplianceOutput(
            "no json block here at all",
            standard: .ebur128
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].check, .levelCompliance)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertNotEqual(results[0].status, .notImplemented)
    }

    // MARK: - runAllChecks regression guards

    /// `corruptFrames` and `levelCompliance` now have real detectors that
    /// require executing FFmpeg — `runAllChecks` must therefore skip them
    /// entirely (leaving them to the caller, e.g. `QualityCheckView`),
    /// exactly like it already does for `blackFrames`/`silenceDetection`,
    /// rather than reporting a `.notImplemented` stub for them.
    func test_runAllChecks_corruptFramesAndLevelCompliance_areOmittedNotStubbed() {
        let profile = QCProfile(
            name: "Test",
            enabledChecks: [.corruptFrames, .levelCompliance, .blackFrames, .silenceDetection],
            loudnessStandard: "EBU R128"
        )

        let results = QualityChecker.runAllChecks(inputPath: "/tmp/does-not-matter.mp4", profile: profile)

        XCTAssertTrue(results.isEmpty, "All four checks require FFmpeg execution, so runAllChecks must " +
                       "resolve none of them synchronously — got \(results)")
    }

    /// `audioSync` and `formatConformance` remain genuinely unimplemented
    /// and must still report `.notImplemented` — never a fabricated pass.
    func test_runAllChecks_audioSyncAndFormatConformance_stillReportNotImplemented() {
        let profile = QCProfile(
            name: "Test",
            enabledChecks: [.audioSync, .formatConformance]
        )

        let results = QualityChecker.runAllChecks(inputPath: "/tmp/does-not-exist-at-all.mp4", profile: profile)

        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertEqual(result.status, .notImplemented)
        }
    }
}
