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

    /// The list of saved cloud storage configurations.
    @State private var savedConfigs: [CloudStorageConfig] = []

    /// The index of the currently selected saved configuration.
    @State private var selectedConfigIndex: Int?

    /// Whether an upload is currently in progress.
    @State private var isUploading = false

    /// Upload progress fraction from 0.0 to 1.0.
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
    @ViewBuilder
    private var uploadSection: some View {
        Section("Upload") {
            if isUploading {
                ProgressView(value: uploadProgress) {
                    Text("Uploading...")
                } currentValueLabel: {
                    Text("\(Int(uploadProgress * 100))%")
                }
            }

            Button {
                // Upload is triggered from the main conversion flow;
                // this button validates the configuration.
                validateConfig()
            } label: {
                Label("Test Configuration", systemImage: "checkmark.circle")
            }
            .disabled(accessToken.isEmpty || remotePath.isEmpty)
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

    /// Validate the current configuration by attempting to build a request.
    private func validateConfig() {
        let config = CloudStorageConfig(
            provider: selectedProvider,
            accessToken: accessToken,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            remotePath: remotePath,
            label: label
        )

        let testRequest: URLRequest?
        switch selectedProvider {
        case .dropbox:
            testRequest = CloudStorageUploader.buildDropboxUploadRequest(
                filePath: "test.mp4",
                config: config
            )
        case .onedrive:
            testRequest = CloudStorageUploader.buildOneDriveUploadRequest(
                filePath: "test.mp4",
                config: config
            )
        case .googleDrive:
            testRequest = CloudStorageUploader.buildGoogleDriveUploadRequest(
                filePath: "test.mp4",
                config: config
            )
        }

        if testRequest != nil {
            statusMessage = "Configuration is valid. Upload request can be built."
            isError = false
        } else {
            statusMessage = "Invalid configuration. Could not build upload request."
            isError = true
        }
    }

    /// Save the current form state as a new configuration.
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

    /// Delete the currently selected saved configuration.
    private func deleteSelectedConfig() {
        guard let idx = selectedConfigIndex, idx < savedConfigs.count else { return }
        savedConfigs.remove(at: idx)
        selectedConfigIndex = nil
        statusMessage = "Configuration deleted."
        isError = false
    }
}
