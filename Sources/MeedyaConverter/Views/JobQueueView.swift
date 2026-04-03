// ============================================================================
// MeedyaConverter — JobQueueView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - JobQueueView

/// Displays the encoding job queue with progress tracking for each job.
///
/// Shows all queued, encoding, completed, failed, and cancelled jobs
/// in a list with real-time progress updates. Provides controls for
/// starting/stopping encoding and managing individual jobs.
struct JobQueueView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.engine.queue.jobs.isEmpty {
                emptyQueueView
            } else {
                queueListView
            }
        }
        .navigationTitle("Encoding Queue")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                queueToolbar
            }
        }
    }

    // MARK: - Empty State

    private var emptyQueueView: some View {
        ContentUnavailableView(
            "No Jobs in Queue",
            systemImage: "list.number",
            description: Text("Select a source file and configure output settings to add encoding jobs.")
        )
    }

    // MARK: - Queue List

    private var queueListView: some View {
        List {
            // Queue statistics header
            queueStatsSection

            // Active and queued jobs
            let activeJobs = viewModel.engine.queue.jobs.filter {
                $0.status == .encoding || $0.status == .paused || $0.status == .queued
            }
            if !activeJobs.isEmpty {
                Section("Active & Pending") {
                    ForEach(activeJobs, id: \.config.id) { job in
                        JobRow(job: job)
                    }
                }
            }

            // Completed jobs
            let finishedJobs = viewModel.engine.queue.jobs.filter {
                $0.status == .completed || $0.status == .failed || $0.status == .cancelled
            }
            if !finishedJobs.isEmpty {
                Section("Finished") {
                    ForEach(finishedJobs, id: \.config.id) { job in
                        JobRow(job: job)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Queue Stats

    private var queueStatsSection: some View {
        Section {
            HStack(spacing: 20) {
                statBadge("Pending", count: viewModel.engine.queue.pendingCount, color: .blue)
                statBadge("Completed", count: viewModel.engine.queue.completedCount, color: .green)
                statBadge("Failed", count: viewModel.engine.queue.failedCount, color: .red)
                Spacer()
                Text("\(viewModel.engine.queue.totalCount) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var queueToolbar: some View {
        Button("Clear Finished", systemImage: "trash") {
            viewModel.engine.queue.clearFinished()
        }
        .disabled(viewModel.engine.queue.completedCount == 0 && viewModel.engine.queue.failedCount == 0)
        .help("Remove completed and failed jobs from the queue")
    }
}

// MARK: - JobRow

/// A single job row showing file name, profile, status, and progress.
struct JobRow: View {
    @ObservedObject var job: EncodingJobState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: file name and status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)

                Text(job.config.inputURL.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(job.config.profile.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Progress bar (only for encoding/paused)
            if job.status == .encoding || job.status == .paused {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Encoding progress: \(Int(job.progress * 100))%")
            }

            // Status detail line
            HStack {
                Text(job.summaryString)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Spacer()

                // Output format
                Text(job.config.outputURL.pathExtension.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if job.status == .queued {
                Button("Cancel") {
                    job.status = .cancelled
                    job.completedAt = Date()
                }
            }
            if job.status == .completed {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(
                        job.config.outputURL.path,
                        inFileViewerRootedAtPath: job.config.outputURL.deletingLastPathComponent().path
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.config.inputURL.lastPathComponent): \(job.summaryString)")
    }

    // MARK: - Status Styling

    private var statusIcon: String {
        switch job.status {
        case .queued: return "clock"
        case .encoding: return "bolt.fill"
        case .paused: return "pause.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued: return .secondary
        case .encoding: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}
