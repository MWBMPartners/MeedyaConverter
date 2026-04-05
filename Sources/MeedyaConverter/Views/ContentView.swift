// ============================================================================
// MeedyaConverter — ContentView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - ContentView

/// The root content view for the MeedyaConverter application.
///
/// Uses a `NavigationSplitView` with a sidebar for navigation between
/// the main workflow areas: Source, Streams, Output, Queue, and Log.
/// The detail pane shows the selected section's content.
struct ContentView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Detail View

    /// Routes the detail pane to the correct view based on sidebar selection.
    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedNavItem {
        case .source:
            SourceFileView()
        case .streams:
            StreamInspectorView()
        case .output:
            OutputSettingsView()
        case .queue:
            JobQueueView()
        case .log:
            ActivityLogView()
        case .burn:
            BurnSettingsView()
        case nil:
            ContentUnavailableView(
                "Select a Section",
                systemImage: "sidebar.left",
                description: Text("Choose a section from the sidebar to get started.")
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Import button — opens file picker
        ToolbarItem(placement: .primaryAction) {
            Button {
                openFilePicker()
            } label: {
                Label("Import", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help("Import media files (Cmd+O)")
            .accessibilityLabel("Import media files")
        }

        // Encode button — start encoding the selected file
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.enqueueSelectedFile()
            } label: {
                Label("Encode", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedFile == nil)
            .help("Add selected file to encoding queue (Cmd+Return)")
            .accessibilityLabel("Add to encoding queue")
        }

        // Engine status indicator
        ToolbarItem(placement: .status) {
            HStack(spacing: 6) {
                if viewModel.isProbing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Probing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.engine.queue.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Encoding...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - File Picker

    /// Open a file picker panel to select media files for import.
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
