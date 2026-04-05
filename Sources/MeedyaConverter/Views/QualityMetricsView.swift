// ============================================================================
// MeedyaConverter — QualityMetricsView (Issue #291)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import Charts
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - MetricSelection
// ---------------------------------------------------------------------------
/// The quality metric(s) the user has selected for analysis.
enum MetricSelection: String, CaseIterable, Identifiable {
    /// VMAF only.
    case vmaf = "VMAF"
    /// SSIM only.
    case ssim = "SSIM"
    /// PSNR only.
    case psnr = "PSNR"
    /// All three metrics.
    case all = "All"

    var id: String { rawValue }
}

// ---------------------------------------------------------------------------
// MARK: - PerFrameDataPoint
// ---------------------------------------------------------------------------
/// A single data point for the per-frame quality chart.
struct PerFrameDataPoint: Identifiable {
    let id = UUID()
    /// Frame index (zero-based).
    let frame: Int
    /// Quality score for this frame.
    let score: Double
}

// ---------------------------------------------------------------------------
// MARK: - QualityMetricsViewModel
// ---------------------------------------------------------------------------
/// Observable view model for the quality metrics analysis interface.
///
/// Manages file selection, metric configuration, analysis execution,
/// and result display. Integrates with `QualityMetrics` and
/// `QualityMetricsBuilder` from ConverterEngine to build FFmpeg arguments
/// and parse output.
///
/// Thread safety: `@MainActor`-isolated for safe SwiftUI binding.
@MainActor
@Observable
final class QualityMetricsViewModel {

    // MARK: - File Selection

    /// Path to the reference (original source) video.
    var referencePath: String = ""

    /// Path to the distorted (encoded) video.
    var distortedPath: String = ""

    // MARK: - Configuration

    /// The metric(s) selected for analysis.
    var selectedMetric: MetricSelection = .vmaf

    // MARK: - Results

    /// The analysis result, populated after a successful run.
    var result: QualityScoreResult?

    /// Per-frame data points for the chart, derived from the result.
    var perFrameData: [PerFrameDataPoint] = []

    /// Whether analysis is currently running.
    var isAnalysing: Bool = false

    /// Error message from the last failed analysis, if any.
    var errorMessage: String?

    /// Human-readable summary of the generated FFmpeg command.
    var generatedCommand: String = ""

    // MARK: - Computed Properties

    /// Whether both file paths are set and valid for analysis.
    var canRunAnalysis: Bool {
        !referencePath.isEmpty && !distortedPath.isEmpty && !isAnalysing
    }

    /// The quality grade string based on the current result.
    var qualityGrade: String {
        result?.qualityGrade ?? "N/A"
    }

    /// Colour associated with the current quality grade.
    var gradeColor: Color {
        switch qualityGrade {
        case "Excellent": return .green
        case "Good":      return .blue
        case "Fair":      return .orange
        case "Poor":      return .red
        default:          return .secondary
        }
    }

    // MARK: - Analysis

    /// Runs the quality analysis with the current configuration.
    ///
    /// Generates the FFmpeg command arguments, updates the command
    /// preview, and (in a full implementation) would execute FFmpeg
    /// and parse the results.
    func runAnalysis() {
        guard canRunAnalysis else { return }

        isAnalysing = true
        errorMessage = nil

        // Generate the appropriate FFmpeg arguments
        var args: [String] = []

        switch selectedMetric {
        case .vmaf:
            let logPath = NSTemporaryDirectory() + "vmaf_log_\(UUID().uuidString).json"
            args = QualityMetrics.buildVMAFArguments(
                referencePath: referencePath,
                distortedPath: distortedPath,
                logPath: logPath
            )
        case .ssim:
            args = QualityMetrics.buildSSIMArguments(
                referencePath: referencePath,
                distortedPath: distortedPath
            )
        case .psnr:
            args = QualityMetrics.buildPSNRArguments(
                referencePath: referencePath,
                distortedPath: distortedPath
            )
        case .all:
            args = QualityMetricsBuilder.buildCombinedArguments(
                referencePath: referencePath,
                distortedPath: distortedPath
            )
        }

        generatedCommand = "ffmpeg " + args.joined(separator: " ")

        // In a full implementation, this would execute FFmpeg via
        // FFmpegProcessController and parse the output. For now,
        // we populate the command preview and mark analysis as complete.
        isAnalysing = false
    }

    /// Clears all results and resets the view model.
    func clearResults() {
        result = nil
        perFrameData = []
        generatedCommand = ""
        errorMessage = nil
    }
}

// ---------------------------------------------------------------------------
// MARK: - QualityMetricsView
// ---------------------------------------------------------------------------
/// VMAF/SSIM/PSNR quality analysis interface.
///
/// Allows the user to select reference and distorted video files, choose
/// which metric(s) to compute, run the analysis, and view results
/// including overall scores with gauges and per-frame quality charts.
///
/// Phase 7 — VMAF/SSIM Quality Scoring (Issue #291)
struct QualityMetricsView: View {

    // MARK: - State

    /// View model managing quality analysis state.
    @State private var viewModel = QualityMetricsViewModel()

    /// Whether the reference file picker is presented.
    @State private var showReferencePicker: Bool = false

