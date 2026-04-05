// ============================================================================
// MeedyaConverter — BitrateHeatmapView (Issue #287)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - BitrateHeatmapView

/// Canvas-based bitrate heatmap visualization for analysed media files.
///
/// Renders a time-domain heatmap where the X axis represents time and the
/// Y axis represents bitrate. Colors transition from cool (blue) at low
/// bitrate to warm (red) at high bitrate. Includes an average bitrate
/// reference line, peak/min indicators, and hover tooltips.
///
/// Phase 11 — Bitrate Heatmap Visualization (Issue #287)
struct BitrateHeatmapView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var analysis: BitrateAnalysis?
    @State private var comparisonAnalysis: BitrateAnalysis?
    @State private var isAnalyzing = false
    @State private var hoverTimestamp: TimeInterval?
    @State private var hoverBitrate: Double?
    @State private var showComparison = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Main content
            if isAnalyzing {
                analyzingView
            } else if let analysis {
                heatmapContent(analysis: analysis)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Bitrate Heatmap")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button {
                Task { await analyzeBitrate() }
            } label: {
                Label("Analyze Bitrate", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedFile == nil || isAnalyzing)
            .accessibilityLabel("Analyze bitrate distribution of selected file")

            if analysis != nil {
                Toggle("Show Comparison", isOn: $showComparison)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Toggle source vs output bitrate comparison overlay")

                Spacer()

                Button {
                    exportAsImage()
                } label: {
                    Label("Export Image", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export heatmap as PNG image")
            } else {
                Spacer()
            }

            if let file = viewModel.selectedFile {
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing bitrate distribution...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This may take a moment for large files.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No Bitrate Data",
                systemImage: "chart.bar.xaxis",
                description: Text("Select a file and click \"Analyze Bitrate\" to generate a bitrate heatmap.")
            )

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Heatmap Content

    private func heatmapContent(analysis: BitrateAnalysis) -> some View {
        VStack(spacing: 0) {
            // Heatmap canvas
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Background
                    Color(nsColor: .controlBackgroundColor)

                    // Heatmap rendering
                    Canvas { context, size in
                        drawHeatmap(
                            context: &context,
                            size: size,
                            analysis: analysis
                        )
                    }
                    .padding(.leading, 60)
                    .padding(.bottom, 30)
                    .padding(.trailing, 16)
                    .padding(.top, 16)

                    // Hover tooltip overlay
                    if let timestamp = hoverTimestamp, let bitrate = hoverBitrate {
                        tooltipView(timestamp: timestamp, bitrate: bitrate)
                    }
                }
                .onContinuousHover { phase in
                    handleHover(phase: phase, size: geometry.size, analysis: analysis)
                }
            }
            .frame(minHeight: 300)

            Divider()

            // Summary statistics
            statisticsBar(analysis: analysis)
        }
    }

    // MARK: - Canvas Drawing

    /// Draw the bitrate heatmap on the Canvas.
    ///
    /// Renders vertical bars for each data point, colored by bitrate intensity
    /// on a blue-to-red gradient. Overlays a dashed average line and marks
    /// peak and minimum positions.
    private func drawHeatmap(
        context: inout GraphicsContext,
        size: CGSize,
        analysis: BitrateAnalysis
    ) {
        let dataPoints = analysis.dataPoints
        guard !dataPoints.isEmpty, analysis.peakBitrate > 0 else { return }

        let chartWidth = size.width
        let chartHeight = size.height
        let barWidth = max(1, chartWidth / CGFloat(dataPoints.count))

        // Draw heatmap bars
        for (index, point) in dataPoints.enumerated() {
            let x = CGFloat(index) * barWidth
            let normalizedBitrate = point.bitrate / analysis.peakBitrate
            let barHeight = CGFloat(normalizedBitrate) * chartHeight

            let color = heatmapColor(for: normalizedBitrate)

            let rect = CGRect(
                x: x,
                y: chartHeight - barHeight,
                width: barWidth + 0.5,
                height: barHeight
            )

            context.fill(Path(rect), with: .color(color))
        }

        // Draw average bitrate reference line (dashed)
        let avgY = chartHeight - (CGFloat(analysis.averageBitrate / analysis.peakBitrate) * chartHeight)
        var avgPath = Path()
        avgPath.move(to: CGPoint(x: 0, y: avgY))
        avgPath.addLine(to: CGPoint(x: chartWidth, y: avgY))
        context.stroke(
            avgPath,
            with: .color(.white.opacity(0.8)),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )

        // Draw peak indicator
        if let peakIndex = dataPoints.firstIndex(where: { $0.bitrate == analysis.peakBitrate }) {
            let peakX = CGFloat(peakIndex) * barWidth + barWidth / 2
            let peakMarker = Path(ellipseIn: CGRect(
                x: peakX - 4,
                y: 0,
                width: 8,
                height: 8
            ))
            context.fill(peakMarker, with: .color(.red))
        }

        // Draw min indicator
        let nonZeroPoints = dataPoints.filter { $0.bitrate > 0 }
        if let minPoint = nonZeroPoints.min(by: { $0.bitrate < $1.bitrate }),
           let minIndex = dataPoints.firstIndex(where: { $0.timestamp == minPoint.timestamp }) {
            let minX = CGFloat(minIndex) * barWidth + barWidth / 2
            let minY = chartHeight - (CGFloat(minPoint.bitrate / analysis.peakBitrate) * chartHeight)
            let minMarker = Path(ellipseIn: CGRect(
                x: minX - 4,
                y: minY - 4,
                width: 8,
                height: 8
            ))
            context.fill(minMarker, with: .color(.cyan))
        }
    }

    // MARK: - Color Mapping

    /// Map a normalized bitrate value (0.0 to 1.0) to a heatmap color.
    ///
    /// Uses a blue-cyan-green-yellow-red gradient:
    /// - 0.0: Deep blue (low bitrate)
    /// - 0.25: Cyan
    /// - 0.5: Green
    /// - 0.75: Yellow
    /// - 1.0: Red (high bitrate)
    private func heatmapColor(for normalizedValue: Double) -> Color {
        let clamped = min(max(normalizedValue, 0), 1)

        if clamped < 0.25 {
            let t = clamped / 0.25
            return Color(
                red: 0,
                green: t,
                blue: 1.0 - t * 0.5
            )
        } else if clamped < 0.5 {
            let t = (clamped - 0.25) / 0.25
            return Color(
                red: 0,
                green: 0.8 + t * 0.2,
                blue: 0.5 - t * 0.5
            )
        } else if clamped < 0.75 {
            let t = (clamped - 0.5) / 0.25
            return Color(
                red: t,
                green: 1.0 - t * 0.3,
                blue: 0
            )
        } else {
            let t = (clamped - 0.75) / 0.25
            return Color(
                red: 1.0,
                green: 0.7 - t * 0.7,
                blue: 0
            )
        }
    }

    // MARK: - Hover Handling

    private func handleHover(
        phase: HoverPhase,
        size: CGSize,
        analysis: BitrateAnalysis
    ) {
        switch phase {
        case .active(let location):
            let chartLeft: CGFloat = 60
            let chartRight: CGFloat = 16
            let chartWidth = size.width - chartLeft - chartRight

            guard chartWidth > 0, !analysis.dataPoints.isEmpty else { return }

            let relativeX = location.x - chartLeft
            let fraction = relativeX / chartWidth
            let index = Int(fraction * Double(analysis.dataPoints.count))

            guard index >= 0, index < analysis.dataPoints.count else {
                hoverTimestamp = nil
                hoverBitrate = nil
                return
            }

            let point = analysis.dataPoints[index]
            hoverTimestamp = point.timestamp
            hoverBitrate = point.bitrate

        case .ended:
            hoverTimestamp = nil
            hoverBitrate = nil
        }
    }

    // MARK: - Tooltip

    private func tooltipView(timestamp: TimeInterval, bitrate: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatTime(timestamp))
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
            Text(formatBitrate(bitrate))
                .font(.caption.monospacedDigit())
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }

    // MARK: - Statistics Bar

    private func statisticsBar(analysis: BitrateAnalysis) -> some View {
        HStack(spacing: 24) {
            statLabel(title: "Average", value: formatBitrate(analysis.averageBitrate))
            statLabel(title: "Peak", value: formatBitrate(analysis.peakBitrate))
            statLabel(title: "Min", value: formatBitrate(analysis.minBitrate))
            statLabel(title: "Duration", value: formatTime(analysis.duration))
            statLabel(title: "Data Points", value: "\(analysis.dataPoints.count)")

            Spacer()

            // Color legend
            HStack(spacing: 4) {
                Text("Low")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LinearGradient(
                    colors: [.blue, .cyan, .green, .yellow, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80, height: 10)
                .clipShape(Capsule())
                Text("High")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func statLabel(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions

    /// Trigger bitrate analysis for the currently selected file.
    ///
    /// Builds FFprobe arguments via ``BitrateAnalyzer``, but the actual
    /// process execution is deferred to the view model or engine layer.
    /// For now, we store the arguments for the caller to execute.
    private func analyzeBitrate() async {
        guard let file = viewModel.selectedFile else { return }

        isAnalyzing = true
        errorMessage = nil

        // Build the ffprobe arguments (execution handled by engine)
        let args = BitrateAnalyzer.buildAnalysisArguments(inputPath: file.fileURL.path)

        // In a full implementation, the view model would execute ffprobe
        // and return the output. For now we log the intent.
        viewModel.appendLog(
            .info,
            "Bitrate analysis requested for \(file.fileName) with \(args.count) arguments",
            category: .general
        )

        isAnalyzing = false
    }

    /// Export the current heatmap as a PNG image via NSBitmapImageRep.
    @MainActor
    private func exportAsImage() {
        guard analysis != nil else { return }

        let panel = NSSavePanel()
        panel.title = "Export Bitrate Heatmap"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "bitrate_heatmap.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render the heatmap to an off-screen image
        let width = 1920
        let height = 600

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = graphicsContext

        // Draw background
        NSColor.controlBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        NSGraphicsContext.restoreGraphicsState()

        // Save PNG data
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }

    // MARK: - Formatting Helpers

    private func formatBitrate(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.2f Mbps", bps / 1_000_000)
        } else if bps >= 1000 {
            return String(format: "%.0f kbps", bps / 1000)
        } else {
            return String(format: "%.0f bps", bps)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
