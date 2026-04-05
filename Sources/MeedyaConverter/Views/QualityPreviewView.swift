// ============================================================================
// MeedyaConverter — QualityPreviewView (Issue #270)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import AVKit
import ConverterEngine

// MARK: - QualityPreviewView

/// A/B quality preview comparing source video against a short encoded preview.
///
/// Displays a side-by-side comparison with a draggable slider divider,
/// a timestamp scrubber to pick which segment to preview, and quality
/// metrics (estimated file size, visual difference). The preview is
/// generated using FFmpeg with the same profile settings as the full
/// encode but limited to a short duration via `-ss` and `-t` flags.
///
/// Phase 7 / Issue #270
struct QualityPreviewView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The source media file to preview.
    let sourceFile: MediaFile

    /// The encoding profile to use for the preview encode.
    let profile: EncodingProfile

    // MARK: - State

    /// Horizontal slider position for the wipe comparison (0.0 = all source, 1.0 = all preview).
    @State private var sliderPosition: CGFloat = 0.5

    /// Start time in seconds for the preview segment.
    @State private var previewStartTime: TimeInterval = 0.0

    /// Duration of the preview segment in seconds.
    @State private var previewDuration: TimeInterval = PreviewGenerator.defaultDuration

    /// URL of the generated preview file, if available.
    @State private var previewURL: URL?

    /// Whether a preview is currently being generated.
    @State private var isGenerating: Bool = false

    /// Progress of the preview generation (0.0–1.0).
    @State private var generationProgress: Double = 0.0

    /// Error message if preview generation failed.
    @State private var errorMessage: String?

    /// Estimated output file size for the full encode.
    @State private var estimatedFileSize: String?

    /// AVPlayer for the source video.
    @State private var sourcePlayer: AVPlayer?

    /// AVPlayer for the preview (encoded) video.
    @State private var previewPlayer: AVPlayer?

    /// Whether both players are synced and playing.
    @State private var isPlaying: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            headerBar

            Divider()

            // Main comparison area
            if previewURL != nil {
                comparisonContent
            } else if isGenerating {
                generatingState
            } else {
                emptyState
            }

            Divider()

            // Timeline scrubber and controls
            bottomControls
        }
        .frame(minWidth: 800, minHeight: 550)
        .navigationTitle("Quality Preview")
        .onDisappear {
            cleanupPreview()
        }
    }

    // MARK: - Header Bar

    /// Top toolbar with comparison mode and action buttons.
    private var headerBar: some View {
        HStack {
            Text("A/B Quality Preview")
                .font(.headline)

            Spacer()

            if previewURL != nil {
                Text("Drag slider to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    cleanupPreview()
                    dismiss()
                }

                if previewURL != nil {
                    Button("Proceed with Full Encode") {
                        cleanupPreview()
                        dismiss()
                        // The caller should observe dismiss and trigger the full encode.
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    /// Displayed before a preview has been generated.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Generate a short preview to compare quality")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("A \(Int(previewDuration))-second clip will be encoded with your current settings so you can evaluate quality before committing to a full encode.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Button {
                generatePreview()
            } label: {
                Label("Generate Preview", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Generating State

    /// Progress view shown while the preview clip is being encoded.
    private var generatingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(value: generationProgress) {
                Text("Encoding preview clip...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(generationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 300)

            Text("Encoding a \(Int(previewDuration))s preview starting at \(formattedTimestamp(previewStartTime))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                cancelGeneration()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Comparison Content

    /// Side-by-side video comparison with slider divider.
    private var comparisonContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Source video (left side)
                if let sourcePlayer {
                    VideoPlayer(player: sourcePlayer)
                        .disabled(true) // Prevent interaction with embedded controls.
                }

                // Encoded preview (right side), clipped by slider position.
                if let previewPlayer {
                    VideoPlayer(player: previewPlayer)
                        .disabled(true)
                        .clipShape(
                            SliderClipShape(position: sliderPosition, totalWidth: geometry.size.width)
                        )
                }

                // Slider divider line.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .position(x: geometry.size.width * sliderPosition, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                sliderPosition = max(0.05, min(0.95, value.location.x / geometry.size.width))
                            }
                    )

                // Labels
                VStack {
                    HStack {
                        Text("SOURCE")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        Text("ENCODED")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(12)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Bottom Controls

    /// Timeline scrubber, playback controls, and quality metrics.
    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Timestamp scrubber for selecting preview start time.
            if let duration = sourceFile.duration, duration > 0 {
                HStack {
                    Text("Preview start:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: $previewStartTime,
                        in: 0...max(0, duration - previewDuration),
                        step: 1.0
                    )

                    Text(formattedTimestamp(previewStartTime))
                        .font(.caption.monospacedDigit())
                        .frame(width: 70, alignment: .trailing)
                }
            }

            HStack {
                // Preview duration picker
                HStack(spacing: 4) {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $previewDuration) {
                        Text("5s").tag(5.0 as TimeInterval)
                        Text("8s").tag(8.0 as TimeInterval)
                        Text("10s").tag(10.0 as TimeInterval)
                        Text("15s").tag(15.0 as TimeInterval)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }

                Spacer()

                // Quality metrics
                if let estimatedFileSize {
                    HStack(spacing: 12) {
                        Label(estimatedFileSize, systemImage: "doc.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Playback controls
                if previewURL != nil {
                    HStack(spacing: 8) {
                        Button {
                            togglePlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            generatePreview()
                        } label: {
                            Label("Re-generate", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                } else if !isGenerating {
                    Button {
                        generatePreview()
                    } label: {
                        Label("Generate Preview", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    /// Generate a preview clip using the current settings.
    private func generatePreview() {
        guard !isGenerating else { return }

        isGenerating = true
        generationProgress = 0.0
        errorMessage = nil

        // Clean up any previous preview.
        if let existingURL = previewURL {
            PreviewGenerator.cleanupPreview(at: existingURL)
            previewURL = nil
            previewPlayer = nil
        }

        let outputURL = PreviewGenerator.previewOutputPath(for: sourceFile.fileURL)
        let inputPath = sourceFile.fileURL.path
        let outputPath = outputURL.path

        let args = PreviewGenerator.buildPreviewArguments(
            inputPath: inputPath,
            outputPath: outputPath,
            profile: profile,
            startTime: previewStartTime,
            duration: previewDuration
        )

        // Execute the preview encode in a background task.
        Task {
            do {
                // Locate the FFmpeg binary via the bundle manager.
                let bundleManager = FFmpegBundleManager()
                let ffmpegInfo = try bundleManager.locateFFmpeg()
                let controller = FFmpegProcessController(binaryPath: ffmpegInfo.path)
                controller.sourceDuration = previewDuration

                // Start the encoding and consume the progress stream.
                let progressStream = try controller.startEncoding(arguments: args)

                for await progress in progressStream {
                    await MainActor.run {
                        if let fraction = progress.fractionComplete {
                            generationProgress = fraction
                        }
                    }
                }

                await MainActor.run {
                    previewURL = outputURL
                    isGenerating = false
                    generationProgress = 1.0

                    // Set up players for comparison.
                    sourcePlayer = AVPlayer(url: sourceFile.fileURL)
                    sourcePlayer?.seek(to: CMTime(seconds: previewStartTime, preferredTimescale: 600))
                    previewPlayer = AVPlayer(url: outputURL)

                    // Compute estimated full-encode file size.
                    let estimate = FileSizeEstimator.estimateOutputSize(
                        profile: profile,
                        duration: sourceFile.duration ?? 0,
                        sourceFileSize: sourceFile.fileSize
                    )
                    estimatedFileSize = estimate.formattedSize
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "Preview generation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Cancel an in-progress preview generation.
    private func cancelGeneration() {
        isGenerating = false
        generationProgress = 0.0
    }

    /// Toggle synchronised playback of source and preview.
    private func togglePlayback() {
        if isPlaying {
            sourcePlayer?.pause()
            previewPlayer?.pause()
        } else {
            sourcePlayer?.play()
            previewPlayer?.play()
        }
        isPlaying.toggle()
    }

    /// Clean up temporary preview files.
    private func cleanupPreview() {
        sourcePlayer?.pause()
        previewPlayer?.pause()
        sourcePlayer = nil
        previewPlayer = nil

        if let url = previewURL {
            PreviewGenerator.cleanupPreview(at: url)
            previewURL = nil
        }
    }

    // MARK: - Formatting

    /// Format a time interval as MM:SS.
    private func formattedTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - SliderClipShape

/// A clip shape that reveals only the right portion of a view based on slider position.
///
/// Used to create the wipe/reveal effect where the encoded preview is shown
/// to the right of the slider divider.
private struct SliderClipShape: Shape {

    /// The normalised slider position (0.0–1.0) where the clip begins.
    let position: CGFloat

    /// The total width of the parent container.
    let totalWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let xOffset = rect.width * position
        return Path(CGRect(
            x: xOffset,
            y: rect.minY,
            width: rect.width - xOffset,
            height: rect.height
        ))
    }
}
