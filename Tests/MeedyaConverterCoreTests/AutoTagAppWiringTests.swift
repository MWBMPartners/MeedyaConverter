// ============================================================================
// MeedyaConverter — AutoTagAppWiringTests (Issue #508, commit 8/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// #508's earlier commits (3-7) built a whole auto-tagging engine that NOTHING
// in the running app ever reached: `EncodingEngine.autoTagSettings` defaults
// to `nil`, and until this commit `AppViewModel.init()` never passed one in.
// That is exactly the "promise vs delivery" defect this codebase's own notes
// call out repeatedly (`.claude/HANDOFF.md`: "two correct pieces with
// nothing connecting them") — a feature that compiles, is unit-tested in
// isolation, and does nothing for a real user. This file is the delivery
// check for #508 commit 8's own promise: that the APP's real engine — the
// one `AppViewModel()` actually builds and runs jobs through — was given a
// settings source, and the RIGHT one.
//
// Deliberately does not re-test `AutoTagSettingsSource` itself (that is
// `AutoTagSettingsTests`, in `ConverterEngineTests`) or `AutoTagWording`
// (`AutoTagWordingTests`, alongside it) — only the ONE wiring fact neither of
// those can see: that `AppViewModel`'s engine has a source at all, and that
// it reads the same `UserDefaults.standard` the Settings toggle (#508 commit
// 9, `@AppStorage(AutoTagSettingsStore.Keys.enabled)`) will write to.
//
// EXTENDED FOR #508 COMMIT 9. Commit 8 proved the engine had a source that
// read the right STORE. It could not yet prove that store answering `true`
// actually changed anything, because nothing wrote to that key before this
// commit added the Settings switch. The two "link" tests below close that:
// they flip `AutoTagSettingsStore.Keys.enabled` in `UserDefaults.standard`
// itself — the one place `@AppStorage` in `AutoTagSettingsSection.swift`
// writes to — and check `currentRequest()` follows it. That means touching
// `.standard` from a test, which every other file in this test target
// avoids (see `AutoTagSettingsTests`, `MakeMKVAccessTests`, etc., all of
// which use a per-test `UserDefaults(suiteName:)`); it is unavoidable here
// because `AppViewModel.init()` hard-codes `suiteName: nil` (deliberately —
// see `AppViewModel.swift`'s own comment on that call), so there is no way
// to hand it an isolated suite instead. Each of those two tests saves
// whatever `.standard` already held for the key and restores it with a
// `defer`, so a run of this file never leaves the developer's real defaults
// changed either way.
//
// A separate group below tests `AutoTagSettingsSection`'s status-line
// functions directly, each using its own fresh, per-test
// `UserDefaults(suiteName:)` — matching every other file's convention —
// precisely so those tests never touch `.standard` at all.
//
// NO `override func setUp()`/`tearDown()` IN THIS FILE, DELIBERATELY. This
// class is `@MainActor` (required so its test methods can construct
// `AppViewModel()` directly), but `XCTestCase.setUp()`/`tearDown()` are
// themselves `nonisolated` in the XCTest overlay, so an `override` of either
// is *also* forced `nonisolated` regardless of the subclass's own
// `@MainActor` — and a `nonisolated` override cannot touch `@MainActor`-
// isolated stored properties without a strict-concurrency warning on every
// line that does. (Verified: an earlier draft of this file used
// `override func setUp()/tearDown()` with instance `var`s for exactly this
// purpose, and `swiftc -typecheck` flagged eleven such warnings.) Every
// other `@MainActor` file in this test target (`SettingsUndoManagerTests`,
// `SmartCropStagingTests`) already avoids `setUp`/`tearDown` for the same
// reason; this file follows that same, already-established shape rather
// than reintroducing the problem.
// ============================================================================

import XCTest
@testable import MeedyaConverterCore
import ConverterEngine

@MainActor
final class AutoTagAppWiringTests: XCTestCase {

