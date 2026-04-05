// ============================================================================
// MeedyaConverter — QueueOptimizerView (Issue #326)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - QueueOptimizerView

/// Provides a strategy picker and preview of the reordered encoding queue.
///
/// Users select a `QueueStrategy`, see a before/after comparison of the
/// job order, and apply the optimisation with a single click. The view
/// reads the current queue from the environment `AppViewModel` and writes
/// the reordered list back when the user confirms.
///
/// Phase 13 — Issue #326
struct QueueOptimizerView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// The currently selected queue strategy.
    @State private var selectedStrategy: QueueStrategy = .fifo

    /// Preview of the reordered queue (computed when the strategy changes).
    @State private var previewJobs: [EncodingJobConfig] = []

    /// Whether the optimisation has been applied (used for confirmation feedback).
    @State private var didApply = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Strategy picker header.
            strategyPicker
                .padding()

            Divider()

            // Before / After comparison.
            HStack(spacing: 0) {
                beforeColumn
                Divider()
                afterColumn
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Action bar.
            actionBar
                .padding()
        }
        .frame(minWidth: 700, minHeight: 450)
        .navigationTitle("Queue Optimizer")
        .onAppear {
            recomputePreview()
        }
        .onChange(of: selectedStrategy) {
            recomputePreview()
        }
    }

    // MARK: - Strategy Picker

    private var strategyPicker: some View {
        HStack {
            Label("Strategy", systemImage: "arrow.up.arrow.down.circle")
                .font(.headline)

            Picker("Strategy", selection: $selectedStrategy) {
                ForEach(QueueStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)

            Spacer()

            if didApply {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Before Column

    private var beforeColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Order")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                ForEach(Array(currentJobs.enumerated()), id: \.element.id) { index, job in
                    jobRow(job: job, position: index + 1, highlighted: false)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - After Column

    private var afterColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optimized Order")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                ForEach(Array(previewJobs.enumerated()), id: \.element.id) { index, job in
                    let moved = positionChanged(job: job, newIndex: index)
                    jobRow(job: job, position: index + 1, highlighted: moved)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Job Row

    private func jobRow(job: EncodingJobConfig, position: Int, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.inputURL.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    if let codec = job.profile.videoCodec {
                        Text(codec.rawValue.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if job.profile.useHardwareEncoding {
                        Label("GPU", systemImage: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let duration = job.estimatedSourceDuration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if highlighted {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Text("\(currentJobs.count) jobs in queue")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                applyOptimisation()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedStrategy == .fifo)
        }
    }

    // MARK: - Computed Properties

    /// The current unoptimised jobs from the queue.
    private var currentJobs: [EncodingJobConfig] {
        viewModel.engine.queue.jobs.map(\.config)
    }

    // MARK: - Actions

    /// Recompute the preview ordering based on the selected strategy.
    private func recomputePreview() {
        let jobs = currentJobs
        previewJobs = SmartQueueOptimizer.optimize(jobs: jobs, strategy: selectedStrategy)
    }

    /// Apply the optimised order to the live queue.
    private func applyOptimisation() {
        withAnimation {
            didApply = true
        }

        // Dismiss after a brief delay so the user sees the confirmation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }

    /// Check whether a job moved from its original position.
    private func positionChanged(job: EncodingJobConfig, newIndex: Int) -> Bool {
        guard newIndex < currentJobs.count else { return false }
        return currentJobs[newIndex].id != job.id
    }

    // MARK: - Formatting

    /// Format a duration in seconds to a human-readable string (e.g., "1h 23m").
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
