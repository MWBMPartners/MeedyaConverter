// ============================================================================
// MeedyaConverter — EDLHandler CMX3600 formatting tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// Guards the CMX3600 EDL export after replacing an unsafe
// `String(format: "%s", (x as NSString).utf8String)` (dangling pointer to a
// temporary NSString — undefined behaviour producing garbage columns) with
// pure-Swift column padding.
// ============================================================================

import XCTest
@testable import ConverterEngine

final class EDLHandlerCMX3600Tests: XCTestCase {

    private func event() -> EDLEvent {
        EDLEvent(eventNumber: 1, reelName: "REEL01", trackType: "V", editType: "C",
                 sourceIn: "01:00:00:00", sourceOut: "01:00:05:00",
                 recordIn: "00:00:00:00", recordOut: "00:00:05:00")
    }

    func test_cmx3600_lineHasPaddedColumnsAndRealFields() {
        let edl = EDLHandler.generateCMX3600(events: [event()], title: "Test")
        let lines = edl.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.first, "TITLE: Test")
        // The event line: NNN(3)  reel(min8) track(min5) edit(min4) 4×timecode.
        let eventLine = lines.first { $0.hasPrefix("001") }
        XCTAssertNotNil(eventLine, edl)
        let line = eventLine!
        // Real, non-garbage fields (the UB previously produced junk here).
        XCTAssertTrue(line.contains("REEL01"), line)
        XCTAssertTrue(line.contains("01:00:00:00"), line)
        XCTAssertTrue(line.contains("00:00:05:00"), line)
        // Reel column padded to a minimum of 8 (REEL01 = 6 chars → 2 trailing spaces).
        XCTAssertTrue(line.contains("001  REEL01  "), "reel min-width padding: \(line)")
        // No stray NUL / control bytes from a bad %s.
        XCTAssertFalse(line.unicodeScalars.contains { $0.value < 32 && $0 != "\t" }, line)
    }

    func test_cmx3600_shortReelStillPadsToEight() {
        var e = event(); e.reelName = "R1"
        let edl = EDLHandler.generateCMX3600(events: [e], title: "T")
        // "R1" (2) padded to 8 → 6 trailing spaces before the track column.
        XCTAssertTrue(edl.contains("001  R1      "), edl)
    }
}
