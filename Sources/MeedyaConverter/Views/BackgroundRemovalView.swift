// ============================================================================
// MeedyaConverter — BackgroundRemovalView (Issue #300)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine
import UniformTypeIdentifiers

// MARK: - BackgroundRemovalView

/// Provides a visual interface for removing backgrounds from images
/// using Apple Vision's person segmentation.
///
/// Features:
/// - Image picker for source selection
/// - Quality level selector (fast/balanced/accurate)
/// - Before/after preview (original vs. processed)
/// - Replace colour picker (transparent or solid colour)
/// - Output format selector (PNG for alpha, JPEG with colour, TIFF)
/// - Batch processing with progress indicator
/// - Apply/export button
///
/// Phase 11 — Background Removal (Issue #300)
struct BackgroundRemovalView: View {

    // MARK: - State

    /// The selected input image URLs (supports batch).
    @State private var selectedImageURLs: [URL] = []

    /// The loaded original image for before-preview.
    @State private var originalImage: NSImage?

    /// The processed image with background removed.
    @State private var processedImage: NSImage?

    /// Whether processing is in progress.
    @State private var isProcessing = false

    /// Processing progress for batch operations (0.0–1.0).
    @State private var batchProgress: Double = 0

    /// Total items in the current batch.
    @State private var batchTotal: Int = 0

    /// Number of items completed in the current batch.
    @State private var batchCompleted: Int = 0

    /// The segmentation quality level.
    @State private var qualityLevel: BackgroundRemovalQuality = .balanced

    /// The output image format.
    @State private var outputFormat: ImageFormat = .png

    /// Whether to use a solid replace colour instead of transparent.
    @State private var useReplaceColor = false

    /// The selected replacement colour.
    @State private var replaceColor: Color = .white

    /// Error message from the most recent operation.
    @State private var errorMessage: String?

    /// Success message from the most recent operation.
    @State private var successMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            controlsSection
            if isProcessing {
                processingSection
            }
            previewSection
            if let error = errorMessage {
                errorBanner(message: error)
            }
            if let success = successMessage {
                successBanner(message: success)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Header

    /// Title and description area.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Background Removal")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Remove backgrounds from images using on-device person segmentation. Supports transparent or solid colour replacement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    /// Image picker, quality/format selectors, colour picker, and action buttons.
    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Choose Image…") {
                    chooseSingleImage()
                }

                Button("Choose Batch…") {
                    chooseBatchImages()
                }

