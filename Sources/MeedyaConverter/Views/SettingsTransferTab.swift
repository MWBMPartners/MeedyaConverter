// ============================================================================
// MeedyaConverter — SettingsTransferTab (Issue #506 commit 8)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Settings › Import & Export. All the logic lives in
// `SettingsTransferViewModel` (in `MeedyaConverterCore`, unit-tested); this
// file is the thin SwiftUI shell over it, plus the one place that actually
// shows `NSSavePanel`/`NSOpenPanel` and wires the two app-module reload
// hooks (`KeyboardShortcutManager.reloadFromDefaults`,
// `AppViewModel.reloadAfterSettingsImport`) into the view model's `didApply`
// callback — see `SettingsTransferViewModel`'s own file overview for why
// that wiring happens HERE rather than inside the view model itself.
//
// THE DOMAIN. `SettingsDomain(defaults: .standard, name: AppInfo
// .Application.id)`: `.standard` because this IS the app (never `.standard`
// with no name, and never a suite name — see `SettingsDomain`'s file
// overview for why the name must always be given explicitly), and
// `AppInfo.Application.id` because that resolves to whichever bundle
// identifier THIS build actually is (the Direct id, or the App Store
// `.Lite` id under `#if APP_STORE`) — unlike the command-line tool, which
// always targets the Direct id specifically because it can never reach the
// sandboxed App Store build's container at all (`SettingsCommand.swift`'s
// own file overview).
//
// THE LIVE PROFILE STORE. `appViewModel.engine.profileStore` is passed
// straight through — never a fresh `EncodingProfileStore()` — so an import
// updates the exact store every other screen (Output Settings, Conditional
// Rules, …) already reads from. See `SettingsTransferViewModel`'s file
// overview for why a second store here would be a real bug, not a style
// nit.
//
// ERRORS. `.alert` is driven by `model.errorMessage`, never a log line —
// the plan's own instruction not to repeat `ProfileManagementView
// .exportProfile`'s mistake (export failures there are only logged).
// ---------------------------------------------------------------------------

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - SettingsTransferTab

struct SettingsTransferTab: View {

    // MARK: - State

    /// Held so `didApply` (below) can call the two app-module reload hooks.
    /// A `let`: `AppViewModel` is a reference type (`@Observable final
    /// class`), so this view still sees live updates through it without
    /// needing `@Bindable` — nothing in this file writes to `appViewModel`
    /// itself, only reads two of its collaborators.
    private let appViewModel: AppViewModel

    /// Built once, in `init`, over `appViewModel`'s own live collaborators —
    /// never rebuilt on every redraw, which would otherwise reset the
    /// person's ticked groups and any in-progress preview each time this
    /// view recomputes its body.
    @State private var model: SettingsTransferViewModel

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        _model = State(wrappedValue: SettingsTransferViewModel(
            domain: SettingsDomain(defaults: .standard, name: AppInfo.Application.id),
            profileStore: appViewModel.engine.profileStore,
            presence: SystemSettingsCredentialPresence(),
            chooseExportDestination: Self.showExportPanel,
            chooseImportSource: Self.showImportPanel,
            didApply: { categories in
                // Only the two settings this commit gave a reload hook to
                // (see `SettingsKeyRegistry`'s comments on
                // "keyboard_shortcuts" and "savedPipelines"). Everything
                // else imported is listed under "next launch" by the
                // engine's own `SettingsImportResult.takesEffectNextLaunch`.
                if categories.contains(.general) {
                    appViewModel.shortcutManager.reloadFromDefaults(.standard)
                }
                if categories.contains(.encoding) {
                    appViewModel.reloadAfterSettingsImport(from: .standard)
                }
            }
        ))
    }

    // MARK: - Body

    var body: some View {
        Form {
            exportSection
            importSection
        }
        .formStyle(.grouped)
        .navigationTitle("Import & Export")
        .sheet(isPresented: sheetBinding) {
            SettingsImportPreviewSheet(model: model)
        }
        .alert("Couldn't complete that", isPresented: errorBinding) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Text("Saves your preferences, encoding profiles and connection details to a "
                + "file you can import on another Mac. Passwords and API keys are never "
                + "included: you enter those again on the other Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(SettingsCategory.allCases, id: \.self) { category in
                Toggle(isOn: exportBinding(for: category)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName)
                        Text(category.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(Text("Export \(category.displayName)"))
                .accessibilityHint(Text(category.explanation))

                if let warning = category.warning, model.exportSelection.contains(category) {
                    Label {
                        Text(warning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Warning: \(warning)"))
                }
            }

            DisclosureGroup("What's never included") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(SettingsTransferViewModel.neverIncludedExplanations.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("\(item.label): \(item.reason)"))
                    }
                }
                .padding(.top, 4)
            }
            .accessibilityHint(Text("Lists every setting that is never written to an exported file, and why."))

            HStack {
                Button("Export Settings…") {
                    model.exportSettings()
                }
                .accessibilityHint(Text("Opens a save dialog to choose where to write the settings file."))

                if let message = model.exportSavedMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(message))
                }
            }
        } header: {
            Text("Export")
        }
    }

    private func exportBinding(for category: SettingsCategory) -> Binding<Bool> {
        Binding(
            get: { model.exportSelection.contains(category) },
            set: { isOn in
                if isOn {
                    model.exportSelection.insert(category)
                } else {
                    model.exportSelection.remove(category)
                }
            }
        )
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Text("Reads a settings file made by \u{201C}Export Settings\u{2026}\u{201D} on this "
                + "Mac or another one. You always see exactly what would change — nothing is "
                + "written until you say so.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Import Settings…") {
                model.beginImport()
            }
            .accessibilityHint(Text("Opens a file dialog, then shows a preview before anything changes."))
        } header: {
            Text("Import")
        }
    }

    // MARK: - Bindings

    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingPreviewSheet },
            set: { isShowing in
                if !isShowing { model.cancelImport() }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isShowing in
                if !isShowing { model.dismissError() }
            }
        )
    }

    // MARK: - File panels (the only AppKit calls in this feature)

    /// `NSSavePanel`, restricted to JSON, pre-filled with `suggestedName`.
    /// Returns `nil` on cancel. `static` and free of `self` so it can be
    /// handed to `SettingsTransferViewModel` as a plain closure with no
    /// capture-list surprises.
    private static func showExportPanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// `NSOpenPanel`, restricted to JSON, single file only. Returns `nil` on
    /// cancel.
    private static func showImportPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
