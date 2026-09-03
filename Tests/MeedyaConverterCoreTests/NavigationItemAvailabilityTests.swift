// ============================================================================
// MeedyaConverter — NavigationItem availability tests (#473)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// Vector Conversion and ProRes-to-Vector now run for real via
// `RasterVectorExecutor`/`ProResVectorExecutor` (#473), which spawn bundled
// potrace/vtracer subprocesses — something the App Store sandbox cannot do,
// and potrace (GPL) may not ship in an App Store bundle (DR-0001). So they
// are hidden only in App Store builds (`#if APP_STORE`, the only build-type
// flag any pipeline actually sets — `release.yml` deliberately never sets
// `DIRECT`); visible everywhere else, with the Convert button disabled and a
// reason shown when a required tool can't be resolved. These tests pin the
// gate so a future edit can't silently re-expose a dead-end tool, or
// silently hide a working one.
// ============================================================================

import XCTest
@testable import MeedyaConverterCore

final class NavigationItemAvailabilityTests: XCTestCase {

    func test_vectorToolsAvailabilityFollowsBuildType() {
        #if APP_STORE
        XCTAssertFalse(NavigationItem.vectorConversion.isAvailable)
        XCTAssertFalse(NavigationItem.proresVector.isAvailable)
        #else
        XCTAssertTrue(NavigationItem.vectorConversion.isAvailable)
        XCTAssertTrue(NavigationItem.proresVector.isAvailable)
        #endif
        XCTAssertFalse(NavigationItem.cloudSync.isAvailable)
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
