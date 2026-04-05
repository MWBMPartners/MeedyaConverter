// ============================================================================
// MeedyaConverter — VideoTrimmerView (Issues #318, #341)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - VideoTrimmerView

/// Video trimming and splitting interface with a visual timeline,
/// draggable trim handles, snip region management, and frame-accurate
/// navigation controls.
///
/// Features:
/// - Timeline bar showing the full video duration with draggable
///   start/end trim handles.
/// - "Add Snip" button to mark interior regions for removal (shown
///   as red zones on the timeline).
/// - Removable snip regions with start/end time display.
/// - "Copy mode (no re-encode)" toggle for lossless trimming.
/// - Split options: by chapter markers or by maximum file size.
/// - Preview of resulting segments after trim/snip operations.
/// - Optional frame-number inputs for frame-accurate navigation
///   (Issue #341).
/// - "Apply" button to execute the configured trim.
///
/// Phase 12 — Video Trimming and Splitting (Issue #318)
/// Phase 12 — Frame-Accurate Trimming (Issue #341)
struct VideoTrimmerView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Total duration of the source video in seconds.
    @State private var duration: TimeInterval = 120.0

    /// Trim start position as a fraction of duration (0.0 to 1.0).
    @State private var trimStartFraction: Double = 0.0

    /// Trim end position as a fraction of duration (0.0 to 1.0).
    @State private var trimEndFraction: Double = 1.0

    /// Interior regions marked for removal.
    @State private var snipRegions: [SnipRegion] = []

    /// Whether to use stream copy (no re-encode) for lossless cutting.
    @State private var copyMode: Bool = true

    /// Whether to split the output at chapter boundaries.
    @State private var splitByChapters: Bool = false

    /// Optional maximum file size for size-based splitting, in megabytes.
    @State private var splitSizeMB: String = ""

    /// Computed segments that will result from the current configuration.
    @State private var resultSegments: [TrimSegment] = []

    /// Whether a trim operation is in progress.
    @State private var isApplying: Bool = false

    /// Error message to display, if any.
    @State private var errorMessage: String?

    // MARK: - Frame Navigation State (Issue #341)

    /// Whether frame-accurate mode is enabled.
    @State private var frameAccurateMode: Bool = false

    /// Start frame number for frame-accurate trimming.
    @State private var startFrameText: String = ""

    /// End frame number for frame-accurate trimming.
    @State private var endFrameText: String = ""

    /// Frames per second of the source video.
    @State private var fps: Double = 24.0

    /// Whether to snap to keyframes for lossless cutting.
    @State private var keyframeAlign: Bool = true

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Timeline and controls
            controlsSection

            Divider()

            // Segments preview and actions
            segmentsSection
        }
        .navigationTitle("Video Trimmer")
        .onChange(of: trimStartFraction) { _, _ in recalculateSegments() }
        .onChange(of: trimEndFraction) { _, _ in recalculateSegments() }
        .onChange(of: snipRegions) { _, _ in recalculateSegments() }
        .onAppear { recalculateSegments() }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Timeline visualization
            timelineView
                .padding(.horizontal)
                .padding(.top, 12)

            // Time labels
            HStack {
                Text(formatTime(trimStartFraction * duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Duration: \(formatTime(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(trimEndFraction * duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Trim sliders
            trimControls
                .padding(.horizontal)

            // Frame-accurate controls (Issue #341)
            if frameAccurateMode {
                frameNavigationControls
                    .padding(.horizontal)
            }

            // Snip controls
            snipControls
                .padding(.horizontal)

            // Options
            optionsControls
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Timeline View

    /// Visual timeline bar with trim handles and snip regions.
    private var timelineView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Full duration background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 40)

                // Trimmed region (active)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(
                        width: max(0, (trimEndFraction - trimStartFraction) * width),
                        height: 40
                    )
                    .offset(x: trimStartFraction * width)

                // Snip regions (red zones to cut out)
                ForEach(snipRegions) { snip in
                    let snipStartX = (snip.startTime / duration) * width
                    let snipWidth = ((snip.endTime - snip.startTime) / duration) * width

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.5))
                        .frame(width: max(2, snipWidth), height: 40)
                        .offset(x: snipStartX)
                }

                // Start trim handle
                trimHandle(color: .green)
                    .offset(x: trimStartFraction * width - 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let fraction = max(0, min(trimEndFraction - 0.01,
                                    value.location.x / width))
                                trimStartFraction = fraction
                            }
                    )

                // End trim handle
                trimHandle(color: .red)
                    .offset(x: trimEndFraction * width - 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let fraction = max(trimStartFraction + 0.01,
                                    min(1.0, value.location.x / width))
                                trimEndFraction = fraction
                            }
                    )
            }
        }
        .frame(height: 40)
        .accessibilityLabel("Video timeline with trim handles")
    }

    /// A draggable trim handle indicator.
    private func trimHandle(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 8, height: 48)
            .shadow(radius: 2)
    }

    // MARK: - Trim Controls

    private var trimControls: some View {
        GroupBox("Trim Range") {
            VStack(spacing: 8) {
                HStack {
                    Text("Start")
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $trimStartFraction, in: 0...1, step: 0.001)
                    Text(formatTime(trimStartFraction * duration))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }

                HStack {
                    Text("End")
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $trimEndFraction, in: 0...1, step: 0.001)
                    Text(formatTime(trimEndFraction * duration))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Frame Navigation Controls (Issue #341)

    private var frameNavigationControls: some View {
        GroupBox("Frame-Accurate Navigation") {
            VStack(spacing: 8) {
                HStack {
                    Text("FPS")
                        .frame(width: 60, alignment: .leading)
                    TextField("Frames per second", value: $fps, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Spacer()
                    Toggle("Keyframe align", isOn: $keyframeAlign)
                }

                HStack {
                    Text("Start Frame")
                        .frame(width: 80, alignment: .leading)
                    TextField("Frame #", text: $startFrameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: startFrameText) { _, newValue in
                            if let frame = Int(newValue), fps > 0 {
                                let time = FrameNavigator.timestampForFrame(frame, fps: fps)
                                trimStartFraction = min(time / duration, 1.0)
                            }
                        }

                    Spacer()

                    Text("End Frame")
                        .frame(width: 80, alignment: .leading)
                    TextField("Frame #", text: $endFrameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: endFrameText) { _, newValue in
                            if let frame = Int(newValue), fps > 0 {
                                let time = FrameNavigator.timestampForFrame(frame, fps: fps)
                                trimEndFraction = min(time / duration, 1.0)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Snip Controls

    private var snipControls: some View {
        GroupBox("Snip Regions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cut out sections from the middle of the video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        addSnipRegion()
                    } label: {
                        Label("Add Snip", systemImage: "scissors")
                    }
                    .accessibilityLabel("Add a new snip region to cut from the video")
                }

                if !snipRegions.isEmpty {
                    ForEach(snipRegions) { snip in
                        HStack {
                            Image(systemName: "scissors")
                                .foregroundStyle(.red)
                            Text("\(formatTime(snip.startTime)) - \(formatTime(snip.endTime))")
                                .font(.caption.monospacedDigit())
                            Text("(\(formatTime(snip.duration)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                snipRegions.removeAll { $0.id == snip.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove snip region")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Options Controls

    private var optionsControls: some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Copy mode (no re-encode)", isOn: $copyMode)
                    .accessibilityLabel("Enable lossless stream copy without re-encoding")

                Toggle("Frame-accurate mode", isOn: $frameAccurateMode)
                    .accessibilityLabel("Enable frame-number input for precise trimming")

                Divider()

                Toggle("Split by chapters", isOn: $splitByChapters)
                    .accessibilityLabel("Split output at chapter boundaries")

                HStack {
                    Text("Split by size (MB)")
                    TextField("e.g., 700", text: $splitSizeMB)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Segments Section

    private var segmentsSection: some View {
        VStack(spacing: 12) {
            // Resulting segments preview
            if !resultSegments.isEmpty {
                GroupBox("Resulting Segments") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(resultSegments) { segment in
                            HStack {
                                Image(systemName: "film")
                                    .foregroundStyle(Color.accentColor)
                                Text(segment.label ?? "Segment")
                                    .font(.caption)
                                Spacer()
                                Text("\(formatTime(segment.startTime)) - \(formatTime(segment.endTime))")
                                    .font(.caption.monospacedDigit())
                                Text("(\(formatTime(segment.duration)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Error display
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Apply button
            HStack {
                Spacer()
                Button {
                    applyTrim()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text("Apply")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
                .accessibilityLabel("Apply the configured trim and snip operations")
            }
            .padding()
        }
    }

    // MARK: - Actions

    /// Add a new snip region at the midpoint of the current trim range.
    private func addSnipRegion() {
        let start = trimStartFraction * duration
        let end = trimEndFraction * duration
        let midpoint = (start + end) / 2
        let regionLength = min(5.0, (end - start) * 0.1) // 5s or 10% of range

        let snip = SnipRegion(
            startTime: midpoint - regionLength / 2,
            endTime: midpoint + regionLength / 2
        )
        snipRegions.append(snip)
    }

    /// Recalculate the resulting segments based on current trim and snip config.
    private func recalculateSegments() {
        let effectiveSnips = snipRegions.filter { snip in
            snip.startTime >= trimStartFraction * duration
                && snip.endTime <= trimEndFraction * duration
        }

        // Calculate segments relative to the trimmed range
        let trimmedDuration = (trimEndFraction - trimStartFraction) * duration
        let adjustedSnips = effectiveSnips.map { snip in
            SnipRegion(
                id: snip.id,
                startTime: snip.startTime - trimStartFraction * duration,
                endTime: snip.endTime - trimStartFraction * duration
            )
        }

        resultSegments = VideoTrimmer.calculateSegments(
            duration: trimmedDuration,
            snipRegions: adjustedSnips
        )
    }

    /// Execute the configured trim operation.
    private func applyTrim() {
        errorMessage = nil
        isApplying = true

        // Build the trim configuration
        let splitBytes: Int64? = if let mb = Double(splitSizeMB) {
            Int64(mb * 1_048_576)
        } else {
            nil
        }

        let _: TrimConfig = TrimConfig(
            trimStart: trimStartFraction * duration,
            trimEnd: trimEndFraction * duration,
            snipRegions: snipRegions,
            splitByChapters: splitByChapters,
            splitBySize: splitBytes,
            copyMode: copyMode
        )

        // In a full implementation, this would invoke FFmpegProcessController
        // with the arguments from VideoTrimmer.buildTrimArguments() or
        // VideoTrimmer.buildSnipArguments(). For now, mark as complete.
        isApplying = false
    }

    // MARK: - Formatting

    /// Format a time interval as `HH:MM:SS.m` for display.
    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let seconds = clamped.truncatingRemainder(dividingBy: 60)
        if hours > 0 {
            return String(format: "%d:%02d:%04.1f", hours, minutes, seconds)
        }
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
}
