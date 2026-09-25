// ============================================================================
// MeedyaConverter — SettingsRegistryAppConstantsTests (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `SettingsKeyRegistry` lives in the engine, which cannot see types that
// belong to the app. So for three app-owned choices it writes the allowed
// values out as plain text, and for two app-owned key constants the tripwire
// scan (`SettingsKeyScanMap`, in ConverterEngineTests) records the key by
// hand. This file closes those gaps from the app side, where the real types
// are visible, so the compiler and these tests catch any drift:
//   - the allowed values for `appearanceMode`, `updateChannel` and
//     `webhookPreset` must equal the raw values of `AppearanceMode`,
//     `UpdateChannel` and `WebhookPreset`, in order;
//   - `PostEncodeActionsView.userDefaultsKey` must be "postEncodeActionChain"
//     (and that key must be `.never`, as hooks can run commands);
//   - `HardwareAccelerationPreference.defaultsKey` must be
//     "useHardwareAcceleration" (and that key must be an exportable
//     true/false Encoding setting).
//
// This is the plan's test 12 (`.claude/plans/settings-export-import-plan.md`
// §7). Local runs cannot RUN app tests (see `.claude/local-test-harness.md`);
// this file was type-checked against the app module by hand, and CI runs it.
// ---------------------------------------------------------------------------

import XCTest
@testable import MeedyaConverterCore
import ConverterEngine

/// `@MainActor` because `PostEncodeActionsView` is a SwiftUI view, so its
/// static `userDefaultsKey` belongs to the main thread; reading it from an
/// ordinary test method is a Swift 6 concurrency warning (seen on the first
/// type-check). Same approach as `SettingsUndoManagerTests` and the other
/// `@MainActor` test classes here. This class has no setUp/tearDown
/// overrides, so the caveat in `AutoTagAppWiringTests` does not apply.
@MainActor
final class SettingsRegistryAppConstantsTests: XCTestCase {

    /// The fixed list of values the registry accepts for `key`, or a failure.
    private func allowedValues(
        for key: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String]? {
        guard let entry = SettingsKeyRegistry.entry(for: key) else {
            XCTFail("\(key) must be in SettingsKeyRegistry.", file: file, line: line)
            return nil
        }
        guard case .string(let allowed?, _)? = entry.rules?.kind else {
            XCTFail("\(key) must be an exportable text setting with a fixed list of values.", file: file, line: line)
            return nil
        }
        return allowed
    }

    func test_appearanceModeValuesMatchTheAppEnum() {
        XCTAssertEqual(allowedValues(for: "appearanceMode"), AppearanceMode.allCases.map(\.rawValue))
    }

    func test_updateChannelValuesMatchTheAppEnum() {
        XCTAssertEqual(allowedValues(for: "updateChannel"), UpdateChannel.allCases.map(\.rawValue))
    }

    func test_webhookPresetValuesMatchTheAppEnum() {
        XCTAssertEqual(allowedValues(for: "webhookPreset"), WebhookPreset.allCases.map(\.rawValue))
    }

    func test_hooksKeyIsTheOneTheRegistryNeverExports() {
        XCTAssertEqual(PostEncodeActionsView.userDefaultsKey, "postEncodeActionChain")
        let entry = SettingsKeyRegistry.entry(for: PostEncodeActionsView.userDefaultsKey)
        XCTAssertEqual(entry?.neverKind, .runsCommands)
    }

    func test_hardwareAccelerationKeyIsTheOneTheRegistryExports() {
        XCTAssertEqual(HardwareAccelerationPreference.defaultsKey, "useHardwareAcceleration")
        let entry = SettingsKeyRegistry.entry(for: HardwareAccelerationPreference.defaultsKey)
        XCTAssertEqual(entry?.category, .encoding)
        XCTAssertEqual(entry?.rules?.kind, .bool)
    }
}
