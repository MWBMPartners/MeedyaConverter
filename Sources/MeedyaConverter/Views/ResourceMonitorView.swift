// ============================================================================
// MeedyaConverter — ResourceMonitorView (Issue #327)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import Darwin

// ---------------------------------------------------------------------------
// MARK: - ResourceMonitor
// ---------------------------------------------------------------------------
/// Observable model that polls system resource usage at one-second
/// intervals during encoding operations.
///
/// Uses `ProcessInfo` for CPU/memory metrics, with IOKit-based GPU
/// monitoring when available. Historical data is retained for the last
/// 60 seconds to power sparkline visualizations.
///
/// Thread safety: All properties are `@MainActor`-isolated and updated
/// by a `Timer`-based polling loop.
@MainActor
@Observable
final class ResourceMonitor {

    // MARK: - Published Properties

    /// Current CPU usage as a percentage (0.0 to 100.0).
    var cpuUsage: Double = 0.0

    /// Current memory usage as a percentage (0.0 to 100.0).
    var memoryUsage: Double = 0.0

    /// Current disk write speed in MB/s, or `nil` if unavailable.
    ///
    /// macOS exposes no public API that attributes disk-write throughput to a
    /// specific process, and the heavy writes during a conversion happen in the
    /// bundled `ffmpeg` *child* process rather than this app — so an honest
    /// per-encode figure cannot be derived here. Reported as unavailable
    /// (`nil`) rather than fabricated. See `gpuUsage` for the same treatment.
    var diskWriteSpeed: Double?

    /// Current GPU usage as a percentage, or `nil` if unavailable.
    var gpuUsage: Double?

    /// Whether the system temperature exceeds the warning threshold.
    var temperatureWarning: Bool = false

    /// Whether the monitor is currently polling.
    var isMonitoring: Bool = false

    // MARK: - Historical Data

    /// CPU usage history for the last 60 seconds.
    var cpuHistory: [Double] = []

    /// Memory usage history for the last 60 seconds.
    var memoryHistory: [Double] = []

    // MARK: - Private

    /// Maximum number of historical data points to retain (60 seconds).
    private let maxHistoryCount = 60

    /// Timer driving the polling loop.
    private var timer: Timer?

    /// Previous-sample CPU tick totals, kept so each poll can compute
    /// the *delta* between samples (the only way to derive a meaningful
    /// percentage from monotonically-increasing tick counters).
    /// `nil` until the first sample completes.
    private var previousCPUTicks: CPUTickTotals?

    // MARK: - Lifecycle

