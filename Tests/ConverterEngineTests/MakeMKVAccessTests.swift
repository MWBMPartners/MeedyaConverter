// ============================================================================
// MeedyaConverter — MakeMKVAccessTests (Issue #503, slice 2)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins the MakeMKV access gate's contract: OFF BY DEFAULT, an opt-in toggle plus
// a non-blank terms acknowledgement are BOTH required for consent, and the
// readiness verdict is honest (never-enabled / not-installed / ready). Uses an
// isolated UserDefaults suite and an injected `locate` closure — no real
// UserDefaults, no file system, no subprocess. Public API only.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class MakeMKVAccessTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "MakeMKVAccessTests.suite"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Consent: off by default

    func test_consent_offByDefault() {
        // Nothing set at all — the master switch must default to off.
        XCTAssertNil(MakeMKVConsentStore.consent(in: defaults))
    }

    func test_consent_enabledButNoAcknowledgementIsRefused() {
        defaults.set(true, forKey: MakeMKVConsentStore.Keys.enabled)
        XCTAssertNil(MakeMKVConsentStore.consent(in: defaults), "toggle without acknowledgement must not consent")
    }

    func test_consent_enabledButWhitespaceAcknowledgementIsRefused() {
        defaults.set(true, forKey: MakeMKVConsentStore.Keys.enabled)
        defaults.set("   \n\t ", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        XCTAssertNil(MakeMKVConsentStore.consent(in: defaults), "whitespace-only acknowledgement must not consent")
    }

    func test_consent_acknowledgementWithoutEnableIsRefused() {
        defaults.set("I accept the terms", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        // enabled not set (off) → still refused even though a real acknowledgement exists.
        XCTAssertNil(MakeMKVConsentStore.consent(in: defaults))
    }

    func test_consent_grantedWhenEnabledAndAcknowledged() {
        defaults.set(true, forKey: MakeMKVConsentStore.Keys.enabled)
        defaults.set("I accept the terms", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        let consent = MakeMKVConsentStore.consent(in: defaults)
        XCTAssertEqual(consent?.acknowledgement, "I accept the terms")
    }

    func test_consent_explicitlyDisabledIsRefused() {
        defaults.set(false, forKey: MakeMKVConsentStore.Keys.enabled)
        defaults.set("I accept the terms", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        XCTAssertNil(MakeMKVConsentStore.consent(in: defaults))
    }

    // MARK: - Binary override path

    func test_binaryOverridePath_absentAndBlankAreNil() {
        XCTAssertNil(MakeMKVConsentStore.binaryOverridePath(in: defaults))
        defaults.set("   ", forKey: MakeMKVConsentStore.Keys.binaryPath)
        XCTAssertNil(MakeMKVConsentStore.binaryOverridePath(in: defaults))
    }

    func test_binaryOverridePath_trimmedValue() {
        defaults.set("  /opt/makemkv/bin/makemkvcon  ", forKey: MakeMKVConsentStore.Keys.binaryPath)
        XCTAssertEqual(MakeMKVConsentStore.binaryOverridePath(in: defaults), "/opt/makemkv/bin/makemkvcon")
    }

    // MARK: - MakeMKVConsent factory

    func test_consentFactory_carriesAcknowledgement() {
        XCTAssertEqual(MakeMKVConsent.userAcknowledged("ok").acknowledgement, "ok")
    }

    // MARK: - Gate readiness

    private struct NotFound: Error {}

    func test_readiness_notEnabledWhenNoConsent_andNeverLocates() {
        var located = false
        let readiness = MakeMKVGate.readiness(consent: nil) {
            located = true
            return "/never"
        }
        guard case .notEnabled = readiness else {
            return XCTFail("no consent must yield .notEnabled, got \(readiness)")
        }
        XCTAssertFalse(located, "a disabled feature must never touch the file system")
        XCTAssertFalse(readiness.isReady)
        XCTAssertNil(readiness.binaryPath)
    }

    func test_readiness_readyWhenConsentAndLocated() {
        let readiness = MakeMKVGate.readiness(consent: .userAcknowledged("ok")) {
            "/opt/makemkv/bin/makemkvcon"
        }
        XCTAssertEqual(readiness, .ready(binaryPath: "/opt/makemkv/bin/makemkvcon"))
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.binaryPath, "/opt/makemkv/bin/makemkvcon")
    }

    func test_readiness_notInstalledWhenConsentButLocateThrows() {
        let readiness = MakeMKVGate.readiness(consent: .userAcknowledged("ok")) {
            throw NotFound()
        }
        guard case .notInstalled = readiness else {
            return XCTFail("a missing binary with consent must yield .notInstalled, got \(readiness)")
        }
        XCTAssertFalse(readiness.isReady)
    }
}
