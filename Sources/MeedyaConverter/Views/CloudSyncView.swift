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

    /// The in-flight upload/download task, retained so it can be
    /// cancelled if the user dismisses this view mid-sync. Mirrors
    /// `LoudnessReportView.analysisTask` / `BenchmarkView.benchmarkTask`.
    @State private var syncTask: Task<Void, Never>?

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
        .onDisappear {
            syncTask?.cancel()
            syncTask = nil
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
                    syncTask = Task { await performUpload() }
                } label: {
                    Label("Upload Profiles", systemImage: "arrow.up.circle")
                }
                .disabled(!isSyncEnabled || isSyncing)

                Spacer()

                Button {
                    syncTask = Task { await performDownload() }
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
    ///
    /// Mirrors `TeamProfileView.pushProfiles()` (see
    /// `TeamProfileView.swift` around line 268): pulls the live profile
    /// list from the shared `EncodingProfileStore`
    /// (`viewModel.engine.profileStore.profiles`) instead of the
    /// previous hardcoded empty array, so `lastUploadCount` reflects the
    /// number of profiles genuinely written to iCloud.
    ///
    /// `CloudSyncView` is a `struct: View`, so this `async` method (and
    /// the plain `Task { }` that calls it from the button) is implicitly
    /// main-actor isolated via `View` conformance — `@State` writes below
    /// are direct property mutations, matching
    /// `QualityMetricsView.runAnalysis()`'s shape.
    /// `CloudProfileSync.uploadProfiles(_:)` performs genuinely blocking
    /// file I/O against the iCloud ubiquity container, so it runs inside
    /// `Task.detached`, capturing/returning only `Sendable` values
    /// (`syncManager` is `@unchecked Sendable`; `[EncodingProfile]` is
    /// `Sendable`) and never touching `self`/`@State` directly — mirroring
    /// how `QualityMetricsView.runAnalysis()` detaches
    /// `FFmpegBundleManager.locateFFmpeg()`.
    private func performUpload() async {
        isSyncing = true
        errorMessage = nil
        lastUploadCount = 0

        let profiles = viewModel.engine.profileStore.profiles
        let manager = syncManager

        do {
            try await Task.detached {
                try manager.uploadProfiles(profiles)
            }.value

            guard !Task.isCancelled else {
                isSyncing = false
                return
            }
            lastUploadCount = profiles.count
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        isSyncing = false
        refreshState()
    }

    /// Downloads profiles from iCloud and merges them into the local
    /// profile store.
    ///
    /// Profiles already known locally (matched by ID) are updated in
    /// place via `EncodingProfileStore.updateProfile(_:)`; profiles not
    /// yet seen locally are added via `addProfile(_:)`. This reuses the
    /// store's existing CRUD surface (the same one `ProfileManagementView`
    /// and `TeamProfileView` exercise) rather than inventing new merge
    /// logic, and makes `lastDownloadCount` reflect real merged profiles
    /// instead of a discarded result.
    ///
    /// Concurrency shape mirrors `performUpload()` above:
    /// `CloudProfileSync.downloadProfiles()` blocks on file I/O, so it
    /// runs inside `Task.detached`; the merge into `profileStore` happens
    /// back on the main actor once the detached call returns, alongside
    /// the other `@State` writes.
    private func performDownload() async {
        isSyncing = true
        errorMessage = nil
        lastDownloadCount = 0

        let manager = syncManager

        do {
            let downloaded = try await Task.detached {
                try manager.downloadProfiles()
            }.value

            guard !Task.isCancelled else {
                isSyncing = false
                return
            }

            let store = viewModel.engine.profileStore
            for profile in downloaded {
                if store.profile(id: profile.id) != nil {
                    store.updateProfile(profile)
                } else {
                    store.addProfile(profile)
                }
            }
            lastDownloadCount = downloaded.count
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        isSyncing = false
        refreshState()
    }
}
