// ============================================================================
// MeedyaConverter — EncodingStatisticsCSVExportTests (Issue #363)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Pure, CI-runnable tests for `EncodingStatistics.csvHeader`/`csvRow` and
// `EncodingStatisticsStore.exportAsCSV()` — string formatting only, no file
// I/O beyond the store's own (already-tested, see
// `EncodingStatisticsStoreTests`) JSON persistence.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class EncodingStatisticsCSVExportTests: XCTestCase {

    // MARK: - Helpers

    /// Splits a CSV row into fields on unquoted commas, respecting
    /// RFC 4180 double-quoted fields — including a doubled `""` inside a
    /// quoted field, which represents one literal `"` character rather
    /// than closing-then-reopening the quoted section. Good enough for
    /// asserting on `csvRow`'s own output in these tests without depending
    /// on a third-party CSV parser.
    private func splitCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if insideQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                insideQuotes.toggle()
                i += 1
                continue
            }
            if char == "," && !insideQuotes {
                fields.append(current)
                current = ""
                i += 1
                continue
            }
            current.append(char)
            i += 1
        }
        fields.append(current)
        return fields
    }

    // MARK: - csvHeader

    func test_csvHeader_columnCount_matchesRowFieldCount() {
        let headerColumns = EncodingStatistics.csvHeader.split(separator: ",")

        var stats = EncodingStatistics(jobID: UUID(), jobName: "sample.mov")
        stats.addDataPoint(EncodingDataPoint(elapsedSeconds: 1, encodedSeconds: 1, fps: 30, frameNumber: 1))
        let rowFields = splitCSVRow(stats.csvRow)

        XCTAssertEqual(headerColumns.count, rowFields.count)
    }

    func test_csvHeader_startsWithJobIdAndJobName() {
        XCTAssertTrue(EncodingStatistics.csvHeader.hasPrefix("job_id,job_name,"))
    }

    // MARK: - csvRow — populated fields

    func test_csvRow_populatedJob_containsRealAggregateValues() throws {
        let jobID = UUID()
        var stats = EncodingStatistics(jobID: jobID, jobName: "movie.mkv")
        stats.addDataPoint(EncodingDataPoint(elapsedSeconds: 1, encodedSeconds: 1, fps: 20, bitrate: 4_000, frameNumber: 20))
        stats.addDataPoint(EncodingDataPoint(elapsedSeconds: 2, encodedSeconds: 2, fps: 30, bitrate: 6_000, frameNumber: 50))
        stats.inputFileSize = 2_000_000
        stats.outputFileSize = 500_000
        stats.videoCodec = "h265"
        stats.audioCodec = "aac"
        stats.endTime = stats.startTime.addingTimeInterval(120)

        let fields = splitCSVRow(stats.csvRow)
        let header = EncodingStatistics.csvHeader.split(separator: ",").map(String.init)

        func value(_ column: String) throws -> String {
            let index = try XCTUnwrap(header.firstIndex(of: column))
            return fields[index]
        }

        XCTAssertEqual(try value("job_id"), jobID.uuidString)
        XCTAssertEqual(try value("job_name"), "movie.mkv")
        XCTAssertEqual(try value("average_fps"), "25.00")
        XCTAssertEqual(try value("peak_fps"), "30.00")
        XCTAssertEqual(try value("minimum_fps"), "20.00")
        XCTAssertEqual(try value("average_bitrate_kbps"), "5000.00")
        XCTAssertEqual(try value("peak_bitrate_kbps"), "6000.00")
        XCTAssertEqual(try value("input_file_size_bytes"), "2000000")
        XCTAssertEqual(try value("output_file_size_bytes"), "500000")
        XCTAssertEqual(try value("compression_ratio"), "4.000")
        XCTAssertEqual(try value("space_savings_percent"), "75.00")
        XCTAssertEqual(try value("video_codec"), "h265")
        XCTAssertEqual(try value("audio_codec"), "aac")
        XCTAssertEqual(try value("data_point_count"), "2")
        XCTAssertEqual(try value("duration_seconds"), "120.00")
    }

    // MARK: - csvRow — never fabricates missing data

    func test_csvRow_jobWithNoDataPointsOrFileSizes_leavesOptionalFieldsEmptyRatherThanFabricated() throws {
        let stats = EncodingStatistics(jobID: UUID(), jobName: "empty.mov")

        let fields = splitCSVRow(stats.csvRow)
        let header = EncodingStatistics.csvHeader.split(separator: ",").map(String.init)

        func value(_ column: String) throws -> String {
            let index = try XCTUnwrap(header.firstIndex(of: column))
            return fields[index]
        }

        // Never-recorded optional metrics are empty fields, not "0" or "N/A".
        XCTAssertEqual(try value("input_file_size_bytes"), "")
        XCTAssertEqual(try value("output_file_size_bytes"), "")
        XCTAssertEqual(try value("compression_ratio"), "")
        XCTAssertEqual(try value("space_savings_percent"), "")
        XCTAssertEqual(try value("average_bitrate_kbps"), "")
        XCTAssertEqual(try value("video_codec"), "")
        XCTAssertEqual(try value("end_time"), "")
        // FPS aggregates are legitimately 0 (defined that way by
        // EncodingStatistics.averageFPS/peakFPS/minimumFPS) when there are
        // no data points — that is the real value, not a placeholder.
        XCTAssertEqual(try value("average_fps"), "0.00")
        XCTAssertEqual(try value("data_point_count"), "0")
    }

    // MARK: - csvRow — escaping

    func test_csvRow_jobNameContainingCommaAndQuote_isEscapedAndRoundTrips() {
        let stats = EncodingStatistics(jobID: UUID(), jobName: "My \"Movie\", Part 1.mov")

        let fields = splitCSVRow(stats.csvRow)
        let header = EncodingStatistics.csvHeader.split(separator: ",").map(String.init)
        let jobNameIndex = header.firstIndex(of: "job_name")!

        // The raw row must quote the field (comma/quote present)...
        XCTAssertTrue(stats.csvRow.contains("\"My \"\"Movie\"\", Part 1.mov\""))
        // ...and a naive splitter that understands quoting recovers the
        // original, unescaped value.
        XCTAssertEqual(fields[jobNameIndex], "My \"Movie\", Part 1.mov")
    }

    func test_csvRow_plainJobName_isNotQuoted() {
        let stats = EncodingStatistics(jobID: UUID(), jobName: "plain_name.mov")
        XCTAssertFalse(stats.csvRow.contains("\"plain_name.mov\""))
        XCTAssertTrue(stats.csvRow.contains("plain_name.mov"))
    }

    // MARK: - EncodingStatisticsStore.exportAsCSV()

    func test_store_exportAsCSV_emptyHistory_isJustTheHeader() {
        let store = EncodingStatisticsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("csv-export-tests-\(UUID().uuidString)")
        )

        let csv = store.exportAsCSV()
        let text = String(data: csv, encoding: .utf8)

        XCTAssertEqual(text, EncodingStatistics.csvHeader)
    }

    func test_store_exportAsCSV_withHistory_headerPlusOneRowPerJob() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("csv-export-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = EncodingStatisticsStore(directory: tempDir)
        store.addStatistics(EncodingStatistics(jobID: UUID(), jobName: "first.mov"))
        store.addStatistics(EncodingStatistics(jobID: UUID(), jobName: "second.mov"))

        let csv = try XCTUnwrap(String(data: store.exportAsCSV(), encoding: .utf8))
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines.count, 3) // header + 2 job rows
        XCTAssertEqual(String(lines[0]), EncodingStatistics.csvHeader)
        XCTAssertTrue(lines[1].contains("first.mov"))
        XCTAssertTrue(lines[2].contains("second.mov"))
    }
}
