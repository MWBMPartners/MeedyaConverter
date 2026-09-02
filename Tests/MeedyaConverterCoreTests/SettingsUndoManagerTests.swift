// ============================================================================
// MeedyaConverter — SettingsUndoManager tests (#330)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// The undo/redo engine existed but had zero callers, so its register→undo→redo
// path had never run. This exercises it end-to-end against a real AppViewModel
// (the manager's key paths are typed to AppViewModel), covering the previously
// unexercised MainActor.assumeIsolated undo/redo closures.
// ============================================================================

import XCTest
import SwiftUI
@testable import MeedyaConverterCore
import ConverterEngine

@MainActor
final class SettingsUndoManagerTests: XCTestCase {

    func test_registerThenUndoRedo_restoresAndReappliesProfile() {
        let vm = AppViewModel()
        let manager = vm.settingsUndoManager

        let original = vm.selectedProfile
        let changed = EncodingProfile(name: "UndoTest", videoCodec: .h264)
        XCTAssertNotEqual(original.id, changed.id)

        // Simulate the user picking a new profile (as the profile picker does).
        vm.selectedProfile = changed
        manager.registerUndo(
            for: \.selectedProfile, on: vm,
            oldValue: original, newValue: changed, description: "Profile Change")

        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.changeCount, 1)

        manager.undo()
        XCTAssertEqual(vm.selectedProfile.id, original.id, "undo restores the previous profile")
        XCTAssertTrue(manager.canRedo)

        manager.redo()
        XCTAssertEqual(vm.selectedProfile.id, changed.id, "redo re-applies the change")
    }

    func test_undoRedo_areNoOpsWhenStackEmpty() {
        let vm = AppViewModel()
        let manager = vm.settingsUndoManager
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        // Safe no-ops (guarded internally).
        manager.undo()
        manager.redo()
        XCTAssertFalse(manager.canUndo)
    }

    func test_removeAllActions_clearsHistory() {
        let vm = AppViewModel()
        let manager = vm.settingsUndoManager
        manager.registerUndo(
            for: \.selectedProfile, on: vm,
            oldValue: vm.selectedProfile, newValue: EncodingProfile(name: "X"),
            description: "Profile Change")
        XCTAssertTrue(manager.canUndo)
        manager.removeAllActions()
        XCTAssertFalse(manager.canUndo)
        XCTAssertEqual(manager.changeCount, 0)
    }
}
