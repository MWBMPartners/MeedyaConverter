// ============================================================================
// MeedyaConverter — EncodingStatisticsStoreTests (Issue #284)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `EncodingStatisticsCollector`/`EncodingStatisticsStore` existed in
// ConverterEngine but were referenced nowhere in the encode pipeline, so
// `EncodingGraphsView` (wired in #448) was always empty. `AppViewModel
// .startQueue()` now creates a collector per job, feeds it from the
// existing `progressInfo` closure, and persists it via
// `EncodingStatisticsStore.addStatistics(_:)` on completion — a view-model
// change that can't itself be exercised from this test target (SPM test
// targets cannot import the `MeedyaConverter` executable target — see the
// note above `MeedyaConvertTests` in Package.swift). What *is* fully
// CI-testable, and covered below, is the real persistence layer that
// wiring depends on:
//   - `EncodingStatisticsStore` round-trips a completed job's statistics
//     through disk (a fresh store instance, backed by the same directory,
//     must read back what an earlier instance wrote).
//   - `EncodingStatisticsCollector.recordProgress`/`setOutputFileSize`/
//     `markComplete` populate the fields `AppViewModel.startQueue()` relies
//     on before handing the snapshot to the store.
//   - `EncodingStatisticsCollector.fps(fromRawProgressLine:)`, the small
//     pure helper added so the view-model wiring can recover FFmpeg's own
//     `fps=` value from `FFmpegProgressInfo.rawLine` without changing
//     `FFmpegProcessController`'s parser.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class EncodingStatisticsStoreTests: XCTestCase {

    // MARK: - Fixtures

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoding-statistics-store-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Store Round Trip

    func test_addStatistics_roundTripsThroughANewStoreInstanceBackedByTheSameDirectory() throws {
        let jobID = UUID()
        var stats = EncodingStatistics(jobID: jobID, jobName: "sample.mov")
        stats.addDataPoint(EncodingDataPoint(
            elapsedSeconds: 1,
            encodedSeconds: 1,
            fps: 30,
            bitrate: 5000,
            frameNumber: 30
        ))
        stats.inputFileSize = 1_000_000
        stats.outputFileSize = 400_000
        stats.endTime = Date()

        let writer = EncodingStatisticsStore(directory: tempDir)
        writer.addStatistics(stats)

        // A brand-new instance, backed by the same directory, must read the
        // persisted history back from disk in its own `init()` — this is
        // exactly what `EncodingGraphsView.onAppear` relies on to see a job
        // completed by a separately-constructed store instance.
        let reader = EncodingStatisticsStore(directory: tempDir)
        let loaded = try XCTUnwrap(reader.statistics(forJob: jobID))

        XCTAssertEqual(loaded.jobID, jobID)
        XCTAssertEqual(loaded.jobName, "sample.mov")
        XCTAssertEqual(loaded.dataPoints.count, 1)
        XCTAssertEqual(loaded.dataPoints.first?.fps, 30)
        XCTAssertEqual(loaded.inputFileSize, 1_000_000)
        XCTAssertEqual(loaded.outputFileSize, 400_000)
        XCTAssertNotNil(loaded.endTime)
    }

    func test_allStatistics_returnsNewestFirst() {
        let store = EncodingStatisticsStore(directory: tempDir)
        let older = EncodingStatistics(jobID: UUID(), jobName: "older", startTime: Date(timeIntervalSince1970: 0))
        let newer = EncodingStatistics(jobID: UUID(), jobName: "newer", startTime: Date(timeIntervalSince1970: 1_000))

        store.addStatistics(older)
        store.addStatistics(newer)

        XCTAssertEqual(store.allStatistics.map(\.jobName), ["newer", "older"])
    }

    func test_clearHistory_removesEverythingIncludingFromANewInstance() {
        let store = EncodingStatisticsStore(directory: tempDir)
        store.addStatistics(EncodingStatistics(jobID: UUID(), jobName: "to-be-cleared"))
        XCTAssertFalse(store.allStatistics.isEmpty)

        store.clearHistory()
        XCTAssertTrue(store.allStatistics.isEmpty)

        let reader = EncodingStatisticsStore(directory: tempDir)
        XCTAssertTrue(reader.allStatistics.isEmpty)
    }

    // MARK: - EncodingStatisticsCollector

    func test_collector_recordProgressAndMarkComplete_populateTheFieldsTheQueueRunnerRelisOn() {
        let jobID = UUID()
        let collector = EncodingStatisticsCollector(jobID: jobID, jobName: "collector.mov")
        collector.setInputMetadata(
            fileSize: 2_000_000,
            duration: 60,
            videoCodec: "h265",
            audioCodec: "aac"
        )

        collector.recordProgress(
            fps: 24,
            bitrate: 6_000,
            encodedSeconds: 10,
            frameNumber: 240,
            outputSizeBytes: 500_000,
            speed: 1.5
        )
        collector.setOutputFileSize(900_000)
        collector.markComplete()

        let stats = collector.currentStatistics
        XCTAssertEqual(stats.jobID, jobID)
        XCTAssertEqual(stats.dataPoints.count, 1)
        XCTAssertEqual(stats.dataPoints.first?.fps, 24)
        XCTAssertEqual(stats.dataPoints.first?.frameNumber, 240)
        XCTAssertEqual(stats.inputFileSize, 2_000_000)
        XCTAssertEqual(stats.inputDuration, 60)
        XCTAssertEqual(stats.videoCodec, "h265")
        XCTAssertEqual(stats.audioCodec, "aac")
        XCTAssertEqual(stats.outputFileSize, 900_000)
        XCTAssertNotNil(stats.endTime)
    }

    func test_collector_recordProgress_throttlesToSampleInterval() {
        let collector = EncodingStatisticsCollector(
            jobID: UUID(),
            jobName: "throttle.mov",
            sampleInterval: 3_600 // effectively never re-samples within this test
        )

        collector.recordProgress(fps: 10, encodedSeconds: 1, frameNumber: 1)
        collector.recordProgress(fps: 20, encodedSeconds: 2, frameNumber: 2)
        collector.recordProgress(fps: 30, encodedSeconds: 3, frameNumber: 3)

        // Only the first call lands — the others are within the sample
        // interval of the first and are dropped, exactly as
        // `AppViewModel.startQueue()` relies on when it calls
        // `recordProgress` on every FFmpeg progress tick.
        XCTAssertEqual(collector.currentStatistics.dataPoints.count, 1)
        XCTAssertEqual(collector.currentStatistics.dataPoints.first?.fps, 10)
    }

    // MARK: - EncodingStatisticsCollector.fps(fromRawProgressLine:)

    func test_fpsFromRawProgressLine_parsesARealFFmpegProgressChunk() {
        let raw = """
        frame=120
        fps=29.97
        bitrate=5000.0kbits/s
        total_size=12345678
        out_time_us=4000000
        speed=2.5x
        progress=continue
        """
        XCTAssertEqual(EncodingStatisticsCollector.fps(fromRawProgressLine: raw), 29.97, accuracy: 0.0001)
    }

    func test_fpsFromRawProgressLine_missingKey_returnsZero() {
        XCTAssertEqual(
            EncodingStatisticsCollector.fps(fromRawProgressLine: "frame=1\nbitrate=100.0kbits/s\n"),
            0
        )
    }

    func test_fpsFromRawProgressLine_nilInput_returnsZero() {
        XCTAssertEqual(EncodingStatisticsCollector.fps(fromRawProgressLine: nil), 0)
    }

    func test_fpsFromRawProgressLine_malformedValue_returnsZeroRatherThanCrashing() {
        XCTAssertEqual(
            EncodingStatisticsCollector.fps(fromRawProgressLine: "fps=not-a-number\n"),
            0
        )
    }

    // MARK: - EncodingStatisticsCollector.markComplete() / markFailed() (Issue #284)

    func test_collector_markComplete_setsSucceededTrue() {
        let collector = EncodingStatisticsCollector(jobID: UUID(), jobName: "ok.mov")
        collector.markComplete()

        let stats = collector.currentStatistics
        XCTAssertNotNil(stats.endTime)
        XCTAssertEqual(stats.succeeded, true)
    }

    func test_collector_markFailed_setsEndTimeAndSucceededFalse() {
        let collector = EncodingStatisticsCollector(jobID: UUID(), jobName: "failed.mov")
        collector.markFailed()

        let stats = collector.currentStatistics
        XCTAssertNotNil(stats.endTime)
        XCTAssertEqual(stats.succeeded, false)
    }

    // MARK: - New Field Round Trip (Issue #284, re #363)

    func test_addStatistics_roundTripsTheThreeNewFieldsThroughANewStoreInstance() throws {
        let jobID = UUID()
        var stats = EncodingStatistics(jobID: jobID, jobName: "tagged.mkv")
        stats.profileName = "Web Standard"
        stats.containerFormat = "mkv"
        stats.succeeded = false
        stats.endTime = Date()

        let writer = EncodingStatisticsStore(directory: tempDir)
        writer.addStatistics(stats)

        let reader = EncodingStatisticsStore(directory: tempDir)
        let loaded = try XCTUnwrap(reader.statistics(forJob: jobID))

        XCTAssertEqual(loaded.profileName, "Web Standard")
        XCTAssertEqual(loaded.containerFormat, "mkv")
        XCTAssertEqual(loaded.succeeded, false)
    }

    // MARK: - Legacy Decode Pin (Issue #284, re #363)

    func test_store_decodesLegacyHistoryFileMissingTheThreeNewFields_asNilRatherThanFailing() throws {
        // Hand-written history file in the exact shape written before
        // `profileName`/`containerFormat`/`succeeded` existed — no trace of
        // those three keys. A `Codable` synthesized from `Optional` stored
        // properties must still decode this via `decodeIfPresent`, leaving
        // the new fields `nil` (interpreted as "legacy, treat as success"
        // by `EncodingStats.init(aggregating:)`) instead of failing to
        // decode the whole history file.
        let jobID = UUID()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startTime = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let endTime = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_120))

        let legacyJSON = """
        [
          {
            "jobID": "\(jobID.uuidString)",
            "jobName": "legacy.mov",
            "startTime": "\(startTime)",
            "endTime": "\(endTime)",
            "dataPoints": [],
            "encodingPasses": 1,
            "inputFileSize": 1000000,
            "outputFileSize": 400000,
            "videoCodec": "h264",
            "audioCodec": "aac"
          }
        ]
        """

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let historyURL = tempDir.appendingPathComponent("encoding_history.json")
        try legacyJSON.data(using: .utf8)!.write(to: historyURL)

        let store = EncodingStatisticsStore(directory: tempDir)
        let loaded = try XCTUnwrap(store.statistics(forJob: jobID))

        XCTAssertEqual(loaded.jobName, "legacy.mov")
        XCTAssertEqual(loaded.inputFileSize, 1_000_000)
        XCTAssertNil(loaded.profileName)
        XCTAssertNil(loaded.containerFormat)
        XCTAssertNil(loaded.succeeded)
    }
}
