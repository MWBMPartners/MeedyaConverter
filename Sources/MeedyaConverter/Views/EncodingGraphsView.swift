// ============================================================================
// MeedyaConverter — EncodingGraphsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import Charts
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - GraphMetric

/// Selectable metrics for the encoding graph.
enum GraphMetric: String, CaseIterable, Identifiable {
    case fps = "FPS"
    case bitrate = "Bitrate"
    case fileSize = "File Size"
    case quantizer = "Quantizer"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var unit: String {
        switch self {
        case .fps: return "fps"
        case .bitrate: return "kbps"
        case .fileSize: return "MB"
        case .quantizer: return "QP"
        }
    }

    var color: Color {
        switch self {
        case .fps: return .blue
        case .bitrate: return .orange
        case .fileSize: return .green
        case .quantizer: return .purple
        }
    }
}

// MARK: - EncodingGraphsView

/// Displays real-time and historical encoding performance graphs.
///
/// Shows FPS, bitrate, file size growth, and quantizer time-series
/// charts during and after encoding jobs. Uses Swift Charts for
/// native macOS chart rendering.
///
/// Phase 7.4
struct EncodingGraphsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var selectedMetric: GraphMetric = .fps
    @State private var selectedJobID: UUID?

    /// Persisted history of completed encoding job statistics, backing
    /// the graphs below. Real, already-tested component
    /// (`EncodingStatisticsStore` in `ConverterEngine`) — reads its JSON
    /// history from disk in its initializer, the same way `CloudSyncView`
    /// seeds its `@State` directly from `CloudProfileSync.shared`.
    @State private var statisticsStore = EncodingStatisticsStore()

    /// Set after a failed CSV export attempt; cleared on the next
    /// successful export or metric change. Never set on success — a
    /// successful export closes the save panel with no further UI, mirroring
    /// `BitrateHeatmapView.exportAsImage()`.
    @State private var exportErrorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Metric selector
            metricPicker

            if let exportErrorMessage {
                exportErrorBanner(message: exportErrorMessage)
            }

            Divider()

            // Main chart area
            if let stats = currentStatistics {
                chartView(for: stats)
                    .padding()

                Divider()

                // Summary statistics
                statisticsSummary(for: stats)
                    .padding()
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Encoding Graphs")
        .onAppear {
            // Reload from disk each time this view appears so a job
            // completed since the store was last constructed shows up.
            // `EncodingStatisticsStore` only reads its history file inside
            // `init()`, so a fresh instance is how a re-read happens.
            // `EncodingStatisticsStore` is `@unchecked Sendable`, so the
            // (potentially non-trivial) JSON decode of the history file is
            // kept off the main actor via `Task.detached`, mirroring
            // `QualityMetricsView.runAnalysis()`'s handling of
            // `FFmpegBundleManager.locateFFmpeg()` — this `Task { }` itself
            // is created from a `View` body closure, so it inherits
            // main-actor isolation and the assignment below is a direct
            // `@State` write, not a `MainActor.run` hop.
            Task {
                statisticsStore = await Task.detached {
                    EncodingStatisticsStore()
                }.value
            }
        }
    }

    // MARK: - Subviews

    private var metricPicker: some View {
        HStack {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(GraphMetric.allCases) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(statisticsStore.allStatistics.isEmpty)
            .help("Export all recorded encoding statistics as CSV")
            .accessibilityLabel("Export encoding statistics as CSV")

            if let stats = currentStatistics {
                Text(stats.jobName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Inline banner shown after a failed CSV export attempt.
    private func exportErrorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
            Button("Dismiss") {
                exportErrorMessage = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func chartView(for stats: EncodingStatistics) -> some View {
        switch selectedMetric {
        case .fps:
            fpsChart(stats: stats)
        case .bitrate:
            bitrateChart(stats: stats)
        case .fileSize:
            fileSizeChart(stats: stats)
        case .quantizer:
            quantizerChart(stats: stats)
        }
    }

    private func fpsChart(stats: EncodingStatistics) -> some View {
        let data = stats.fpsTimeSeries
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("FPS", point.value)
                )
                .foregroundStyle(GraphMetric.fps.color)
            }

            if stats.averageFPS > 0 {
                RuleMark(y: .value("Average", stats.averageFPS))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Avg: \(String(format: "%.1f", stats.averageFPS)) fps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxisLabel("Elapsed Time (seconds)")
        .chartYAxisLabel("Frames per Second")
        .frame(minHeight: 250)
    }

    private func bitrateChart(stats: EncodingStatistics) -> some View {
        let data = stats.bitrateTimeSeries
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("Bitrate (kbps)", point.value)
                )
                .foregroundStyle(
                    GraphMetric.bitrate.color.opacity(0.3)
                )

                LineMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("Bitrate (kbps)", point.value)
                )
                .foregroundStyle(GraphMetric.bitrate.color)
            }
        }
        .chartXAxisLabel("Elapsed Time (seconds)")
        .chartYAxisLabel("Bitrate (kbps)")
        .frame(minHeight: 250)
    }

    private func fileSizeChart(stats: EncodingStatistics) -> some View {
        let data = stats.fileSizeTimeSeries.map {
            (elapsed: $0.elapsed, value: Double($0.value) / 1_048_576.0)
        }
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("Size (MB)", point.value)
                )
                .foregroundStyle(
                    GraphMetric.fileSize.color.opacity(0.3)
                )

                LineMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("Size (MB)", point.value)
                )
                .foregroundStyle(GraphMetric.fileSize.color)
            }
        }
        .chartXAxisLabel("Elapsed Time (seconds)")
        .chartYAxisLabel("Output Size (MB)")
        .frame(minHeight: 250)
    }

    private func quantizerChart(stats: EncodingStatistics) -> some View {
        let data = stats.quantizerTimeSeries
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time (s)", point.elapsed),
                    y: .value("QP", point.value)
                )
                .foregroundStyle(GraphMetric.quantizer.color)
            }
        }
        .chartXAxisLabel("Elapsed Time (seconds)")
        .chartYAxisLabel("Quantizer Parameter")
        .frame(minHeight: 250)
    }

    private func statisticsSummary(for stats: EncodingStatistics) -> some View {
        HStack(spacing: 24) {
            statCard(
                title: "Average FPS",
                value: String(format: "%.1f", stats.averageFPS),
                unit: "fps"
            )

            if let bitrate = stats.averageBitrate {
                statCard(
                    title: "Average Bitrate",
                    value: String(format: "%.0f", bitrate),
                    unit: "kbps"
                )
            }

            if let ratio = stats.compressionRatio {
                statCard(
                    title: "Compression",
                    value: String(format: "%.1f", ratio),
                    unit: "x"
                )
            }

            if let savings = stats.spaceSavingsPercent {
                statCard(
                    title: "Space Saved",
                    value: String(format: "%.1f", savings),
                    unit: "%"
                )
            }

            if let duration = stats.totalEncodingDuration {
                statCard(
                    title: "Duration",
                    value: formatDuration(duration),
                    unit: ""
                )
            }
        }
    }

    private func statCard(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 80)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Encoding Data",
            systemImage: "chart.xyaxis.line",
            description: Text("Encoding statistics will appear here during and after encoding jobs.")
        )
    }

    // MARK: - Helpers

    /// The statistics currently displayed: the history entry matching
    /// `selectedJobID` if one is set, otherwise the most recently
    /// completed job. Real data sourced from `EncodingStatisticsStore`
    /// (`ConverterEngine`) — `nil` (driving `emptyStateView` above) is an
    /// honest reflection of "no encode has been recorded yet", not a
    /// placeholder.
    private var currentStatistics: EncodingStatistics? {
        let history = statisticsStore.allStatistics
        if let selectedJobID {
            return history.first { $0.jobID == selectedJobID }
        }
        return history.first
    }

    // MARK: - Actions

    /// Exports every recorded job's statistics as CSV via
    /// `EncodingStatisticsStore.exportAsCSV()` (Issue #363) — one row per
    /// completed job, not just the currently-displayed one. Pure string
    /// formatting on the `ConverterEngine` side (see
    /// `EncodingStatistics.csvHeader`/`csvRow`); this method only adds the
    /// `NSSavePanel` and the file write, mirroring
    /// `BitrateHeatmapView.exportAsImage()` / `StatisticsExportView
    /// .exportData()`'s CSV branch.
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Encoding Statistics"
        panel.nameFieldStringValue = "encoding_statistics.csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try statisticsStore.exportAsCSV().write(to: url, options: .atomic)
            exportErrorMessage = nil
        } catch {
            exportErrorMessage = "Failed to export CSV: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}
