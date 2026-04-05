// ============================================================================
// MeedyaConverter — ParallelEncodingView (Issue #286)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - ActiveEncodingJob
// ---------------------------------------------------------------------------
/// View-layer model representing a single active encoding job with progress.
///
/// Used by the parallel encoding dashboard to display per-job status,
/// progress bars, and resource allocation indicators.
struct ActiveEncodingJob: Identifiable {

    /// Unique identifier for this active job.
    let id: UUID

    /// Display name derived from the source file.
    let fileName: String

    /// The encoding profile name being used.
    let profileName: String

    /// Current encoding progress (0.0 to 1.0).
    var progress: Double

    /// Current encoding speed (e.g., "2.4x").
    var speed: String

    /// Estimated time remaining in seconds.
    var etaSeconds: Double?

    /// Whether this job is using GPU acceleration.
    var isGPUAccelerated: Bool

    /// CPU weight consumed by this job.
    var cpuWeight: Double

    /// GPU weight consumed by this job.
    var gpuWeight: Double

    /// RAM consumed by this job in MB.
    var ramMB: Int
}

// ---------------------------------------------------------------------------
// MARK: - ParallelEncodingViewModel
// ---------------------------------------------------------------------------
/// Observable view model for the parallel encoding dashboard.
///
/// Manages the concurrent encoding slider, calculates resource allocation,
/// and displays active job progress. Integrates with `ParallelEncoder`
/// from ConverterEngine for capacity recommendations.
///
/// Thread safety: `@MainActor`-isolated for safe SwiftUI binding.
@MainActor
@Observable
final class ParallelEncodingViewModel {

    // MARK: - Configuration

    /// Maximum number of concurrent encoding jobs (user-configurable).
    var maxConcurrent: Int

    /// Whether CPU affinity pinning is enabled.
    var cpuAffinity: Bool = false

    /// Whether GPU sharing between concurrent encodes is allowed.
    var gpuSharing: Bool = true

    // MARK: - System Info

    /// Total CPU cores available on this system.
    let totalCores: Int

    /// Total physical RAM in GB.
    let totalRAMGB: Int

    /// System-recommended maximum concurrent jobs.
    let recommendedMax: Int

    // MARK: - Active Jobs

    /// Currently running encoding jobs with live progress.
    var activeJobs: [ActiveEncodingJob] = []

    /// Aggregate throughput in frames per second across all active jobs.
    var totalFPS: Double = 0.0

    /// Aggregate CPU usage across all active jobs (0.0 to 1.0).
    var aggregateCPUUsage: Double = 0.0

    /// Aggregate GPU usage across all active jobs (0.0 to 1.0).
    var aggregateGPUUsage: Double = 0.0

    /// Total RAM consumed by all active jobs in MB.
    var totalRAMUsageMB: Int = 0

    // MARK: - Computed Properties

    /// Returns the parallel encoder configuration for the current settings.
    var encoderConfig: ParallelEncoderConfig {
        ParallelEncoderConfig(
            maxConcurrent: maxConcurrent,
            cpuAffinity: cpuAffinity,
            gpuSharing: gpuSharing
        )
    }

    /// Human-readable system capacity summary.
    var capacitySummary: String {
        ParallelEncoder.capacitySummary
    }

    /// Whether the current concurrency exceeds the recommended maximum.
    var isOverSubscribed: Bool {
        maxConcurrent > recommendedMax
    }

    // MARK: - Initialisation

    init() {
        let recommended = ParallelEncoder.determineMaxConcurrent()
        self.maxConcurrent = recommended
        self.recommendedMax = recommended
        self.totalCores = ProcessInfo.processInfo.activeProcessorCount
        self.totalRAMGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }

    // MARK: - Resource Calculation

    /// Recalculates aggregate resource usage from active jobs.
    func updateResourceUsage() {
        aggregateCPUUsage = activeJobs.reduce(0) { $0 + $1.cpuWeight }
        aggregateGPUUsage = activeJobs.reduce(0) { $0 + $1.gpuWeight }
        totalRAMUsageMB = activeJobs.reduce(0) { $0 + $1.ramMB }
    }
}

// ---------------------------------------------------------------------------
// MARK: - ParallelEncodingView
// ---------------------------------------------------------------------------
/// Parallel encoding dashboard for managing concurrent encode sessions.
///
/// Displays a concurrency slider, active job list with individual progress
/// bars, CPU/GPU allocation gauges, and total throughput metrics.
///
/// Phase 8 — Split View / Parallel Encoding (Issue #286)
struct ParallelEncodingView: View {

    // MARK: - State

    /// View model managing parallel encoding state.
    @State private var viewModel = ParallelEncodingViewModel()

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                concurrencyConfigSection
                resourceAllocationSection
                activeJobsSection
                throughputSection
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Concurrency Configuration

