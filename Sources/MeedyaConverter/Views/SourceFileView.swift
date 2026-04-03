// ============================================================================
// MeedyaConverter — SourceFileView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - SourceFileView

/// The source file import view with drag-and-drop support and a file list.
///
/// Displays imported media files in a list with summary metadata.
/// Supports drag-and-drop of media files onto the view and keyboard
/// navigation for accessibility.
struct SourceFileView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var isDragTargeted = false

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.sourceFiles.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDragTargeted {
                dropOverlay
            }
        }
        .navigationTitle("Source Files")
    }

    // MARK: - Empty State

    /// Shown when no files have been imported yet.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Source Files", systemImage: "doc.badge.plus")
        } description: {
            Text("Drag and drop media files here, or click Import to browse.")
        } actions: {
            Button("Import Files") {
                openFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .accessibilityLabel("No source files imported. Drag and drop media files or click Import.")
    }

    // MARK: - File List

    /// List of imported source files with selection support.
    private var fileListView: some View {
        List(selection: Binding(
            get: { viewModel.selectedFile?.id },
            set: { newID in
                viewModel.selectedFile = viewModel.sourceFiles.first { $0.id == newID }
            }
        )) {
            ForEach(viewModel.sourceFiles) { file in
                SourceFileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
                        Button("Remove") {
                            viewModel.removeSourceFile(file)
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(
                                file.fileURL.path,
                                inFileViewerRootedAtPath: file.fileURL.deletingLastPathComponent().path
                            )
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear All", systemImage: "trash") {
                    viewModel.clearSourceFiles()
                }
                .disabled(viewModel.sourceFiles.isEmpty)
                .help("Remove all imported files")
            }
        }
    }

    // MARK: - Drop Overlay

    /// Visual indicator when files are being dragged over the view.
    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.blue, style: StrokeStyle(lineWidth: 3, dash: [10]))
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(8)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Text("Drop media files to import")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityLabel("Drop zone active — release to import files")
    }

    // MARK: - Drop Handling

    /// Handle dropped file URL items.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.isFileURL {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            Task {
                await viewModel.importFiles(urls)
            }
        }

        return true
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Import Media Files"
        panel.message = "Select one or more media files to convert."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video
        ]

        guard panel.runModal() == .OK else { return }

        Task {
            await viewModel.importFiles(panel.urls)
        }
    }
}

// MARK: - SourceFileRow

/// A single row in the source file list showing file metadata.
struct SourceFileRow: View {
    let file: MediaFile

    var body: some View {
        HStack(spacing: 12) {
            // File type icon
            Image(systemName: file.isAudioOnly ? "music.note" : "film")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                // File name
                Text(file.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Summary line (container, resolution, codec, duration)
                Text(file.summaryString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // File size badge
            if let sizeStr = file.fileSizeString {
                Text(sizeStr)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.fileName), \(file.summaryString)")
    }
}
