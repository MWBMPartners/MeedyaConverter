// ============================================================================
// MeedyaConverter — SmartCropView (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - SmartCropView

/// Provides a visual interface for subject-aware smart cropping.
///
/// Users can load an image (or video frame), detect subjects using
/// Vision framework analysis, preview the resulting crop rectangle
/// with bounding box overlays, and apply the crop to an encoding job.
///
/// Features:
/// - Image preview with detected subject bounding boxes
/// - Aspect ratio selector (16:9, 4:3, 1:1, 9:16)
/// - Rule-of-thirds toggle for compositional alignment
/// - Subject detection with confidence display
/// - Crop preview overlay
/// - FFmpeg filter string generation
///
/// Phase 11 — Smart Crop / Subject Detection (Issue #299)
struct SmartCropView: View {

    // MARK: - Aspect Ratio Options

    /// Predefined aspect ratio options for the crop selector.
    enum AspectRatioOption: String, CaseIterable {
        case ratio16_9 = "16:9"
        case ratio4_3 = "4:3"
        case ratio1_1 = "1:1"
        case ratio9_16 = "9:16"

        /// Numeric width/height ratio value.
        var numericValue: Double {
            switch self {
            case .ratio16_9: return 16.0 / 9.0
            case .ratio4_3: return 4.0 / 3.0
            case .ratio1_1: return 1.0
            case .ratio9_16: return 9.0 / 16.0
            }
        }
    }

    // MARK: - State

    /// The selected image URL for subject detection.
    @State private var selectedImageURL: URL?

    /// The loaded image for preview display.
    @State private var previewImage: NSImage?

    /// Detected subjects from the most recent analysis.
    @State private var detectedSubjects: [SubjectDetectionResult] = []

    /// Whether a detection operation is in progress.
    @State private var isDetecting = false

    /// The selected target aspect ratio.
    @State private var selectedAspectRatio: AspectRatioOption = .ratio16_9

    /// Whether to apply rule-of-thirds positioning.
    @State private var useRuleOfThirds = false

    /// The calculated crop rectangle in pixel coordinates.
    @State private var cropRect: CGRect?

    /// The generated FFmpeg crop filter string.
    @State private var cropFilterString: String?

