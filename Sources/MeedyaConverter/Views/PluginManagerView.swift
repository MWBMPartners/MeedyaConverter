// ============================================================================
// MeedyaConverter — PluginManagerView (Issue #353)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// UI for managing MeedyaConverter plugins. Displays a list of loaded
// plugins with their name, version, and description. Provides controls
// to add new plugin bundles (via file picker), remove plugins, and
// view plugin details.
//
// The view uses a two-column layout: a plugin list on the left and a
// detail pane on the right. Each plugin row shows an enable/disable
// toggle, and the detail pane shows full metadata.
//
// Phase 15 — Plugin System for Custom Processing (Issue #353)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - PluginManagerView
// ---------------------------------------------------------------------------
/// Plugin management interface for viewing, adding, and removing plugins.
///
/// Presents a list of all registered plugins from the ``PluginManager``
/// with controls for adding plugin bundles, removing selected plugins,
/// and inspecting plugin details.
///
/// ### Layout
/// - **Left column**: Scrollable plugin list with name, version, and
///   enable/disable toggle.
/// - **Right column**: Detail pane showing full metadata for the
///   selected plugin.
/// - **Toolbar**: Add and remove buttons.
struct PluginManagerView: View {

    // MARK: - State

    /// The plugin manager instance. Created locally for standalone use;
    /// in production, this would be injected via the environment.
    @State private var pluginManager = PluginManager()

    /// The ID of the currently selected plugin for the detail pane.
    @State private var selectedPluginID: String?

    /// Set of disabled plugin IDs. Disabled plugins remain registered
    /// but are excluded from pipeline execution.
    @State private var disabledPluginIDs: Set<String> = []

    /// Whether the file picker for adding a plugin bundle is presented.
    @State private var showAddPluginPicker = false

    /// Whether the remove confirmation alert is presented.
    @State private var showRemoveConfirmation = false

    /// Error message from the most recent operation, if any.
    @State private var errorMessage: String?

    /// Whether the error alert is presented.
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            pluginListSidebar
        } detail: {
            pluginDetailView
        }
        .navigationTitle("Plugin Manager")
        .frame(minWidth: 700, minHeight: 400)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                pluginToolbar
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Remove Plugin", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                removeSelectedPlugin()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this plugin? This action cannot be undone.")
        }
        .onAppear {
            pluginManager.loadPlugins()
            // Register the example plugin for demonstration.
            pluginManager.register(TimestampMetadataPlugin())
        }
    }

    // MARK: - Plugin List Sidebar

    /// Scrollable list of loaded plugins with enable/disable toggles.
    private var pluginListSidebar: some View {
        List(selection: $selectedPluginID) {
            if pluginManager.loadedPlugins.isEmpty {
                ContentUnavailableView(
                    "No Plugins Loaded",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Add plugin bundles using the + button in the toolbar.")
                )
            } else {
                ForEach(pluginManager.loadedPlugins, id: \.id) { plugin in
                    pluginRow(plugin)
                        .tag(plugin.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250)
    }

    /// A single plugin row showing name, version, and enable/disable toggle.
    ///
    /// - Parameter plugin: The plugin to display.
    /// - Returns: A row view with plugin metadata and toggle.
    private func pluginRow(_ plugin: any MeedyaPlugin) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.headline)
                Text("v\(plugin.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { !disabledPluginIDs.contains(plugin.id) },
                set: { enabled in
                    if enabled {
                        disabledPluginIDs.remove(plugin.id)
                    } else {
                        disabledPluginIDs.insert(plugin.id)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Enable \(plugin.name)")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Plugin Detail View

    /// Detail pane showing full metadata for the selected plugin.
    @ViewBuilder
    private var pluginDetailView: some View {
        if let pluginID = selectedPluginID,
           let plugin = pluginManager.loadedPlugins.first(where: { $0.id == pluginID }) {
            Form {
                Section("Plugin Information") {
                    LabeledContent("Name", value: plugin.name)
                    LabeledContent("Version", value: plugin.version)
                    LabeledContent("Identifier", value: plugin.id)
                }

                Section("Description") {
                    Text(plugin.description)
                        .foregroundStyle(.secondary)
                }

                Section("Status") {
                    LabeledContent("Enabled") {
                        Image(systemName: disabledPluginIDs.contains(plugin.id) ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(disabledPluginIDs.contains(plugin.id) ? .red : .green)
                    }
                }

                Section("Additional FFmpeg Arguments") {
                    let args = plugin.additionalArguments()
                    if args.isEmpty {
                        Text("None")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(args.joined(separator: " "))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(plugin.name)
        } else {
            ContentUnavailableView(
                "Select a Plugin",
                systemImage: "puzzlepiece.extension",
                description: Text("Choose a plugin from the sidebar to view its details.")
            )
        }
    }

    // MARK: - Toolbar

    /// Toolbar items for adding and removing plugins.
    @ViewBuilder
    private var pluginToolbar: some View {
        // Add plugin button.
        Button {
            showAddPluginPicker = true
        } label: {
            Label("Add Plugin", systemImage: "plus")
        }
        .fileImporter(
            isPresented: $showAddPluginPicker,
            allowedContentTypes: [.bundle],
            allowsMultipleSelection: false
        ) { result in
            handlePluginImport(result)
        }
        .accessibilityLabel("Add a plugin bundle")

        // Remove plugin button.
        Button {
            showRemoveConfirmation = true
        } label: {
            Label("Remove Plugin", systemImage: "minus")
        }
        .disabled(selectedPluginID == nil)
        .accessibilityLabel("Remove selected plugin")
    }

    // MARK: - Actions

    /// Handles the result of the file importer for adding plugin bundles.
    ///
    /// Copies the selected bundle to the plugin directory and reloads
    /// plugins from disk.
    ///
    /// - Parameter result: The file importer result containing the
    ///   selected URL or error.
    private func handlePluginImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }

            let pluginDir = PluginManager.defaultPluginDirectory
            let destinationURL = pluginDir.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: true
            )

            do {
                let fileManager = FileManager.default

                // Ensure plugin directory exists.
                if !fileManager.fileExists(atPath: pluginDir.path) {
                    try fileManager.createDirectory(
                        at: pluginDir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }

                // Copy bundle to plugin directory.
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)

                // Reload plugins.
                pluginManager.loadPlugins()
            } catch {
                errorMessage = "Failed to install plugin: \(error.localizedDescription)"
                showError = true
            }

        case .failure(let error):
            errorMessage = "Failed to select plugin: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Removes the currently selected plugin from the manager and
    /// optionally from disk.
    private func removeSelectedPlugin() {
        guard let pluginID = selectedPluginID else { return }
        pluginManager.unregister(id: pluginID)
        selectedPluginID = nil
    }
}
