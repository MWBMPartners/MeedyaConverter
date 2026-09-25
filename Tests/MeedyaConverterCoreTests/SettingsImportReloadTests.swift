// ============================================================================
// MeedyaConverter — SettingsImportReloadTests (Issue #506 commit 8)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Plan test 11 (§7): after an import, `AppViewModel
// .reloadAfterSettingsImport(from:)` shows the imported `savedPipelines`,
// and `KeyboardShortcutManager.reloadFromDefaults(_:)` shows the imported
// bindings and does NOT write them back.
//
// Both methods take an explicit `defaults: UserDefaults` parameter (default
// `.standard` for production) FOR EXACTLY THIS REASON: so these tests can
// drive them against a throwaway suite and never touch the developer's own
// settings file. Every suite is created fresh inside a per-test temp folder
// and removed at the end of that same test.
//
// NO `override func setUp()`/`tearDown()` IN THIS FILE, DELIBERATELY — see
// `SettingsTransferViewModelTests.swift`'s file overview (in this same test
// target) for why: this class is `@MainActor`, but `XCTestCase.setUp()`/
// `tearDown()` are themselves `nonisolated`, so an override of either would
// warn on every line touching a `@MainActor`-isolated stored property.
//
// ONE assertion needs `.standard` itself: proving `reloadFromDefaults`
// genuinely does not write back. `KeyboardShortcutManager.save()` is
// hard-coded to `UserDefaults.standard` (it always writes there — see that
// method's own comment), so nothing else can stand in for it. This follows
// the SAME precedent `AutoTagAppWiringTests.swift` already establishes for
// exactly this situation (see that file's own header comment for why): read
// whatever `.standard` already holds for the key first, restore it with
// `defer` no matter how the test ends, and only ever overwrite that key from
// inside the code path under test — never assign to it directly.
// ---------------------------------------------------------------------------

import XCTest
@testable import MeedyaConverterCore
import ConverterEngine

// MARK: - Shared throwaway suite helper

/// A settings suite stored at a path inside `root`, so its file disappears
/// with `root` rather than lingering in `~/Library/Preferences` (the same
/// reasoning `SettingsTransferTestWorld`, in `SettingsTransferViewModelTests
/// .swift`, gives in full). A free function rather than a shared type
/// because each test here only ever needs ONE suite.
private func makeReloadTestSuite(root: URL, _ label: String) -> UserDefaults {
    let name = root.appendingPathComponent("\(label).plist").path
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("UserDefaults(suiteName:) refused \(name)")
    }
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func makeReloadTestRoot() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-import-reload-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: - SettingsImportReloadTests

@MainActor
final class SettingsImportReloadTests: XCTestCase {

    // MARK: - AppViewModel.reloadAfterSettingsImport (savedPipelines)

    /// `AppViewModel()` is cheap and side-effect-free enough to construct
    /// directly in a test — already established by `AutoTagAppWiringTests`
    /// and `SettingsUndoManagerTests` in this same test target.
    func test_reloadAfterSettingsImport_showsImportedPipelines() throws {
        let root = makeReloadTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = makeReloadTestSuite(root: root, "pipelines-imported")

        let viewModel = AppViewModel()
        let imported = [
            EncodingPipeline(
                id: UUID(), name: "Imported Pipeline",
                steps: [PipelineStep(id: UUID(), name: "Thumbnail", type: .extractThumbnail, config: [:])],
                cleanIntermediateFiles: false
            ),
        ]
        suite.set(try JSONEncoder().encode(imported), forKey: "savedPipelines")

        viewModel.reloadAfterSettingsImport(from: suite)

        XCTAssertEqual(viewModel.savedPipelines.map(\.id), imported.map(\.id))
        XCTAssertEqual(viewModel.savedPipelines.map(\.name), ["Imported Pipeline"])
    }

    /// A "Replace" import can remove `savedPipelines` entirely (when the
    /// file's "Encoding" group doesn't mention it). After that, this Mac
    /// should show exactly what a fresh launch would show: an empty list,
    /// the same fallback `savedPipelines`'s own default-value expression
    /// uses.
    func test_reloadAfterSettingsImport_fallsBackToEmptyWhenSuiteHasNothing() {
        let root = makeReloadTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let emptySuite = makeReloadTestSuite(root: root, "pipelines-empty")

        let viewModel = AppViewModel()
        viewModel.reloadAfterSettingsImport(from: emptySuite)

        XCTAssertTrue(viewModel.savedPipelines.isEmpty)
    }

    // MARK: - KeyboardShortcutManager.reloadFromDefaults

    /// Re-reading a throwaway suite's shortcuts applies them to `bindings`.
    func test_reloadFromDefaults_showsImportedBindings() throws {
        let root = makeReloadTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = makeReloadTestSuite(root: root, "shortcuts-imported")

        let manager = KeyboardShortcutManager()
        let imported = [
            ShortcutBinding(action: "encode.start", label: "Start Encoding", key: "e", modifiers: ["command", "shift"]),
        ]
        suite.set(try JSONEncoder().encode(imported), forKey: "keyboard_shortcuts")

        manager.reloadFromDefaults(suite)

        XCTAssertEqual(manager.bindings, imported)
    }

    /// A "Replace" import can remove `keyboard_shortcuts` entirely (when the
    /// file's "General" group doesn't mention it). After that, this Mac
    /// should show exactly what a fresh launch would show: the factory
    /// bindings, the same fallback `init()` uses.
    func test_reloadFromDefaults_fallsBackToFactoryBindingsWhenSuiteHasNothing() {
        let root = makeReloadTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let emptySuite = makeReloadTestSuite(root: root, "shortcuts-empty")

        let manager = KeyboardShortcutManager()
        manager.reloadFromDefaults(emptySuite)

        XCTAssertEqual(manager.bindings, KeyboardShortcutManager.defaultBindings)
    }

    /// The behaviour the plan specifically asked for: reloading does NOT
    /// write the just-read value back anywhere. See the file overview for
    /// why this one assertion, alone in this file, briefly touches
    /// `.standard`, and how it always restores what was there.
    func test_reloadFromDefaults_doesNotWriteBackToStandard() throws {
        let root = makeReloadTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalStandardValue = UserDefaults.standard.data(forKey: "keyboard_shortcuts")
        defer {
            if let originalStandardValue {
                UserDefaults.standard.set(originalStandardValue, forKey: "keyboard_shortcuts")
            } else {
                UserDefaults.standard.removeObject(forKey: "keyboard_shortcuts")
            }
        }

        let manager = KeyboardShortcutManager()
        let suite = makeReloadTestSuite(root: root, "shortcuts-no-writeback")
        let imported = [ShortcutBinding(action: "file.import", label: "Import", key: "i", modifiers: ["command"])]
        suite.set(try JSONEncoder().encode(imported), forKey: "keyboard_shortcuts")

        manager.reloadFromDefaults(suite)

        XCTAssertEqual(manager.bindings, imported, "the reload itself must still have applied")
        XCTAssertEqual(UserDefaults.standard.data(forKey: "keyboard_shortcuts"), originalStandardValue,
                       "reloadFromDefaults must never write back to .standard")
    }
}