    /// Starts resource monitoring with one-second polling intervals.
    ///
    /// If monitoring is already active, this method is a no-op.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        cpuHistory.removeAll()
        memoryHistory.removeAll()

        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollResources()
            }
        }
    }

    /// Stops resource monitoring and invalidates the polling timer.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    // MARK: - Polling

    /// Samples current system resource metrics.
    private func pollResources() {
        let info = ProcessInfo.processInfo

        // CPU: real system-wide CPU usage via host_statistics(HOST_CPU_LOAD_INFO).
        //
        // The kernel exposes four monotonically-increasing tick
        // counters per host (user / system / idle / nice). The
        // percentage for the *interval since the previous poll* is:
        //   busy_delta / total_delta * 100
        // where busy_delta = (user + system + nice) deltas and
        // total_delta = busy_delta + idle_delta.
        //
        // The first poll has no prior sample to diff against, so
        // ``cpuUsage`` is left at its previous value (0.0 on first
        // run) and the baseline is stashed for the next tick.
        if let sample = sampleCPUTicks() {
            if let prev = previousCPUTicks {
                let userDelta   = sample.user   &- prev.user
                let systemDelta = sample.system &- prev.system
                let idleDelta   = sample.idle   &- prev.idle
                let niceDelta   = sample.nice   &- prev.nice
                let busy  = userDelta &+ systemDelta &+ niceDelta
                let total = busy &+ idleDelta
                if total > 0 {
                    cpuUsage = min(
                        (Double(busy) / Double(total)) * 100.0,
                        100.0
                    )
                }
            }
            previousCPUTicks = sample
        }

        // Memory: Use ProcessInfo physical memory and approximate usage.
        let totalMemory = Double(info.physicalMemory)
        // Approximate used memory via task_info in a simplified manner.
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size
        ) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPtr,
                    &count
                )
            }
        }
        if result == KERN_SUCCESS {
            let usedMemory = Double(taskInfo.resident_size)
            memoryUsage = (usedMemory / totalMemory) * 100.0
        }

        // Disk: no public API attributes write throughput to a process, and the
        // encode's heavy writes happen in the ffmpeg child process, not here —
        // so report as unavailable rather than fabricate a figure.
        diskWriteSpeed = nil

        // GPU: Not available via public API without IOKit private headers.
        // Set to nil to indicate unavailability.
        gpuUsage = nil

        // Temperature warning based on ProcessInfo thermal state.
        temperatureWarning = info.thermalState == .serious
                          || info.thermalState == .critical

        // Append to history, trimming to max count.
        cpuHistory.append(cpuUsage)
        memoryHistory.append(memoryUsage)

        if cpuHistory.count > maxHistoryCount {
            cpuHistory.removeFirst()
        }
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst()
        }
    }

    // Note: Timer cleanup is handled by stopMonitoring() called from
    // the view's onDisappear modifier. A deinit cannot be used here
    // because @MainActor isolation prevents accessing `timer` from
    // the nonisolated deinit context in Swift 6.

    // MARK: - CPU Sampling

    /// Snapshot of the kernel's host-wide CPU tick counters.
    ///
    /// Each field is a *cumulative* count of clock ticks the system
    /// has spent in that state since boot. They only become a usable
    /// percentage when diffed against a prior sample.
    fileprivate struct CPUTickTotals {
        let user: natural_t
        let system: natural_t
        let idle: natural_t
        let nice: natural_t
    }

    /// Reads the current host CPU tick counters via the mach
    /// ``host_statistics`` API (`HOST_CPU_LOAD_INFO`).
    ///
    /// Returns `nil` if the kernel call fails for any reason — the
    /// caller is expected to fall back to leaving ``cpuUsage`` at its
    /// previous value rather than displaying a fabricated number.
    private func sampleCPUTicks() -> CPUTickTotals? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                intPtr in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    intPtr,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTickTotals(
            user:   info.cpu_ticks.0,   // CPU_STATE_USER
            system: info.cpu_ticks.1,   // CPU_STATE_SYSTEM
            idle:   info.cpu_ticks.2,   // CPU_STATE_IDLE
            nice:   info.cpu_ticks.3    // CPU_STATE_NICE
        )
    }
}

// ---------------------------------------------------------------------------
// MARK: - ResourceMonitorView
// ---------------------------------------------------------------------------
/// Real-time system resource monitoring dashboard with live gauges,
/// usage bars, and sparkline history charts.
///
/// Displays CPU usage (circular gauge), memory usage (bar), disk write
/// speed, GPU usage (when available), temperature warnings, and a
/// historical sparkline covering the last 60 seconds of each metric.
///
/// Phase 13 — Resource Monitoring Dashboard (Issue #327)
struct ResourceMonitorView: View {

    // MARK: - State

    @State private var monitor = ResourceMonitor()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with start/stop controls
            headerBar

            Divider()

