// ============================================================================
// MeedyaConverter — SettingsTransferViewModelTests (Issue #506 commit 8)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Plan test 10 (§7): `SettingsTransferViewModelTests`, with an injected
// suite, profile store, presence checker and panel closures. Every test
// below builds its own `SettingsTransferViewModel` over:
//   - a settings suite named by an ABSOLUTE PATH inside a per-test temp
//     folder (`SettingsTransferTestWorld`, below), exactly as
//     `SettingsTransferFixture` does in `Tests/ConverterEngineTests
//     /SettingsTransferTestSupport.swift` (that type lives in a different
//     test TARGET and is not visible here, so this file keeps its own small,
//     independent copy of the same idea — see that file's comment for why a
//     plain suite NAME would leave a stray file in `~/Library/Preferences`
//     that no cleanup step can reliably remove);
//   - a temporary `EncodingProfileStore`, never the app's real one;
//   - `FakePresence`, a fixed-answer `SettingsCredentialPresence` that never
//     touches a real Keychain item;
//   - `chooseExportDestination`/`chooseImportSource` closures that return a
//     fixed URL (or `nil`, to simulate the person cancelling the panel) —
//     `NSSavePanel`/`NSOpenPanel` never appear in a test run.
//
// NO `override func setUp()`/`tearDown()` IN THIS FILE, DELIBERATELY — same
// reason `AutoTagAppWiringTests.swift`'s own header comment already gives
// for this test target: this class is `@MainActor` (needed so its test
// methods can construct `SettingsTransferViewModel`/`AppViewModel` directly),
// but `XCTestCase.setUp()`/`tearDown()` are themselves `nonisolated`, so an
// `override` of either is ALSO forced `nonisolated` regardless of the
// subclass's own `@MainActor` — and a `nonisolated` override cannot touch
// `@MainActor`-isolated stored properties without a strict-concurrency
// warning on every line that does. So instead, each test builds its own
// `SettingsTransferTestWorld` at the top and tears it down with its own
// `defer`, exactly like `SmartCropStagingTests` and `SettingsUndoManagerTests`
// already do in this same test target.
//
// Nothing here touches `UserDefaults.standard`, the owner's real Keychain,
// or the real `~/Library/Application Support/MeedyaConverter/Profiles`
// folder.
// ---------------------------------------------------------------------------

import XCTest
@testable import MeedyaConverterCore
import ConverterEngine

// MARK: - SettingsTransferTestWorld

