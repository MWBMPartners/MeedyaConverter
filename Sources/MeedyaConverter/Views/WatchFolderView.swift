// ============================================================================
// MeedyaConverter — WatchFolderView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides the SwiftUI interface for configuring and managing watch folders
// (hot folders) that automatically encode new media files.
//
// Features:
//   - Add, edit, and remove watch folder configurations.
//   - Watch folder path picker and output path picker.
//   - Encoding profile selector.
//   - File extension filter with checkboxes for common formats.
//   - Recursive monitoring toggle.
//   - Delete-after-encode toggle.
//   - Start/Stop monitoring toggle with live status indicator.
//   - Activity log of auto-encoded files.
//
// Phase 11 — Watch Folder / Hot Folder Auto-Encoding (Issue #268)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// MARK: - WatchFolderView

/// Interface for configuring and managing watch folders that automatically
/// encode new media files dropped into designated directories.
///
/// Displays a list of watch folder configurations on the left with a
/// detail/edit panel on the right. Each configuration can be independently
/// started and stopped.
struct WatchFolderView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// All watch folder configurations.
    @State private var configs: [WatchFolderConfig] = []

    /// Currently selected configuration ID.
    @State private var selectedConfigId: String?

    /// The monitor instance.
    @State private var monitor = WatchFolderMonitor.shared

    /// Activity log entries displayed in the log section.
    @State private var logEntries: [WatchFolderLogEntry] = []

    /// Whether to show the delete confirmation alert.
    @State private var showDeleteConfirmation = false

    /// Config pending deletion.
    @State private var configToDelete: WatchFolderConfig?

    // MARK: - Common Extensions

    /// Common media file extensions presented as checkboxes.
    private static let commonExtensions = [
        "mp4", "mkv", "mov", "avi", "wmv", "flv", "webm",
        "m4v", "ts", "mts", "m2ts", "mpg", "mpeg", "vob"
    ]

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            configListSidebar
        } detail: {
            configDetailView
        }
        .navigationTitle("Watch Folders")
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            configs = monitor.loadConfigs()
            logEntries = monitor.logEntries
        }
    }

    // MARK: - Sidebar

    /// List of watch folder configurations with add/remove controls.
    private var configListSidebar: some View {
        VStack {
            List(selection: $selectedConfigId) {
                ForEach(configs) { config in
                    WatchFolderRow(config: config, isMonitoring: monitor.isMonitoring)
                        .tag(config.id)
                }
            }

            HStack {
                Button {
                    addNewConfig()
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Spacer()

                Button {
                    if let id = selectedConfigId,
                       let config = configs.first(where: { $0.id == id }) {
                        configToDelete = config
                        showDeleteConfirmation = true
                    }
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selectedConfigId == nil)
            }
            .padding(8)
        }
        .alert("Delete Watch Folder?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let config = configToDelete {
                    deleteConfig(config)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the watch folder configuration.")
        }
    }

    // MARK: - Detail View

    /// Detail panel showing the selected configuration's settings,
    /// or a placeholder when nothing is selected.
    @ViewBuilder
    private var configDetailView: some View {
        if let id = selectedConfigId,
           let index = configs.firstIndex(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    configSettingsSection(index: index)
                    extensionFilterSection(index: index)
                    monitoringControlSection(config: configs[index])
                    activityLogSection
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Watch Folder Selected",
                systemImage: "folder.badge.questionmark",
                description: Text("Select a watch folder from the sidebar or add a new one.")
            )
        }
    }

    // MARK: - Settings Section

    /// Path pickers, profile selector, and toggles.
    private func configSettingsSection(index: Int) -> some View {
        GroupBox("Configuration") {
            Form {
                // Label
                TextField("Name:", text: $configs[index].name)

                // Watch path
                HStack {
                    Text("Watch Path:")
                    Text(configs[index].watchPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose...") {
                        chooseDirectory(for: .watch, index: index)
                    }
                }

                // Output path
                HStack {
                    Text("Output Path:")
                    Text(configs[index].outputPath ?? configs[index].effectiveOutputPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose...") {
                        chooseDirectory(for: .output, index: index)
                    }
                }

                // Profile name
                TextField("Profile Name:", text: $configs[index].profileName)

                // Toggles
                Toggle("Recursive (include subdirectories)", isOn: $configs[index].recursive)

                Picker("After Encoding:", selection: $configs[index].postAction) {
                    Text("Leave in Place").tag(PostProcessingAction.leaveInPlace)
                    Text("Move to Completed").tag(PostProcessingAction.moveToCompleted)
                    Text("Delete Source").tag(PostProcessingAction.deleteSource)
                }

                Toggle("Active", isOn: $configs[index].isActive)
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Extension Filter

    /// Checkboxes for common media file extensions.
    private func extensionFilterSection(index: Int) -> some View {
        GroupBox("File Extension Filter") {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100))
            ], alignment: .leading, spacing: 8) {
                ForEach(Self.commonExtensions, id: \.self) { ext in
                    Toggle(ext.uppercased(), isOn: Binding(
                        get: { configs[index].fileExtensions.contains(ext) },
                        set: { isOn in
                            if isOn {
                                configs[index].fileExtensions.append(ext)
                            } else {
                                configs[index].fileExtensions.removeAll { $0 == ext }
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .padding(8)

            Text("Leave unchecked to accept all recognised media extensions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Monitoring Control

    /// Start/stop toggle with status indicator.
    private func monitoringControlSection(config: WatchFolderConfig) -> some View {
        GroupBox("Monitoring") {
            HStack {
                Circle()
                    .fill(monitor.isMonitoring ? .green : .secondary)
                    .frame(width: 10, height: 10)

                Text(monitor.isMonitoring ? "Monitoring Active" : "Monitoring Stopped")
                    .font(.headline)

                Spacer()

                Button(monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                    if monitor.isMonitoring {
                        monitor.stop(configId: config.id)
                    } else {
                        monitor.start(config: config) { _ in
                            // Encoding trigger handled by app coordinator.
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.isMonitoring ? .red : .green)
            }
            .padding(8)
        }
    }

    // MARK: - Activity Log

    /// Table of recently detected and processed files.
    private var activityLogSection: some View {
        GroupBox("Activity Log") {
            if logEntries.isEmpty {
                Text("No activity yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Table(logEntries) {
                    TableColumn("File") { entry in
                        Text(entry.filePath.lastPathComponent)
                            .lineLimit(1)
                    }
                    TableColumn("Status") { entry in
                        Text(entry.status.rawValue.capitalized)
                    }
                    .width(100)
                    TableColumn("Time") { entry in
                        Text(entry.detectedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        ))
                    }
                    .width(80)
                }
                .frame(minHeight: 150)
            }

            HStack {
                Spacer()
                Button("Clear Log") {
                    monitor.clearLog()
                    logEntries = []
                }
                .disabled(logEntries.isEmpty)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    /// Describes which directory picker is being invoked.
    private enum DirectoryPickerTarget {
        case watch
        case output
    }

    /// Presents an NSOpenPanel to choose a directory.
    private func chooseDirectory(for target: DirectoryPickerTarget, index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch target {
        case .watch:
            configs[index].watchPath = url.path
        case .output:
            configs[index].outputPath = url.path
        }

        saveConfigs()
    }

    /// Adds a new watch folder configuration with default values.
    private func addNewConfig() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let newConfig = WatchFolderConfig(
            name: "Watch Folder \(configs.count + 1)",
            watchPath: home.appendingPathComponent("Downloads").path,
            outputPath: home.appendingPathComponent("Movies/Encoded").path,
            profileName: "webStandard",
            fileExtensions: ["mp4", "mkv", "mov"]
        )
        configs.append(newConfig)
        selectedConfigId = newConfig.id
        saveConfigs()
    }

    /// Deletes a watch folder configuration.
    private func deleteConfig(_ config: WatchFolderConfig) {
        monitor.stop(configId: config.id)
        configs.removeAll { $0.id == config.id }
        if selectedConfigId == config.id {
            selectedConfigId = configs.first?.id
        }
        saveConfigs()
    }

    /// Persists current configurations to disk.
    private func saveConfigs() {
        try? monitor.saveConfigs(configs)
    }
}

// MARK: - WatchFolderRow

/// A single row in the watch folder list sidebar.
///
/// Shows the name, watch path, and a small status indicator.
private struct WatchFolderRow: View {

    /// The watch folder configuration to display.
    let config: WatchFolderConfig

    /// Whether the monitor is currently active.
    let isMonitoring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: config.isActive ? "folder.fill" : "folder")
                    .foregroundStyle(config.isActive ? .blue : .secondary)

                Text(config.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(config.watchPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}
