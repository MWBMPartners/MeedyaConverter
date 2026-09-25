// ============================================================================
// MeedyaConverter — SettingsImportPreviewSheet (Issue #506 commit 8)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The sheet `SettingsTransferTab` shows after `beginImport()` has checked a
// settings file. It shows the SAME preview the command-line tool's `settings
// import` prints (both call `SettingsImporter.preview`), then, after
// applying, the SAME kind of result the command-line tool prints
// (`SettingsImportResult.reportLines`) — so the two front ends never
// disagree about what a given file does.
//
// Nothing on this screen writes anything by itself. Every value shown comes
// from `model.importPreview` / `model.importResult`, both computed by the
// engine (`SettingsImporter.preview` / `.apply`); this file only lays them
// out. The one exception is the mode picker and the per-group tick boxes,
// which call `model.setImportMode`/`setImportSelection` — both of which
// recompute the preview and write nothing themselves either.
//
// REPLACE'S CONFIRMATION STEP. `model.requestApply()` sets
// `model.isAwaitingReplaceConfirmation` instead of applying, whenever
// "Replace" would remove something (`preview.replaceConfirmation != nil`).
// While that flag is set, this sheet shows the removal-count sentence with
// its own "Replace Anyway" button, wired to `model.confirmReplaceAndApply()`
// — a SEPARATE method, so nothing here can accidentally skip the
// confirmation by calling `requestApply()` a second time from the wrong
// place.
//
// ACCESSIBILITY. Every row that combines several `Text`s into one idea
// (a setting's before/after values, a warning, a "still needed" line) uses
// `.accessibilityElement(children: .combine)` with an explicit label, so
// VoiceOver reads it as one sentence rather than as disconnected fragments.
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// MARK: - SettingsImportPreviewSheet

struct SettingsImportPreviewSheet: View {

    let model: SettingsTransferViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let plan = model.importPlan {
                        Text(plan.sourceDescription)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }

                    if model.importResult == nil {
                        modePicker
                    }

                    if let preview = model.importPreview {
                        groupsSection(preview)

                        if !preview.warnings.isEmpty {
                            calloutSection(title: "Warnings", lines: preview.warnings, icon: "exclamationmark.triangle.fill", tint: .orange)
                        }

                        if !preview.crossChecks.isEmpty {
                            calloutSection(title: "Worth knowing", lines: preview.crossChecks, icon: "info.circle.fill", tint: .secondary)
                        }

                        if model.importResult == nil, let confirmation = preview.replaceConfirmation,
                           model.isAwaitingReplaceConfirmation {
                            replaceConfirmationBanner(confirmation)
                        }

                        if model.importResult == nil, !preview.ignored.isEmpty {
                            ignoredSection(preview.ignored)
                        }
                    }

                    if let result = model.importResult {
                        resultSection(result)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Import Settings")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(20)
    }

    // MARK: Mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("How to import", selection: modeBinding) {
                Text("Add to my settings (recommended)").tag(SettingsImportMode.merge)
                Text("Replace my settings in the ticked groups").tag(SettingsImportMode.replace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text("How to import"))

