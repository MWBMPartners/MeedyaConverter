// ============================================================================
// MeedyaConverter — CloudSyncView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides the SwiftUI interface for managing iCloud Drive-based encoding
// profile synchronisation.
//
// Features:
//   - Enable/disable iCloud sync toggle.
//   - Sync status indicator with coloured dot and description.
//   - Last sync timestamp display.
//   - Manual sync (upload/download) buttons.
//   - Conflict resolution UI showing local vs. remote profile details.
//   - Error handling and user feedback.
//
// Phase 12 — iCloud Drive Profile Sync (Issue #297)
// ---------------------------------------------------------------------------

import SwiftUI
import ConverterEngine

// MARK: - CloudSyncView

/// Interface for managing iCloud Drive profile synchronisation.
///
/// Displays the current sync status, provides manual sync controls,
/// and surfaces any conflicts that need resolution.
struct CloudSyncView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// The shared sync manager instance.
    @State private var syncManager = CloudProfileSync.shared

    /// Whether sync is enabled.
    @State private var isSyncEnabled: Bool = CloudProfileSync.shared.isSyncEnabled

    /// Current sync status.
    @State private var status: CloudSyncStatus = CloudProfileSync.shared.status

    /// Last successful sync date.
    @State private var lastSyncDate: Date? = CloudProfileSync.shared.lastSyncDate

    /// Conflicts detected during sync.
    @State private var conflicts: [CloudSyncConflict] = []

    /// Whether a sync operation is in progress.
    @State private var isSyncing: Bool = false

    /// Error message to display.
    @State private var errorMessage: String?

    /// Whether to show the error alert.
    @State private var showError: Bool = false

    /// Number of profiles uploaded in the last sync.
    @State private var lastUploadCount: Int = 0

    /// Number of profiles downloaded in the last sync.
    @State private var lastDownloadCount: Int = 0

    // MARK: - Body

    var body: some View {
        Form {
            syncToggleSection
            statusSection
            manualSyncSection
            conflictSection
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud Profile Sync")
        .frame(minWidth: 500, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            refreshState()
        }
        .alert("Sync Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Toggle Section

    /// Enable/disable toggle for iCloud sync.
    private var syncToggleSection: some View {
        Section {
            Toggle("Enable iCloud Profile Sync", isOn: $isSyncEnabled)
                .onChange(of: isSyncEnabled) { _, newValue in
                    if newValue {
                        syncManager.enableSync()
                    } else {
                        syncManager.disableSync()
                    }
                    refreshState()
                }

            Text("When enabled, encoding profiles are automatically synchronised across all your Macs signed into the same iCloud account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("iCloud Sync", systemImage: "icloud")
        }
    }

    // MARK: - Status Section

    /// Current sync status with indicator and last sync time.
    private var statusSection: some View {
        Section("Status") {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(statusDescription)
                    .font(.subheadline)

                Spacer()
            }

            if let date = lastSyncDate {
                HStack {
                    Text("Last Sync:")
                        .foregroundStyle(.secondary)
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if lastUploadCount > 0 || lastDownloadCount > 0 {
                HStack {
                    if lastUploadCount > 0 {
                        Label(
                            "\(lastUploadCount) uploaded",
                            systemImage: "arrow.up.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if lastDownloadCount > 0 {
                        Label(
                            "\(lastDownloadCount) downloaded",
                            systemImage: "arrow.down.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Manual Sync Section

    /// Buttons for triggering manual upload/download.
    private var manualSyncSection: some View {
        Section("Manual Sync") {
            HStack {
                Button {
                    performUpload()
                } label: {
                    Label("Upload Profiles", systemImage: "arrow.up.circle")
                }
                .disabled(!isSyncEnabled || isSyncing)

                Spacer()

                Button {
                    performDownload()
                } label: {
                    Label("Download Profiles", systemImage: "arrow.down.circle")
                }
                .disabled(!isSyncEnabled || isSyncing)
            }

            if isSyncing {
                ProgressView("Syncing...")
                    .progressViewStyle(.linear)
            }
        }
    }

    // MARK: - Conflict Section

    /// Displays conflicts and resolution controls.
    @ViewBuilder
    private var conflictSection: some View {
        if !conflicts.isEmpty {
            Section("Conflicts (\(conflicts.count))") {
                ForEach(conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile: \(conflict.localProfile.name)")
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Local")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(conflict.localDate.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("vs")
                                .foregroundStyle(.secondary)

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("iCloud")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(conflict.remoteDate.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Button("Keep Local") {
                                _ = syncManager.resolveConflict(
                                    conflictId: conflict.id,
                                    keepLocal: true
                                )
                                refreshState()
                            }
                            .buttonStyle(.bordered)

                            Button("Keep iCloud") {
                                _ = syncManager.resolveConflict(
                                    conflictId: conflict.id,
                                    keepLocal: false
                                )
                                refreshState()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("Resolve All (Keep Newer)") {
                    _ = syncManager.resolveAllConflictsNewerWins()
                    refreshState()
                }
                .disabled(conflicts.isEmpty)
            }
        }
    }

    // MARK: - Computed Properties

    /// Colour for the sync status indicator dot.
    private var statusColor: Color {
        switch status {
        case .disabled:     return .secondary
        case .idle:         return .green
        case .uploading:    return .blue
        case .downloading:  return .blue
        case .error:        return .red
        case .unavailable:  return .orange
        }
    }

    /// Human-readable description of the current sync status.
    private var statusDescription: String {
        switch status {
        case .disabled:     return "Sync is disabled"
        case .idle:         return "Sync is idle"
        case .uploading:    return "Uploading profiles..."
        case .downloading:  return "Downloading profiles..."
        case .error:        return "An error occurred"
        case .unavailable:  return "iCloud is not available"
        }
    }

    // MARK: - Actions

    /// Refreshes all state from the sync manager.
    private func refreshState() {
        isSyncEnabled = syncManager.isSyncEnabled
        status = syncManager.status
        lastSyncDate = syncManager.lastSyncDate
        conflicts = syncManager.conflicts
    }

    /// Uploads local profiles to iCloud.
    private func performUpload() {
        isSyncing = true
        // In a full implementation, fetch profiles from the profile manager.
        // For now, demonstrate the API.
        do {
            let profiles: [EncodingProfile] = []  // Would be fetched from profile store.
            try syncManager.uploadProfiles(profiles)
            lastUploadCount = profiles.count
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSyncing = false
        refreshState()
    }

    /// Downloads profiles from iCloud.
    private func performDownload() {
        isSyncing = true
        do {
            let profiles = try syncManager.downloadProfiles()
            lastDownloadCount = profiles.count
            // In a full implementation, merge into local profile store.
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSyncing = false
        refreshState()
    }
}