    /// `AppViewModel()` must be cheap and side-effect-free enough to
    /// construct directly in a test — every other `MeedyaConverterCoreTests`
    /// file already relies on this (`SettingsUndoManagerTests`,
    /// `SmartCropStagingTests`), so this is not a new assumption; recorded
    /// here anyway because it is the precondition every assertion below
    /// depends on.
    func test_appViewModelEngine_hasAnAutoTagSettingsSource() {
        let viewModel = AppViewModel()

        // Before this commit, `EncodingEngine(ffmpegPath:ffprobePath:)` was
        // called with NO `autoTagSettings` argument, so this was always
        // `nil` — meaning `AutoTagRunner.run` could never be reached from a
        // real app encode no matter what a user did in Settings. This is
        // the one assertion that proves that gap is closed.
        XCTAssertNotNil(
            viewModel.engine.autoTagSettings,
            "AppViewModel's engine must be given an AutoTagSettingsSource (#508 commit 8) " +
            "— without one, EncodingEngine.encode(job:onProgress:) never calls AutoTagRunner " +
            "at all, whatever the Settings toggle says."
        )
    }

    /// The app's real Settings tab writes `AutoTagSettingsStore.Keys.enabled`
    /// via `@AppStorage`, which implicitly reads/writes `UserDefaults
    /// .standard`. If `AppViewModel.init()` built its `AutoTagSettingsSource`
    /// with any OTHER suite — a leftover test suite name, a typo, a `nil`
    /// vs. a named suite mix-up — the toggle would flip a value this engine
    /// never reads, and auto-tagging would silently stay off forever no
    /// matter what the user does. That is the exact shape of bug `#507`
    /// exists for on the MeedyaDB side; this is #508's version of the same
    /// check. `AutoTagSettingsSource.readsStandardDefaults`'s own doc
    /// comment names this test file directly as its reason for existing.
    func test_appViewModelEngine_autoTagSettingsReadsStandardDefaults() {
        let viewModel = AppViewModel()

        guard let autoTagSettings = viewModel.engine.autoTagSettings else {
            XCTFail("Expected the engine to have an AutoTagSettingsSource at all (see the other test in this file).")
            return
        }

        XCTAssertTrue(
            autoTagSettings.readsStandardDefaults,
            "AppViewModel must construct its AutoTagSettingsSource with suiteName: nil, " +
            "so it reads UserDefaults.standard — the same store @AppStorage " +
            "(AutoTagSettingsStore.Keys.enabled) implicitly reads and writes."
        )
    }

    // MARK: - #508 commit 9: the Settings switch actually reaches the engine
    //
    // The two tests above (commit 8) prove the engine's `AutoTagSettingsSource`
    // reads `UserDefaults.standard`. They cannot prove that store answering
    // `true` changes anything, because until THIS commit nothing ever wrote
    // `AutoTagSettingsStore.Keys.enabled` there. These two close that gap by
    // writing to `.standard` directly — the exact key
    // `AutoTagSettingsSection`'s `@AppStorage` writes to — and reading back
    // through the same `currentRequest()` a real job calls. Each saves
    // whatever was there before and restores it with `defer`, so this file
    // never leaves the developer's real defaults changed.

    /// Turning the switch on must make a real job's request non-nil. If this
    /// failed, the Settings toggle added in this commit would visibly flip
    /// but do nothing — the "promise vs delivery" gap this whole test file's
    /// header calls out, one commit later.
    func test_turningOnTheSettingsSwitch_makesTheEngineRequestNonNil() {
        let key = AutoTagSettingsStore.Keys.enabled
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(true, forKey: key)

        let viewModel = AppViewModel()

        XCTAssertNotNil(
            viewModel.engine.autoTagSettings?.currentRequest(),
            "With AutoTagSettingsStore.Keys.enabled = true in UserDefaults.standard " +
            "(what AutoTagSettingsSection's @AppStorage writes to), the engine's own " +
            "settings source must build a real AutoTagRequest."
        )
    }