            Text(modeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(modeExplanation))
        }
    }

    private var modeBinding: Binding<SettingsImportMode> {
        Binding(get: { model.importMode }, set: { model.setImportMode($0) })
    }

    private var modeExplanation: String {
        switch model.importMode {
        case .merge:
            return "Only the settings in this file change. Anything the file doesn't mention "
                + "stays as it is."
        case .replace:
            return "Makes the ticked groups match the file exactly. Settings in those groups "
                + "that aren't in the file go back to their defaults, and profiles, servers and "
                + "rules that aren't in the file are removed. Passwords and keys are never touched."
        }
    }

    // MARK: Groups

    private func groupsSection(_ preview: SettingsImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(preview.groups, id: \.category) { group in
                groupRow(group)
            }
        }
    }

    private func groupRow(_ group: SettingsGroupPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: selectionBinding(for: group.category)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.category.displayName)
                        .fontWeight(.medium)
                    Text(group.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.importResult != nil)
            .accessibilityLabel(Text("Import \(group.category.displayName)"))
            .accessibilityHint(Text(group.summary))

            if let warning = group.category.warning, model.importSelection.contains(group.category) {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Warning: \(warning)"))
            }

            if group.changeCount > 0, group.isSelected, model.importResult == nil {
                DisclosureGroup("Show details (\(group.changeCount) changed)") {
                    itemDetails(group)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func itemDetails(_ group: SettingsGroupPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let profileChanges = group.profileChanges {
                listChangeRows(profileChanges)
            } else {
                ForEach(group.items.filter { $0.change != .unchanged }, id: \.key) { item in
                    itemRow(item)
                }
                ForEach(Array(group.listChanges.sorted(by: { $0.key < $1.key })), id: \.key) { key, changes in
                    // The registry's own label ("SFTP servers", "Saved
                    // encoding pipelines", …) as a heading for this list's
                    // changes. (The engine also has an `itemNoun(for:)`
                    // helper with the same purpose, but it is `internal` to
                    // `ConverterEngine`, so it isn't visible from this
                    // module — the registry's public `label` says the same
                    // thing.)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsKeyRegistry.entry(for: key)?.label ?? key)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        listChangeRows(changes)
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.leading, 4)
    }

    private func itemRow(_ item: SettingsItemPreview) -> some View {
        let description: String = {
            switch item.change {
            case .added:
                return "\(item.label): will be set to \(item.fileValue ?? "—")."
            case .changed:
                return "\(item.label): \(item.currentValue ?? "unset") → \(item.fileValue ?? "—")."
            case .removed:
                return "\(item.label): goes back to its default (was \(item.currentValue ?? "unset"))."
            case .unchanged:
                return "\(item.label): already \(item.currentValue ?? "unset")."
            }
        }()
        return Text(description)
            .font(.caption2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(description))
    }

    private func listChangeRows(_ changes: SettingsListChanges) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(changes.added, id: \.self) { name in
                Text("+ \(name) (new)").font(.caption2)
            }
            ForEach(changes.updated, id: \.self) { name in
                Text("~ \(name) (updates yours)").font(.caption2)
            }
            ForEach(changes.removed, id: \.self) { name in
                Text("− \(name) (removed)").font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private func selectionBinding(for category: SettingsCategory) -> Binding<Bool> {
        Binding(
            get: { model.importSelection.contains(category) },
            set: { isOn in
                var selection = model.importSelection
                if isOn { selection.insert(category) } else { selection.remove(category) }
                model.setImportSelection(selection)
            }
        )
    }

    // MARK: Warnings / cross-checks / ignored

    private func calloutSection(title: String, lines: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.semibold)
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(line).font(.caption)
                } icon: {
                    Image(systemName: icon).foregroundStyle(tint)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(line))
            }
        }
    }

    private func replaceConfirmationBanner(_ confirmation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(confirmation).font(.callout)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(confirmation))

            Button("Replace Anyway", role: .destructive) {
                model.confirmReplaceAndApply()
            }
            .accessibilityHint(Text("Writes the import now, removing what the confirmation message names."))
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ignoredSection(_ ignored: [SettingsIgnoredItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not imported (\(ignored.count))").font(.subheadline).fontWeight(.semibold)
            ForEach(Array(ignored.enumerated()), id: \.offset) { _, item in
                Text(item.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Result

    private func resultSection(_ result: SettingsImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result").font(.subheadline).fontWeight(.semibold)
            ForEach(Array(result.reportLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .accessibilityLabel(Text(line))
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            if model.importResult != nil {
                Button("Done") { model.cancelImport() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { model.cancelImport() }
                    .accessibilityHint(Text("Closes this without changing anything."))
                // While a Replace confirmation is showing, this button is
                // greyed out, and the ONLY way on is the red "Replace Anyway"
                // button inside the warning above. It used to relabel itself
                // "Replace Anyway" and apply on a second press, so a
                // double-click here replaced settings unread.
                Button("Import") {
                    model.requestApply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.importPreview == nil
                        || model.importSelection.isEmpty
                        || model.isAwaitingReplaceConfirmation
                )
            }
        }
        .padding(20)
    }
}
