// ============================================================================
// MeedyaConverter — SettingsTransferViewModel (Issue #506 commit 8)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The logic behind Settings › Import & Export. Everything that decides WHAT
// is exported or imported already lives in the engine
// (`Sources/ConverterEngine/Settings/…`, #506 commits 4-6): the allow-list,
// the file format, redaction, validation, preview and apply. This file only:
//   - asks for a file to save to or read from (through injected closures,
//     never `NSSavePanel`/`NSOpenPanel` directly — see "Injected seams"
//     below, and `SettingsTransferViewModelTests` for how tests drive it
//     without ever showing a real panel);
//   - calls the engine's `SettingsExporter` / `SettingsImporter`;
//   - holds the screen's state (which groups are ticked, the preview, the
//     result) so `SettingsTransferTab` and `SettingsImportPreviewSheet` stay
//     thin SwiftUI views;
//   - tells the app to refresh what it keeps loaded in memory once an
//     import actually writes something (`didApply`, below).
//
// THE LIVE PROFILE STORE, NEVER A NEW ONE (the plan's own rule, §5). This
// view model does not construct an `EncodingProfileStore` itself — the
// caller passes one in, and in the running app that must be
// `viewModel.engine.profileStore` (`AppViewModel`'s own live store), the
// exact one every other screen reads and writes through. A second store
// built fresh here would not see edits made through the first one, and vice
// versa — precisely the bug the plan warns about (comparing it to the
// in-flight `APIKeyManager` fault). Tests pass their own throwaway store
// instead (`EncodingProfileStore(storageDirectory:)` over a temp folder),
// which is correct there because a test has no second, already-live store
// for it to collide with.
//
// ERRORS ALWAYS SURFACE AS AN ALERT, NEVER ONLY A LOG. `errorMessage` is the
// ONLY place this file reports a failure. The plan calls out
// `ProfileManagementView.exportProfile` by name as the anti-pattern NOT to
// repeat here: that method's `catch` only calls `viewModel.appendLog(.error,
// …)`, so a failed export looks, from the person's side, exactly like
// nothing happened. This view model has no `appendLog` call anywhere in it
// on purpose — every `catch` block sets `errorMessage`, and the SwiftUI view
// turns that into an `.alert`.
//
// PREVIEW-FIRST, ALWAYS. `beginImport()` only ever calls
// `SettingsImporter.prepare`, which validates the whole file and writes
// nothing (see that method's own file overview). Nothing is written until
// the person explicitly asks to apply (`requestApply()`), and "Replace"
// additionally requires an explicit confirmation step
// (`isAwaitingReplaceConfirmation`) once `SettingsImportPreview
// .replaceConfirmation` says the mode would actually remove something — see
// `requestApply()`'s own comment for exactly when that gate applies.
//
// WHY THIS FILE NEVER CALLS `KeyboardShortcutManager.reloadFromDefaults` OR
// `AppViewModel.reloadAfterSettingsImport` ITSELF. Both belong to the app
// module's `AppViewModel`/`KeyboardShortcutManager`, and this view model
// must stay constructible with nothing more than the engine types above (so
// `SettingsTransferViewModelTests`, in this same test target, can build one
// without an `AppViewModel` at all). Instead, `didApply` is called once,
// right after a successful `apply`, with the groups that were actually
// written; `SettingsTransferTab` supplies a `didApply` that calls those two
// reload methods when the relevant group was applied. See
// `SettingsKeyRegistry`'s comments on `"keyboard_shortcuts"` and
// `"savedPipelines"` for why those two specifically needed a reload rather
// than staying `.nextLaunch`.
// ---------------------------------------------------------------------------

import Foundation
import ConverterEngine

// MARK: - SettingsTransferViewModel

@MainActor
@Observable
final class SettingsTransferViewModel {

    // MARK: - Injected seams

    /// The settings file to read from and write to. In the running app this
    /// is always `.standard` paired with the app's own bundle identifier
    /// (see `SettingsDomain`'s file overview for why a domain's `defaults`
    /// and `name` must always be given together, and never defaulted).
    private let domain: SettingsDomain