    /// Slider and controls for setting the maximum concurrent job count.
    private var concurrencyConfigSection: some View {
        GroupBox("Concurrent Encoding") {
            VStack(alignment: .leading, spacing: 12) {
                // Concurrency slider
                HStack {
                    Text("Max Concurrent Jobs:")
                        .frame(width: 160, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.maxConcurrent) },
                            set: { viewModel.maxConcurrent = max(1, Int($0)) }
                        ),
                        in: 1...Double(max(viewModel.recommendedMax * 2, 8)),
                        step: 1
                    )

                    Text("\(viewModel.maxConcurrent)")
                        .font(.title2.bold().monospaced())
                        .frame(width: 40)
                }

                if viewModel.isOverSubscribed {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Exceeds recommended maximum of \(viewModel.recommendedMax). Performance may degrade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Options
                HStack(spacing: 24) {
                    Toggle("CPU Affinity", isOn: $viewModel.cpuAffinity)
                        .help("Pin each encode process to specific CPU cores for better cache locality")

                    Toggle("GPU Sharing", isOn: $viewModel.gpuSharing)
                        .help("Allow multiple GPU-accelerated encodes to share the GPU simultaneously")
                }

                // System info
                Text(viewModel.capacitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Resource Allocation

    /// Gauges showing aggregate CPU, GPU, and RAM usage.
    private var resourceAllocationSection: some View {
        GroupBox("Resource Allocation") {
            HStack(spacing: 24) {
                resourceGauge(
                    title: "CPU",
                    value: viewModel.aggregateCPUUsage,
                    maxValue: 1.0,
                    color: .blue,
                    subtitle: "\(viewModel.totalCores) cores"
                )

                resourceGauge(
                    title: "GPU",
                    value: viewModel.aggregateGPUUsage,
                    maxValue: 1.0,
                    color: .green,
                    subtitle: viewModel.gpuSharing ? "Shared" : "Exclusive"
                )

                resourceGauge(
                    title: "RAM",
                    value: Double(viewModel.totalRAMUsageMB) / 1024.0,
                    maxValue: Double(viewModel.totalRAMGB),
                    color: .orange,
                    subtitle: "\(viewModel.totalRAMGB) GB total"
                )
            }
            .padding(12)
        }
    }

    /// A single circular resource gauge.
    private func resourceGauge(
        title: String,
        value: Double,
        maxValue: Double,
        color: Color,
        subtitle: String
    ) -> some View {
        VStack(spacing: 8) {
            Gauge(value: min(value, maxValue), in: 0...maxValue) {
                Text(title)
                    .font(.caption.bold())
            } currentValueLabel: {
                Text("\(Int(value / maxValue * 100))%")
                    .font(.caption.monospaced())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            .scaleEffect(1.2)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Active Jobs

    /// List of currently encoding jobs with individual progress.
    private var activeJobsSection: some View {
        GroupBox("Active Jobs (\(viewModel.activeJobs.count) / \(viewModel.maxConcurrent))") {
            if viewModel.activeJobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No active encoding jobs")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Jobs will appear here when encoding begins.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.activeJobs) { job in
                        activeJobRow(job)
                    }
                }
                .padding(8)
            }
        }
    }

    /// A single active job row with progress bar and resource indicators.
    private func activeJobRow(_ job: ActiveEncodingJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: job.isGPUAccelerated ? "cpu" : "memorychip")
                    .foregroundStyle(job.isGPUAccelerated ? .green : .blue)
                    .help(job.isGPUAccelerated ? "GPU-accelerated" : "CPU encoding")

                Text(job.fileName)
                    .font(.body.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(job.speed)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let eta = job.etaSeconds {
                    Text(formatETA(eta))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(job.progress * 100))%")
                    .font(.caption.bold().monospaced())
                    .frame(width: 40, alignment: .trailing)
            }

            ProgressView(value: job.progress)
                .tint(job.isGPUAccelerated ? .green : .blue)

            HStack(spacing: 12) {
                Text("Profile: \(job.profileName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("CPU: \(String(format: "%.0f%%", job.cpuWeight * 100))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("GPU: \(String(format: "%.0f%%", job.gpuWeight * 100))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("RAM: \(job.ramMB) MB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Throughput

    /// Aggregate throughput metrics across all active jobs.
    private var throughputSection: some View {
        GroupBox("Throughput") {
            HStack(spacing: 32) {
                VStack {
                    Text(String(format: "%.1f", viewModel.totalFPS))
                        .font(.title.bold().monospaced())
                    Text("Total FPS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("\(viewModel.activeJobs.count)")
                        .font(.title.bold().monospaced())
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    let avgProgress = viewModel.activeJobs.isEmpty
                        ? 0.0
                        : viewModel.activeJobs.reduce(0) { $0 + $1.progress } / Double(viewModel.activeJobs.count)
                    Text("\(Int(avgProgress * 100))%")
                        .font(.title.bold().monospaced())
                    Text("Avg Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        }
    }

    // MARK: - Helpers

    /// Formats a duration in seconds as "Xh Ym Zs" or "Ym Zs".
    private func formatETA(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        if h > 0 {
            return "\(h)h \(m)m"
        } else if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------
#if DEBUG
#Preview("Parallel Encoding") {
    ParallelEncodingView()
        .frame(width: 700, height: 600)
}
#endif
