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

    /// The engine metric type(s) this selection expands to. "All" runs
    /// VMAF, SSIM, and PSNR as separate sequential FFmpeg passes (Issue #434).
    var qualityMetricTypes: [QualityMetricType] {
        switch self {
        case .vmaf: return [.vmaf]
        case .ssim: return [.ssim]
        case .psnr: return [.psnr]
        case .all: return [.vmaf, .ssim, .psnr]
        }
    }
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

    // MARK: - Cancellation (Issue #434)

    /// The in-flight analysis task, retained so it can be cancelled when the
    /// user cancels or the view disappears. `nonisolated(unsafe)` because
    /// `deinit` (always nonisolated, even for `@MainActor` classes) needs to
    /// cancel it too — mirrors `StoreManager.transactionListenerTask`.
    @ObservationIgnored
    nonisolated(unsafe) private var analysisTask: Task<Void, Never>?

    /// The FFmpeg process controller for the pass currently running,
    /// retained so `cancelAnalysis()` can stop the running process rather
    /// than merely abandoning it.
    @ObservationIgnored
    nonisolated(unsafe) private var currentController: FFmpegProcessController?

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
    /// Mirrors the execution pattern proven in
    /// `LoudnessReportView.runAnalysis()` (Issue #433): locate FFmpeg via
    /// `FFmpegBundleManager`, build arguments with the `QualityMetrics`
    /// builders, run them through `FFmpegProcessController.startEncoding(
    /// arguments:)`, then parse the result — from the VMAF JSON log for
    /// VMAF, or from `controller.errorOutput` (stderr) for SSIM/PSNR.
    ///
    /// "All" runs VMAF, SSIM, and PSNR as three sequential FFmpeg passes so
    /// each metric gets its own dedicated filter graph and log/output to
    /// parse (a single combined pass cannot report all three independently).
    ///
    /// The background work runs on a detached task — this view model is
    /// `@MainActor`-isolated, so a plain `Task { }` here would infer that
    /// isolation and could block the UI thread on the libvmaf pre-flight
    /// probe (which blocks synchronously on process exit) and on the
    /// FFmpeg passes themselves. All UI-state mutations explicitly hop back
    /// to the main actor.
    func runAnalysis() {
        guard canRunAnalysis else { return }

        isAnalysing = true
        errorMessage = nil
        result = nil
        perFrameData = []
        generatedCommand = ""

        let reference = referencePath
        let distorted = distortedPath
        let metric = selectedMetric

        analysisTask = Task.detached { [weak self] in
            let bundleManager = FFmpegBundleManager()
            let ffmpegPath: String
            do {
                ffmpegPath = try bundleManager.locateFFmpeg().path
            } catch {
                await MainActor.run {
                    self?.errorMessage = "FFmpeg could not be found. Install FFmpeg or configure its location in Settings before analysing quality."
                    self?.isAnalysing = false
                }
                return
            }

            var metricsToRun = metric.qualityMetricTypes

            // VMAF pre-flight (Issue #434): libvmaf may be absent even in an
            // otherwise-working FFmpeg build. Skip VMAF gracefully rather
            // than letting the whole pass fail with a filter-not-found error.
            if metricsToRun.contains(.vmaf) {
                let hasLibvmaf = Self.probeLibvmafAvailable(ffmpegPath: ffmpegPath)
                if !hasLibvmaf {
                    metricsToRun.removeAll { $0 == .vmaf }
                    await MainActor.run {
                        if metric == .vmaf {
                            self?.errorMessage = "VMAF requires an FFmpeg build with libvmaf support, which this FFmpeg binary does not have. Install a build with --enable-libvmaf, or choose SSIM/PSNR instead."
                        } else {
                            self?.errorMessage = "VMAF was skipped: this FFmpeg binary was not built with libvmaf support. SSIM and PSNR were still computed."
                        }
                    }
                }
            }

            guard !metricsToRun.isEmpty else {
                await MainActor.run { self?.isAnalysing = false }
                return
            }

            var vmafScore: Double?
            var perFrame: [Double]?
            var ssimScore: Double?
            var psnrScore: Double?
            var commandsRun: [String] = []

            passLoop: for metricType in metricsToRun {
                if Task.isCancelled { break passLoop }

                let controller = FFmpegProcessController(binaryPath: ffmpegPath)
                await MainActor.run { self?.currentController = controller }

                var vmafLogPath: String?
                let arguments: [String]
                switch metricType {
                case .vmaf:
                    let logPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent("vmaf_log_\(UUID().uuidString).json").path
                    vmafLogPath = logPath
                    arguments = QualityMetrics.buildVMAFArguments(
                        referencePath: reference,
                        distortedPath: distorted,
                        logPath: logPath
                    )
                case .ssim:
                    arguments = QualityMetrics.buildSSIMArguments(
                        referencePath: reference,
                        distortedPath: distorted
                    )
                case .psnr:
                    arguments = QualityMetrics.buildPSNRArguments(
                        referencePath: reference,
                        distortedPath: distorted
                    )
                }

                commandsRun.append("ffmpeg " + arguments.joined(separator: " "))

                defer {
                    if let vmafLogPath {
                        try? FileManager.default.removeItem(atPath: vmafLogPath)
                    }
                }

                do {
                    let progressStream = try controller.startEncoding(arguments: arguments)
                    for await _ in progressStream {
                        if Task.isCancelled {
                            controller.stopEncoding()
                            break
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "\(metricType.rawValue.uppercased()) analysis failed: \(error.localizedDescription)"
                    }
                    continue passLoop
                }

                if Task.isCancelled { break passLoop }

                switch metricType {
                case .vmaf:
                    if let vmafLogPath, let parsed = QualityMetrics.parseVMAFLog(vmafLogPath) {
                        vmafScore = parsed.vmaf
                        perFrame = parsed.perFrameScores
                    } else {
                        // Fall back to the aggregate score FFmpeg also prints
                        // to stderr, in case the JSON log could not be read.
                        vmafScore = QualityMetricsBuilder.parseVMAFScore(from: controller.errorOutput)
                    }
                case .ssim:
                    ssimScore = QualityMetrics.parseSSIMOutput(controller.errorOutput)
                case .psnr:
                    psnrScore = QualityMetrics.parsePSNROutput(controller.errorOutput)
                }
            }

            let finalResult = QualityScoreResult(
                vmaf: vmafScore,
                ssim: ssimScore,
                psnr: psnrScore,
                perFrameScores: perFrame
            )
            let combinedCommand = commandsRun.joined(separator: "\n\n")

            await MainActor.run {
                self?.currentController = nil
                self?.generatedCommand = combinedCommand
                if vmafScore == nil && ssimScore == nil && psnrScore == nil {
                    if self?.errorMessage == nil {
                        self?.errorMessage = "Could not read quality metric data from the FFmpeg output."
                    }
                } else {
                    self?.result = finalResult
                    self?.perFrameData = (perFrame ?? []).enumerated().map {
                        PerFrameDataPoint(frame: $0.offset, score: $0.element)
                    }
                }
                self?.isAnalysing = false
            }
        }
    }

    /// Cancel an in-progress quality analysis.
    ///
    /// Stops the currently-running FFmpeg process (if any), cancels the
    /// analysis `Task`, and deletes any in-flight VMAF temp log so no
    /// process, task, or temp file is left behind after the user cancels or
    /// navigates away from this view.
    func cancelAnalysis() {
        currentController?.stopEncoding()
        currentController = nil
        analysisTask?.cancel()
        analysisTask = nil
        isAnalysing = false
    }

    /// Clears all results and resets the view model.
    func clearResults() {
        result = nil
        perFrameData = []
        generatedCommand = ""
        errorMessage = nil
    }

    /// Whether the given FFmpeg binary was built with libvmaf support.
    ///
    /// Probes the compiled-in filter list (`-hide_banner -filters`) rather
    /// than attempting to run VMAF outright, so a build missing libvmaf can
    /// be detected and reported gracefully instead of failing the whole
    /// pass with an obscure "no such filter" error. Bundled static builds
    /// usually include libvmaf; a user-supplied or Homebrew FFmpeg might not.
    ///
    /// `nonisolated` (not `@MainActor`, despite the enclosing class) and
    /// invoked from a detached task so the blocking `waitUntilExit()` call
    /// never runs on the main thread.
    private nonisolated static func probeLibvmafAvailable(ffmpegPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-hide_banner", "-filters"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("libvmaf")
    }

    deinit {
        currentController?.stopEncoding()
        analysisTask?.cancel()
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
        .onDisappear {
            viewModel.cancelAnalysis()
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

                if viewModel.isAnalysing {
                    Button {
                        viewModel.cancelAnalysis()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Cancel quality analysis")
                }

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