    /// The LIVE profile store — see the file overview.
    private let profileStore: EncodingProfileStore

    /// Answers "is this secret saved here?" without reading it.
    private let presence: any SettingsCredentialPresence

    /// Written into an exported file so the importing Mac can show "Made by
    /// MeedyaConverter 0.1.0 on …".
    private let appVersion: String

    /// The clock, so tests get a fixed date instead of "now".
    private let now: @Sendable () -> Date

    /// Asks where to save an export. `suggestedName` is the file name to
    /// pre-fill (see `defaultExportFileName`). Returns `nil` when the person
    /// cancelled the panel — nothing is written in that case. The production
    /// default (in `SettingsTransferTab`) wraps `NSSavePanel`; tests pass a
    /// closure that returns a fixed URL inside their own temp folder, so no
    /// panel ever appears in a test run.
    private let chooseExportDestination: (_ suggestedName: String) -> URL?

    /// Asks which file to import. Returns `nil` when the person cancelled.
    /// The production default wraps `NSOpenPanel`; tests supply a fixed URL.
    private let chooseImportSource: () -> URL?

    /// Called once, right after `apply` succeeds, with the groups that were
    /// actually written (`SettingsImportResult.appliedCategories`, as a
    /// `Set` so the caller can simply check `.contains(.general)` /
    /// `.contains(.encoding)`). See the file overview for why the two
    /// app-module reload hooks are wired up here rather than being called
    /// directly by this file. Defaults to a no-op so a test that doesn't
    /// care about reloading can omit it.
    private let didApply: (Set<SettingsCategory>) -> Void

    init(
        domain: SettingsDomain,
        profileStore: EncodingProfileStore,
        presence: any SettingsCredentialPresence,
        appVersion: String = AppInfo.Version.number,
        now: @escaping @Sendable () -> Date = { Date() },
        chooseExportDestination: @escaping (String) -> URL?,
        chooseImportSource: @escaping () -> URL?,
        didApply: @escaping (Set<SettingsCategory>) -> Void = { _ in }
    ) {
        self.domain = domain
        self.profileStore = profileStore
        self.presence = presence
        self.appVersion = appVersion
        self.now = now
        self.chooseExportDestination = chooseExportDestination
        self.chooseImportSource = chooseImportSource
        self.didApply = didApply
        self.exportSelection = SettingsExporter.defaultCategories
    }

    /// A fresh importer over this view model's domain, store and presence
    /// checker. Built on demand (not stored) because `SettingsImporter` is a
    /// plain value wrapper over three references — there is nothing to gain
    /// from caching it, and building it fresh removes any chance of it
    /// silently going stale relative to `domain`/`profileStore`.
    private var importer: SettingsImporter {
        SettingsImporter(domain: domain, profileStore: profileStore, presence: presence)
    }

    // MARK: - Export state

    /// Which groups are ticked for export. Starts at
    /// `SettingsExporter.defaultCategories` (every group except "This Mac
    /// only" — owner decision 3).
    var exportSelection: Set<SettingsCategory>

    /// "Saved “…”.", shown in place after a successful export. `nil` before
    /// the first export, and cleared at the start of every new attempt.
    private(set) var exportSavedMessage: String?

    // MARK: - Import state

    /// The checked file, once `beginImport()` has validated one. `nil` until
    /// then, and after `cancelImport()`.
    private(set) var importPlan: SettingsImportPlan?

    /// Which groups are ticked for import. Starts at the plan's own
    /// `defaultSelection` once a file is loaded.
    private(set) var importSelection: Set<SettingsCategory> = []

    /// "Add to my settings" (merge, the default) or "Replace my settings in
    /// the ticked groups".
    private(set) var importMode: SettingsImportMode = .merge

    /// What the current `importSelection`/`importMode` would do. Recomputed
    /// by `recomputePreview()` whenever either changes. `nil` until a file
    /// has been checked.
    private(set) var importPreview: SettingsImportPreview?

    /// What the last `apply` actually did. `nil` until one has succeeded;
    /// reset to `nil` at the start of every new `beginImport()`.
    private(set) var importResult: SettingsImportResult?

