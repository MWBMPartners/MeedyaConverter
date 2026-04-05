// ============================================================================
// MeedyaConverter — BatchRenameView (Issue #332)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - BatchRenameView

/// A view for batch renaming files using find/replace rules or
/// sequential naming templates.
///
/// Features a rule builder with regex support, a live preview table
/// showing original and new filenames, apply/undo buttons, and a
/// sequential naming mode toggle.
///
/// Phase 14 — Batch Rename Tool (Issue #332)
struct BatchRenameView: View {

    // MARK: - State

    /// The list of rename rules configured by the user.
    @State private var rules: [RenameRule] = [
        RenameRule(findPattern: "", replaceWith: ""),
    ]

    /// The source file URLs to rename.
    @State private var files: [URL] = []

    /// The computed rename previews based on current rules and files.
    @State private var previews: [RenamePreview] = []

    /// Whether sequential naming mode is active (replaces rule-based mode).
    @State private var isSequentialMode = false

    /// The sequential naming template (e.g. "Episode_###").
    @State private var sequentialTemplate = "File_###"

    /// The starting number for sequential naming.
    @State private var startNumber = 1

    /// URLs of files before the last apply, for undo support.
    @State private var undoStack: [URL] = []

    /// Whether an undo operation is available.
    @State private var canUndo = false

    /// Alert state for errors during rename application.
    @State private var errorMessage: String?

    /// Whether to show the error alert.
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Toolbar
            toolbar
                .padding()

            Divider()

