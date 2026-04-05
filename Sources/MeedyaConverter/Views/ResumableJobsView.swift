// ============================================================================
// MeedyaConverter — ResumableJobsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ResumableJobsView

/// Displays a list of encoding jobs that were interrupted and can be resumed.
///
/// Shows each resumable checkpoint with the source filename, progress at
/// the time of interruption, and the date it was saved. Provides a "Resume"
/// button per job and a "Clear All" button to discard all checkpoints.
///
/// Can be embedded inline (e.g., in the Queue section of the sidebar)
/// or presented as a sheet.
struct ResumableJobsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var checkpoints: [EncodingCheckpoint] = []
    @State private var showClearConfirmation = false

    // MARK: - Body

    var body: some View {
        Group {
            if checkpoints.isEmpty {
                ContentUnavailableView(
                    "No Interrupted Jobs",
                    systemImage: "checkmark.circle",
                    description: Text("All previous encodes completed normally.")
                )
            } else {
                checkpointList
            }
        }
        .navigationTitle("Resumable Jobs")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    loadCheckpoints()
                }
                .help("Reload checkpoint list from disk")
            }

            if !checkpoints.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .help("Delete all saved checkpoints")
                }
            }
        }
        .alert("Clear All Checkpoints?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                clearAllCheckpoints()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all saved resume points. Interrupted encodes will need to start from the beginning.")
        }
        .onAppear {
            loadCheckpoints()
        }
    }

    // MARK: - Checkpoint List

    private var checkpointList: some View {
        List {
            ForEach(checkpoints) { checkpoint in
                checkpointRow(checkpoint)
            }
            .onDelete { offsets in
                deleteCheckpoints(at: offsets)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Checkpoint Row

    private func checkpointRow(_ checkpoint: EncodingCheckpoint) -> some View {
        HStack(spacing: 12) {
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(checkpoint.inputURL.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    // Progress badge
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("\(Int(checkpoint.progressFraction * 100))% completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Timestamp
                    Text(checkpoint.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Profile name
                Text("Profile: \(checkpoint.profileSnapshot.name)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Resume button
            Button {
                resumeCheckpoint(checkpoint)
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Resume encoding from \(Int(checkpoint.progressFraction * 100))%")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(checkpoint.inputURL.lastPathComponent), \(Int(checkpoint.progressFraction * 100)) percent completed")
        .accessibilityAction(named: "Resume") {
            resumeCheckpoint(checkpoint)
        }
    }

    // MARK: - Actions

    /// Load all resumable checkpoints from the checkpoint manager.
    private func loadCheckpoints() {
        let manager = CheckpointManager()
        checkpoints = manager.listResumableCheckpoints()
    }

    /// Resume an interrupted encoding job by re-enqueuing it.
    private func resumeCheckpoint(_ checkpoint: EncodingCheckpoint) {
        let outputDir = checkpoint.outputURL.deletingLastPathComponent()
        let outputExtension = checkpoint.profileSnapshot.containerFormat.fileExtensions.first ?? "mkv"
        let baseName = checkpoint.inputURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir
            .appendingPathComponent("\(baseName)_resumed")
            .appendingPathExtension(outputExtension)

        let config = EncodingJobConfig(
            inputURL: checkpoint.inputURL,
            outputURL: outputURL,
            profile: checkpoint.profileSnapshot
        )

        viewModel.engine.queue.addJob(config)
        viewModel.appendLog(.info, "Resumed interrupted job: \(checkpoint.inputURL.lastPathComponent) from \(Int(checkpoint.progressFraction * 100))%")

        // Delete the checkpoint since it has been re-enqueued
        let manager = CheckpointManager()
        manager.deleteCheckpoint(for: checkpoint.jobId)
        loadCheckpoints()

        // Switch to queue view
        viewModel.selectedNavItem = .queue
    }

    /// Delete checkpoints at the given offsets.
    private func deleteCheckpoints(at offsets: IndexSet) {
        let manager = CheckpointManager()
        for index in offsets {
            let checkpoint = checkpoints[index]
            manager.deleteCheckpoint(for: checkpoint.jobId)
        }
        checkpoints.remove(atOffsets: offsets)
    }

    /// Delete all checkpoints.
    private func clearAllCheckpoints() {
        let manager = CheckpointManager()
        manager.deleteAllCheckpoints()
        checkpoints.removeAll()
        viewModel.appendLog(.info, "Cleared all encoding checkpoints")
    }
}

// MARK: - ResumableJobsBanner

/// A compact banner showing the count of resumable jobs.
///
/// Designed to be embedded in the sidebar or queue view as a
/// non-intrusive notification that interrupted jobs are available.
struct ResumableJobsBanner: View {

    // MARK: - Properties

    /// Number of resumable checkpoints available.
    let resumableCount: Int

    /// Action to perform when the banner is tapped.
    let onTap: () -> Void

    // MARK: - Body

    var body: some View {
        if resumableCount > 0 {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .foregroundStyle(.orange)

                    Text("\(resumableCount) interrupted job\(resumableCount == 1 ? "" : "s") can be resumed")
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(resumableCount) interrupted jobs available to resume")
        }
    }
}