    /// Whether `SettingsImportPreviewSheet` should be shown. `SwiftUI`'s
    /// `.sheet(isPresented:)` binds straight to this.
    var isShowingPreviewSheet = false

    /// `true` between a "Replace" request that would remove something and
    /// the person confirming it. While this is `true`, the sheet shows the
    /// removal-count sentence (`importPreview.replaceConfirmation`) with a
    /// "Replace Anyway" button wired to `confirmReplaceAndApply()`, and
    /// nothing has been written yet.
    private(set) var isAwaitingReplaceConfirmation = false

    // MARK: - Errors (an alert, never only a log — see the file overview)

    /// The message for `SettingsTransferTab`'s `.alert`. `nil` when there is
    /// nothing to show. Every `catch` block below sets this; none of them
    /// also calls a logger, on purpose.
    var errorMessage: String?

    // MARK: - Export

    /// The suggested export file name: "MeedyaConverter Settings
    /// YYYY-MM-DD.json" (the plan's own wording for the `NSSavePanel`).
    static func defaultExportFileName(now: Date) -> String {
        let formatter = DateFormatter()
        // Fixed, locale-independent digits for a FILE NAME — using the
        // user's own locale here could give a name like "المعدل 2026" on an
        // Arabic system, which is a needless place for locale-dependent
        // formatting to leak into something meant to sort and glob cleanly.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "MeedyaConverter Settings \(formatter.string(from: now)).json"
    }

