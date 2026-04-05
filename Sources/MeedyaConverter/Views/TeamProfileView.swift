// ============================================================================
// MeedyaConverter — TeamProfileView (Issue #345)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - TeamProfileView

/// Settings view for configuring team shared encoding profile repositories.
///
/// Provides repository configuration (sync method, server URL, shared
/// folder), push/pull buttons, sync status display, a conflict resolution
/// list, and a view of team member activity.
///
/// Phase 14.1 — Team Shared Encoding Profiles (Issue #345)
struct TeamProfileView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The currently selected synchronisation method.
    @State private var syncMethod: SyncMethod = .iCloudSharedFolder

    /// The server URL string for HTTP/Git sync.
    @State private var serverURLString = ""

    /// The shared folder path for iCloud sync.
    @State private var sharedFolderPath = ""

    /// Whether a sync operation is currently in progress.
    @State private var isSyncing = false

    /// The date of the last successful sync.
    @State private var lastSyncDate: Date?

    /// Status message from the last operation.
    @State private var statusMessage: String?

    /// Whether the status represents an error.
    @State private var isError = false

    /// Profiles pulled from the remote repository.
    @State private var remoteProfiles: [EncodingProfile] = []

    /// Profiles with conflicts that need review.
    @State private var conflictedProfiles: [EncodingProfile] = []

    /// Whether to show the conflict resolution sheet.
    @State private var showConflicts = false

    /// The team profile manager instance.
    @State private var manager = TeamProfileManager()

    // MARK: - Body

    var body: some View {
        Form {
            repositorySection
            syncActionsSection
            statusSection
            conflictsSection
            teamActivitySection
        }
        .formStyle(.grouped)
        .navigationTitle("Team Profiles")
    }

    // MARK: - Repository Configuration

    /// Section for configuring the team profile repository connection.
    @ViewBuilder
    private var repositorySection: some View {
        Section {
            Picker("Sync Method", selection: $syncMethod) {
                Text("iCloud Shared Folder")
                    .tag(SyncMethod.iCloudSharedFolder)
                Text("Git Repository")
                    .tag(SyncMethod.gitRepository)
                Text("HTTP Server")
                    .tag(SyncMethod.httpServer)
            }
            .pickerStyle(.segmented)

            switch syncMethod {
            case .iCloudSharedFolder:
                HStack {
                    TextField("Shared Folder Path", text: $sharedFolderPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseForFolder()
                    }
                }

            case .gitRepository, .httpServer:
                TextField(
                    syncMethod == .gitRepository ? "Repository URL" : "Server URL",
                    text: $serverURLString
                )
                .textFieldStyle(.roundedBorder)
            }
        } header: {
            Text("Repository Configuration")
        } footer: {
            Text("Configure how team encoding profiles are shared between machines.")
        }
    }

    // MARK: - Sync Actions

    /// Section with push and pull buttons for syncing profiles.
    @ViewBuilder
    private var syncActionsSection: some View {
        Section("Sync Actions") {
            HStack(spacing: 12) {
                Button {
                    pushProfiles()
                } label: {
                    Label("Push Profiles", systemImage: "arrow.up.circle")
                }
                .disabled(isSyncing)

                Button {
                    pullProfiles()
                } label: {
                    Label("Pull Profiles", systemImage: "arrow.down.circle")
                }
                .disabled(isSyncing)

                Spacer()

                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Status

    /// Section displaying the current sync status.
    @ViewBuilder
    private var statusSection: some View {
        Section("Sync Status") {
            if let lastSync = lastSyncDate {
                LabeledContent("Last Sync") {
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Last Sync") {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }

            if let message = statusMessage {
                HStack {
                    Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(isError ? .red : .green)
                    Text(message)
                        .foregroundStyle(isError ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Conflicts

    /// Section listing profiles with merge conflicts.
    @ViewBuilder
    private var conflictsSection: some View {
        if !conflictedProfiles.isEmpty {
            Section("Conflicts (\(conflictedProfiles.count))") {
                ForEach(conflictedProfiles) { profile in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Resolve All (Use Newest)") {
                    resolveAllConflicts()
                }
            }
        }
    }

    // MARK: - Team Activity

    /// Section showing recent team member activity (placeholder).
    @ViewBuilder
    private var teamActivitySection: some View {
        Section("Team Activity") {
            if remoteProfiles.isEmpty {
                ContentUnavailableView(
                    "No Team Profiles",
                    systemImage: "person.3",
                    description: Text("Pull from the repository to see shared profiles.")
                )
            } else {
                ForEach(remoteProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(profile.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Open a folder browser panel to select the shared folder path.
    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the shared folder for team profiles"

        if panel.runModal() == .OK, let url = panel.url {
            sharedFolderPath = url.path
        }
    }

    /// Build a ``TeamProfileRepository`` from the current form state.
    private func buildRepository() -> TeamProfileRepository {
        TeamProfileRepository(
            serverURL: URL(string: serverURLString),
            sharedFolderPath: sharedFolderPath.isEmpty ? nil : URL(fileURLWithPath: sharedFolderPath),
            syncMethod: syncMethod
        )
    }

    /// Push local profiles to the configured repository.
    private func pushProfiles() {
        isSyncing = true
        statusMessage = nil
        isError = false

        let repository = buildRepository()
        let profiles = viewModel.engine.profileStore.profiles

        Task.detached {
            do {
                let mgr = TeamProfileManager(repository: repository)
                try mgr.pushProfiles(profiles, to: repository)
                await MainActor.run {
                    lastSyncDate = Date()
                    statusMessage = "Pushed \(profiles.count) profiles successfully."
                    isError = false
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isError = true
                    isSyncing = false
                }
            }
        }
    }

    /// Pull profiles from the configured repository.
    private func pullProfiles() {
        isSyncing = true
        statusMessage = nil
        isError = false

        let repository = buildRepository()

        Task.detached {
            do {
                let mgr = TeamProfileManager(repository: repository)
                let pulled = try mgr.pullProfiles(from: repository)
                await MainActor.run {
                    remoteProfiles = pulled
                    lastSyncDate = Date()
                    statusMessage = "Pulled \(pulled.count) profiles."
                    isError = false
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isError = true
                    isSyncing = false
                }
            }
        }
    }

    /// Resolve all conflicts by preferring the newest version.
    private func resolveAllConflicts() {
        let merged = manager.resolveConflicts(
            local: viewModel.engine.profileStore.profiles,
            remote: conflictedProfiles
        )
        conflictedProfiles = []
        statusMessage = "Resolved conflicts. \(merged.count) profiles merged."
        isError = false
    }
}