                if !selectedImageURLs.isEmpty {
                    Text(selectedImageURLs.count == 1
                         ? selectedImageURLs[0].lastPathComponent
                         : "\(selectedImageURLs.count) images selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                // Quality level
                VStack(alignment: .leading) {
                    Text("Quality").font(.caption).foregroundStyle(.secondary)
                    Picker("Quality", selection: $qualityLevel) {
                        ForEach(BackgroundRemovalQuality.allCases, id: \.self) { level in
                            Text(level.rawValue.capitalized).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                // Output format
                VStack(alignment: .leading) {
                    Text("Format").font(.caption).foregroundStyle(.secondary)
                    Picker("Format", selection: $outputFormat) {
                        Text("PNG").tag(ImageFormat.png)
                        Text("JPEG").tag(ImageFormat.jpeg)
                        Text("TIFF").tag(ImageFormat.tiff)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                // Replace colour toggle and picker
                VStack(alignment: .leading) {
                    Text("Background").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Toggle("Solid colour", isOn: $useReplaceColor)
                            .toggleStyle(.checkbox)
                        if useReplaceColor {
                            ColorPicker("", selection: $replaceColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 30)
                        }
                    }
                }

                Spacer()

                Button("Apply") {
                    Task { await processImages() }
                }
                .disabled(selectedImageURLs.isEmpty || isProcessing)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Processing Progress

    /// Progress indicator for batch processing.
    private var processingSection: some View {
        VStack(spacing: 8) {
            if batchTotal > 1 {
                ProgressView(
                    "Processing \(batchCompleted)/\(batchTotal)…",
                    value: batchProgress,
                    total: 1.0
                )
            } else {
                ProgressView("Processing image…")
            }
        }
        .padding()
    }

    // MARK: - Preview

    /// Before/after image preview.
    private var previewSection: some View {
        HStack(spacing: 16) {
            // Original image
            GroupBox("Original") {
                if let image = originalImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                } else {
                    Text("No image loaded")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                }
            }

            // Processed image
            GroupBox("Result") {
                if let image = processedImage {
                    // Checkerboard background to show transparency
                    ZStack {
                        checkerboardBackground
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .frame(maxHeight: 300)
                } else {
                    Text("Not yet processed")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                }
            }
        }
    }

    /// Checkerboard pattern to indicate transparency in the preview.
    private var checkerboardBackground: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 10
            let rows = Int(ceil(size.height / tileSize))
            let cols = Int(ceil(size.width / tileSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color.white : Color.gray.opacity(0.3))
                    )
                }
            }
        }
    }

    // MARK: - Status Banners

    /// Displays an error message.
    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Displays a success message.
    private func successBanner(message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(message)
                .foregroundStyle(.green)
            Spacer()
            Button("Dismiss") {
                successMessage = nil
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    /// Presents an open panel to choose a single image.
    private func chooseSingleImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.message = "Select an image for background removal."
        if panel.runModal() == .OK, let url = panel.url {
            selectedImageURLs = [url]
            originalImage = NSImage(contentsOf: url)
            processedImage = nil
            errorMessage = nil
            successMessage = nil
        }
    }

    /// Presents an open panel to choose multiple images for batch processing.
    private func chooseBatchImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.message = "Select images for batch background removal."
        if panel.runModal() == .OK {
            selectedImageURLs = panel.urls
            if let firstURL = panel.urls.first {
                originalImage = NSImage(contentsOf: firstURL)
            }
            processedImage = nil
            errorMessage = nil
            successMessage = nil
        }
    }

    /// Processes the selected images with the current configuration.
    private func processImages() async {
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        batchCompleted = 0
        batchTotal = selectedImageURLs.count
        batchProgress = 0

        let config = buildConfig()

        if selectedImageURLs.count == 1 {
            // Single image — show preview
            do {
                let data = try await BackgroundRemover.processImage(
                    inputURL: selectedImageURLs[0],
                    config: config
                )
                if let nsImage = NSImage(data: data) {
                    processedImage = nsImage
                }
                successMessage = "Background removed successfully."
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // Batch processing — save to output directory
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.message = "Choose output directory for processed images."
            savePanel.nameFieldLabel = "Output Folder:"
            savePanel.nameFieldStringValue = "BackgroundRemoved"

            // Use a simple directory approach: save to Desktop subfolder
            let outputDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BackgroundRemoved")

            do {
                let outputURLs = try await batchProcess(
                    inputURLs: selectedImageURLs,
                    outputDir: outputDir,
                    config: config
                )
                successMessage = "Processed \(outputURLs.count) images to \(outputDir.lastPathComponent)/"
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isProcessing = false
    }

    /// Processes a batch of images with progress tracking.
    ///
    /// - Parameters:
    ///   - inputURLs: Source image URLs.
    ///   - outputDir: Output directory.
    ///   - config: Background removal configuration.
    /// - Returns: Array of output file URLs.
    private func batchProcess(
        inputURLs: [URL],
        outputDir: URL,
        config: BackgroundRemovalConfig
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        var outputURLs: [URL] = []
        let ext = config.outputFormat.fileExtension

        for inputURL in inputURLs {
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputURL = outputDir.appendingPathComponent("\(baseName)_nobg.\(ext)")

            try await BackgroundRemover.removeBackground(
                inputURL: inputURL,
                outputURL: outputURL,
                config: config
            )
            outputURLs.append(outputURL)
            batchCompleted += 1
            batchProgress = Double(batchCompleted) / Double(batchTotal)
        }

        return outputURLs
    }

    /// Builds a ``BackgroundRemovalConfig`` from the current UI state.
    private func buildConfig() -> BackgroundRemovalConfig {
        var hexColor: String?
        if useReplaceColor {
            hexColor = colorToHex(replaceColor)
        }

        return BackgroundRemovalConfig(
            qualityLevel: qualityLevel,
            outputFormat: outputFormat,
            replaceColor: hexColor
        )
    }

    /// Converts a SwiftUI ``Color`` to a hex string.
    ///
    /// - Parameter color: The SwiftUI colour.
    /// - Returns: A hex string in ``"#RRGGBB"`` format.
    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = Int(converted.redComponent * 255)
        let g = Int(converted.greenComponent * 255)
        let b = Int(converted.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
