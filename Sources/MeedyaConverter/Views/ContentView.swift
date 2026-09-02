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

    /// The user's configured keyboard shortcuts, so that the toolbar's
    /// live commands track any rebinding made in Settings → Keyboard
    /// Shortcuts rather than staying hardcoded (Issue #331).
    @Environment(KeyboardShortcutManager.self) private var shortcutManager

    /// The shared colour theme (Issue #336), so the optional sidebar tint is
    /// applied to the navigation column rather than persisted and ignored.
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - State

    /// Whether a drag operation is currently hovering over the window.
    @State private var isDragTargeted = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            SidebarView()
                // Apply the user's optional sidebar tint (Issue #336). When
                // none is chosen the accent tint inherited from the root is
                // used, so this changes nothing until the user opts in.
                .tint(themeManager.sidebarTint ?? themeManager.accentColor)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            toolbarContent
        }
        // Touch Bar — context-sensitive encoding controls (Issue #181)
        .touchBar {
            TouchBarProvider()
                .environment(viewModel)
        }
        // Global drag-and-drop — import files dropped anywhere on the
        // window and switch to the Source view (Issue #366).
        .onDrop(
            of: [.fileURL, .movie, .video, .audio],
            isTargeted: $isDragTargeted
        ) { providers in
            DropHandler.extractURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                Task { @MainActor in
                    await viewModel.importFiles(urls)
                    viewModel.selectedNavItem = .source
                }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.blue, lineWidth: 3)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Detail View

    /// Routes the detail pane to the correct view based on sidebar selection.
    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedNavItem {

        // -- Workflow ------------------------------------------------------
        case .source:
            SourceFileView()
        case .mediaBrowser:
            MediaBrowserView()
        case .streams:
            StreamInspectorView()
        case .output:
            OutputSettingsView()

        // -- Monitor -------------------------------------------------------
        case .queue:
            JobQueueView()
        case .resumableJobs:
            ResumableJobsView()
        case .log:
            ActivityLogView()
        case .dashboard:
            DashboardView()
        case .encodingGraphs:
            EncodingGraphsView()
        case .statisticsExport:
            StatisticsExportView()
        case .resourceMonitor:
            ResourceMonitorView()

        // -- Tools ---------------------------------------------------------
        case .images:
            ImageConversionView()
        case .vectorConversion:
            VectorConversionView()
        case .proresVector:
            ProResVectorView()
        case .burn:
            BurnSettingsView()
        case .trimEdit:
            VideoTrimmerView()
        case .analyze:
            AnalysisHubView()
        case .metadataTags:
            MetadataTagEditorView()
        case .batchRename:
            BatchRenameView()
        case .concatenation:
            ConcatenationView()
        case .watermark:
            WatermarkView()
        case .multiOutput:
            MultiOutputView()
        case .conditionalRules:
            ConditionalRulesView()
        case .dualDynamicHDR:
            DualDynamicHDRView()
        case .filterGraph:
            FilterGraphEditorView()
        case .edlEditor:
            EDLEditorView()
        case .animatedImage:
            AnimatedImageView()
        case .smartCrop:
            SmartCropView()
        case .backgroundRemoval:
            BackgroundRemovalView()
        case .voiceIsolation:
            VoiceIsolationView()
        case .duplicateFinder:
            DuplicateFinderView()

        // -- Performance ---------------------------------------------------
        case .parallelEncoding:
            ParallelEncodingView()
        case .queueOptimizer:
            QueueOptimizerView()
        case .benchmark:
            BenchmarkView()
        case .storageAnalysis:
            StorageAnalysisView()
        case .comparisonLibrary:
            ComparisonLibraryView()
        case .recentFiles:
            RecentFilesView()

        // -- Distribution --------------------------------------------------
        case .videoUpload:
            VideoUploadView()
        case .cloudStorage:
            CloudStorageView()
        case .sftp:
            SFTPSettingsView()
        case .podcastFeed:
            PodcastFeedView()
        case .teamProfile:
            TeamProfileView()
        case .cloudSync:
            CloudSyncView()

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
            // Reflects the user's "file.import" binding from Settings →
            // Keyboard Shortcuts, falling back to the factory Cmd+O when
            // no binding is found (Issue #331).
            .keyboardShortcut(
                shortcutManager.binding(for: "file.import") ?? KeyboardShortcut("o", modifiers: .command)
            )
            // The tooltip must name the shortcut that is actually bound, not a
            // hard-coded one — otherwise rebinding in Settings leaves the help
            // text advertising a key combination that no longer works.
            .help("Import media files (\(shortcutManager.displayString(for: "file.import") ?? "\u{2318}O"))")
            .accessibilityLabel("Import media files")
        }

        // Encode button — start encoding the selected file
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.enqueueSelectedFile()
            } label: {
                Label("Encode", systemImage: "play.fill")
            }
            // Reflects the user's "encode.start" binding from Settings →
            // Keyboard Shortcuts, falling back to the factory Cmd+Return
            // when no binding is found (Issue #331).
            .keyboardShortcut(
                shortcutManager.binding(for: "encode.start") ?? KeyboardShortcut(.return, modifiers: .command)
            )
            .disabled(viewModel.selectedFile == nil)
            .help("Add selected file to encoding queue (\(shortcutManager.displayString(for: "encode.start") ?? "\u{2318}\u{21A9}"))")
            .accessibilityLabel("Add to encoding queue")
        }

        // Mini player toggle (Issue #280)
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.miniPlayer.toggle()
            } label: {
                Label(
                    viewModel.miniPlayer.isVisible ? "Hide Mini Player" : "Show Mini Player",
                    systemImage: viewModel.miniPlayer.isVisible ? "pip.exit" : "pip.enter"
                )
            }
            .help("Toggle floating mini player (progress overlay)")
            .accessibilityLabel("Toggle mini player")
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