            // Gauges and charts
            ScrollView {
                VStack(spacing: 20) {
                    // Primary gauges row
                    HStack(spacing: 24) {
                        cpuGauge
                        memoryBar
                        diskSpeedIndicator
                    }
                    .padding(.horizontal, 20)

                    // GPU and temperature row
                    HStack(spacing: 24) {
                        gpuIndicator
                        temperatureBadge
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    Divider()
                        .padding(.horizontal, 20)

                    // Historical sparklines
                    VStack(alignment: .leading, spacing: 16) {
                        Text("History (last 60s)")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        sparklineSection(
                            title: "CPU Usage",
                            data: monitor.cpuHistory,
                            color: .blue,
                            unit: "%"
                        )

                        sparklineSection(
                            title: "Memory Usage",
                            data: monitor.memoryHistory,
                            color: .green,
                            unit: "%"
                        )
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .onDisappear {
            monitor.stopMonitoring()
        }
    }

    // MARK: - Header

    /// Header bar with monitoring controls.
    private var headerBar: some View {
        HStack {
            Text("Resource Monitor")
                .font(.headline)

            Spacer()

            if monitor.isMonitoring {
                Button("Stop Monitoring") {
                    monitor.stopMonitoring()
                }
            } else {
                Button("Start Monitoring") {
                    monitor.startMonitoring()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - CPU Gauge

    /// Circular gauge showing current CPU usage.
    private var cpuGauge: some View {
        VStack(spacing: 8) {
            Gauge(value: monitor.cpuUsage, in: 0...100) {
                Text("CPU")
                    .font(.caption)
            } currentValueLabel: {
                Text(String(format: "%.0f%%", monitor.cpuUsage))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(cpuGaugeGradient)
            .frame(width: 80, height: 80)

            Text("CPU Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Gradient for the CPU gauge that shifts from green to red.
    private var cpuGaugeGradient: some ShapeStyle {
        if monitor.cpuUsage > 80 {
            return AnyShapeStyle(.red)
        } else if monitor.cpuUsage > 50 {
            return AnyShapeStyle(.orange)
        } else {
            return AnyShapeStyle(.green)
        }
    }

    // MARK: - Memory Bar

    /// Horizontal bar showing memory usage.
    private var memoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", monitor.memoryUsage))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(.green)
                        .frame(
                            width: geometry.size.width
                                 * min(monitor.memoryUsage / 100.0, 1.0)
                        )
                }
            }
            .frame(height: 8)

            Text("Memory Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 120)
    }

    // MARK: - Disk Speed

    /// Disk write speed indicator (shows N/A when unavailable).
    private var diskSpeedIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(monitor.diskWriteSpeed != nil ? .blue : .secondary)

            if let disk = monitor.diskWriteSpeed {
                Text(String(format: "%.0f MB/s", disk))
                    .font(.title3)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            } else {
                Text("N/A")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("Disk Write")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - GPU Indicator

    /// GPU usage indicator (shows N/A when unavailable).
    private var gpuIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(monitor.gpuUsage != nil ? .purple : .secondary)

            if let gpu = monitor.gpuUsage {
                Text(String(format: "%.0f%%", gpu))
                    .font(.title3)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            } else {
                Text("N/A")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("GPU Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Temperature Badge

    /// Temperature warning badge.
    private var temperatureBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: monitor.temperatureWarning
                  ? "thermometer.sun.fill"
                  : "thermometer.medium")
            .foregroundStyle(monitor.temperatureWarning ? .red : .green)

            Text(monitor.temperatureWarning ? "High Temp" : "Normal")
                .font(.subheadline)
                .foregroundStyle(monitor.temperatureWarning ? .red : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            monitor.temperatureWarning
                ? Color.red.opacity(0.1)
                : Color.green.opacity(0.05),
            in: Capsule()
        )
    }

    // MARK: - Sparkline

    /// A labelled sparkline chart for a single metric's history.
    private func sparklineSection(
        title: String,
        data: [Double],
        color: Color,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let latest = data.last {
                    Text(String(format: "%.1f %@", latest, unit))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            sparklineChart(data: data, color: color)
                .frame(height: 40)
        }
        .padding(.horizontal, 20)
    }

    /// Mini line chart (sparkline) for historical data points.
    private func sparklineChart(data: [Double], color: Color) -> some View {
        GeometryReader { geometry in
            if data.count > 1 {
                let maxVal = max(data.max() ?? 1, 1)
                let width = geometry.size.width
                let height = geometry.size.height

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = width * Double(index) / Double(data.count - 1)
                        let y = height * (1.0 - value / maxVal)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 1.5)
            } else {
                Rectangle()
                    .fill(color.opacity(0.1))
            }
        }
    }
}