    /// Every setting that never travels, with its reason — read straight
    /// from `SettingsKeyRegistry`, so the "What's never included" disclosure
    /// the plan asks for can never go stale relative to the registry itself.
    static var neverIncludedExplanations: [(label: String, reason: String)] {
        SettingsKeyRegistry.entries
            .compactMap { entry -> (label: String, reason: String)? in
                guard case .never(_, let reason) = entry.decision else { return nil }
                return (entry.label, reason)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Asks where to save, builds the file for `exportSelection`, and saves
    /// it. On success, `exportSavedMessage` is set; on any failure —
    /// including the exporter's own self-check
    /// (`SettingsExportError.selfCheckFailed`) — `errorMessage` is set
    /// instead, and nothing was written (`SettingsExporter.write` writes
    /// atomically, so a failure never leaves a partial file behind).
    /// Does nothing (and touches neither message) if the person cancels the
    /// save panel.
    func exportSettings() {
        errorMessage = nil
        exportSavedMessage = nil
        guard let url = chooseExportDestination(Self.defaultExportFileName(now: now())) else { return }

        let exporter = SettingsExporter(
            domain: domain, profileStore: profileStore, presence: presence,
            appVersion: appVersion, now: now
        )
        do {
            try exporter.write(to: url, categories: exportSelection)
            exportSavedMessage = "Saved “\(url.lastPathComponent)”."
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - Import: choose a file, check it, preview

    /// Asks which file to import, checks the WHOLE file
    /// (`SettingsImporter.prepare`, which writes nothing), and — if it is a
    /// valid MeedyaConverter settings file — opens the preview sheet with
    /// its default selection (every group in the file except "This Mac
    /// only") and mode ("Add to my settings"). On a bad file, sets
    /// `errorMessage` (whose text, from `SettingsImportError`, already ends
    /// "Nothing was changed.") and leaves the sheet closed. Does nothing if
    /// the person cancels the open panel.
    func beginImport() {
        errorMessage = nil
        importResult = nil
        guard let url = chooseImportSource() else { return }
        do {
            let plan = try SettingsImporter.prepare(contentsOf: url)
            importPlan = plan
            importSelection = plan.defaultSelection
            importMode = .merge
            isAwaitingReplaceConfirmation = false
            recomputePreview()
            isShowingPreviewSheet = true
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Ticks or unticks groups for the current import and recomputes the
    /// preview. Writes nothing.
    func setImportSelection(_ selection: Set<SettingsCategory>) {
        importSelection = selection
        recomputePreview()
    }

    /// Switches between "Add to my settings" and "Replace my settings in
    /// the ticked groups" and recomputes the preview. Writes nothing.
    /// Changing the mode always clears any pending replace confirmation:
    /// the counts it was about to confirm may no longer be right.
    func setImportMode(_ mode: SettingsImportMode) {
        importMode = mode
        recomputePreview()
    }

    /// Recomputes `importPreview` for the current selection and mode, and
    /// clears any pending replace confirmation (it was computed for the
    /// PREVIOUS selection or mode, so it is no longer trustworthy). Writes
    /// nothing — `SettingsImporter.preview` is read-only by contract.
    private func recomputePreview() {
        isAwaitingReplaceConfirmation = false
        guard let importPlan else {
            importPreview = nil
            return
        }
        importPreview = importer.preview(importPlan, selection: importSelection, mode: importMode)
    }

    // MARK: - Import: apply

    /// Applies the current preview — UNLESS the mode is "Replace" and
    /// applying it would remove at least one setting, profile or list item
    /// (`importPreview.replaceConfirmation != nil`), in which case this only
    /// sets `isAwaitingReplaceConfirmation` and returns without writing
    /// anything. The sheet reads that flag to show the removal-count
    /// sentence with its own "Replace Anyway" button
    /// (`confirmReplaceAndApply()`), so the person always sees exactly what
    /// would be removed before it happens. Calling this again after the flag
    /// is already set applies immediately — it means the same button was
    /// pressed a second time, which is itself the confirmation.
    func requestApply() {
        guard let importPreview else { return }
        // In Replace mode with something to remove, this ONLY ever asks. It
        // never applies, however many times it is called. It used to apply
        // on a second call ("the second press confirms"), so a quick
        // double-click on the footer button replaced settings before the
        // warning could be read (the orchestrator's review of #506 8/9). The
        // one way to apply is `confirmReplaceAndApply()`, from the separate
        // red button inside the warning.
        if importMode == .replace, importPreview.replaceConfirmation != nil {
            isAwaitingReplaceConfirmation = true
            return
        }
        performApply()
    }

    /// Applies after the person has explicitly confirmed a "Replace" that
    /// would remove something. Exists as its own method (rather than only
    /// relying on calling `requestApply()` twice) so the sheet's "Replace
    /// Anyway" button can be wired to something whose name says what it
    /// does.
    func confirmReplaceAndApply() {
        // Only valid while a confirmation is actually on screen. A stray call
        // (e.g. a stale button after the mode changed back to Merge) must not
        // apply a Replace nobody was asked about.
        guard isAwaitingReplaceConfirmation else { return }
        performApply()
    }

    /// Writes the import (`SettingsImporter.apply`, all-or-nothing — see
    /// that method's own file overview) and records the result, or sets
    /// `errorMessage` on failure (in which case nothing was written).
    /// Either way, calls `didApply` only on SUCCESS, and only with the
    /// groups that were actually applied, so a failed apply never triggers
    /// the app-module reload hooks for a change that never happened.
    private func performApply() {
        guard let importPlan else { return }
        do {
            let result = try importer.apply(importPlan, selection: importSelection, mode: importMode)
            importResult = result
            isAwaitingReplaceConfirmation = false
            didApply(Set(result.appliedCategories))
        } catch {
            errorMessage = Self.describe(error)
            isAwaitingReplaceConfirmation = false
        }
    }

    /// Closes the preview sheet and clears every piece of import state.
    /// Used by BOTH the sheet's "Cancel" button (before anything was
    /// applied — this writes nothing, matching every `SettingsImportError`
    /// message's own "Nothing was changed.") and its "Done" button (after a
    /// successful apply — the import already happened; this only dismisses
    /// the sheet and resets the view model so the next "Import Settings…"
    /// starts clean).
    func cancelImport() {
        importPlan = nil
        importSelection = []
        importMode = .merge
        importPreview = nil
        importResult = nil
        isAwaitingReplaceConfirmation = false
        isShowingPreviewSheet = false
    }

    // MARK: - Errors

    /// Dismisses the current error alert without otherwise changing
    /// anything.
    func dismissError() {
        errorMessage = nil
    }

    /// Plain English for any thrown error, preferring the engine's own
    /// `LocalizedError` message (which for an import failure always ends
    /// "Nothing was changed.") over Swift's generic description.
    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
