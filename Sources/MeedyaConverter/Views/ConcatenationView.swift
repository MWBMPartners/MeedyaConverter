// ============================================================================
// MeedyaConverter — ConcatenationView (Issue #322)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - ConcatenationView

/// Video concatenation and joining interface.
///
/// Provides a drag-to-reorder file list, add/remove file controls,
/// a method picker (lossless demuxer vs. re-encode filter), crossfade
/// duration slider (filter mode only), compatibility warnings for
/// demuxer mode, and output path selection.
///
/// Phase 9 — Video Concatenation and Joining (Issue #322)
struct ConcatenationView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Ordered list of input file URLs to concatenate.
    @State private var files: [URL] = []

    /// Selected concatenation method (lossless or re-encode).
    @State private var method: ConcatMethod = .demuxer

    /// Crossfade duration in seconds (filter mode only).
    @State private var crossfadeDuration: Double = 1.0

    /// Whether crossfade is enabled (filter mode only).
    @State private var crossfadeEnabled = false

    /// Compatibility warnings for demuxer mode.
    @State private var compatibilityWarnings: [String] = []

    /// Output file path for the concatenated result.
    @State private var outputPath: String = ""

    /// Whether the file import dialog is presented.
    @State private var showingFileImporter = false

    /// Error message to display in an alert.
    @State private var errorMessage: String?

    /// Whether the error alert is presented.
    @State private var showError = false

    /// The currently selected file ID for drag-to-reorder.
    @State private var selectedFileID: URL?

    /// Whether a drag operation is hovering over this view.
    @State private var isDragTargeted = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with add/remove controls
            controlsBar

            Divider()

            // Main content
            if files.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    fileListView
                        .frame(minWidth: 300)

                    settingsPanel
                        .frame(minWidth: 280, maxWidth: 320)
                }
            }
        }
        .navigationTitle("Concatenation")
        // Drop video files to add to the concatenation list (Issue #366).
        .onDrop(
            of: [.fileURL, .movie, .video, .audio],
            isTargeted: $isDragTargeted
        ) { providers in
            DropHandler.extractURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                Task { @MainActor in
                    files.append(contentsOf: urls)
                    validateFiles()
                }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 3)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.movie, .audio, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Controls Bar

    /// Top toolbar with add/remove file buttons and method picker.
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button {
                showingFileImporter = true
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .accessibilityLabel("Add files to concatenation list")

            Button {
                removeSelectedFile()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selectedFileID == nil)
            .accessibilityLabel("Remove selected file")

            Button {
                files.removeAll()
                compatibilityWarnings.removeAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(files.isEmpty)
            .accessibilityLabel("Clear all files")

            Spacer()

            // Method picker
            Picker("Method:", selection: $method) {
                ForEach(ConcatMethod.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .onChange(of: method) { _, _ in
                validateFiles()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - File List

    /// Drag-to-reorder list of input files.
    private var fileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Input Files")
                    .font(.headline)
                Spacer()
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // File list with reordering
            List(selection: $selectedFileID) {
                ForEach(files, id: \.self) { file in
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                                .font(.body)
                                .lineLimit(1)

                            Text(file.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .tag(file)
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    files.move(fromOffsets: source, toOffset: destination)
                    validateFiles()
                }
            }

            // Compatibility warnings
            if !compatibilityWarnings.isEmpty && method == .demuxer {
                warningsView
            }
        }
    }

    // MARK: - Settings Panel

    /// Right-side panel with concatenation settings and output path.
    private var settingsPanel: some View {
        Form {
            // Method info
            Section("Method") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(method.displayName)
                        .font(.headline)

                    switch method {
                    case .demuxer:
                        Text(
                            "Lossless concatenation — no re-encoding. "
                            + "Requires all files to have the same codec, "
                            + "resolution, and frame rate."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    case .filter:
                        Text(
                            "Re-encode concatenation — supports different "
                            + "codecs, resolutions, and optional crossfade "
                            + "transitions between segments."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Crossfade settings (filter mode only)
            if method == .filter {
                Section("Crossfade") {
                    Toggle("Enable Crossfade", isOn: $crossfadeEnabled)

                    if crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text(
                                    String(format: "%.1fs", crossfadeDuration)
                                )
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: $crossfadeDuration,
                                in: 0.1...5.0,
                                step: 0.1
                            ) {
                                Text("Crossfade Duration")
                            }
                        }
                    }
                }
            }

            // Output path
            Section("Output") {
                HStack {
                    TextField("Output Path", text: $outputPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        chooseOutputPath()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Warnings View

    /// Displays compatibility warnings for demuxer mode.
    private var warningsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Compatibility Warnings", systemImage: "exclamationmark.triangle")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            ForEach(compatibilityWarnings, id: \.self) { warning in
                Text("  \(warning)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.05))
    }

    // MARK: - Empty State

    /// Placeholder view when no files have been added.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Add Video Files to Concatenate")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Drag files here or click \"Add Files\" to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Add Files") {
                showingFileImporter = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Handles the result of the file importer dialog.
    private func handleFileImport(
        _ result: Result<[URL], any Error>
    ) {
        switch result {
        case .success(let urls):
            files.append(contentsOf: urls)
            validateFiles()
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Removes the currently selected file from the list.
    private func removeSelectedFile() {
        guard let selected = selectedFileID,
              let index = files.firstIndex(of: selected) else { return }
        files.remove(at: index)
        selectedFileID = nil
        validateFiles()
    }

    /// Runs compatibility validation on the current file list.
    private func validateFiles() {
        compatibilityWarnings = VideoConcatenator.validateCompatibility(
            files: files
        )
    }

    /// Presents a save panel for choosing the output file path.
    private func chooseOutputPath() {
        let panel = NSSavePanel()
        panel.title = "Choose Output Location"
        panel.allowedContentTypes = [.movie, .mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "concatenated.mp4"

        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }
}