    /// Removing the key (never written, or explicitly cleared) must make
    /// `currentRequest()` nil again — the off-by-default guarantee
    /// `AutoTagSettingsStore.swift`'s own header describes, exercised here
    /// through the same door a real job uses.
    func test_removingTheSettingsSwitch_makesTheEngineRequestNil() {
        let key = AutoTagSettingsStore.Keys.enabled
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)

        let viewModel = AppViewModel()

        XCTAssertNil(
            viewModel.engine.autoTagSettings?.currentRequest(),
            "With no value for AutoTagSettingsStore.Keys.enabled, UserDefaults" +
            ".bool(forKey:) reads false, and currentRequest() must return nil."
        )
    }

    // MARK: - #508 commit 9: the status line is AutoTagGate's own wording
    //
    // `AutoTagSettingsSection`'s status line is built by two small `static`
    // functions (`readiness(in:hasTMDBKey:)`, `statusText(for:)`) precisely
    // so they can be called here without a SwiftUI view-inspection library,
    // which this codebase does not have. Every test below opens its own
    // fresh `UserDefaults(suiteName:)` and tears it down with `defer`,
    // matching `AutoTagSettingsTests`' own convention — never `.standard`.

    /// Off by default (nothing written): the text must be exactly
    /// `AutoTagGate.offReason` — the same constant a real run's skip
    /// decision would report, not a hand-typed copy of that sentence that
    /// could silently drift from it.
    func test_statusText_offByDefault_matchesAutoTagGate() {
        let suiteName = "AutoTagAppWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let readiness = AutoTagSettingsSection.readiness(in: defaults, hasTMDBKey: false)
        XCTAssertEqual(AutoTagSettingsSection.statusText(for: readiness), AutoTagGate.offReason)
    }

    /// On, but no TMDB key saved: `AutoTagGate.limitedNoTMDBKeyReason`.
    func test_statusText_onWithNoTMDBKey_matchesAutoTagGate() {
        let suiteName = "AutoTagAppWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let readiness = AutoTagSettingsSection.readiness(in: defaults, hasTMDBKey: false)
        XCTAssertEqual(AutoTagSettingsSection.statusText(for: readiness), AutoTagGate.limitedNoTMDBKeyReason)
    }

    /// On, with a TMDB key saved: `AutoTagGate.readyReason`.
    func test_statusText_onWithTMDBKey_matchesAutoTagGate() {
        let suiteName = "AutoTagAppWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AutoTagSettingsStore.Keys.enabled)
        let readiness = AutoTagSettingsSection.readiness(in: defaults, hasTMDBKey: true)
        XCTAssertEqual(AutoTagSettingsSection.statusText(for: readiness), AutoTagGate.readyReason)
    }

    /// Belt and braces, over all four (enabled × hasTMDBKey) combinations:
    /// `AutoTagSettingsSection.readiness(in:hasTMDBKey:)` is not a
    /// re-implementation of the gate's logic, it IS `AutoTagGate.readiness`
    /// — proven by comparing against a direct call with the identical
    /// inputs. `AutoTagReadiness` is `Equatable`, so the whole case
    /// (including the wrapped `AutoTagConfig`/reason) is compared, not just
    /// the text.
    func test_sectionReadiness_isLiterallyAutoTagGatesOwnReadiness() {
        let suiteName = "AutoTagAppWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for enabled in [false, true] {
            for hasTMDBKey in [false, true] {
                defaults.set(enabled, forKey: AutoTagSettingsStore.Keys.enabled)

                let viaSection = AutoTagSettingsSection.readiness(in: defaults, hasTMDBKey: hasTMDBKey)
                let viaGate = AutoTagGate.readiness(in: defaults, hasTMDBKey: hasTMDBKey)

                XCTAssertEqual(
                    viaSection, viaGate,
                    "enabled=\(enabled) hasTMDBKey=\(hasTMDBKey): AutoTagSettingsSection.readiness " +
                    "must equal AutoTagGate.readiness for the same inputs."
                )
            }
        }
    }
}
