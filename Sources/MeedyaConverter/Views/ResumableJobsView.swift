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
/// the time of interruption, and the date it was saved. Provides a
/// "Re-queue" button per job — this restarts the job from the beginning,
/// it does not seek-resume mid-file (that is not implemented yet) — and a
/// "Clear All" button to discard all checkpoints.
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

            // Re-queue button. Labelled honestly: this restarts the job
            // from the beginning, it does not seek-resume from
            // `checkpoint.progressFraction` — true mid-file resume is
            // not implemented yet.
            Button {
                resumeCheckpoint(checkpoint)
            } label: {
                Label("Re-queue", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Re-queue this job from the start (was \(Int(checkpoint.progressFraction * 100))% done when interrupted)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(checkpoint.inputURL.lastPathComponent), \(Int(checkpoint.progressFraction * 100)) percent completed")
        .accessibilityAction(named: "Re-queue") {
            resumeCheckpoint(checkpoint)
        }
    }

    // MARK: - Actions

    /// Load all resumable checkpoints from the checkpoint manager.
    private func loadCheckpoints() {
        let manager = CheckpointManager()
        checkpoints = manager.listResumableCheckpoints()
    }

    /// Re-queue an interrupted encoding job from the start.
    ///
    /// This is honest-minimal resumable jobs: it builds a fresh
    /// `EncodingJobConfig` for the same input/profile with no seek offset,
    /// so the job re-encodes from 0% rather than continuing from
    /// `checkpoint.progressFraction`/`checkpoint.lastGoodTimestamp`. True
    /// mid-file resume (seeking past already-encoded content) is deferred.
    private func resumeCheckpoint(_ checkpoint: EncodingCheckpoint) {
        let outputDir = checkpoint.outputURL.deletingLastPathComponent()
        let outputExtension = checkpoint.profileSnapshot.containerFormat.fileExtensions.first ?? "mkv"
        let baseName = checkpoint.inputURL.deletingPathExtension().lastPathComponent
        // F-002 defensive sanitisation per SECURITY.md (Cycle 25).
        let component = PathSanitizer.sanitizeFilenameComponent("\(baseName)_resumed")
        let outputURL = outputDir
            .appendingPathComponent(component)
            .appendingPathExtension(outputExtension)

        let config = EncodingJobConfig(
            inputURL: checkpoint.inputURL,
            outputURL: outputURL,
            profile: checkpoint.profileSnapshot
        )

        viewModel.engine.queue.addJob(config)
        viewModel.appendLog(.info, "Re-queued interrupted job from the start: \(checkpoint.inputURL.lastPathComponent) (was \(Int(checkpoint.progressFraction * 100))% done when interrupted)")

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

                    Text("\(resumableCount) interrupted job\(resumableCount == 1 ? "" : "s") can be re-queued")
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
            .accessibilityLabel("\(resumableCount) interrupted jobs available to re-queue")
        }
    }
}
