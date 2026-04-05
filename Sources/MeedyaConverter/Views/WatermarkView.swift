// ============================================================================
// MeedyaConverter — WatermarkView (Issue #298)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - WatermarkView

/// Configuration view for applying watermark overlays to batch images and videos.
///
/// Provides a type picker (text vs. image), text input with font and
/// colour controls, image file picker, a 9-grid position selector,
/// opacity and scale sliders, and a live filter-string preview.
///
/// Phase 10.2 — Watermark Overlay for Batch Images (Issue #298)
struct WatermarkView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The watermark type (text or image).
    @State private var watermarkType: WatermarkType = .text

    /// The text string for text watermarks.
    @State private var watermarkText = "Copyright"

    /// The file path for image watermarks.
    @State private var imagePath = ""

    /// The watermark position within the frame.
    @State private var position: WatermarkPosition = .bottomRight

    /// Opacity value from 0.0 (invisible) to 1.0 (fully opaque).
    @State private var opacity: Double = 0.5

    /// Scale factor for image watermarks (1.0 = original size).
    @State private var scale: Double = 1.0

    /// Margin in pixels from the nearest frame edge.
    @State private var margin: Double = 10

    // MARK: - Body

    var body: some View {
        Form {
            typeSection
            contentSection
            positionSection
            adjustmentSection
            previewSection
        }
        .formStyle(.grouped)
        .navigationTitle("Watermark Overlay")
    }

    // MARK: - Type Selection

    /// Section for selecting the watermark type.
    @ViewBuilder
    private var typeSection: some View {
        Section("Watermark Type") {
            Picker("Type", selection: $watermarkType) {
                Label("Text", systemImage: "textformat")
                    .tag(WatermarkType.text)
                Label("Image", systemImage: "photo")
                    .tag(WatermarkType.image)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Content

    /// Section for configuring the watermark content (text or image path).
    @ViewBuilder
    private var contentSection: some View {
        Section("Content") {
            switch watermarkType {
            case .text:
                TextField("Watermark Text", text: $watermarkText)
                    .textFieldStyle(.roundedBorder)

            case .image:
                HStack {
                    TextField("Image File Path", text: $imagePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseForImage()
                    }
                }
            }
        }
    }

    // MARK: - Position Grid

    /// Section with a 3x3 grid for selecting watermark position.
    @ViewBuilder
    private var positionSection: some View {
        Section("Position") {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    positionButton(.topLeft, label: "TL")
                    Spacer()
                    positionButton(.center, label: "C")
                        .opacity(0) // placeholder for top row centre
                    Spacer()
                    positionButton(.topRight, label: "TR")
                }

                HStack(spacing: 2) {
                    Spacer()
                    positionButton(.center, label: "Centre")
                    Spacer()
                }

                HStack(spacing: 2) {
                    positionButton(.bottomLeft, label: "BL")
                    Spacer()
                    positionButton(.center, label: "C")
                        .opacity(0) // placeholder for bottom row centre
                    Spacer()
                    positionButton(.bottomRight, label: "BR")
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// A toggle-style button for selecting a watermark position.
    @ViewBuilder
    private func positionButton(
        _ pos: WatermarkPosition,
        label: String
    ) -> some View {
        Button {
            position = pos
        } label: {
            Text(label)
                .font(.caption)
                .frame(width: 60, height: 32)
                .background(
                    position == pos
                        ? Color.accentColor.opacity(0.3)
                        : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Adjustments

    /// Section with opacity, scale, and margin sliders.
    @ViewBuilder
    private var adjustmentSection: some View {
        Section("Adjustments") {
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(opacity * 100))%")
                Slider(value: $opacity, in: 0.0...1.0, step: 0.05)
            }

            if watermarkType == .image {
                VStack(alignment: .leading) {
                    Text("Scale: \(String(format: "%.0f", scale * 100))%")
                    Slider(value: $scale, in: 0.1...2.0, step: 0.05)
                }
            }

            VStack(alignment: .leading) {
                Text("Margin: \(Int(margin)) px")
                Slider(value: $margin, in: 0...100, step: 1)
            }
        }
    }

    // MARK: - Preview

    /// Section displaying the generated FFmpeg filter string.
    @ViewBuilder
    private var previewSection: some View {
        Section("FFmpeg Filter Preview") {
            let config = buildConfig()
            let filterString: String = {
                switch watermarkType {
                case .text:
                    return WatermarkOverlay.buildTextWatermarkFilter(config: config)
                case .image:
                    return WatermarkOverlay.buildImageWatermarkFilter(config: config)
                }
            }()

            Text(filterString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    /// Open a file browser to select a watermark image.
    private func browseForImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.message = "Select a watermark image"

        if panel.runModal() == .OK, let url = panel.url {
            imagePath = url.path
        }
    }

    /// Build a ``WatermarkConfig`` from the current form state.
    private func buildConfig() -> OverlayWatermarkConfig {
        OverlayWatermarkConfig(
            type: watermarkType,
            text: watermarkType == .text ? watermarkText : nil,
            imagePath: watermarkType == .image ? imagePath : nil,
            position: position,
            opacity: opacity,
            scale: scale,
            margin: Int(margin)
        )
    }
}