            HSplitView {
                // MARK: Rules Panel
                rulesPanel
                    .frame(minWidth: 280, maxWidth: 350)

                // MARK: Preview Table
                previewTable
                    .frame(minWidth: 400)
            }
        }
        .alert("Rename Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Toolbar

    /// Top toolbar with file selection, mode toggle, and action buttons.
    private var toolbar: some View {
        HStack {
            Button {
                selectFiles()
            } label: {
                Label("Add Files", systemImage: "doc.badge.plus")
            }
            .accessibilityLabel("Select files to rename")

            Text("\(files.count) file(s)")
                .foregroundStyle(.secondary)
                .font(.caption)

            Spacer()

            Toggle("Sequential Mode", isOn: $isSequentialMode)
                .toggleStyle(.switch)
                .accessibilityLabel("Toggle sequential naming mode")
                .onChange(of: isSequentialMode) { _, _ in
                    updatePreview()
                }

            Spacer()

            Button {
                applyRename()
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            .disabled(files.isEmpty || previews.filter(\.changed).isEmpty)
            .accessibilityLabel("Apply rename")

            Button {
                performUndo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo last rename")
        }
    }

    // MARK: - Rules Panel

    /// Left panel containing the rename rules or sequential template.
    private var rulesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSequentialMode {
                // Sequential naming controls
                Form {
                    Section("Sequential Naming") {
                        TextField(
                            "Template",
                            text: $sequentialTemplate,
                            prompt: Text("Episode_###")
                        )
                        .accessibilityLabel("Sequential naming template")
                        .onChange(of: sequentialTemplate) { _, _ in
                            updatePreview()
                        }

                        Stepper(
                            "Start: \(startNumber)",
                            value: $startNumber,
                            in: 0...99999
                        )
                        .accessibilityLabel("Starting number")
                        .onChange(of: startNumber) { _, _ in
                            updatePreview()
                        }

                        Text("Use # for number placeholders. ### = zero-padded to 3 digits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            } else {
                // Rule-based controls
                List {
                    ForEach(rules.indices, id: \.self) { index in
                        ruleEditor(at: index)
                    }
                    .onDelete(perform: deleteRule)
                }
                .listStyle(.inset)

                HStack {
                    Button {
                        rules.append(RenameRule(findPattern: "", replaceWith: ""))
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Rule Editor

    /// An inline editor for a single rename rule.
    ///
    /// - Parameter index: The index of the rule in the `rules` array.
    /// - Returns: A view for editing the rule.
    private func ruleEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                "Find",
                text: $rules[index].findPattern,
                prompt: Text("Find...")
            )
            .accessibilityLabel("Find pattern for rule \(index + 1)")
            .onChange(of: rules[index].findPattern) { _, _ in
                updatePreview()
            }

            TextField(
                "Replace",
                text: $rules[index].replaceWith,
                prompt: Text("Replace with...")
            )
            .accessibilityLabel("Replacement for rule \(index + 1)")
            .onChange(of: rules[index].replaceWith) { _, _ in
                updatePreview()
            }

            HStack {
                Toggle("Regex", isOn: $rules[index].isRegex)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Use regex for rule \(index + 1)")
                    .onChange(of: rules[index].isRegex) { _, _ in
                        updatePreview()
                    }

                Toggle("Case Sensitive", isOn: $rules[index].caseSensitive)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Case sensitive for rule \(index + 1)")
                    .onChange(of: rules[index].caseSensitive) { _, _ in
                        updatePreview()
                    }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Preview Table

    /// Right panel showing the live rename preview table.
    private var previewTable: some View {
        Table(previews) {
            TableColumn("Original") { preview in
                Text(preview.originalName)
                    .foregroundStyle(preview.changed ? .primary : .secondary)
            }
            .width(min: 150)

            TableColumn("New Name") { preview in
                Text(preview.newName)
                    .foregroundStyle(preview.changed ? .green : .secondary)
            }
            .width(min: 150)

            TableColumn("Changed") { preview in
                Image(systemName: preview.changed ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(preview.changed ? .green : .secondary)
            }
            .width(60)
        }
    }

    // MARK: - Actions

    /// Opens a file panel to select files for renaming.
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            files = panel.urls
            updatePreview()
        }
    }

    /// Updates the preview table based on the current rules and files.
    private func updatePreview() {
        guard !files.isEmpty else {
            previews = []
            return
        }

        if isSequentialMode {
            previews = BatchRenamer.buildSequentialNames(
                files: files,
                template: sequentialTemplate,
                startNumber: startNumber
            )
        } else {
            let activeRules = rules.filter { !$0.findPattern.isEmpty }
            previews = BatchRenamer.preview(files: files, rules: activeRules)
        }
    }

    /// Applies the rename operation to all files.
    private func applyRename() {
        let activeRules = rules.filter { !$0.findPattern.isEmpty }
        guard !files.isEmpty, !activeRules.isEmpty || isSequentialMode else { return }

        // Store current file URLs for undo
        undoStack = files

        do {
            if isSequentialMode {
                // For sequential mode, build rules from the preview
                let seqPreviews = BatchRenamer.buildSequentialNames(
                    files: files,
                    template: sequentialTemplate,
                    startNumber: startNumber
                )
                // Apply by creating individual rules per file
                var newFiles: [URL] = []
                let fm = FileManager.default
                for (index, url) in files.enumerated() {
                    let directory = url.deletingLastPathComponent()
                    let newURL = directory.appendingPathComponent(
                        seqPreviews[index].newName
                    )
                    if newURL != url {
                        try fm.moveItem(at: url, to: newURL)
                    }
                    newFiles.append(newURL)
                }
                files = newFiles
            } else {
                files = try BatchRenamer.apply(files: files, rules: activeRules)
            }
            canUndo = true
            updatePreview()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Undoes the last rename operation by restoring original filenames.
    private func performUndo() {
        guard canUndo, undoStack.count == files.count else { return }

        let fm = FileManager.default
        do {
            var restoredFiles: [URL] = []
            for (current, original) in zip(files, undoStack) {
                if current != original {
                    try fm.moveItem(at: current, to: original)
                }
                restoredFiles.append(original)
            }
            files = restoredFiles
            canUndo = false
            updatePreview()
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Deletes rules at the specified offsets.
    private func deleteRule(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        if rules.isEmpty {
            rules.append(RenameRule(findPattern: "", replaceWith: ""))
        }
        updatePreview()
    }
}
