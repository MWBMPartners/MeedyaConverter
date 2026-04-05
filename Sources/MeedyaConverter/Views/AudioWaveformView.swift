// ============================================================================
// MeedyaConverter — AudioWaveformView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - AudioWaveformView

/// Canvas-based waveform renderer for audio stream visualisation.
///
/// Draws a symmetric waveform centred around a horizontal axis with
/// colour coding for amplitude levels:
/// - **Blue/Green** — normal levels.
/// - **Orange** — loud levels (above 0.8 normalised amplitude).
/// - **Red** — clipping (at or above 0.99 normalised amplitude).
///
/// Supports horizontal scrolling and pinch-to-zoom via magnification
/// gesture, plus a timeline ruler along the bottom edge.
struct AudioWaveformView: View {

    // MARK: - Properties

    /// The waveform data to render.
    let waveformData: WaveformData?

    /// The currently selected audio channel index (0-based).
    /// Only relevant when multi-channel data is available.
    @Binding var selectedChannel: Int

    /// Whether waveform analysis is in progress.
    let isAnalysing: Bool

    /// Callback when the user taps the Analyse button.
    let onAnalyse: () -> Void

    // MARK: - State

    @State private var magnification: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0.0

    // MARK: - Constants

    /// Amplitude threshold above which bars are drawn in orange (loud).
    private static let loudThreshold: Float = 0.8

    /// Amplitude threshold at or above which bars are drawn in red (clipping).
    private static let clipThreshold: Float = 0.99

    /// Height of the timeline ruler at the bottom of the waveform.
    private static let rulerHeight: CGFloat = 20

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let data = waveformData {
                waveformContent(data)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            if isAnalysing {
                ProgressView("Analysing audio...")
                    .controlSize(.small)
            } else {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("No waveform data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onAnalyse()
                } label: {
                    Label("Analyse Audio", systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Waveform Content

    private func waveformContent(_ data: WaveformData) -> some View {
        VStack(spacing: 0) {
            // Header with metadata
            waveformHeader(data)

            // Waveform canvas with gestures
            GeometryReader { geometry in
                let totalWidth = geometry.size.width * magnification
                let canvasHeight = geometry.size.height - Self.rulerHeight

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Waveform bars
                        Canvas { context, size in
                            drawWaveform(
                                context: context,
                                size: CGSize(width: size.width, height: canvasHeight),
                                data: data
                            )
                        }
                        .frame(width: totalWidth, height: canvasHeight)

                        // Timeline ruler
                        Canvas { context, size in
                            drawRuler(
                                context: context,
                                size: size,
                                duration: data.duration
                            )
                        }
                        .frame(width: totalWidth, height: Self.rulerHeight)
                        .background(Color(.separatorColor).opacity(0.3))
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            magnification = max(1.0, min(50.0, value))
                        }
                )
            }
            .frame(minHeight: 120)

            // Footer with controls
            waveformFooter(data)
        }
    }

    // MARK: - Header

    private func waveformHeader(_ data: WaveformData) -> some View {
        HStack {
            // Channel selector
            if data.channels > 1 {
                Picker("Channel", selection: $selectedChannel) {
                    ForEach(0..<data.channels, id: \.self) { ch in
                        Text("Channel \(ch + 1)").tag(ch)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            Spacer()

            // Peak level
            HStack(spacing: 4) {
                Text("Peak:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f dBFS", 20 * log10(max(data.peakAmplitude, 0.0001))))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(data.hasClipping ? .red : .primary)
            }

            // Clipping indicator
            if data.hasClipping {
                Label("Clipping Detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private func waveformFooter(_ data: WaveformData) -> some View {
        HStack {
            // Duration
            Text(formatDuration(data.duration))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        magnification = max(1.0, magnification / 2)
                    }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(magnification <= 1.0)

                Text("\(Int(magnification))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 30)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        magnification = min(50.0, magnification * 2)
                    }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(magnification >= 50.0)
            }

            Spacer()

            // Re-analyse button
            Button {
                onAnalyse()
            } label: {
                Label("Re-analyse", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isAnalysing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Waveform Drawing

    /// Draw the waveform bars on the canvas.
    private func drawWaveform(
        context: GraphicsContext,
        size: CGSize,
        data: WaveformData
    ) {
        let barCount = Int(size.width)
        guard barCount > 0 else { return }

        let downsampled = AudioWaveformGenerator.downsample(data, targetSampleCount: barCount)
        let centreY = size.height / 2

        for (index, amplitude) in downsampled.enumerated() {
            let x = CGFloat(index)
            let barHeight = CGFloat(abs(amplitude)) * centreY
            let colour = barColour(for: abs(amplitude))

            // Draw symmetric bar around centre line
            let rect = CGRect(
                x: x,
                y: centreY - barHeight,
                width: 1,
                height: barHeight * 2
            )
            context.fill(Path(rect), with: .color(colour))
        }

        // Draw centre line
        let centreLine = Path { path in
            path.move(to: CGPoint(x: 0, y: centreY))
            path.addLine(to: CGPoint(x: size.width, y: centreY))
        }
        context.stroke(centreLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

        // Draw peak level indicator line
        if data.peakAmplitude > 0 {
            let peakY = centreY - CGFloat(data.peakAmplitude) * centreY
            let peakLine = Path { path in
                path.move(to: CGPoint(x: 0, y: peakY))
                path.addLine(to: CGPoint(x: size.width, y: peakY))
            }
            context.stroke(
                peakLine,
                with: .color(data.hasClipping ? .red.opacity(0.5) : .orange.opacity(0.4)),
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
            )

            // Mirror below centre
            let peakYBottom = centreY + CGFloat(data.peakAmplitude) * centreY
            let peakLineBottom = Path { path in
                path.move(to: CGPoint(x: 0, y: peakYBottom))
                path.addLine(to: CGPoint(x: size.width, y: peakYBottom))
            }
            context.stroke(
                peakLineBottom,
                with: .color(data.hasClipping ? .red.opacity(0.5) : .orange.opacity(0.4)),
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
            )
        }
    }

    // MARK: - Timeline Ruler

    /// Draw time markers along the bottom of the waveform.
    private func drawRuler(
        context: GraphicsContext,
        size: CGSize,
        duration: TimeInterval
    ) {
        guard duration > 0 else { return }

        // Determine tick interval based on zoom level
        let tickInterval: TimeInterval
        let pixelsPerSecond = size.width / duration
        if pixelsPerSecond > 100 {
            tickInterval = 1
        } else if pixelsPerSecond > 20 {
            tickInterval = 5
        } else if pixelsPerSecond > 5 {
            tickInterval = 30
        } else {
            tickInterval = 60
        }

        var time: TimeInterval = 0
        while time <= duration {
            let x = (time / duration) * size.width
            let isMajor = time.truncatingRemainder(dividingBy: tickInterval * 5) == 0

            // Tick mark
            let tickHeight: CGFloat = isMajor ? 8 : 4
            let tick = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: tickHeight))
            }
            context.stroke(tick, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

            // Time label for major ticks
            if isMajor {
                let label = formatDuration(time)
                let text = Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x, y: size.height - 4),
                    anchor: .bottom
                )
            }

            time += tickInterval
        }
    }

    // MARK: - Helpers

    /// Determine the bar colour based on normalised amplitude.
    private func barColour(for amplitude: Float) -> Color {
        if amplitude >= Self.clipThreshold {
            return .red
        } else if amplitude >= Self.loudThreshold {
            return .orange
        } else {
            return .accentColor
        }
    }

    /// Format a time interval as MM:SS or HH:MM:SS.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}
