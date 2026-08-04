// ============================================================================
// MeedyaConverter — EncodingStatsAggregationTests (Issue #284, re #363)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `EncodingStats.init(aggregating:)` is now the only path that produces
// Dashboard aggregates — derived from the per-job history persisted by
// `EncodingStatisticsStore`, replacing the deleted `StatisticsTracker`
// (which had zero callers of its `recordEncode` write path and so always
// reported zeros). These tests exercise the aggregation logic in isolation
// from any file I/O.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class EncodingStatsAggregationTests: XCTestCase {

    // MARK: - Helpers

    /// Builds an `EncodingStatistics` record with the given aggregation
    /// inputs set directly, bypassing `EncodingStatisticsCollector` (whose
    /// wiring is exercised elsewhere) since only the resulting struct's
    /// fields matter to `EncodingStats.init(aggregating:)`.
    private func makeJob(
        succeeded: Bool?,
        inputFileSize: Int64? = nil,
        outputFileSize: Int64? = nil,
        durationSeconds: TimeInterval = 0,
        videoCodec: String? = nil,
        profileName: String? = nil,
        containerFormat: String? = nil
    ) -> EncodingStatistics {
        var job = EncodingStatistics(jobID: UUID(), jobName: "job.mov", startTime: Date(timeIntervalSince1970: 0))
        job.endTime = Date(timeIntervalSince1970: durationSeconds)
        job.succeeded = succeeded
        job.inputFileSize = inputFileSize
        job.outputFileSize = outputFileSize
        job.videoCodec = videoCodec
        job.profileName = profileName
        job.containerFormat = containerFormat
        return job
    }

    // MARK: - Empty History

    func test_aggregating_emptyHistory_producesZeroedStatsWithZeroSuccessRate() {
        let stats = EncodingStats(aggregating: [])

        XCTAssertEqual(stats.totalEncodes, 0)
        XCTAssertEqual(stats.successfulEncodes, 0)
        XCTAssertEqual(stats.failedEncodes, 0)
        XCTAssertEqual(stats.totalEncodingTime, 0)
        XCTAssertEqual(stats.totalInputBytes, 0)
        XCTAssertEqual(stats.totalOutputBytes, 0)
        XCTAssertTrue(stats.codecUsage.isEmpty)
        XCTAssertTrue(stats.profileUsage.isEmpty)
        XCTAssertTrue(stats.containerUsage.isEmpty)
        XCTAssertEqual(stats.successRate, 0)
    }

    // MARK: - Success / Failure Counting

    func test_aggregating_twoSucceededOneFailed_producesCorrectCountsAndSuccessRate() {
        let history = [
            makeJob(succeeded: true),
            makeJob(succeeded: true),
            makeJob(succeeded: false),
        ]

        let stats = EncodingStats(aggregating: history)

        XCTAssertEqual(stats.totalEncodes, 3)
        XCTAssertEqual(stats.successfulEncodes, 2)
        XCTAssertEqual(stats.failedEncodes, 1)
        XCTAssertEqual(stats.successRate, 2.0 / 3.0, accuracy: 0.0001)
    }

    func test_aggregating_legacyRecordWithNilSucceeded_isCountedAsSuccess() {
        // `EncodingStatistics.succeeded == nil` means "written before the
        // field existed" — those records were only ever produced by the
        // success-only `markComplete()` path, so `nil` must count as a
        // success, not be silently dropped or counted as a failure.
        let history = [makeJob(succeeded: nil)]

        let stats = EncodingStats(aggregating: history)

        XCTAssertEqual(stats.totalEncodes, 1)
        XCTAssertEqual(stats.successfulEncodes, 1)
        XCTAssertEqual(stats.failedEncodes, 0)
        XCTAssertEqual(stats.successRate, 1.0, accuracy: 0.0001)
    }

    // MARK: - Byte Totals

    func test_aggregating_bytesAreSummedOnlyFromSucceededJobs() {
        let succeeded = makeJob(succeeded: true, inputFileSize: 1_000, outputFileSize: 400)
        let failed = makeJob(succeeded: false, inputFileSize: 5_000, outputFileSize: 5_000)

        let stats = EncodingStats(aggregating: [succeeded, failed])

        // A failed job's (possibly partial/garbage) file sizes must never
        // be folded into the totals — only the succeeded job's bytes count.
        XCTAssertEqual(stats.totalInputBytes, 1_000)
        XCTAssertEqual(stats.totalOutputBytes, 400)
    }

    func test_aggregating_legacyNilSucceededJob_bytesAreIncludedAsASuccess() {
        let job = makeJob(succeeded: nil, inputFileSize: 2_000, outputFileSize: 800)

        let stats = EncodingStats(aggregating: [job])

        XCTAssertEqual(stats.totalInputBytes, 2_000)
        XCTAssertEqual(stats.totalOutputBytes, 800)
    }

    // MARK: - Encoding Time

    func test_aggregating_sumsTotalEncodingDurationAcrossAllJobsRegardlessOfOutcome() {
        let succeeded = makeJob(succeeded: true, durationSeconds: 100)
        let failed = makeJob(succeeded: false, durationSeconds: 50)

        let stats = EncodingStats(aggregating: [succeeded, failed])

        XCTAssertEqual(stats.totalEncodingTime, 150, accuracy: 0.001)
    }

    // MARK: - Usage Distributions

    func test_aggregating_tallyCodecProfileAndContainerUsageAcrossJobs() {
        let history = [
            makeJob(succeeded: true, videoCodec: "h265", profileName: "Web Standard", containerFormat: "mkv"),
            makeJob(succeeded: true, videoCodec: "h265", profileName: "Archive", containerFormat: "mkv"),
            makeJob(succeeded: false, videoCodec: "av1", profileName: "Web Standard", containerFormat: "mp4"),
        ]

        let stats = EncodingStats(aggregating: history)

        XCTAssertEqual(stats.codecUsage["h265"], 2)
        XCTAssertEqual(stats.codecUsage["av1"], 1)
        XCTAssertEqual(stats.profileUsage["Web Standard"], 2)
        XCTAssertEqual(stats.profileUsage["Archive"], 1)
        XCTAssertEqual(stats.containerUsage["mkv"], 2)
        XCTAssertEqual(stats.containerUsage["mp4"], 1)
    }

    func test_aggregating_jobsWithNilCodecProfileContainer_areNotTallied() {
        let history = [makeJob(succeeded: true)]

        let stats = EncodingStats(aggregating: history)

        XCTAssertTrue(stats.codecUsage.isEmpty)
        XCTAssertTrue(stats.profileUsage.isEmpty)
        XCTAssertTrue(stats.containerUsage.isEmpty)
    }
}
