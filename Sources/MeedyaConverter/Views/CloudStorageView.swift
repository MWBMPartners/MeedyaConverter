// ============================================================================
// MeedyaConverter — CloudStorageView (Issue #347)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - CloudStorageView

/// Settings view for configuring Dropbox, OneDrive, and Google Drive uploads.
///
/// Provides a provider picker, OAuth authorisation flow, remote folder
/// browser, upload progress display, and management of saved upload
/// configurations.
///
/// Phase 12.4 — Dropbox/OneDrive/Google Drive Upload (Issue #347)
struct CloudStorageView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openURL) private var openURL

    // MARK: - State

    /// The selected cloud storage provider.
    @State private var selectedProvider: CloudStorageProvider = .dropbox

    /// The OAuth client ID for the selected provider.
    @State private var clientId = ""

    /// The OAuth access token obtained from the authorisation flow.
    @State private var accessToken = ""

    /// The OAuth refresh token (if provided by the authorisation flow).
    @State private var refreshToken = ""

    /// The remote folder path where files will be uploaded.
    @State private var remotePath = "/"

    /// A user-facing label for this saved configuration.
    @State private var label = ""

    /// The list of saved cloud storage configurations. Hydrated from
    /// `CloudStorageProfileStore` on appear and persisted through
    /// `persistConfigs()` (Issue #459) — before #459 this array was
    /// pure `@State` and never survived an app relaunch.
    @State private var savedConfigs: [CloudStorageConfig] = []

    /// The index of the currently selected saved configuration.
    @State private var selectedConfigIndex: Int?

    /// The Keychain-backed store for provider OAuth tokens (Issue
    /// #459). `@State` so this class instance — and the `keys` it
    /// caches after `loadKeys()` — survives across this view's body
    /// re-evaluations, matching the `@State private var manager = ...`
    /// pattern already used by `ThemeSettingsView` / `PluginManagerView`
    /// / `RecentFilesView` for other on-disk-backed managers.
    @State private var apiKeyManager = APIKeyManager()

    /// The local file path to test-upload via the real executor.
    /// Defaults to the currently selected source file (if any) so the
    /// common case — "upload the file I'm already working with" — needs
    /// no extra picking.
    @State private var uploadFilePath = ""

    /// Whether an upload is currently in progress.
    @State private var isUploading = false

    /// Upload progress fraction from 0.0 to 1.0, driven by real
    /// `CloudUploadExecutor` progress callbacks (see `performUpload()`).
    @State private var uploadProgress: Double = 0.0

    /// Status message from the last operation.
    @State private var statusMessage: String?

    /// Whether the status represents an error.
    @State private var isError = false

    /// Whether to show the delete confirmation dialog.
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        HSplitView {
            savedConfigsList
                .frame(minWidth: 200, maxWidth: 280)

            Form {
                providerSection
                authSection
                destinationSection
                uploadSection
                statusSection
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Cloud Storage")
        .onAppear {
            loadSavedConfigsFromDisk()
            hydrateTokenForSelectedProvider()
            if uploadFilePath.isEmpty, let selected = viewModel.selectedFile {
                uploadFilePath = selected.fileURL.path
            }
        }
        .onChange(of: selectedProvider) { _, _ in
            hydrateTokenForSelectedProvider()
        }
    }

    // MARK: - Saved Configurations List

    /// Sidebar list of saved cloud storage configurations.
    @ViewBuilder
    private var savedConfigsList: some View {
        VStack(alignment: .leading) {
            Text("Saved Configurations")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            List(selection: $selectedConfigIndex) {
                ForEach(Array(savedConfigs.enumerated()), id: \.offset) { index, config in
                    HStack {
                        Image(systemName: providerIcon(config.provider))
                        VStack(alignment: .leading) {
                            Text(config.label)
                                .font(.body)
                            Text(config.provider.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(index)
                }
            }
            .onChange(of: selectedConfigIndex) { _, newValue in
                if let idx = newValue, idx < savedConfigs.count {
                    loadConfig(savedConfigs[idx])
                }
            }

            HStack {
                Button {
                    saveCurrentConfig()
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedConfigIndex == nil)
                .confirmationDialog(
                    "Delete this configuration?",
                    isPresented: $showDeleteConfirmation
                ) {
                    Button("Delete", role: .destructive) {
                        deleteSelectedConfig()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Provider Selection

    /// Section for choosing the cloud storage provider.
    @ViewBuilder
    private var providerSection: some View {
        Section("Provider") {
            Picker("Cloud Provider", selection: $selectedProvider) {
                ForEach(CloudStorageProvider.allCases, id: \.self) { provider in
                    Label(providerDisplayName(provider), systemImage: providerIcon(provider))
                        .tag(provider)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - OAuth Authorisation

    /// Section for managing the OAuth authorisation flow.
    @ViewBuilder
    private var authSection: some View {
        Section("Authorisation") {
            TextField("OAuth Client ID", text: $clientId)
                .textFieldStyle(.roundedBorder)

            Button("Authorise with \(providerDisplayName(selectedProvider))") {
                startOAuthFlow()
            }
            .disabled(clientId.isEmpty)

            TextField("Access Token", text: $accessToken)
                .textFieldStyle(.roundedBorder)

            TextField("Refresh Token (optional)", text: $refreshToken)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Destination

    /// Section for configuring the remote upload destination.
    @ViewBuilder
    private var destinationSection: some View {
        Section("Destination") {
            TextField("Remote Folder Path", text: $remotePath)
                .textFieldStyle(.roundedBorder)

            TextField("Label (e.g., \"Work Dropbox\")", text: $label)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Upload

    /// Section with upload controls and progress display.
    ///
    /// Issue #459: this used to only validate that a `URLRequest` could
    /// be built ("Test Configuration") — it never sent anything, so a
    /// wrong path, an expired token, or a real server-side rejection
    /// all reported the same fake success. The button now binds to
    /// `performUpload()`, which executes a real, authenticated transfer
    /// via `CloudUploadExecutor` and reports the real outcome.
    @ViewBuilder
    private var uploadSection: some View {
        Section("Upload") {
            HStack {
                TextField("File to Upload", text: $uploadFilePath, prompt: Text("/path/to/output.mp4"))
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    browseForFile()
                }
            }

            if isUploading {
                ProgressView(value: uploadProgress) {
                    Text("Uploading...")
                } currentValueLabel: {
                    Text("\(Int(uploadProgress * 100))%")
                }
            }

            Button {
                performUpload()
            } label: {
                Label("Upload File", systemImage: "arrow.up.circle")
            }
            .disabled(accessToken.isEmpty || remotePath.isEmpty || uploadFilePath.isEmpty || isUploading)
        }
    }

    // MARK: - Status

    /// Section displaying the operation status.
    @ViewBuilder
    private var statusSection: some View {
        if let message = statusMessage {
            Section("Status") {
                HStack {
                    Image(systemName: isError
                          ? "exclamationmark.triangle"
                          : "checkmark.circle")
                        .foregroundStyle(isError ? .red : .green)
                    Text(message)
                        .foregroundStyle(isError ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Return the SF Symbol name for a provider.
    private func providerIcon(_ provider: CloudStorageProvider) -> String {
        switch provider {
        case .dropbox: return "arrow.down.doc"
        case .onedrive: return "cloud"
        case .googleDrive: return "externaldrive"
        }
    }

    /// Return the human-readable display name for a provider.
    private func providerDisplayName(_ provider: CloudStorageProvider) -> String {
        switch provider {
        case .dropbox: return "Dropbox"
        case .onedrive: return "OneDrive"
        case .googleDrive: return "Google Drive"
        }
    }

    /// Start the OAuth 2.0 authorisation flow by opening the browser.
    private func startOAuthFlow() {
        let url = CloudStorageUploader.authURL(
            provider: selectedProvider,
            clientId: clientId
        )
        openURL(url)
        statusMessage = "Opened browser for authorisation. Paste the access token above after granting access."
        isError = false
    }

    /// Opens a file panel to select the local file to test-upload.
    /// Mirrors `SFTPSettingsView.browseForKeyFile()`.
    private func browseForFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            uploadFilePath = url.path
        }
    }

    /// Save the current form state as a new configuration and persist
    /// it (Issue #459): the token goes to the Keychain via
    /// `apiKeyManager`, and the redacted metadata goes to
    /// `UserDefaults` so `PostEncodeActionChain.uploadViaCloud` can
    /// resolve this configuration by id later. See `persistConfigs()`.
    private func saveCurrentConfig() {
        let config = CloudStorageConfig(
            provider: selectedProvider,
            accessToken: accessToken,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            remotePath: remotePath,
            label: label.isEmpty ? providerDisplayName(selectedProvider) : label
        )
        savedConfigs.append(config)
        selectedConfigIndex = savedConfigs.count - 1
        persistConfigs()
        statusMessage = "Configuration saved."
        isError = false
    }

    /// Load a saved configuration into the form fields.
    private func loadConfig(_ config: CloudStorageConfig) {
        selectedProvider = config.provider
        accessToken = config.accessToken
        refreshToken = config.refreshToken ?? ""
        remotePath = config.remotePath
        label = config.label
    }

    /// Delete the currently selected saved configuration, including its
    /// Keychain-stored token. Mirrors
    /// `SFTPSettingsView.deleteProfile(at:)`'s cleanup — without this, a
    /// deleted configuration's token would linger in the Keychain
    /// indefinitely (orphaned but still resident).
    private func deleteSelectedConfig() {
        guard let idx = selectedConfigIndex, idx < savedConfigs.count else { return }
        removeStoredToken(for: savedConfigs[idx])
        savedConfigs.remove(at: idx)
        selectedConfigIndex = nil
        persistConfigs()
        statusMessage = "Configuration deleted."
        isError = false
    }

    // MARK: - Persistence (Issue #459)

    /// `UserDefaults` key under which the redacted configuration array
    /// lives. Sourced from `CloudStorageProfileStore.userDefaultsKey` so
    /// this view and the read-only `CloudStorageProfileStore` used by
    /// `PostEncodeActionChain` can never drift onto different keys.
    private static let userDefaultsKey = CloudStorageProfileStore.userDefaultsKey

    /// Loads saved configurations from `UserDefaults`, restoring each
    /// entry's access/refresh token from the Keychain via
    /// `apiKeyManager`. Delegates to `CloudStorageProfileStore` so the
    /// read path is shared with `PostEncodeActionChain` rather than
    /// reimplemented here.
    private func loadSavedConfigsFromDisk() {
        savedConfigs = CloudStorageProfileStore.loadProfiles(apiKeyManager: apiKeyManager)
    }

    /// Writes the current `savedConfigs` to `UserDefaults` with secrets
    /// redacted, after pushing each entry's real access/refresh token to
    /// the Keychain via `apiKeyManager`. This is the single chokepoint
    /// where a token crosses from `@State` into durable storage — the
    /// same "redact at the point of persistence" pattern
    /// `SFTPSettingsView.persistProfiles()` uses for SFTP passwords —
    /// so there is one place to audit for the #380 invariant ("no
    /// secret in the on-disk JSON").
    private func persistConfigs() {
        var redacted: [CloudStorageConfig] = []

        for config in savedConfigs {
            if !config.accessToken.isEmpty {
                // `clientId` is a single form field shared by every saved
                // configuration in this view, so it must only overwrite
                // the Keychain entry for the configuration currently
                // being edited (matched by provider + label) — otherwise
                // saving one configuration would stamp its Client ID
                // onto every OTHER saved configuration's stored entry
                // too. For any other configuration, preserve whatever
                // apiKey value it already had in the Keychain.
                let apiKeyToStore: String
                if config.provider == selectedProvider && config.label == label {
                    apiKeyToStore = clientId
                } else {
                    apiKeyToStore = apiKeyManager
                        .keys(for: apiKeyProvider(for: config.provider))
                        .first(where: { ($0.label ?? "") == config.label })?
                        .apiKey ?? ""
                }

                apiKeyManager.storeKey(
                    StoredAPIKey(
                        provider: apiKeyProvider(for: config.provider),
                        apiKey: apiKeyToStore,
                        accessToken: config.accessToken,
                        refreshToken: config.refreshToken,
                        label: config.label
                    )
                )
            }
            var copy = config
            copy.accessToken = ""
            copy.refreshToken = nil
            redacted.append(copy)
        }

        if let data = try? JSONEncoder().encode(redacted) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Removes a configuration's Keychain-stored token.
    private func removeStoredToken(for config: CloudStorageConfig) {
        apiKeyManager.removeKey(provider: apiKeyProvider(for: config.provider), label: config.label)
    }

    /// Maps the request-builder-side provider enum to the Keychain-side
    /// one. Delegates to `CloudStorageProfileStore.apiKeyProvider(for:)`
    /// so the mapping lives in exactly one place.
    private func apiKeyProvider(for provider: CloudStorageProvider) -> APIKeyProvider {
        CloudStorageProfileStore.apiKeyProvider(for: provider)
    }

    /// Loads a previously-saved token for `selectedProvider` (if any)
    /// into the client ID / access / refresh token fields, so switching
    /// the provider picker or reopening this view doesn't leave the
    /// user re-pasting a token they already saved.
    private func hydrateTokenForSelectedProvider() {
        let matches = apiKeyManager.keys(for: apiKeyProvider(for: selectedProvider))
        guard let stored = matches.first(where: { ($0.label ?? "") == label }) ?? matches.first else {
            return
        }
        if let token = stored.accessToken, !token.isEmpty {
            accessToken = token
        }
        if let refresh = stored.refreshToken, !refresh.isEmpty {
            refreshToken = refresh
        }
        if !stored.apiKey.isEmpty {
            clientId = stored.apiKey
        }
    }

    // MARK: - Real Upload (Issue #459)

    /// Performs a real, authenticated upload of `uploadFilePath` using
    /// the currently-configured provider, via `CloudUploadExecutor`.
    ///
    /// Progress crosses from `CloudUploadExecutor`'s `@Sendable`
    /// callback (invoked on whatever thread `URLSession`'s delegate
    /// queue uses, not necessarily the main actor) into this view's
    /// `@State` via an `AsyncStream` — the documented-safe bridge for
    /// exactly this "background callback into SwiftUI state" shape,
    /// which avoids ever capturing `self` (a non-`Sendable` `View`)
    /// inside a `@Sendable` closure. `AsyncStream.Continuation` is
    /// itself `Sendable`, so it is the only thing the progress closure
    /// captures.
    ///
    /// The upload itself runs in a plain `Task { }` — not
    /// `Task.detached` — created directly from this (main-actor-
    /// isolated, since `CloudStorageView` is a `View`) method, the same
    /// pattern `SFTPSettingsView.testConnection()` uses for its
    /// connection probe. Unlike that probe's blocking `Process`
    /// invocation, `CloudUploadExecutor`'s work is genuinely `async`
    /// (`URLSession`, no blocking syscalls), so no `Task.detached` hop
    /// off the main actor is needed here.
    private func performUpload() {
        guard !isUploading else { return }
        guard !accessToken.isEmpty else {
            statusMessage = "Enter an access token first."
            isError = true
            return
        }
        guard !uploadFilePath.isEmpty else {
            statusMessage = "Choose a file to upload first."
            isError = true
            return
        }

        let fileURL = URL(fileURLWithPath: uploadFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            statusMessage = "File not found: \(uploadFilePath)"
            isError = true
            return
        }

        let config = CloudStorageConfig(
            provider: selectedProvider,
            accessToken: accessToken,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            remotePath: remotePath,
            label: label.isEmpty ? providerDisplayName(selectedProvider) : label
        )

        isUploading = true
        uploadProgress = 0
        statusMessage = nil
        isError = false

        let (stream, continuation) = AsyncStream<UploadProgress>.makeStream()

        let progressTask = Task {
            for await update in stream {
                uploadProgress = update.fraction
            }
        }

        Task {
            defer { progressTask.cancel() }
            let executor = CloudUploadExecutor()

            do {
                let result = try await executor.uploadToCloudStorage(
                    fileURL: fileURL,
                    config: config
                ) { update in
                    continuation.yield(update)
                }
                continuation.finish()

                isUploading = false
                uploadProgress = 1.0
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeText = formatter.string(fromByteCount: result.fileSize)
                let destination = result.remoteURL ?? config.remotePath
                statusMessage = "Uploaded \(sizeText) to \(destination) "
                    + "(\(String(format: "%.1f", result.uploadDuration))s)."
                isError = false
            } catch {
                continuation.finish()
                isUploading = false
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }
}