    /// Error message from the most recent operation.
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            controlsSection
            if isDetecting {
                ProgressView("Detecting subjects…")
                    .padding()
            }
            HStack(spacing: 16) {
                imagePreviewSection
                detectionResultsSection
            }
            if let filter = cropFilterString {
                cropFilterSection(filter: filter)
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
            Text("Smart Crop")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Detect subjects in an image and calculate an optimal crop rectangle for the desired aspect ratio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    /// Image picker, aspect ratio selector, rule-of-thirds toggle, and detect button.
    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button("Choose Image…") {
                chooseImage()
            }

            if let url = selectedImageURL {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            Picker("Aspect Ratio:", selection: $selectedAspectRatio) {
                ForEach(AspectRatioOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            Toggle("Rule of Thirds", isOn: $useRuleOfThirds)
                .toggleStyle(.checkbox)

            Button("Detect Subjects") {
                Task { await detectSubjects() }
            }
            .disabled(selectedImageURL == nil || isDetecting)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Image Preview

    /// Image preview with bounding box overlays for detected subjects.
    @ViewBuilder
    private var imagePreviewSection: some View {
        GroupBox("Preview") {
            if let image = previewImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            GeometryReader { geo in
                                // Draw bounding boxes for each detected subject
                                ForEach(
                                    Array(detectedSubjects.enumerated()),
                                    id: \.offset
                                ) { _, subject in
                                    boundingBoxOverlay(
                                        subject: subject,
                                        displaySize: geo.size,
                                        imageSize: CGSize(
                                            width: image.size.width,
                                            height: image.size.height
                                        )
                                    )
                                }
                                // Draw crop rectangle preview
                                if let crop = cropRect {
                                    cropOverlay(
                                        crop: crop,
                                        displaySize: geo.size,
                                        imageSize: CGSize(
                                            width: image.size.width,
                                            height: image.size.height
                                        )
                                    )
                                }
                            }
                        }
                }
                .frame(maxWidth: 400, maxHeight: 300)
            } else {
                Text("No image selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400, maxHeight: 300)
            }
        }
    }

    // MARK: - Detection Results

    /// List of detected subjects with type, confidence, and bounding box details.
    @ViewBuilder
    private var detectionResultsSection: some View {
        GroupBox("Detected Subjects") {
            if detectedSubjects.isEmpty {
                Text("No subjects detected yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(
                        Array(detectedSubjects.enumerated()),
                        id: \.offset
                    ) { index, subject in
                        HStack {
                            // Subject type badge
                            Text(subject.subjectType.rawValue.capitalized)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForSubjectType(subject.subjectType).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(colorForSubjectType(subject.subjectType))

                            Spacer()

                            // Confidence
                            Text(String(format: "%.0f%%", subject.confidence * 100))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            Text("#\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: 250)
    }

    // MARK: - Crop Filter Output

    /// Displays the generated FFmpeg crop filter string.
    private func cropFilterSection(filter: String) -> some View {
        GroupBox("FFmpeg Crop Filter") {
            HStack {
                Text(filter)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Apply to Job") {
                    applyCropToJob()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Overlays

    /// Draws a bounding box overlay for a detected subject.
    ///
    /// Converts Vision's normalised coordinates (bottom-left origin) to
    /// SwiftUI's coordinate system (top-left origin) scaled to the display size.
    private func boundingBoxOverlay(
        subject: SubjectDetectionResult,
        displaySize: CGSize,
        imageSize: CGSize
    ) -> some View {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        let scale = min(scaleX, scaleY)

        let offsetX = (displaySize.width - imageSize.width * scale) / 2
        let offsetY = (displaySize.height - imageSize.height * scale) / 2

        // Convert from Vision coordinates (bottom-left) to display (top-left)
        let x = subject.boundingBox.origin.x * imageSize.width * scale + offsetX
        let y = (1.0 - subject.boundingBox.origin.y - subject.boundingBox.height) * imageSize.height * scale + offsetY
        let w = subject.boundingBox.width * imageSize.width * scale
        let h = subject.boundingBox.height * imageSize.height * scale

        return Rectangle()
            .stroke(colorForSubjectType(subject.subjectType), lineWidth: 2)
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }

    /// Draws a crop rectangle preview overlay.
    private func cropOverlay(
        crop: CGRect,
        displaySize: CGSize,
        imageSize: CGSize
    ) -> some View {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        let scale = min(scaleX, scaleY)

        let offsetX = (displaySize.width - imageSize.width * scale) / 2
        let offsetY = (displaySize.height - imageSize.height * scale) / 2

        let x = crop.origin.x * scale + offsetX
        let y = crop.origin.y * scale + offsetY
        let w = crop.width * scale
        let h = crop.height * scale

        return Rectangle()
            .stroke(Color.green, lineWidth: 2)
            .background(Color.green.opacity(0.05))
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }

    // MARK: - Actions

    /// Presents an open panel to choose an image file.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.message = "Select an image for subject detection."
        if panel.runModal() == .OK, let url = panel.url {
            selectedImageURL = url
            previewImage = NSImage(contentsOf: url)
            detectedSubjects = []
            cropRect = nil
            cropFilterString = nil
        }
    }

    /// Runs subject detection and calculates the crop rectangle.
    private func detectSubjects() async {
        guard let imageURL = selectedImageURL else { return }
        isDetecting = true
        errorMessage = nil
        detectedSubjects = []
        cropRect = nil
        cropFilterString = nil

        let subjects = await SmartCropDetector.detectSubjects(imageURL: imageURL)
        detectedSubjects = subjects

        // Calculate crop rectangle
        if let image = previewImage {
            let imageSize = CGSize(width: image.size.width, height: image.size.height)
            var rect = SmartCropDetector.calculateCropRect(
                subjects: subjects,
                targetAspectRatio: selectedAspectRatio.numericValue,
                imageSize: imageSize
            )

            // Apply rule of thirds if enabled and subjects exist
            if useRuleOfThirds, let firstSubject = subjects.first {
                let subjectCenterX = (firstSubject.boundingBox.origin.x + firstSubject.boundingBox.width / 2) * imageSize.width
                let subjectCenterY = (1.0 - firstSubject.boundingBox.origin.y - firstSubject.boundingBox.height / 2) * imageSize.height
                rect = SmartCropDetector.applyRuleOfThirds(
                    subjectCenter: CGPoint(x: subjectCenterX, y: subjectCenterY),
                    imageSize: imageSize,
                    cropSize: rect.size
                )
            }

            cropRect = rect
            cropFilterString = SmartCropDetector.buildCropFilter(cropRect: rect)
        }

        isDetecting = false
    }

    /// Applies the crop filter to the current encoding job.
    private func applyCropToJob() {
        // Crop filter application would be handled by the parent view or view model
    }

    // MARK: - Helpers

    /// Returns a colour associated with a subject type for visual differentiation.
    ///
    /// - Parameter type: The subject type.
    /// - Returns: A ``Color`` for the bounding box and badge.
    private func colorForSubjectType(_ type: SubjectType) -> Color {
        switch type {
        case .face: return .blue
        case .person: return .purple
        case .saliency: return .orange
        case .unknown: return .gray
        }
    }
}
