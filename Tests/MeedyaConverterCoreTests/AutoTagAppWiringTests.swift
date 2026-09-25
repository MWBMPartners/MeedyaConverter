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
}
