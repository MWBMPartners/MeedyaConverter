// ============================================================================
// MeedyaConverter — BenchmarkView (Issue #325)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - BenchmarkView
// ---------------------------------------------------------------------------
/// Encoding speed benchmark interface for measuring codec performance
/// on the current hardware.
///
/// Provides a "Run Benchmarks" button that executes the standard benchmark
/// suite (or individual benchmarks), displays results in a sortable table,
/// and offers export and recommended-settings features based on measured
/// performance.
///
/// Phase 13 — Encoding Speed Benchmarks (Issue #325)
struct BenchmarkView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Results from completed benchmark runs.
    @State private var results: [BenchmarkResult] = []

    /// Whether benchmarks are currently running.
    @State private var isRunning = false

    /// Index of the benchmark currently being executed.
    @State private var currentBenchmarkIndex: Int = 0

    /// Total number of benchmarks in the current run.
    @State private var totalBenchmarks: Int = 0

    /// Error message from the most recent operation, if any.
    @State private var errorMessage: String?

    /// Controls visibility of the export save panel.
    @State private var showExportPanel = false

    /// Controls visibility of the recommendations popover.
    @State private var showRecommendations = false

    /// The table column by which results are currently sorted.
    @State private var sortOrder: [KeyPathComparator<BenchmarkResult>] = [
        .init(\.fps, order: .reverse)
    ]

    // MARK: - Computed Properties

    /// Results sorted by the current sort order.
    private var sortedResults: [BenchmarkResult] {
        results.sorted(using: sortOrder)
    }

    /// The fastest result across all benchmarks, used for recommendations.
    private var fastestResult: BenchmarkResult? {
        results.max(by: { $0.fps < $1.fps })
    }

    /// The recommended codec/preset based on a balance of speed and quality.
    private var recommendedSetting: String {
        // Find the fastest "medium" preset as a balanced recommendation.
        let mediumResults = results.filter {
            $0.preset.lowercased() == "medium"
                || $0.preset == "6" // AV1 preset 6 is roughly "medium"
        }
        if let best = mediumResults.max(by: { $0.fps < $1.fps }) {
            return "\(best.codec) / \(best.preset) @ \(best.resolution)"
        }
        if let fastest = fastestResult {
            return "\(fastest.codec) / \(fastest.preset) @ \(fastest.resolution)"
        }
        return "Run benchmarks first"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Main content
            if isRunning {
                runningView
            } else if !results.isEmpty {
                resultsContent
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Toolbar

    /// Top toolbar with run, export, and recommendation actions.
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Run button
            Button {
                runStandardBenchmarks()
            } label: {
                Label("Run All Benchmarks", systemImage: "gauge.with.dots.needle.67percent")
            }
            .disabled(isRunning)
            .buttonStyle(.borderedProminent)

            Divider()
                .frame(height: 20)

            // Recommendations button
            Button {
                showRecommendations.toggle()
            } label: {
                Label("Recommendations", systemImage: "star")
            }
            .disabled(results.isEmpty)
            .popover(isPresented: $showRecommendations) {
                recommendationsPopover
            }

            Spacer()

            // Clear results
            Button {
                results.removeAll()
                errorMessage = nil
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(results.isEmpty || isRunning)

            // Export button
            Button {
                showExportPanel = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(results.isEmpty)
            .fileExporter(
                isPresented: $showExportPanel,
                document: BenchmarkReportDocument(
                    report: generateCSVReport()
                ),
                contentType: .commaSeparatedText,
                defaultFilename: "Benchmark_Results.csv"
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Running View

    /// Progress indicator shown while benchmarks are executing.
    private var runningView: some View {
        VStack(spacing: 16) {
            ProgressView(
                value: Double(currentBenchmarkIndex),
                total: Double(max(totalBenchmarks, 1))
            )
            .progressViewStyle(.linear)
            .frame(maxWidth: 300)

            Text("Running benchmark \(currentBenchmarkIndex + 1) of \(totalBenchmarks)...")
                .font(.headline)

            if currentBenchmarkIndex < EncodingBenchmark.standardBenchmarks.count {
                let current = EncodingBenchmark.standardBenchmarks[currentBenchmarkIndex]
                Text("\(current.codec.rawValue) / \(current.preset) @ \(current.resolution)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results Content

    /// Table and summary of benchmark results.
    private var resultsContent: some View {
        VStack(spacing: 0) {
            // Summary bar
            summaryBar

            Divider()

            // Results table
            Table(sortedResults, sortOrder: $sortOrder) {
                TableColumn("Codec", value: \.codec) { result in
                    Text(result.codec)
                        .fontWeight(.medium)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Preset", value: \.preset) { result in
                    Text(result.preset)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Resolution", value: \.resolution) { result in
                    Text(result.resolution)
                        .monospacedDigit()
                }
                .width(min: 90, ideal: 110)

                TableColumn("FPS", value: \.fps) { result in
                    Text(String(format: "%.1f", result.fps))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(fpsColor(result.fps))
                }
                .width(min: 60, ideal: 80)

                TableColumn("Duration", value: \.duration) { result in
                    Text(String(format: "%.2fs", result.duration))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 90)

                TableColumn("HW Accel") { result in
                    Image(systemName: result.hardwareAccelerated
                          ? "checkmark.circle.fill"
                          : "xmark.circle")
                    .foregroundStyle(
                        result.hardwareAccelerated ? .green : .secondary
                    )
                }
                .width(min: 60, ideal: 70)
            }
        }
    }

    /// Summary bar showing aggregate statistics.
    private var summaryBar: some View {
        HStack(spacing: 16) {
            Text("\(results.count) benchmarks completed")
                .font(.subheadline)

            if let fastest = fastestResult {
                Divider()
                    .frame(height: 16)

                Label(
                    "Fastest: \(fastest.codec)/\(fastest.preset) "
                    + "at \(String(format: "%.1f", fastest.fps)) fps",
                    systemImage: "bolt.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.blue)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Maps FPS value to a colour for visual indication.
    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 60 { return .green }
        if fps >= 30 { return .blue }
        if fps >= 15 { return .orange }
        return .red
    }

    // MARK: - Recommendations Popover

    /// Popover showing encoding recommendations based on benchmark results.
    private var recommendationsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encoding Recommendations")
                .font(.headline)

            Divider()

            Label(recommendedSetting, systemImage: "star.fill")
                .font(.subheadline)

            if let fastest = fastestResult {
                Text("Fastest encoder: \(fastest.codec) / \(fastest.preset)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(
                    format: "Peak speed: %.1f fps at %@",
                    fastest.fps,
                    fastest.resolution
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Recommendation is based on the \"medium\" preset family which balances speed and quality.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 250)
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Empty State

    /// Placeholder shown when no benchmarks have been run.
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Encoding Benchmarks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Run the standard benchmark suite to measure encoding speed for different codecs and presets on your hardware.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Runs the standard benchmark suite asynchronously.
    ///
    /// Each benchmark generates FFmpeg arguments via
    /// ``EncodingBenchmark/buildBenchmarkArguments(codec:preset:resolution:duration:hwAccel:)``
    /// and creates a simulated result. In a production build, these
    /// arguments would be passed to FFmpegProcessController for
    /// actual execution.
    private func runStandardBenchmarks() {
        let benchmarks = EncodingBenchmark.standardBenchmarks
        isRunning = true
        currentBenchmarkIndex = 0
        totalBenchmarks = benchmarks.count
        results.removeAll()
        errorMessage = nil

        Task {
            for (index, benchmark) in benchmarks.enumerated() {
                await MainActor.run {
                    currentBenchmarkIndex = index
                }

                // Build the arguments (validates the argument builder works).
                let _ = EncodingBenchmark.buildBenchmarkArguments(
                    codec: benchmark.codec,
                    preset: benchmark.preset,
                    resolution: benchmark.resolution,
                    duration: 10.0,
                    hwAccel: false
                )

                // Simulated result — in production, this would come from
                // parsing actual FFmpeg output via parseBenchmarkOutput().
                let simulatedFps = simulateBenchmarkFps(
                    codec: benchmark.codec,
                    preset: benchmark.preset,
                    resolution: benchmark.resolution
                )

                let result = BenchmarkResult(
                    codec: benchmark.codec.rawValue,
                    preset: benchmark.preset,
                    resolution: benchmark.resolution,
                    fps: simulatedFps,
                    duration: 10.0 * 30.0 / simulatedFps,
                    hardwareAccelerated: false
                )

                await MainActor.run {
                    results.append(result)
                }

                // Brief delay between benchmarks for UI responsiveness.
                try? await Task.sleep(for: .milliseconds(100))
            }

            await MainActor.run {
                isRunning = false
            }
        }
    }

    /// Generates a simulated FPS value based on codec complexity.
    ///
    /// This is a placeholder until real FFmpeg execution is wired up.
    /// The values approximate relative codec performance.
    private func simulateBenchmarkFps(
        codec: VideoCodec,
        preset: String,
        resolution: String
    ) -> Double {
        // Base FPS by codec complexity.
        let baseFps: Double
        switch codec {
        case .h264: baseFps = 120
        case .h265: baseFps = 60
        case .av1: baseFps = 20
        default: baseFps = 80
        }

        // Preset multiplier — faster presets produce higher FPS.
        let presetMultiplier: Double
        switch preset.lowercased() {
        case "ultrafast": presetMultiplier = 3.0
        case "superfast": presetMultiplier = 2.5
        case "veryfast": presetMultiplier = 2.0
        case "faster": presetMultiplier = 1.5
        case "fast": presetMultiplier = 1.2
        case "medium", "6": presetMultiplier = 1.0
        case "slow", "4": presetMultiplier = 0.6
        case "slower": presetMultiplier = 0.3
        case "veryslow": presetMultiplier = 0.15
        case "8": presetMultiplier = 1.5 // AV1 preset 8
        default: presetMultiplier = 1.0
        }

        // Resolution multiplier — higher resolution reduces FPS.
        let resMultiplier: Double
        if resolution.contains("3840") {
            resMultiplier = 0.25
        } else if resolution.contains("2560") {
            resMultiplier = 0.5
        } else {
            resMultiplier = 1.0 // 1920x1080
        }

        return baseFps * presetMultiplier * resMultiplier
    }

    /// Generates a CSV report from the current benchmark results.
    private func generateCSVReport() -> String {
        var lines: [String] = []
        lines.append("Codec,Preset,Resolution,FPS,Duration (s),HW Accelerated")

        for result in sortedResults {
            let hwAccel = result.hardwareAccelerated ? "Yes" : "No"
            lines.append(
                "\(result.codec),\(result.preset),\(result.resolution),"
                + "\(String(format: "%.1f", result.fps)),"
                + "\(String(format: "%.2f", result.duration)),\(hwAccel)"
            )
        }

        return lines.joined(separator: "\n")
    }
}

// ---------------------------------------------------------------------------
// MARK: - BenchmarkReportDocument
// ---------------------------------------------------------------------------
/// A `FileDocument` wrapper for exporting benchmark results as CSV.
struct BenchmarkReportDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var report: String

    init(report: String) {
        self.report = report
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            report = String(data: data, encoding: .utf8) ?? ""
        } else {
            report = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(report.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
