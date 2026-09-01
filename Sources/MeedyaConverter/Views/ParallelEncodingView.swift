// ============================================================================
// MeedyaConverter — ParallelEncodingView (Issue #286)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - ParallelEncodingView
// ---------------------------------------------------------------------------
/// Parallel encoding dashboard — the control surface for how many encoding
/// jobs run at once, and a live view of the ones that are.
///
/// ### What is real here
///
/// The Max Concurrent Jobs slider writes
/// `ParallelEncoder.maxConcurrentJobsDefaultsKey`, which is the value
/// `AppViewModel.startQueue()`'s runner reads on every slot top-up. This is
/// the actual control, not a mirror of one: dragging it to 1 restores the
/// strictly sequential queue, and it is the documented rollback switch for
/// the whole feature.
///
/// The Active Jobs list is `AppViewModel.activeJobStates` — the same
/// `EncodingJobState` objects the queue is encoding — so progress, speed and
/// ETA are the encoder's own numbers.
///
/// The CPU / GPU / RAM figures are `ParallelEncoder.estimateResourceUsage`
/// **estimates** derived from each job's codec and resolution, and are
/// labelled as estimates everywhere they appear. Nothing here samples real
/// process utilisation; the Resource Monitor view does that.
///
/// Phase 8 — Split View / Parallel Encoding (Issue #286)
struct ParallelEncodingView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Settings

    /// The user's requested maximum concurrent jobs.
    ///
    /// Defaults to 1 — sequential encoding, the behaviour the queue has
    /// always had. The runner clamps this to the hardware ceiling, and to 1
    /// entirely for installs without the Parallel Encoding entitlement.
    @AppStorage(ParallelEncoder.maxConcurrentJobsDefaultsKey)
    private var requestedConcurrency: Int = 1

    // MARK: - Derived System Info

    private let recommendedMax = ParallelEncoder.determineMaxConcurrent()
    private let totalCores = ProcessInfo.processInfo.activeProcessorCount
    private let totalRAMGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    /// Whether this install may actually run more than one job at a time.
    private var isEntitled: Bool {
        FeatureGateManager.shared.isEntitled(to: .parallelEncoding)
    }

    /// The concurrency the runner will actually use for the requested
    /// value — the same clamping the runner applies, shown to the user so
    /// the slider never claims more than it delivers.
    private var effectiveConcurrency: Int {
        ParallelEncoder.resolveConcurrency(
            requested: requestedConcurrency,
            entitled: isEntitled,
            hardwareCeiling: recommendedMax
        )
    }

    /// Jobs currently in flight, straight from the queue runner.
    private var activeJobs: [EncodingJobState] {
        viewModel.activeJobStates
    }

    /// Per-job resource estimates for the jobs in flight.
    private var estimates: [ResourceEstimate] {
        activeJobs.map { ParallelEncoder.estimateResourceUsage(job: $0.config) }
    }

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
                HStack {
                    Text("Max Concurrent Jobs:")
                        .frame(width: 160, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(max(1, requestedConcurrency)) },
                            set: { requestedConcurrency = max(1, Int($0)) }
                        ),
                        in: 1...Double(max(recommendedMax * 2, 8)),
                        step: 1
                    )
                    .disabled(!isEntitled)

                    Text("\(max(1, requestedConcurrency))")
                        .font(.title2.bold().monospaced())
                        .frame(width: 40)
                }

                Text("Applies as encoding slots free up — a change mid-queue "
                     + "takes effect from the next job to start, and never "
                     + "interrupts a job already running. Set it to 1 for "
                     + "strictly sequential encoding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !isEntitled {
                    Label(
                        "Concurrent encoding requires the Parallel Encoding "
                        + "feature. Jobs run one at a time on this install.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if effectiveConcurrency < requestedConcurrency {
                    Label(
                        "Clamped to \(effectiveConcurrency) — twice the "
                        + "recommended maximum for this machine.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if requestedConcurrency > recommendedMax {
                    Label(
                        "Exceeds the recommended maximum of \(recommendedMax). "
                        + "Encoding speed per job may drop, and each concurrent "
                        + "job needs its own temporary disk space.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                Text(ParallelEncoder.capacitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Resource Allocation

    /// Gauges showing the aggregate *estimated* CPU, GPU, and RAM demand of
    /// the jobs currently in flight.
    private var resourceAllocationSection: some View {
        GroupBox("Estimated Resource Demand") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 24) {
                    resourceGauge(
                        title: "CPU",
                        value: estimates.reduce(0.0) { $0 + $1.cpuWeight },
                        maxValue: Double(max(1, effectiveConcurrency)),
                        color: .blue,
                        subtitle: "\(totalCores) cores"
                    )

                    resourceGauge(
                        title: "GPU",
                        value: estimates.reduce(0.0) { $0 + $1.gpuWeight },
                        maxValue: Double(max(1, effectiveConcurrency)),
                        color: .green,
                        subtitle: "hardware encoders"
                    )

                    resourceGauge(
                        title: "RAM",
                        value: Double(estimates.reduce(0) { $0 + $1.ramMB }) / 1024.0,
                        maxValue: Double(max(1, totalRAMGB)),
                        color: .orange,
                        subtitle: "\(totalRAMGB) GB total"
                    )
                }

                Text("Estimates from each job's codec and output resolution — "
                     + "not measured utilisation. See Resource Monitor for "
                     + "live system usage.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        let safeMax = max(maxValue, 0.001)
        return VStack(spacing: 8) {
            Gauge(value: min(value, safeMax), in: 0...safeMax) {
                Text(title)
                    .font(.caption.bold())
            } currentValueLabel: {
                Text("\(Int(min(value, safeMax) / safeMax * 100))%")
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
        GroupBox("Active Jobs (\(activeJobs.count) / \(effectiveConcurrency))") {
            if activeJobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
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
                    ForEach(activeJobs, id: \.config.id) { job in
                        ActiveJobRow(job: job)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Throughput

    /// Aggregate throughput across the jobs in flight.
    ///
    /// "Combined Speed" is the sum of the encoder's own realtime-speed
    /// multipliers, which is the one genuinely additive throughput figure
    /// available: `EncodingJobState` carries no per-job frame rate, so a
    /// total-FPS tile could only have been invented.
    private var throughputSection: some View {
        GroupBox("Throughput") {
            HStack(spacing: 32) {
                VStack {
                    let speeds = activeJobs.compactMap(\.speed)
                    Text(speeds.isEmpty ? "—" : String(format: "%.1fx", speeds.reduce(0, +)))
                        .font(.title.bold().monospaced())
                    Text("Combined Speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("\(activeJobs.count)")
                        .font(.title.bold().monospaced())
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    let avgProgress = activeJobs.isEmpty
                        ? 0.0
                        : activeJobs.reduce(0.0) { $0 + $1.progress } / Double(activeJobs.count)
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
}

// ---------------------------------------------------------------------------
// MARK: - ActiveJobRow
// ---------------------------------------------------------------------------
/// A single in-flight job: live progress from the encoder, plus this job's
/// estimated resource share.
///
/// Uses `@ObservedObject` rather than `@Environment`/`@Observable` because
/// `EncodingJobState` is a Combine `ObservableObject` — the same pattern
/// `JobQueueView.JobRow` uses, and the reason each row is its own view: a
/// parent that merely read `job.progress` would not re-render on change.
private struct ActiveJobRow: View {

    @ObservedObject var job: EncodingJobState

    /// This job's estimated resource share. A pure function of the job's
    /// immutable `config`, so it is computed once per render rather than
    /// stored.
    private var estimate: ResourceEstimate {
        ParallelEncoder.estimateResourceUsage(job: job.config)
    }

    private var isGPUAccelerated: Bool {
        job.config.profile.useHardwareEncoding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isGPUAccelerated ? "cpu" : "memorychip")
                    .foregroundStyle(isGPUAccelerated ? .green : .blue)
                    .help(isGPUAccelerated ? "Hardware-accelerated" : "Software encoding")
                    .accessibilityLabel(
                        isGPUAccelerated ? "Hardware-accelerated encoding" : "Software encoding"
                    )

                Text(job.config.inputURL.lastPathComponent)
                    .font(.body.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let speed = job.speed {
                    Text(String(format: "%.1fx", speed))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let eta = job.eta {
                    Text(Self.formatETA(eta))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(job.progress * 100))%")
                    .font(.caption.bold().monospaced())
                    .frame(width: 40, alignment: .trailing)
            }

            ProgressView(value: job.progress)
                .tint(job.status == .paused ? .orange : (isGPUAccelerated ? .green : .blue))

            HStack(spacing: 12) {
                Text("Profile: \(job.config.profile.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("CPU (est): \(String(format: "%.0f%%", estimate.cpuWeight * 100))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("GPU (est): \(String(format: "%.0f%%", estimate.gpuWeight * 100))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("RAM (est): \(estimate.ramMB) MB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if job.status == .paused {
                    Text("Paused")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.config.inputURL.lastPathComponent): \(job.summaryString)")
    }

    /// Formats a duration in seconds as "Xh Ym" or "Ym Zs".
    private static func formatETA(_ seconds: Double) -> String {
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
