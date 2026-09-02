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

    // MARK: - State

    @State private var showCancelConfirmation = false
    @State private var showStartConfirmation = false

    /// "Confirm before starting encoding" (#475 —
    /// `SettingsView.GeneralSettingsTab`'s toggle was persisted but never
    /// read). Gates the "Start Queue" button below, the main choke point
    /// for kicking off encoding from the Queue tab.
    @AppStorage("confirmBeforeEncoding") private var confirmBeforeEncoding = false

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
            ToolbarItemGroup(placement: .primaryAction) {
                queueControls
            }
            ToolbarItemGroup(placement: .automatic) {
                queueManagement
            }
        }
        .alert("Cancel Encoding?", isPresented: $showCancelConfirmation) {
            Button("Cancel Encoding", role: .destructive) {
                viewModel.cancelCurrentJob()
            }
            Button("Continue Encoding", role: .cancel) {}
        } message: {
            Text("This will stop every encoding job in flight and halt the queue. Partial output files will be deleted.")
        }
        .alert("Start Encoding?", isPresented: $showStartConfirmation) {
            Button("Start Encoding") {
                Task {
                    await viewModel.startQueue()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will begin encoding \(viewModel.engine.queue.pendingCount) queued file(s).")
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

            // Overall queue progress
            if viewModel.isQueueRunning {
                overallProgressSection
            }

            // Active and queued jobs
            let activeJobs = viewModel.engine.queue.jobs.filter {
                $0.status == .encoding || $0.status == .paused || $0.status == .queued
            }
            if !activeJobs.isEmpty {
                Section("Active & Pending") {
                    ForEach(activeJobs, id: \.config.id) { job in
                        JobRow(job: job)
                    }
                    .onMove { source, destination in
                        // `source`/`destination` are indices into `activeJobs`
                        // (this section's filtered list), not into the full
                        // `viewModel.engine.queue.jobs` array that
                        // `moveJob(fromIndex:toIndex:)` operates on. Whenever a
                        // finished job exists, those index spaces diverge and
                        // handing the filtered indices straight to `moveJob`
                        // reordered the wrong job.
                        //
                        // Reconcile by computing the drag's *desired relative
                        // order* of just the active jobs, then rebuild the full
                        // queue's ID order by walking the full array and
                        // substituting that new order into the active jobs'
                        // existing slots — finished jobs keep their exact
                        // position, and `reorder(to:)` (keyed by job ID) applies
                        // the result without any index-space translation.
                        var reorderedActive = activeJobs
                        reorderedActive.move(fromOffsets: source, toOffset: destination)

                        let activeIDs = Set(activeJobs.map(\.config.id))
                        var reorderedActiveIDs = reorderedActive.map(\.config.id).makeIterator()

                        let newOrder = viewModel.engine.queue.jobs.map { job in
                            activeIDs.contains(job.config.id)
                                ? (reorderedActiveIDs.next() ?? job.config.id)
                                : job.config.id
                        }
                        viewModel.engine.queue.reorder(to: newOrder)
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

    // MARK: - Overall Progress

    private var overallProgressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Queue Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    let completed = viewModel.engine.queue.completedCount
                    let total = viewModel.engine.queue.totalCount
                    Text("\(completed) of \(total) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let total = viewModel.engine.queue.totalCount
                let completed = viewModel.engine.queue.completedCount
                // Sum of every in-flight job's fraction, not just one job's
                // (Issue #286). With the default concurrency of 1 there is
                // exactly one term and this is the previous expression.
                let currentProgress = viewModel.activeJobStates
                    .reduce(0.0) { $0 + $1.progress }
                let overallProgress = total > 0
                    ? min(1.0, (Double(completed) + currentProgress) / Double(total))
                    : 0

                ProgressView(value: overallProgress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Overall queue progress: \(Int(overallProgress * 100))%")
            }
        }
    }

    // MARK: - Queue Controls

    @ViewBuilder
    private var queueControls: some View {
        if viewModel.isQueueRunning {
            // Pause/Resume
            // Pause/Resume and Cancel are queue-wide: they act on every
            // job in flight, not just one (Issue #286). At the default
            // concurrency of 1 that is a single job, as before.
            if viewModel.activeJobStates.contains(where: { $0.status == .paused }) {
                Button("Resume", systemImage: "play.fill") {
                    viewModel.resumeCurrentJob()
                }
                .help("Resume encoding")
            } else {
                Button("Pause", systemImage: "pause.fill") {
                    viewModel.pauseCurrentJob()
                }
                .help("Pause every encoding job in flight")
            }

            // Cancel
            Button("Cancel", systemImage: "stop.fill") {
                showCancelConfirmation = true
            }
            .help("Cancel every encoding job in flight and stop the queue")
        } else {
            // Start Queue
            Button("Start Queue", systemImage: "play.fill") {
                if confirmBeforeEncoding {
                    showStartConfirmation = true
                } else {
                    Task {
                        await viewModel.startQueue()
                    }
                }
            }
            .disabled(viewModel.engine.queue.pendingCount == 0)
            .help("Start encoding queued jobs")
        }
    }

    // MARK: - Queue Management

    @ViewBuilder
    private var queueManagement: some View {
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

            // Progress bar (for encoding/paused)
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

                // Encoding stats
                if job.status == .encoding {
                    HStack(spacing: 8) {
                        if let fps = job.currentFrame {
                            Text("frame \(fps)")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let bitrate = job.currentBitrate {
                            Text(String(format: "%.0f kbps", bitrate))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Elapsed time for completed jobs
                if job.status == .completed, let elapsed = job.elapsedTime {
                    Text(formatDuration(elapsed))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

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
                Button("Open Output File") {
                    NSWorkspace.shared.open(job.config.outputURL)
                }
            }
            if job.status == .failed {
                if let error = job.errorMessage {
                    Button("Copy Error") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    }
                }
            }
        }
        // Drag the finished output straight to Finder / Mail / another app
        // (Issue #285). `DraggableFileView`'s `.draggableFile` modifier was a
        // complete drag-source component with zero callers; wiring it here on
        // completed rows makes drag-out real. `nil` for any non-completed job,
        // so only a genuinely-produced output file is draggable.
        .draggableFile(job.status == .completed ? job.config.outputURL : nil)
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

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
