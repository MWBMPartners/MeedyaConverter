// ============================================================================
// MeedyaConverter — NavigationItem availability tests (#473)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// The Vector Conversion and ProRes-to-Vector tools are settings-only forms
// whose converters (RasterVectorConverter/ProResToVectorConverter) are
// argument-builders with no process runner and no bundled tracing tools, so
// they cannot convert anything. Per #473 they are hidden until that wiring
// exists. These tests pin the gate so a future edit can't silently re-expose
// a dead-end tool.
// ============================================================================

import XCTest
@testable import MeedyaConverterCore

final class NavigationItemAvailabilityTests: XCTestCase {

    func test_vectorToolsAreUnavailable() {
        XCTAssertFalse(NavigationItem.vectorConversion.isAvailable)
        XCTAssertFalse(NavigationItem.proresVector.isAvailable)
    }

    func test_ordinaryToolsRemainAvailable() {
        for item in [NavigationItem.source, .queue, .images, .watermark, .multiOutput] {
            XCTAssertTrue(item.isAvailable, "\(item) should be available")
        }
    }

    /// isAvailable and the unavailable set are the same fact stated two ways.
    func test_availabilityMatchesUnavailableSet() {
        for item in NavigationItem.allCases {
            XCTAssertEqual(item.isAvailable, !NavigationItem.unavailable.contains(item), "\(item)")
        }
    }

    /// Everything listed as unavailable is a real case (guards typos).
    func test_unavailableSetContainsOnlyRealCases() {
        for item in NavigationItem.unavailable {
            XCTAssertTrue(NavigationItem.allCases.contains(item), "\(item)")
        }
    }
}
