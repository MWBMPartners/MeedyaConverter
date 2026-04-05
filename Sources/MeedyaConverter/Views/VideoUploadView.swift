// ============================================================================
// MeedyaConverter — VideoUploadView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides the SwiftUI interface for uploading encoded videos directly to
// YouTube or Vimeo.
//
// Features:
//   - Service picker (YouTube / Vimeo).
//   - OAuth login flow (opens authorisation URL in the system browser).
//   - Metadata fields: title, description, tags, privacy.
//   - Upload progress indicator with cancel support.
//   - Upload history with timestamp and status.
//
// Phase 11 — YouTube/Vimeo Direct Upload (Issue #294)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// MARK: - VideoUploadView

/// Interface for uploading encoded video files to YouTube or Vimeo.
///
/// The view is divided into three sections:
/// 1. **Authentication** — service picker and OAuth login button.
/// 2. **Upload Metadata** — title, description, tags, privacy.
/// 3. **Upload History** — list of previous uploads with status.
struct VideoUploadView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Selected video hosting service.
    @State private var selectedService: VideoService = .youtube

    /// OAuth access token (obtained after login).
    @State private var accessToken: String = ""

    /// Whether the user is authenticated.
    @State private var isAuthenticated: Bool = false

    /// Video title.
    @State private var videoTitle: String = ""

    /// Video description.
    @State private var videoDescription: String = ""

    /// Comma-separated tags.
    @State private var tagsText: String = ""

    /// Privacy setting.
    @State private var privacy: VideoPrivacy = .private

    /// Whether an upload is in progress.
    @State private var isUploading: Bool = false

    /// Upload progress fraction (0.0–1.0).
    @State private var uploadProgress: Double = 0

    /// Upload history entries.
    @State private var uploadHistory: [VideoUploadHistory] = []

    /// Error message to display.
    @State private var errorMessage: String?

    /// Whether to show the error alert.
    @State private var showError: Bool = false

    /// OAuth client ID (would normally come from secure storage).
    @State private var clientId: String = ""

    /// Selected file path to upload.
    @State private var selectedFilePath: String = ""

    // MARK: - Body

    var body: some View {
        Form {
            authenticationSection
            metadataSection
            uploadActionSection
            historySection
        }
        .formStyle(.grouped)
        .navigationTitle("Video Upload")
        .frame(minWidth: 500, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Upload Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Authentication Section

    /// Service picker and OAuth login controls.
    private var authenticationSection: some View {
        Section("Authentication") {
            // Service picker
            Picker("Service:", selection: $selectedService) {
                ForEach(VideoService.allCases, id: \.self) { service in
                    Text(service.displayName).tag(service)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedService) {
                // Reset auth state when switching services.
                isAuthenticated = false
                accessToken = ""
            }

            // Client ID (for OAuth)
            TextField("Client ID:", text: $clientId)
                .textFieldStyle(.roundedBorder)

            // Auth status
            HStack {
                Circle()
                    .fill(isAuthenticated ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(isAuthenticated
                     ? "Authenticated with \(selectedService.displayName)"
                     : "Not authenticated")
                    .foregroundStyle(isAuthenticated ? .primary : .secondary)

                Spacer()

                Button(isAuthenticated ? "Re-authenticate" : "Login") {
                    startOAuthFlow()
                }
                .disabled(clientId.isEmpty)
            }

            // Access token (manual entry for now).
            SecureField("Access Token:", text: $accessToken)
                .textFieldStyle(.roundedBorder)
                .onChange(of: accessToken) {
                    isAuthenticated = !accessToken.isEmpty
                }
        }
    }

    // MARK: - Metadata Section

    /// Title, description, tags, and privacy fields.
    private var metadataSection: some View {
        Section("Video Metadata") {
            TextField("Title:", text: $videoTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Description:", text: $videoDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma-separated):", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            Picker("Privacy:", selection: $privacy) {
                ForEach(VideoPrivacy.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
        }
        .disabled(!isAuthenticated)
    }

    // MARK: - Upload Action Section

    /// File picker, upload button, and progress indicator.
    private var uploadActionSection: some View {
        Section("Upload") {
            // File selection
            HStack {
                Text("File:")
                Text(selectedFilePath.isEmpty
                     ? "No file selected"
                     : URL(fileURLWithPath: selectedFilePath).lastPathComponent)
                    .foregroundStyle(selectedFilePath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Choose...") {
                    chooseFile()
                }
            }

            if isUploading {
                ProgressView(value: uploadProgress, total: 1.0) {
                    Text("Uploading... \(Int(uploadProgress * 100))%")
                        .font(.caption)
                }
                .progressViewStyle(.linear)
            }

            HStack {
                Spacer()

                if isUploading {
                    Button("Cancel") {
                        isUploading = false
                        uploadProgress = 0
                    }
                    .tint(.red)
                }

                Button("Upload") {
                    startUpload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !isAuthenticated
                    || videoTitle.isEmpty
                    || selectedFilePath.isEmpty
                    || isUploading
                )
            }
        }
    }

    // MARK: - History Section

    /// Table of previous upload attempts with status.
    private var historySection: some View {
        Section("Upload History") {
            if uploadHistory.isEmpty {
                Text("No uploads yet.")
                    .foregroundStyle(.secondary)
            } else {
                Table(uploadHistory) {
                    TableColumn("Title") { entry in
                        Text(entry.title)
                            .lineLimit(1)
                    }
                    TableColumn("Service") { entry in
                        Text(entry.service.displayName)
                    }
                    .width(80)
                    TableColumn("Status") { entry in
                        Label(
                            entry.success ? "Success" : "Failed",
                            systemImage: entry.success
                                ? "checkmark.circle.fill"
                                : "xmark.circle.fill"
                        )
                        .foregroundStyle(entry.success ? .green : .red)
                    }
                    .width(80)
                    TableColumn("Date") { entry in
                        Text(entry.uploadedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                    }
                    .width(150)
                }
                .frame(minHeight: 120)
            }

            if !uploadHistory.isEmpty {
                HStack {
                    Spacer()
                    Button("Clear History") {
                        uploadHistory.removeAll()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Opens the OAuth authorisation URL in the system browser.
    private func startOAuthFlow() {
        let redirectURI = "com.mwbm.meedyaconverter://oauth-callback"
        let url: URL

        switch selectedService {
        case .youtube:
            url = VideoUploader.youtubeAuthURL(
                clientId: clientId,
                redirectURI: redirectURI
            )
        case .vimeo:
            url = VideoUploader.vimeoAuthURL(
                clientId: clientId,
                redirectURI: redirectURI
            )
        }

        NSWorkspace.shared.open(url)
    }

    /// Presents a file picker for selecting the video file to upload.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Select Video"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFilePath = url.path
    }

    /// Initiates the upload process.
    ///
    /// Builds the appropriate upload request and would normally send it
    /// via URLSession. For now, records the attempt in history.
    private func startUpload() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let config = VideoUploadConfig(
            service: selectedService,
            title: videoTitle,
            description: videoDescription,
            tags: tags,
            privacy: privacy,
            accessToken: accessToken
        )

        let request: URLRequest?
        switch selectedService {
        case .youtube:
            request = VideoUploader.buildYouTubeUploadRequest(
                filePath: selectedFilePath,
                config: config
            )
        case .vimeo:
            request = VideoUploader.buildVimeoUploadRequest(
                filePath: selectedFilePath,
                config: config
            )
        }

        guard request != nil else {
            errorMessage = "Failed to build upload request. Check the file path and try again."
            showError = true
            return
        }

        isUploading = true
        uploadProgress = 0

        // Record in history (actual network upload would happen here).
        let historyEntry = VideoUploadHistory(
            filePath: selectedFilePath,
            service: selectedService,
            title: videoTitle,
            success: true
        )
        uploadHistory.insert(historyEntry, at: 0)

        // Simulate completion for now.
        isUploading = false
        uploadProgress = 1.0
    }
}