/// One test's throwaway temp folder and the settings suites made inside it.
/// A plain (non-actor-isolated) type on purpose, so it can be built and torn
/// down from inside an `@MainActor` test method without any of the
/// `nonisolated`-override friction the file overview describes.
private final class SettingsTransferTestWorld {
    let root: URL
    private var suiteNames: [String] = []

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-transfer-vm-tests-\(UUID().uuidString)")
        // The "Preferences" folder that makeDomain's path-named suites live
        // in is created up front, as the engine's SettingsTransferTestSupport
        // does. On an older macOS the settings service may not create a
        // missing folder, which would silently lose the suite.
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("Preferences"), withIntermediateDirectories: true
        )
    }

    /// A settings domain stored at a path inside `root`, so its file
    /// disappears when `root` is removed rather than lingering in
    /// `~/Library/Preferences` (see the file overview).
    func makeDomain(_ label: String) -> SettingsDomain {
        // Named by an absolute path WITHOUT a ".plist" suffix, inside a
        // "Preferences" folder: exactly the naming the engine's
        // SettingsTransferTestSupport uses, which passes on CI. An earlier
        // version added ".plist". On the CI runner (macOS 15),
        // `persistentDomain(forName:)`, the call SettingsDomain reads
        // through, then found NOTHING, so every export came back empty and
        // four tests failed (CI run 36131537575). It worked on the owner's
        // newer macOS, which is why local checks didn't catch it. macOS adds
        // ".plist" to the file itself.
        let name = root.appendingPathComponent("Preferences").appendingPathComponent(label).path
        suiteNames.append(name)
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("UserDefaults(suiteName:) refused \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        return SettingsDomain(defaults: defaults, name: name)
    }

    /// A profile store over its own folder inside `root` — never the app's
    /// real `Profiles/user_profiles.json`.
    func makeProfileStore(_ label: String) -> EncodingProfileStore {
        EncodingProfileStore(storageDirectory: root.appendingPathComponent("Profiles-\(label)"))
    }

    /// Removes every suite this world made and the whole temp folder. Call
    /// from a `defer` at the top of each test.
    func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

/// Fixed answers to "is this secret saved?", for tests that don't care which
/// Keychain items exist (that is `SettingsCredentialNeedsTests`, in
/// `ConverterEngineTests`) — only that the view model reads whatever its
/// `presence` says. Never touches a real Keychain item.
private struct SettingsTransferFakePresence: SettingsCredentialPresence {
    var apiKeys: [String: KeyPresence] = [:]
    var smtp: KeyPresence = .missing

    func apiKey(for provider: APIKeyProvider, label: String?) -> KeyPresence {
        apiKeys[provider.rawValue] ?? .missing
    }
    func smtpPassword() -> KeyPresence { smtp }
    func sftpPassword(forProfileID id: UUID) -> KeyPresence { .missing }
    func fileExists(atPath path: String) -> Bool { false }
}

/// A box for a closure to record into, without mutating a captured `var`
/// inside an escaping closure (the hard rule for this session): the closure
/// captures this `let` reference and mutates ITS property instead. Plain
/// (non-isolated) on purpose, same reason as `SettingsTransferTestWorld`.
private final class SettingsTransferCategoryBox {
    var value: Set<SettingsCategory> = []
}

/// A fixed clock for these tests. Declared at file scope (not as a member of
/// the `@MainActor` test class) so it is NOT main-actor-isolated: the view
/// model's `now` parameter is `@Sendable`, and a `@Sendable` closure cannot
/// reference a main-actor-isolated value.
private let settingsTransferFixedDate = Date(timeIntervalSince1970: 1_800_000_000)

/// Builds a `SettingsTransferViewModel` wired for these tests: a fixed date,
/// and export/import panel closures that return the given URLs instead of
/// ever showing `NSSavePanel`/`NSOpenPanel`.
@MainActor
private func makeSettingsTransferTestModel(
    domain: SettingsDomain,
    profileStore: EncodingProfileStore,
    presence: SettingsCredentialPresence = SettingsTransferFakePresence(),
    exportURL: URL? = nil,
    importURL: URL? = nil,
    didApply: @escaping (Set<SettingsCategory>) -> Void = { _ in }
) -> SettingsTransferViewModel {
    SettingsTransferViewModel(
        domain: domain,
        profileStore: profileStore,
        presence: presence,
        appVersion: "9.9.9",
        now: { settingsTransferFixedDate },
        chooseExportDestination: { _ in exportURL },
        chooseImportSource: { importURL },
        didApply: didApply
    )
}

// MARK: - SettingsTransferViewModelTests

@MainActor
final class SettingsTransferViewModelTests: XCTestCase {

    // MARK: - Export

    /// The view model's export writes a real file, and it holds no secret —
    /// even one planted directly into the source domain outside any UI
    /// (`mediaServerAPIKey`, a "never" key the exporter must simply skip).
    func test_export_writesRealFileWithNoSecret() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let domain = world.makeDomain("export-src")
        domain.defaults.set("smtp.example.com", forKey: "emailSMTPHost")
        domain.defaults.set("SENTINEL-must-never-appear", forKey: "mediaServerAPIKey")
        let store = world.makeProfileStore("export-src")
        let exportURL = world.root.appendingPathComponent("export.json")
        let model = makeSettingsTransferTestModel(domain: domain, profileStore: store, exportURL: exportURL)

        model.exportSettings()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.exportSavedMessage, "Saved \u{201C}export.json\u{201D}.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        let bytes = try Data(contentsOf: exportURL)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("SENTINEL"),
                       "a settings file must never contain a secret, however it got into the domain")
    }

    /// Cancelling the save panel (the closure returns `nil`) does nothing:
    /// no file, no success message, no error.
    func test_export_cancelledPanel_doesNothing() {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let domain = world.makeDomain("export-cancel")
        let store = world.makeProfileStore("export-cancel")
        let model = makeSettingsTransferTestModel(domain: domain, profileStore: store, exportURL: nil)

        model.exportSettings()

        XCTAssertNil(model.exportSavedMessage)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - Import: preview

    /// "This Mac only" starts UNTICKED even when the file itself contains a
    /// "thisMac" section (owner decision 3, applied identically to import as
    /// to export).
    func test_beginImport_previewHasThisMacOff() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("thismac-src")
        sourceDomain.defaults.set("Dark", forKey: "appearanceMode")
        sourceDomain.defaults.set("/usr/local/bin/ffmpeg", forKey: "customFFmpegPath")
        let sourceStore = world.makeProfileStore("thismac-src")
        let fileURL = world.root.appendingPathComponent("thismac.json")
        let exportModel = makeSettingsTransferTestModel(domain: sourceDomain, profileStore: sourceStore, exportURL: fileURL)
        exportModel.exportSelection = Set(SettingsCategory.allCases)
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        let targetDomain = world.makeDomain("thismac-dst")
        let targetStore = world.makeProfileStore("thismac-dst")
        let importModel = makeSettingsTransferTestModel(domain: targetDomain, profileStore: targetStore, importURL: fileURL)

        importModel.beginImport()

        XCTAssertNil(importModel.errorMessage)
        let plan = try XCTUnwrap(importModel.importPlan)
        XCTAssertTrue(plan.categoriesInFile.contains(.thisMac),
                     "the source export included This Mac settings, so the file DOES have that group")
        XCTAssertFalse(importModel.importSelection.contains(.thisMac),
                       "but it must not be ticked by default")
        XCTAssertTrue(importModel.isShowingPreviewSheet)
    }

    /// A file that isn't a settings file at all sets `errorMessage` (an
    /// alert), never only a log line — and its text ends "Nothing was
    /// changed.", which is true here since nothing was ever read into a
    /// plan.
    func test_beginImport_badFile_setsErrorMessage() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let badURL = world.root.appendingPathComponent("not-json.json")
        try Data("this is not a settings file".utf8).write(to: badURL)
        let domain = world.makeDomain("badfile-dst")
        let store = world.makeProfileStore("badfile-dst")
        let model = makeSettingsTransferTestModel(domain: domain, profileStore: store, importURL: badURL)

        model.beginImport()

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains("Nothing was changed."), "message was: \(message)")
        XCTAssertFalse(model.isShowingPreviewSheet)
        XCTAssertNil(model.importPlan)
    }

    /// Cancelling the open panel does nothing: no plan, no error, no sheet.
    func test_beginImport_cancelledPanel_doesNothing() {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let domain = world.makeDomain("import-cancel-panel")
        let store = world.makeProfileStore("import-cancel-panel")
        let model = makeSettingsTransferTestModel(domain: domain, profileStore: store, importURL: nil)

        model.beginImport()

        XCTAssertNil(model.importPlan)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isShowingPreviewSheet)
    }

    /// A default profile the file names that isn't on this Mac, and isn't
    /// being imported, shows the engine's cross-check sentence — the same
    /// one the command-line tool prints, since both call the same
    /// `SettingsImporter.preview`.
    func test_preview_showsDefaultProfileCrossCheck() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("crosscheck-src")
        sourceDomain.defaults.set("Some Profile Nobody Has", forKey: "defaultProfileName")
        let sourceStore = world.makeProfileStore("crosscheck-src")
        let fileURL = world.root.appendingPathComponent("crosscheck.json")
        let exportModel = makeSettingsTransferTestModel(domain: sourceDomain, profileStore: sourceStore, exportURL: fileURL)
        exportModel.exportSelection = [.encoding]
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        let targetDomain = world.makeDomain("crosscheck-dst")
        let targetStore = world.makeProfileStore("crosscheck-dst")
        let importModel = makeSettingsTransferTestModel(domain: targetDomain, profileStore: targetStore, importURL: fileURL)

        importModel.beginImport()

        let preview = try XCTUnwrap(importModel.importPreview)
        XCTAssertTrue(preview.crossChecks.contains { $0.contains("Some Profile Nobody Has") },
                     "cross-checks were: \(preview.crossChecks)")
    }

    // MARK: - Import: apply (merge)

    /// Preview, then apply: the target domain actually changes, and
    /// `didApply` fires once with exactly the applied groups.
    func test_applyImport_mergeMode_changesTargetAndCallsDidApply() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("apply-src")
        sourceDomain.defaults.set("Dark", forKey: "appearanceMode")
        let sourceStore = world.makeProfileStore("apply-src")
        let fileURL = world.root.appendingPathComponent("apply.json")
        let exportModel = makeSettingsTransferTestModel(domain: sourceDomain, profileStore: sourceStore, exportURL: fileURL)
        exportModel.exportSelection = [.general]
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        let targetDomain = world.makeDomain("apply-dst")
        let targetStore = world.makeProfileStore("apply-dst")
        let box = SettingsTransferCategoryBox()
        let importModel = makeSettingsTransferTestModel(
            domain: targetDomain, profileStore: targetStore, importURL: fileURL,
            didApply: { categories in box.value = categories }
        )

        importModel.beginImport()
        XCTAssertNil(targetDomain.defaults.string(forKey: "appearanceMode"), "unset before apply")

        importModel.setImportSelection([.general])
        importModel.requestApply()

        XCTAssertNil(importModel.errorMessage)
        XCTAssertNotNil(importModel.importResult)
        XCTAssertEqual(targetDomain.defaults.string(forKey: "appearanceMode"), "Dark")
        XCTAssertEqual(box.value, [.general], "didApply must fire with exactly the applied groups")
    }

    /// "Still needed on this Mac" lists an item the source had set up
    /// (recorded in the file's `notIncluded`) that the TARGET's presence
    /// checker says is missing.
    func test_applyImport_showsStillNeeded() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("stillneeded-src")
        let sourceStore = world.makeProfileStore("stillneeded-src")
        let fileURL = world.root.appendingPathComponent("stillneeded.json")
        let sourcePresence = SettingsTransferFakePresence(apiKeys: [APIKeyProvider.tmdb.rawValue: .present])
        let exportModel = makeSettingsTransferTestModel(
            domain: sourceDomain, profileStore: sourceStore, presence: sourcePresence, exportURL: fileURL
        )
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        let targetDomain = world.makeDomain("stillneeded-dst")
        let targetStore = world.makeProfileStore("stillneeded-dst")
        let targetPresence = SettingsTransferFakePresence(apiKeys: [APIKeyProvider.tmdb.rawValue: .missing])
        let importModel = makeSettingsTransferTestModel(
            domain: targetDomain, profileStore: targetStore, presence: targetPresence, importURL: fileURL
        )

        importModel.beginImport()
        importModel.requestApply()

        let result = try XCTUnwrap(importModel.importResult)
        XCTAssertTrue(result.stillNeeded.contains { $0.title == "TMDB key" },
                     "still needed: \(result.stillNeeded.map(\.title))")
        // The full sentence names where to go set it up, matching the CLI's
        // own wording (both read `SettingsCredentialNeed.line`).
        XCTAssertTrue(result.reportLines.contains { $0.contains("TMDB key: Settings") })
    }

    // MARK: - Import: replace mode

    /// "Replace" that would remove or reset something asks for confirmation
    /// FIRST — `requestApply()` alone must write nothing — and only writes
    /// once `confirmReplaceAndApply()` is called.
    func test_replaceMode_requiresConfirmationThenWrites() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("replace-src")
        sourceDomain.defaults.set("Light", forKey: "appearanceMode")
        let sourceStore = world.makeProfileStore("replace-src")
        let fileURL = world.root.appendingPathComponent("replace.json")
        let exportModel = makeSettingsTransferTestModel(domain: sourceDomain, profileStore: sourceStore, exportURL: fileURL)
        exportModel.exportSelection = [.general]
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        // The target has a "General" setting the file does not mention, so
        // "Replace" on that group would reset it — exactly what
        // `replaceConfirmation` must warn about before anything is written.
        let targetDomain = world.makeDomain("replace-dst")
        targetDomain.defaults.set(true, forKey: "confirmBeforeEncoding")
        let targetStore = world.makeProfileStore("replace-dst")
        let importModel = makeSettingsTransferTestModel(domain: targetDomain, profileStore: targetStore, importURL: fileURL)

        importModel.beginImport()
        importModel.setImportMode(.replace)

        let preview = try XCTUnwrap(importModel.importPreview)
        XCTAssertNotNil(preview.replaceConfirmation,
                        "the target's extra setting means Replace has something to confirm")

        importModel.requestApply()
        XCTAssertTrue(importModel.isAwaitingReplaceConfirmation, "must wait, not apply yet")

        // A second press of the footer button (a double-click) must STILL not
        // apply: only confirmReplaceAndApply() may. (Orchestrator review of
        // #506 8/9: it used to apply on the second call.)
        importModel.requestApply()
        XCTAssertTrue(importModel.isAwaitingReplaceConfirmation, "a second request must keep waiting")
        XCTAssertNil(importModel.importResult, "a second request must not apply a Replace")
        XCTAssertEqual(targetDomain.defaults.object(forKey: "confirmBeforeEncoding") as? Bool, true,
                       "nothing may be written before the explicit confirmation")
        XCTAssertNil(importModel.importResult, "nothing written while waiting for confirmation")
        XCTAssertEqual(targetDomain.defaults.bool(forKey: "confirmBeforeEncoding"), true,
                       "target untouched before confirmation")

        importModel.confirmReplaceAndApply()

        XCTAssertNil(importModel.errorMessage)
        XCTAssertNotNil(importModel.importResult)
        XCTAssertFalse(importModel.isAwaitingReplaceConfirmation)
        XCTAssertNil(targetDomain.defaults.object(forKey: "confirmBeforeEncoding"),
                    "Replace reset it, since the file didn't mention it")
        XCTAssertEqual(targetDomain.defaults.string(forKey: "appearanceMode"), "Light",
                       "the file's own value was written")
    }

    // MARK: - Cancel

    /// Cancelling the preview sheet — whether before requesting apply, or
    /// after a "Replace" is awaiting confirmation — writes nothing.
    func test_cancelImport_writesNothing() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let sourceDomain = world.makeDomain("cancel-src")
        sourceDomain.defaults.set("Dark", forKey: "appearanceMode")
        let sourceStore = world.makeProfileStore("cancel-src")
        let fileURL = world.root.appendingPathComponent("cancel.json")
        let exportModel = makeSettingsTransferTestModel(domain: sourceDomain, profileStore: sourceStore, exportURL: fileURL)
        exportModel.exportSelection = [.general]
        exportModel.exportSettings()
        XCTAssertNil(exportModel.errorMessage)

        // The target needs a "General" setting the file does NOT mention, so
        // Replace has something to remove and therefore something to
        // confirm. An EMPTY target (the first version of this test) gives
        // Replace nothing to remove. It then rightly applies straight away
        // like a merge, since the confirmation exists to warn about
        // removals, and the test's premise failed on CI (run 36132295070).
        // The same setup as test_replaceMode_requiresConfirmationThenWrites.
        let targetDomain = world.makeDomain("cancel-dst")
        targetDomain.defaults.set(true, forKey: "confirmBeforeEncoding")
        let targetStore = world.makeProfileStore("cancel-dst")
        let importModel = makeSettingsTransferTestModel(domain: targetDomain, profileStore: targetStore, importURL: fileURL)

        importModel.beginImport()
        importModel.setImportMode(.replace)
        XCTAssertNotNil(importModel.importPreview?.replaceConfirmation,
                        "precondition: Replace has something to remove, so it must ask")
        importModel.requestApply()
        XCTAssertTrue(importModel.isAwaitingReplaceConfirmation, "got as far as awaiting confirmation")

        importModel.cancelImport()

        XCTAssertFalse(importModel.isShowingPreviewSheet)
        XCTAssertNil(importModel.importPlan)
        XCTAssertNil(importModel.importPreview)
        XCTAssertNil(importModel.importResult)
        XCTAssertFalse(importModel.isAwaitingReplaceConfirmation)
        XCTAssertNil(targetDomain.defaults.string(forKey: "appearanceMode"),
                    "cancel must never write, even after Replace was awaiting confirmation")
        XCTAssertEqual(targetDomain.defaults.object(forKey: "confirmBeforeEncoding") as? Bool, true,
                       "cancel must not remove what Replace would have removed")
    }

    // MARK: - Errors

    /// `dismissError()` clears the alert state without touching anything
    /// else.
    func test_dismissError_clearsErrorMessageOnly() throws {
        let world = SettingsTransferTestWorld()
        defer { world.tearDown() }

        let badURL = world.root.appendingPathComponent("bad.json")
        try Data("nope".utf8).write(to: badURL)
        let domain = world.makeDomain("dismiss-error")
        let store = world.makeProfileStore("dismiss-error")
        let model = makeSettingsTransferTestModel(domain: domain, profileStore: store, importURL: badURL)

        model.beginImport()
        XCTAssertNotNil(model.errorMessage)

        model.dismissError()

        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.importPlan, "dismissing the error doesn't retroactively load a plan")
    }
}
