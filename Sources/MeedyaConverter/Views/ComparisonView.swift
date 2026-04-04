// ============================================================================
// MeedyaConverter — ComparisonView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ComparisonView

/// A/B comparison viewer for source vs. encoded video quality.
///
/// Supports side-by-side, slider wipe, toggle, and difference
/// visualization modes. Displays SSIM/PSNR quality metrics.
///
/// Phase 7.11
struct ComparisonView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var comparisonMode: ComparisonMode = .sideBySide
    @State private var selectedFrameIndex: Int = 0
    @State private var sliderPosition: CGFloat = 0.5
    @State private var showingSource: Bool = true
    @State private var ssimValue: Double?
    @State private var psnrValue: Double?
    @State private var frames: [ComparisonFrame] = []
    @State private var isLoading: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector toolbar
            modeSelectorBar

            Divider()

            // Main comparison area
            if frames.isEmpty {
                emptyState
            } else {
                comparisonContent
            }

            Divider()

            // Frame timeline / quality metrics
            bottomBar
        }
        .navigationTitle("A/B Comparison")
    }

    // MARK: - Mode Selector

    private var modeSelectorBar: some View {
        HStack {
            Picker("Mode", selection: $comparisonMode) {
                ForEach(ComparisonMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
                Text("Extracting frames...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Comparison Content

    @ViewBuilder
    private var comparisonContent: some View {
        switch comparisonMode {
        case .sideBySide:
            sideBySideView
        case .slider:
            sliderView
        case .toggle:
            toggleView
        case .difference:
            differenceView
        }
    }

    private var sideBySideView: some View {
        HStack(spacing: 2) {
            VStack {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                frameImage(path: currentFrame?.sourceImagePath)
            }
            VStack {
                Text("Encoded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                frameImage(path: currentFrame?.encodedImagePath)
            }
        }
        .padding()
    }

    private var sliderView: some View {
        GeometryReader { geometry in
            ZStack {
                // Encoded frame (full width)
                frameImage(path: currentFrame?.encodedImagePath)

                // Source frame (clipped to slider position)
                frameImage(path: currentFrame?.sourceImagePath)
                    .clipShape(
                        Rectangle()
                            .size(
                                width: geometry.size.width * sliderPosition,
                                height: geometry.size.height
                            )
                    )

                // Slider line
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .position(
                        x: geometry.size.width * sliderPosition,
                        y: geometry.size.height / 2
                    )
                    .shadow(radius: 2)

                // Labels
                VStack {
                    HStack {
                        Text("Source")
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text("Encoded")
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.horizontal, 8)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        sliderPosition = max(0, min(1, value.location.x / geometry.size.width))
                    }
            )
        }
        .padding()
    }

    private var toggleView: some View {
        VStack {
            Text(showingSource ? "Source" : "Encoded")
                .font(.caption)
                .foregroundStyle(.secondary)

            frameImage(path: showingSource
                ? currentFrame?.sourceImagePath
                : currentFrame?.encodedImagePath
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSource.toggle()
                }
            }

            Text("Click to toggle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var differenceView: some View {
        VStack {
            Text("Pixel Difference (amplified)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // In a full implementation, this would show the difference image
            // generated by FrameComparisonExtractor.buildDifferenceArguments()
            frameImage(path: nil)
                .overlay {
                    Text("Difference visualization requires FFmpeg processing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .padding()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Frame scrubber
            if !frames.isEmpty {
                HStack(spacing: 8) {
                    Button(action: { previousFrame() }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Text("Frame \(selectedFrameIndex + 1) / \(frames.count)")
                        .font(.caption.monospacedDigit())

                    if let frame = currentFrame {
                        Text("@ \(frame.formattedTimestamp)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Button(action: { nextFrame() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }

                Slider(
                    value: Binding(
                        get: { Double(selectedFrameIndex) },
                        set: { selectedFrameIndex = Int($0) }
                    ),
                    in: 0...Double(max(0, frames.count - 1)),
                    step: 1
                )
                .frame(maxWidth: 200)
            }

            Spacer()

            // Quality metrics
            HStack(spacing: 16) {
                if let ssim = ssimValue {
                    HStack(spacing: 4) {
                        Text("SSIM:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.4f", ssim))
                            .font(.caption.monospacedDigit())
                            .fontWeight(.medium)
                    }
                }

                if let psnr = psnrValue {
                    HStack(spacing: 4) {
                        Text("PSNR:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f dB", psnr))
                            .font(.caption.monospacedDigit())
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Comparison Available",
            systemImage: "rectangle.split.2x1",
            description: Text("Complete an encoding job to compare source and output quality.")
        )
    }

    // MARK: - Helpers

    private var currentFrame: ComparisonFrame? {
        guard selectedFrameIndex >= 0 && selectedFrameIndex < frames.count else { return nil }
        return frames[selectedFrameIndex]
    }

    private func frameImage(path: String?) -> some View {
        Group {
            if let path = path, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func previousFrame() {
        if selectedFrameIndex > 0 {
            selectedFrameIndex -= 1
        }
    }

    private func nextFrame() {
        if selectedFrameIndex < frames.count - 1 {
            selectedFrameIndex += 1
        }
    }
}
