// ============================================================================
// MeedyaConverter — MeedyaDBAccessTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers the MeedyaDB settings store and gate. Three things matter most:
//
//   1. Contributing is OFF on a fresh install — nothing leaves the machine
//      until someone deliberately turns it on.
//   2. Switched on but unusable NAMES what is missing, rather than sitting
//      there silently doing nothing.
//   3. The API key never reaches UserDefaults, which is a plain-text plist.
//
// Every test gets its OWN UserDefaults suite, named with a fresh UUID, and
// tears it down afterwards. CI runs `swift test --parallel`, so a shared
// suite name would let a sibling test's setUp/tearDown wipe this one's state
// mid-run — a race that reads perfectly fine when a reviewer traces a single
// test in isolation.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MeedyaDBAccessTests: XCTestCase {

    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "MeedyaDBAccessTests-\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("could not make a private UserDefaults suite")
        }
        defaults = suite
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults.standard
        suiteName = ""
        super.tearDown()
    }

    private func turnOn(baseURL: String? = "https://db.example") {
        defaults.set(true, forKey: MeedyaDBConfigStore.Keys.enabled)
        if let url = baseURL {
            defaults.set(url, forKey: MeedyaDBConfigStore.Keys.baseURL)
        }
    }

    // MARK: - Off by default

    func test_freshInstall_contributesNothing() {
        XCTAssertFalse(MeedyaDBConfigStore.isEnabled(in: defaults))
        XCTAssertNil(MeedyaDBConfigStore.baseURL(in: defaults))

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: nil)

        XCTAssertFalse(readiness.isReady)
        XCTAssertNil(readiness.config)
        XCTAssertEqual(readiness, .off(reason: MeedyaDBGate.offReason))
    }

    func test_offEvenWithAServerAndKeyAlreadyFilledIn() {
        // Someone who fills the fields in and then switches the feature off
        // must stop contributing, not keep going on stored details.
        defaults.set("https://db.example", forKey: MeedyaDBConfigStore.Keys.baseURL)

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: "mdk_live_key")

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness, .off(reason: MeedyaDBGate.offReason))
    }

    // MARK: - On but unusable names what is missing

    func test_onWithNothingFilledIn_namesBothMissingPieces() {
        defaults.set(true, forKey: MeedyaDBConfigStore.Keys.enabled)

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: nil)

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness, .incomplete(reason: MeedyaDBGate.missingBothReason))
    }

    func test_onWithAServerButNoKey_saysTheKeyIsMissing() {
        turnOn()

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: nil)

        XCTAssertEqual(readiness, .incomplete(reason: MeedyaDBGate.missingKeyReason))
    }

    func test_onWithAKeyButNoServer_saysTheServerIsMissing() {
        defaults.set(true, forKey: MeedyaDBConfigStore.Keys.enabled)

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: "mdk_live_key")

        XCTAssertEqual(readiness, .incomplete(reason: MeedyaDBGate.missingURLReason))
    }

    func test_whitespaceOnlyValuesCountAsMissing() {
        defaults.set(true, forKey: MeedyaDBConfigStore.Keys.enabled)
        defaults.set("   \n ", forKey: MeedyaDBConfigStore.Keys.baseURL)

        XCTAssertNil(MeedyaDBConfigStore.baseURL(in: defaults))
        XCTAssertEqual(
            MeedyaDBGate.readiness(in: defaults, apiKey: "  \n"),
            .incomplete(reason: MeedyaDBGate.missingBothReason),
            "a key or address that is only whitespace is not a key or address"
        )
    }

    // MARK: - Fully configured

    func test_onWithBothPieces_isReadyAndUsable() throws {
        turnOn()

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: " mdk_live_key ")

        XCTAssertTrue(readiness.isReady)
        XCTAssertNil(readiness.reason)
        let config = try XCTUnwrap(readiness.config)
        XCTAssertEqual(config.baseURL, "https://db.example")
        XCTAssertEqual(config.apiKey, "mdk_live_key", "surrounding whitespace must be trimmed, not sent")
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.isUsable,
                      "the engine's own usability check must agree with the gate")
    }

    // MARK: - Submission mode fails safe

    func test_submissionMode_defaultsToAnonymous() {
        XCTAssertEqual(MeedyaDBConfigStore.submissionMode(in: defaults), .anonymous)
    }

    func test_submissionMode_fullOnlyWhenExactlyFull() {
        defaults.set("full", forKey: MeedyaDBConfigStore.Keys.submissionMode)
        XCTAssertEqual(MeedyaDBConfigStore.submissionMode(in: defaults), .full)

        // Anything else — a typo, a different case, a stale value from a
        // future version — must fall back to sending LESS, never more.
        for wrong in ["Full", "FULL", "ful", "everything", "", "anonymous"] {
            defaults.set(wrong, forKey: MeedyaDBConfigStore.Keys.submissionMode)
            XCTAssertEqual(
                MeedyaDBConfigStore.submissionMode(in: defaults),
                .anonymous,
                "\"\(wrong)\" must not be read as full — an unrecognised value must send less, not more"
            )
        }
    }

    // MARK: - The API key must never touch UserDefaults

    func test_theAPIKeyNeverReachesUserDefaults() {
        turnOn()
        let secret = "mdk_live_thisMustNeverBeWrittenToDisk"

        let readiness = MeedyaDBGate.readiness(in: defaults, apiKey: secret)
        XCTAssertTrue(readiness.isReady, "precondition: the key was actually used")

        // UserDefaults is a plain-text plist in the user's Library. Sweep the
        // WHOLE suite rather than checking a named key, so this still catches
        // a leak under some future key nobody thought to look at.
        let stored = defaults.persistentDomain(forName: suiteName) ?? [:]
        for (key, value) in stored {
            XCTAssertFalse(
                "\(value)".contains(secret),
                "the API key leaked into UserDefaults under \"\(key)\" — it belongs in the Keychain"
            )
        }
    }

    // MARK: - Key spelling is a contract with the Settings UI

    func test_defaultsKeySpellingIsPinned() {
        // The Settings UI writes these with @AppStorage and the engine reads
        // them here. If either side is renamed alone, the app silently stops
        // seeing the user's settings — so the spelling is pinned on purpose.
        XCTAssertEqual(MeedyaDBConfigStore.Keys.enabled, "meedyadb.enabled")
        XCTAssertEqual(MeedyaDBConfigStore.Keys.baseURL, "meedyadb.baseURL")
        XCTAssertEqual(MeedyaDBConfigStore.Keys.submissionMode, "meedyadb.submissionMode")
    }
}
