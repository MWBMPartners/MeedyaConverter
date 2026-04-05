// ============================================================================
// MeedyaConverter — MediaServerSettingsView (Issue #295)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MediaServerSettingsView

/// Settings view for configuring Plex, Jellyfin, and Emby media server
/// integrations.
///
/// Provides server type selection, URL and API key inputs, library
/// fetching and selection, connection testing, manual scan triggering,
/// and an auto-scan toggle for post-encode automation.
///
/// Uses the existing `MediaServerType` and `MediaServerConfig` types
/// from `MediaServerNotifier`, and the `MediaServerIntegration` utility
/// for library listing.
///
/// Phase 17 — Media Server Integration (Issue #295)
struct MediaServerSettingsView: View {

    // MARK: - State

    /// The selected media server type.
    @AppStorage("mediaServerType") private var serverTypeRaw = MediaServerType.plex.rawValue

    /// The media server host (e.g. "192.168.1.10").
    @AppStorage("mediaServerHost") private var serverHost = ""

    /// The media server port.
    @AppStorage("mediaServerPort") private var serverPort = 32400

    /// Whether to use TLS (https) for the connection.
    @AppStorage("mediaServerUseTLS") private var useTLS = false

    /// The API key or authentication token.
    @AppStorage("mediaServerAPIKey") private var apiKey = ""

    /// The selected library ID (Plex section or Jellyfin/Emby folder).
    @AppStorage("mediaServerLibraryId") private var libraryId = ""

    /// Whether to automatically trigger a library scan after each successful encode.
    @AppStorage("mediaServerAutoScan") private var autoScan = false

    /// The list of available libraries fetched from the server.
    @State private var availableLibraries: [(id: String, name: String)] = []

    /// Whether libraries are currently being fetched.
    @State private var isFetchingLibraries = false

    /// Whether a connection test is in progress.
    @State private var isTesting = false

    /// Whether a manual scan trigger is in progress.
    @State private var isScanning = false

    /// Feedback message from the last operation (test, fetch, or scan).
    @State private var feedbackMessage: String?

    /// Whether the feedback indicates an error.
    @State private var feedbackIsError = false

    // MARK: - Computed Properties

    /// The selected server type derived from the raw `AppStorage` string.
    private var serverType: MediaServerType {
        MediaServerType(rawValue: serverTypeRaw) ?? .plex
    }

    /// Build a `MediaServerConfig` from the current settings, or `nil` if invalid.
    private var currentConfig: MediaServerConfig? {
        guard !serverHost.isEmpty, !apiKey.isEmpty else { return nil }
        return MediaServerConfig(
            serverType: serverType,
            displayName: "\(serverType.displayName) Server",
            host: serverHost,
            port: serverPort,
            apiKey: apiKey,
            useTLS: useTLS,
            libraryID: libraryId.isEmpty ? nil : libraryId
        )
    }

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Server Type
            Section("Media Server") {
                Picker("Server Type", selection: Binding(
                    get: { serverType },
                    set: { newValue in
                        serverTypeRaw = newValue.rawValue
                        serverPort = newValue.defaultPort
                        availableLibraries = []
                        libraryId = ""
                    }
                )) {
                    ForEach(MediaServerType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Media server type")
            }

            // MARK: Connection Details
            Section("Connection") {
                TextField("Host", text: $serverHost, prompt: Text("192.168.1.10"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Media server hostname or IP address")

                HStack {
                    TextField("Port", value: $serverPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityLabel("Media server port number")

                    Toggle("Use TLS", isOn: $useTLS)
                        .accessibilityLabel("Connect using HTTPS")
                }

                SecureField("API Key", text: $apiKey, prompt: Text(apiKeyPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Media server API key or token")

                // Test Connection button.
                HStack {
                    Button {
                        testConnection()
                    } label: {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(currentConfig == nil || isTesting)
                    .accessibilityLabel("Test connectivity to the media server")

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            // MARK: Library Selection
            Section("Library") {
                HStack {
                    if availableLibraries.isEmpty {
                        Text("No libraries loaded.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Library", selection: $libraryId) {
                            Text("All Libraries").tag("")
                            ForEach(availableLibraries, id: \.id) { library in
                                Text(library.name).tag(library.id)
                            }
                        }
                        .accessibilityLabel("Select a specific library to refresh")
                    }

                    Spacer()

                    Button {
                        fetchLibraries()
                    } label: {
                        Label("Fetch", systemImage: "arrow.clockwise")
                    }
                    .disabled(currentConfig == nil || isFetchingLibraries)
                    .accessibilityLabel("Fetch available libraries from the server")

                    if isFetchingLibraries {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            // MARK: Automation
            Section("Automation") {
                Toggle("Auto-scan after successful encode", isOn: $autoScan)
                    .accessibilityLabel("Automatically trigger a library scan after each successful encode")

                if autoScan && currentConfig == nil {
                    Text("Configure a valid host and API key to enable auto-scan.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // MARK: Manual Actions
            Section("Manual Actions") {
                HStack {
                    Button {
                        triggerScan()
                    } label: {
                        Label("Trigger Library Scan Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(currentConfig == nil || isScanning)
                    .accessibilityLabel("Manually trigger a library scan on the media server")

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            // MARK: Feedback
            if let message = feedbackMessage {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(feedbackIsError ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Media Server")
    }

    // MARK: - Actions

    /// Test connectivity to the configured media server.
    private func testConnection() {
        guard let config = currentConfig else { return }
        isTesting = true
        feedbackMessage = nil

        Task {
            do {
                let reachable = try await MediaServerIntegration.testConnection(config: config)
                await MainActor.run {
                    if reachable {
                        feedbackMessage = "Connection successful."
                        feedbackIsError = false
                    } else {
                        feedbackMessage = "Server responded but connection test failed."
                        feedbackIsError = true
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = "Connection failed: \(error.localizedDescription)"
                    feedbackIsError = true
                    isTesting = false
                }
            }
        }
    }

    /// Fetch the list of available libraries from the media server.
    private func fetchLibraries() {
        guard let config = currentConfig else { return }
        isFetchingLibraries = true
        feedbackMessage = nil

        Task {
            do {
                let libraries = try await MediaServerIntegration.listLibraries(config: config)
                await MainActor.run {
                    availableLibraries = libraries
                    feedbackMessage = "Found \(libraries.count) \(libraries.count == 1 ? "library" : "libraries")."
                    feedbackIsError = false
                    isFetchingLibraries = false
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = "Failed to fetch libraries: \(error.localizedDescription)"
                    feedbackIsError = true
                    isFetchingLibraries = false
                }
            }
        }
    }

    /// Manually trigger a library scan on the configured media server.
    private func triggerScan() {
        guard let config = currentConfig else { return }
        isScanning = true
        feedbackMessage = nil

        Task {
            do {
                try await MediaServerIntegration.triggerLibraryScan(config: config)
                await MainActor.run {
                    feedbackMessage = "Library scan triggered successfully."
                    feedbackIsError = false
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = "Scan failed: \(error.localizedDescription)"
                    feedbackIsError = true
                    isScanning = false
                }
            }
        }
    }

    // MARK: - Display Helpers

    /// Placeholder text for the API key field based on the selected type.
    private var apiKeyPlaceholder: String {
        switch serverType {
        case .plex: return "X-Plex-Token"
        case .jellyfin: return "Jellyfin API Key"
        case .emby: return "Emby API Key"
        }
    }
}
