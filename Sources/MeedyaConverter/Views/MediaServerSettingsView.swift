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

    /// The API key manager backing the Keychain-held media server key.
    /// Not `@Observable`, so it never drives a redraw on its own — every
    /// change goes through `refreshKey()`. Mirrors
    /// `MetadataSettingsTab.keyManager` (#506 commit 1).
    @State private var keyManager = APIKeyManager()

    /// What the user is currently typing. Cleared the moment it is saved
    /// or discarded, so a pending key never lingers in memory longer than
    /// it must (mirrors `MetadataSettingsTab.pendingTMDBKey`).
    @State private var pendingAPIKey: String = ""

    /// Whether a key exists right now, via `MediaServerCredentialStore
    /// .currentKey` (Keychain first, the legacy settings-file value only
    /// while it still exists) — NOT the key itself, which is never held
    /// in view state for longer than a single action needs it.
    @State private var hasKey = false

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

    /// The last key save/remove refusal shown in `feedbackMessage`, or nil.
    /// Compared against `feedbackMessage` so a later successful save clears
    /// ONLY its own earlier error — never a connection-test, fetch or scan
    /// message the person may still be reading. (A flag would not do: the
    /// other actions set `feedbackMessage` without knowing about it.)
    @State private var lastKeyFeedback: String?

    // MARK: - Computed Properties

    /// The selected server type derived from the raw `AppStorage` string.
    private var serverType: MediaServerType {
        MediaServerType(rawValue: serverTypeRaw) ?? .plex
    }

    /// Trimmed form of `pendingAPIKey`, used to decide whether Save/Replace
    /// should be enabled and what actually gets stored.
    private var trimmedPendingKey: String {
        pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain-English notice shown when the once-per-launch startup
    /// migration (`AppStartupMigrations`, run from `AppViewModel.init`)
    /// could not move a legacy plaintext key into the Keychain. Its
    /// presence is inferred from the legacy `UserDefaults` value still
    /// being there: a successful migration removes it immediately, so if
    /// it still exists by the time this screen renders, this launch's
    /// migration attempt did not succeed.
    ///
    /// The wording was the #506 plan's (§4) verbatim: "...because the
    /// Keychain didn't accept it. It will be moved automatically when the
    /// Keychain allows." It was changed when `APIKeyManager.storeKey`
    /// gained a second way to fail (refusing because it could not read its
    /// list of saved keys safely): this screen cannot tell which of the two
    /// happened, so blaming the Keychain would sometimes be untrue. The
    /// Activity Log line written at launch (`AppViewModel`) carries the
    /// actual reason. The migration runs once per launch, which is what
    /// "the next time MeedyaConverter starts" promises — no more.
    private var legacyMigrationWarning: String? {
        guard let legacyValue = UserDefaults.standard.string(forKey: MediaServerCredentialStore.legacyDefaultsKey),
              !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return "Your media server key is still in the app's settings file, because it "
            + "could not be moved to the Keychain. MeedyaConverter will try again the "
            + "next time it starts; the Activity Log says why it failed."
    }

    /// Load the persisted media server configuration independent of this
    /// view being on screen — the same `UserDefaults` keys this view's
    /// `@AppStorage` properties bind to, plus the Keychain-held API key
    /// (#506 commit 1 — the key itself no longer lives in `UserDefaults`
    /// at all; see `MediaServerCredentialStore`). Mirrors
    /// `EmailSettingsView.loadSMTPConfig()`.
    ///
    /// Used by `AppViewModel`'s post-encode auto-scan wiring (Issue #295 /
    /// #203) to trigger a library scan without needing a
    /// `MediaServerSettingsView` instance, and by this view's own actions
    /// (Test Connection, Fetch, Trigger Scan) — called ONLY from inside
    /// those actions, never from a computed property read on every
    /// redraw, because after this key moved to the Keychain that would
    /// mean a Keychain read on every SwiftUI redraw of this screen (#506
    /// plan §4). The buttons that call these actions are instead enabled
    /// from `hasKey && !serverHost.isEmpty`, which needs no Keychain
    /// access.
    ///
    /// - Parameters:
    ///   - defaults: Where the non-secret settings, and the legacy
    ///     fallback value, live. Production callers use `.standard`;
    ///     tests can pass an isolated suite.
    ///   - keyManager: Where the Keychain-held key is read from.
    ///     Production callers use a real `APIKeyManager()`; tests can
    ///     pass a fake conforming to `MediaServerKeyStoring`.
    /// - Returns: A configured `MediaServerConfig`, or `nil` if
    ///   `serverHost` or the key is missing.
    static func loadMediaServerConfig(
        defaults: UserDefaults = .standard,
        keyManager: MediaServerKeyStoring = APIKeyManager()
    ) -> MediaServerConfig? {
        let host = defaults.string(forKey: "mediaServerHost") ?? ""
        let apiKey = MediaServerCredentialStore.currentKey(defaults: defaults, store: keyManager) ?? ""
        guard !host.isEmpty, !apiKey.isEmpty else { return nil }

        let typeRaw = defaults.string(forKey: "mediaServerType") ?? MediaServerType.plex.rawValue
        let serverType = MediaServerType(rawValue: typeRaw) ?? .plex
        let port = (defaults.object(forKey: "mediaServerPort") as? Int) ?? serverType.defaultPort
        let useTLS = (defaults.object(forKey: "mediaServerUseTLS") as? Bool) ?? false
        let libraryId = defaults.string(forKey: "mediaServerLibraryId") ?? ""

        return MediaServerConfig(
            serverType: serverType,
            displayName: "\(serverType.displayName) Server",
            host: host,
            port: port,
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

                // The key itself is never `@AppStorage` — that is a
                // plain-text plist in the user's Library (SECURITY.md
                // F-013). It goes to the Keychain via
                // `MediaServerCredentialStore`, same rule as TMDB's tab
                // (`MetadataSettingsTab.providerKeysSection`).
                if hasKey {
                    Label("A key is saved in your Keychain", systemImage: "key.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("A media server key is saved in your Keychain")
                    Text("For your safety the saved key is never shown again. You can "
                         + "replace it by entering a new one, or remove it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let migrationWarning = legacyMigrationWarning {
                    Text(migrationWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(migrationWarning)
                }

                // SecureField, never TextField: a key must not be readable
                // over the user's shoulder or captured in a screen
                // recording.
                SecureField(
                    hasKey ? "Replace the saved key" : "API Key",
                    text: $pendingAPIKey,
                    prompt: Text(apiKeyPlaceholder)
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(hasKey ? "Replace the saved media server API key or token"
                                            : "Media server API key or token")

                HStack {
                    Button(hasKey ? "Replace Key" : "Save Key") { saveKey() }
                        .disabled(trimmedPendingKey.isEmpty)
                        .accessibilityLabel(hasKey ? "Replace the saved media server key"
                                                    : "Save the media server key")
                    if hasKey {
                        Button("Remove Key", role: .destructive) { removeKey() }
                            .accessibilityLabel("Remove the saved media server key")
                    }
                }

                // Test Connection button.
                HStack {
                    Button {
                        testConnection()
                    } label: {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(!hasKey || serverHost.isEmpty || isTesting)
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
                    .disabled(!hasKey || serverHost.isEmpty || isFetchingLibraries)
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

                if autoScan && (!hasKey || serverHost.isEmpty) {
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
                    .disabled(!hasKey || serverHost.isEmpty || isScanning)
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
        .onAppear { refreshKey() }
        // `keyManager` is a long-lived `@State` instance for as long as
        // this screen is open, so it cannot tell us on its own when
        // ANOTHER `APIKeyManager` instance — or the startup migration in
        // `AppViewModel.init`, which constructs its own — changes the
        // media server record. Mirrors `MetadataSettingsTab`'s identical
        // `.onReceive` for TMDB.
        .onReceive(
            NotificationCenter.default.publisher(for: APIKeyManager.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            refreshKey()
        }
    }

    // MARK: - Key management (#506 commit 1)

    /// Re-reads whether a key is saved, via `MediaServerCredentialStore
    /// .currentKey` — Keychain first, the legacy settings-file value only
    /// while it still exists. Mirrors `MetadataSettingsTab.refreshKeys()`:
    /// without this, `keyManager` being a long-lived `@State` instance
    /// means the screen could go on showing stale information after some
    /// OTHER `APIKeyManager` instance (or the startup migration) wrote
    /// here.
    private func refreshKey() {
        let stored = MediaServerCredentialStore.currentKey(defaults: .standard, store: keyManager)
        hasKey = !(stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Save (or replace) the media server key. Always via
    /// `MediaServerCredentialStore.saveKey`, which writes to the Keychain
    /// only.
    ///
    /// A refusal (`APIKeyStoreError`: the list of saved keys could not be
    /// read safely, so nothing was changed) is shown in this screen's
    /// existing feedback line, in red, rather than being lost. The typed
    /// key then stays in the (secure) field so trying again is one click.
    /// Success does not write a "saved" message: the "A key is saved"
    /// label that `refreshKey()` shows is the confirmation, and it comes
    /// from reading the key back rather than from assuming.
    private func saveKey() {
        let key = trimmedPendingKey
        guard !key.isEmpty else { return }
        do {
            try MediaServerCredentialStore.saveKey(key, store: keyManager)
            pendingAPIKey = ""
            // Clear an earlier refusal message so it cannot linger beside a
            // key that did save. Only a key-related message is ours to
            // clear; see `clearKeyFeedback()`.
            clearKeyFeedback()
        } catch {
            showKeyFeedback("The key was not saved. " + error.localizedDescription)
        }
        refreshKey()
    }

    /// Remove the saved media server key. A refusal is reported exactly as
    /// in `saveKey()`.
    private func removeKey() {
        do {
            try MediaServerCredentialStore.removeKey(store: keyManager)
            pendingAPIKey = ""
            clearKeyFeedback()
        } catch {
            // "did not finish": `removeKey(store:)` makes two calls, and in
            // principle the second could refuse after the first worked.
            // `refreshKey()` below shows what is actually saved now.
            showKeyFeedback("Removing the key did not finish. " + error.localizedDescription)
        }
        refreshKey()
    }

    /// Shows a key save/remove refusal in the shared feedback line, and
    /// remembers exactly what was shown (see `lastKeyFeedback`).
    private func showKeyFeedback(_ message: String) {
        feedbackMessage = message
        feedbackIsError = true
        lastKeyFeedback = message
    }

    /// Clears the feedback line, but only while it still shows the key
    /// refusal this screen last put there. If a connection test, fetch or
    /// scan has replaced it since, that newer message is left alone.
    private func clearKeyFeedback() {
        if let lastKeyFeedback, feedbackMessage == lastKeyFeedback {
            feedbackMessage = nil
            feedbackIsError = false
        }
        lastKeyFeedback = nil
    }

    // MARK: - Actions

    /// Test connectivity to the configured media server.
    private func testConnection() {
        // Built here, inside the action, rather than read from a computed
        // property on every redraw — see `loadMediaServerConfig`'s doc
        // comment for why that would now mean a Keychain read on every
        // redraw of this screen.
        guard let config = Self.loadMediaServerConfig(keyManager: keyManager) else { return }
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
        guard let config = Self.loadMediaServerConfig(keyManager: keyManager) else { return }
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
        guard let config = Self.loadMediaServerConfig(keyManager: keyManager) else { return }
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