    /// Whether the distorted file picker is presented.
    @State private var showDistortedPicker: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fileSelectionSection
                metricConfigSection
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }
                if viewModel.result != nil {
                    scoreDisplaySection
                    perFrameChartSection
                }
                commandPreviewSection
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 500)
        .fileImporter(
            isPresented: $showReferencePicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.referencePath = url.path
            }
        }
        .fileImporter(
            isPresented: $showDistortedPicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .video],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.distortedPath = url.path
            }
        }
    }

    // MARK: - File Selection

    /// Reference and distorted file picker controls.
    private var fileSelectionSection: some View {
        GroupBox("File Selection") {
            VStack(alignment: .leading, spacing: 12) {
                // Reference file
                HStack {
                    Text("Reference:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Select original/source video...", text: $viewModel.referencePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        showReferencePicker = true
                    }
                }

                // Distorted file
                HStack {
                    Text("Distorted:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Select encoded/distorted video...", text: $viewModel.distortedPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        showDistortedPicker = true
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Metric Configuration

    /// Metric selector and run button.
    private var metricConfigSection: some View {
        GroupBox("Analysis Configuration") {
            HStack(spacing: 16) {
                Text("Metric:")
                    .frame(width: 80, alignment: .trailing)

                Picker("Metric", selection: $viewModel.selectedMetric) {
                    ForEach(MetricSelection.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                Button {
                    viewModel.runAnalysis()
                } label: {
                    Label(
                        viewModel.isAnalysing ? "Analysing..." : "Run Analysis",
                        systemImage: viewModel.isAnalysing ? "hourglass" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRunAnalysis)
                .accessibilityLabel(viewModel.isAnalysing ? "Analysis in progress" : "Run quality analysis")

                Button {
                    viewModel.clearResults()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(viewModel.result == nil && viewModel.generatedCommand.isEmpty)
                .accessibilityLabel("Clear analysis results")
            }
            .padding(8)
        }
    }

    // MARK: - Score Display

    /// Gauge-style display of the analysis scores.
    private var scoreDisplaySection: some View {
        GroupBox("Quality Scores") {
            HStack(spacing: 32) {
                if let vmaf = viewModel.result?.vmaf {
                    scoreGauge(
                        title: "VMAF",
                        value: vmaf,
                        maxValue: 100,
                        color: vmaf >= 93 ? .green : vmaf >= 80 ? .blue : vmaf >= 60 ? .orange : .red
                    )
                }

                if let ssim = viewModel.result?.ssim {
                    scoreGauge(
                        title: "SSIM",
                        value: ssim,
                        maxValue: 1.0,
                        color: ssim >= 0.97 ? .green : ssim >= 0.92 ? .blue : ssim >= 0.85 ? .orange : .red
                    )
                }

                if let psnr = viewModel.result?.psnr {
                    scoreGauge(
                        title: "PSNR",
                        value: psnr,
                        maxValue: 60,
                        color: psnr >= 40 ? .green : psnr >= 35 ? .blue : psnr >= 30 ? .orange : .red
                    )
                }

                Spacer()

                // Overall grade
                VStack(spacing: 4) {
                    Text(viewModel.qualityGrade)
                        .font(.title.bold())
                        .foregroundStyle(viewModel.gradeColor)
                    Text("Overall Grade")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let result = viewModel.result {
                        Image(systemName: result.meetsRecommendedThresholds
                              ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(result.meetsRecommendedThresholds ? .green : .red)
                            .help(result.meetsRecommendedThresholds
                                  ? "Meets recommended quality thresholds"
                                  : "Below recommended quality thresholds")
                            .accessibilityLabel(result.meetsRecommendedThresholds
                                  ? "Passes quality thresholds"
                                  : "Below quality thresholds")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    /// A single circular score gauge.
    private func scoreGauge(
        title: String,
        value: Double,
        maxValue: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Gauge(value: value, in: 0...maxValue) {
                Text(title)
                    .font(.caption.bold())
            } currentValueLabel: {
                Text(title == "SSIM"
                     ? String(format: "%.4f", value)
                     : String(format: "%.1f", value))
                    .font(.caption.monospaced())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            .scaleEffect(1.4)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 100)
    }

    // MARK: - Per-Frame Chart

    /// Swift Charts view showing per-frame quality scores.
    private var perFrameChartSection: some View {
        GroupBox("Per-Frame Quality") {
            if viewModel.perFrameData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Per-frame data will appear here after VMAF analysis with logging enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                Chart(viewModel.perFrameData) { point in
                    LineMark(
                        x: .value("Frame", point.frame),
                        y: .value("Score", point.score)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXAxisLabel("Frame")
                .chartYAxisLabel("VMAF Score")
                .frame(height: 200)
                .padding(8)
            }
        }
    }

    // MARK: - Command Preview

    /// Preview of the generated FFmpeg command.
    private var commandPreviewSection: some View {
        GroupBox("Generated FFmpeg Command") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.generatedCommand.isEmpty {
                    Text("Configure files and metric, then click \"Run Analysis\" to generate the command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    Text(viewModel.generatedCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(4)

                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.generatedCommand, forType: .string)
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy generated command to clipboard")
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Error Banner

    /// Displays an error message.
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss error message")
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Preview
// ---------------------------------------------------------------------------
#if DEBUG
#Preview("Quality Metrics") {
    QualityMetricsView()
        .frame(width: 700, height: 600)
}
#endif
