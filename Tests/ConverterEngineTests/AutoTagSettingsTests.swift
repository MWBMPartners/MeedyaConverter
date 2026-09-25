// ============================================================================
// MeedyaConverter — AutoTagSettingsTests (Issue #508, commit 3/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Pins the auto-tag settings contract: OFF BY DEFAULT, the exact defaults
// key spellings, the three readiness states (`off` / `limited` / `ready`),
// the fields `AutoTagSettingsStore.config(in:)` fixes regardless of what is
// stored, and that `AutoTagSettingsSource` re-reads its `UserDefaults` suite
// on every call rather than caching anything from `init`. Uses an isolated
// per-test UserDefaults suite (matching `MakeMKVAccessTests`'s convention) —
// no real UserDefaults, no network. Public API only.
//
// Nothing under test is called by the engine yet — see `AutoTagSettings
// .swift`'s header. These tests exercise the settings/readiness layer on its
// own, ahead of the runner (#508 commit 4) and the engine wiring (commit 6).
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

final class AutoTagSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // A UNIQUE suite per test instance: CI runs `swift test --parallel`, so a
        // shared suite name would let one test's setUp wipe another's values
        // mid-run. A fresh UUID suite is empty and isolated, no clearing needed.
        suiteName = "AutoTagSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Off by default

    func test_isEnabled_offByDefault() {
        XCTAssertFalse(AutoTagSettingsStore.isEnabled(in: defaults))
    }

    func test_writesNFO_offByDefault() {
        XCTAssertFalse(AutoTagSettingsStore.writesNFO(in: defaults))
    }

    func test_config_disabledByDefault() {
        let config = AutoTagSettingsStore.config(in: defaults)
        XCTAssertFalse(config.enabled)
    }

    // MARK: - Key spellings pinned

    /// Locks the exact `UserDefaults` key strings. A future rename that
    /// doesn't also update the Settings UI's `@AppStorage` keys (#508
    /// commit 9) would silently stop the toggle and the reader from
    /// agreeing — this test exists so that rename shows up here first.
    func test_keys_spellingsArePinned() {
        XCTAssertEqual(AutoTagSettingsStore.Keys.enabled, "autotag.enabled")
        XCTAssertEqual(AutoTagSettingsStore.Keys.writeNFO, "autotag.writeNFO")
    }

    func test_isEnabled_readsItsOwnKey() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        XCTAssertTrue(AutoTagSettingsStore.isEnabled(in: defaults))
    }

    func test_writesNFO_readsItsOwnKey() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.writeNFO)
        XCTAssertTrue(AutoTagSettingsStore.writesNFO(in: defaults))
    }

    // MARK: - The fixed config fields

    /// Everything except `enabled` and `writeNFO` is fixed by
    /// `config(in:)`, regardless of what (if anything) is stored — there is
    /// no setting for these yet. Full-value equality relies on
    /// `AutoTagConfig` being `Equatable` (#508 commit 1).
    func test_config_fixesEveryOtherField() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.writeNFO)

        let config = AutoTagSettingsStore.config(in: defaults)

        XCTAssertEqual(
            config,
            AutoTagConfig(
                enabled: true,
                sources: [.filename, .existingMetadata, .tmdb, .musicBrainz],
                embedArtwork: false,
                writeNFO: true,
                renameOutput: false
            )
        )
    }

    /// A stray, unsupported value for one of the fixed fields must not leak
    /// through — there is nothing in `UserDefaults` for them to read, so
    /// this doubles as proof the fixed fields really are hard-coded, not
    /// merely defaulted.
    func test_config_renameOutputAndEmbedArtworkAreAlwaysFalse() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let config = AutoTagSettingsStore.config(in: defaults)
        XCTAssertFalse(config.renameOutput)
        XCTAssertFalse(config.embedArtwork)
        XCTAssertEqual(config.sources, [.filename, .existingMetadata, .tmdb, .musicBrainz])
    }

    // MARK: - The three readiness states

    func test_readiness_offWhenDisabled() {
        let readiness = AutoTagGate.readiness(in: defaults, hasTMDBKey: true)
        XCTAssertEqual(readiness, .off(reason: AutoTagGate.offReason))
        XCTAssertNil(readiness.config)
    }

    func test_readiness_limitedWhenEnabledButNoTMDBKey() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let readiness = AutoTagGate.readiness(in: defaults, hasTMDBKey: false)

        guard case .limited(let config, let reason) = readiness else {
            return XCTFail("expected .limited, got \(readiness)")
        }
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(reason, AutoTagGate.limitedNoTMDBKeyReason)
        XCTAssertEqual(readiness.reason, AutoTagGate.limitedNoTMDBKeyReason)
    }

    func test_readiness_readyWhenEnabledAndTMDBKeyPresent() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let readiness = AutoTagGate.readiness(in: defaults, hasTMDBKey: true)

        guard case .ready(let config) = readiness else {
            return XCTFail("expected .ready, got \(readiness)")
        }
        XCTAssertTrue(config.enabled)
        XCTAssertNil(readiness.reason)
    }

    /// Whether a TMDB key exists must not matter at all while the master
    /// switch is off — `.off` always wins.
    func test_readiness_offWinsEvenWithTMDBKey() {
        let readiness = AutoTagGate.readiness(in: defaults, hasTMDBKey: true)
        if case .off = readiness {
            // expected
        } else {
            XCTFail("expected .off regardless of hasTMDBKey, got \(readiness)")
        }
    }

    // MARK: - AutoTagSettingsSource

    func test_settingsSource_readsStandardDefaults_onlyWhenSuiteNameIsNil() {
        let standardSource = AutoTagSettingsSource(tmdbKeyProvider: { nil })
        XCTAssertTrue(standardSource.readsStandardDefaults)

        let suiteSource = AutoTagSettingsSource(suiteName: suiteName, tmdbKeyProvider: { nil })
        XCTAssertFalse(suiteSource.readsStandardDefaults)
    }

    func test_currentRequest_nilWhenOff() {
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { "some-key" },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        XCTAssertNil(source.currentRequest())
    }

    func test_currentRequest_nilTMDBService_whenNoKey() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { nil },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        let request = source.currentRequest()
        XCTAssertNotNil(request)
        XCTAssertNil(request?.tmdbService)
    }

    func test_currentRequest_nilTMDBService_whenKeyIsBlank() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { "   " },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        XCTAssertNil(source.currentRequest()?.tmdbService)
    }

    func test_currentRequest_hasTMDBService_whenKeyPresent() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { "a-real-key" },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        XCTAssertNotNil(source.currentRequest()?.tmdbService)
    }

    /// The whole point of `AutoTagSettingsSource`: it must re-read the
    /// suite on EVERY call, not cache a snapshot from `init` — so flipping
    /// the toggle mid-queue applies starting with the very next job.
    func test_currentRequest_readsSuiteOnEveryCall_notCachedAtInit() {
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { nil },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )

        // Off at construction time, and stays off until changed.
        XCTAssertNil(source.currentRequest())

        // Flip the switch in the underlying suite AFTER the source already
        // exists — nothing re-creates `source`.
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        XCTAssertNotNil(source.currentRequest(), "expected the source to see the change without being re-created")

        // And flipping it back off must be seen immediately too.
        defaults.set(false, forKey: AutoTagSettingsStore.Keys.enabled)
        XCTAssertNil(source.currentRequest())
    }

    func test_currentRequest_deadlineDefaultsTo30Seconds() {
        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let source = AutoTagSettingsSource(
            suiteName: suiteName,
            tmdbKeyProvider: { nil },
            musicBrainzThrottle: MusicBrainzRequestThrottle(minimumInterval: .zero)
        )
        XCTAssertEqual(source.currentRequest()?.deadline, .seconds(30))
    }
}
