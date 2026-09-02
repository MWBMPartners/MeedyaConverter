// ============================================================================
// MeedyaConverter — SmartCropView (Issue #299)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - SmartCropView

/// Subject-aware crop for the selected source file (Issue #299).
///
/// "Analyze" samples frames across the selected video with ffmpeg, runs
/// Vision face/saliency detection on each (`SmartCropVideoAnalyzer`), and
/// computes one crop at the chosen aspect ratio — inside the auto-detected
/// black-bar area when "Auto-crop black bars" is on. The preview shows the
/// middle sampled frame with that frame's subjects and the crop; changing
/// the aspect ratio or rule-of-thirds recomputes the crop without
/// re-analysing. "Apply to Next Encode" stages the crop on
/// `AppViewModel.pendingManualCropFilter`, which the next
/// `enqueueSelectedFile()` merges into the job's `-vf` (before any staged
/// filter graph, with precedence over auto-crop). Runs ffmpeg with progress
/// and Cancel; needs a re-encoding (non-passthrough) profile to apply.
struct SmartCropView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

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

    @State private var selectedAspectRatio: AspectRatioOption = .ratio16_9
    @State private var useRuleOfThirds = false
    @State private var sampleCount = 9
    @State private var isAnalysing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var progress: SmartCropVideoProgress?
    @State private var statusText = ""
    @State private var result: SmartCropVideoResult?
    @State private var analysedFileURL: URL?
    @State private var sourceWidth = 0
    @State private var sourceHeight = 0
    @State private var activeArea: CropRect?
    @State private var previewImage: NSImage?
    @State private var cropRect: CropRect?
    @State private var errorMessage: String?
    @State private var didApplyToJob = false
    @State private var didCopyFilter = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            sourceSection
            controlsSection
            if isAnalysing {
                progressSection
            }
            HStack(spacing: 16) {
                previewSection
                resultsSection
            }
            if let cropRect {
                cropFilterSection(cropRect)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: selectedAspectRatio) { recomputeCrop() }
        .onChange(of: useRuleOfThirds) { recomputeCrop() }
        .onChange(of: viewModel.selectedFile?.fileURL) { _, new in
            if new != analysedFileURL { resetResults() }
        }
        .onDisappear { cancel() }
    }

    // MARK: - Header

    /// Title and description area.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Smart Crop")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Detect subjects across the selected video and compute a crop for the desired aspect ratio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Source

    /// The currently selected source file, or a prompt to pick one.
    @ViewBuilder
    private var sourceSection: some View {
        if let file = viewModel.selectedFile {
            HStack(spacing: 12) {
                LabeledContent("File", value: file.fileName)
                if let video = file.primaryVideoStream, let w = video.width, let h = video.height {
                    Text("\(w)×\(h)")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Select a source file in the Source tab to crop.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    /// Aspect ratio selector, rule-of-thirds toggle, sample-count stepper, and analyze button.
    private var controlsSection: some View {
        HStack(spacing: 12) {
            Picker("Aspect Ratio:", selection: $selectedAspectRatio) {
                ForEach(AspectRatioOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            Toggle("Rule of Thirds", isOn: $useRuleOfThirds)
                .toggleStyle(.checkbox)

            Stepper("Sample frames: \(sampleCount)", value: $sampleCount, in: 3...21, step: 2)

            Button("Analyze Video") {
                startAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedFile == nil || isAnalysing)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel, action: cancel)
        }
        if let progress {
            ProgressView(value: Double(progress.completedFrames), total: Double(progress.totalFrames))
        }
    }

    // MARK: - Preview

    /// Preview of the middle sampled frame with subject and crop overlays.
    @ViewBuilder
    private var previewSection: some View {
        GroupBox("Preview") {
            if let image = previewImage {
                let subjects = result?.previewFrameIndex.map { result?.perFrameSubjects[$0] ?? [] } ?? []
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            GeometryReader { geo in
                                ForEach(Array(subjects.enumerated()), id: \.offset) { _, subject in
                                    boundingBoxOverlay(
                                        subject: subject,
                                        displaySize: geo.size,
                                        imageSize: CGSize(width: sourceWidth, height: sourceHeight))
                                }
                                if let cropRect {
                                    cropOverlay(
                                        crop: CGRect(x: cropRect.x, y: cropRect.y, width: cropRect.width, height: cropRect.height),
                                        displaySize: geo.size,
                                        imageSize: CGSize(width: sourceWidth, height: sourceHeight))
                                }
                            }
                        }
                }
                .frame(maxWidth: 400, maxHeight: 300)
            } else {
                Text("Analyze the selected video to see a preview.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400, maxHeight: 300)
            }
        }
    }

    // MARK: - Results

    /// Summary of the most recent analysis.
    @ViewBuilder
    private var resultsSection: some View {
        GroupBox("Detection") {
            if let r = result {
                VStack(alignment: .leading, spacing: 6) {
                    let s = r.summary
                    Text("Subjects in \(s.framesWithSubjects) of \(s.framesAnalysed) frames · \(s.faceCount) face detections")
                    if r.skippedFrames > 0 {
                        Text("\(r.skippedFrames) frame(s) could not be read")
                            .foregroundStyle(.secondary)
                    }
                    if let activeArea {
                        Label("Inside auto-detected picture area \(activeArea.displayString)", systemImage: "rectangle.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No analysis yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 250)
    }

    // MARK: - Crop Filter Output

    /// Displays the computed FFmpeg crop filter and staging controls.
    private func cropFilterSection(_ crop: CropRect) -> some View {
        GroupBox("FFmpeg Crop Filter") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(crop.displayString)
                            .foregroundStyle(.secondary)
                        Text(crop.filterString)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        copyFilter(crop)
                    } label: {
                        Label(didCopyFilter ? "Copied!" : "Copy Filter", systemImage: didCopyFilter ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        applyCropToJob()
                    } label: {
                        Label(didApplyToJob ? "Staged" : "Apply to Next Encode", systemImage: didApplyToJob ? "checkmark" : "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedProfile.videoPassthrough)
                    .help("Stage this crop onto the next job you queue")
                }
                if viewModel.selectedProfile.videoPassthrough {
                    Text("The selected profile copies the video stream — choose a re-encoding profile to crop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.pendingFilterGraphVideo?.contains("crop=") == true {
                    Text("A staged Filter Graph also contains a crop; both will apply in sequence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func startAnalysis() {
        guard let file = viewModel.selectedFile else { return }
        guard let video = file.primaryVideoStream, let w = video.width, let h = video.height, w > 0, h > 0 else {
            errorMessage = "The selected file has no video stream with known dimensions."
            return
        }
        resetResults()
        sourceWidth = w
        sourceHeight = h
        isAnalysing = true
        statusText = "Locating FFmpeg…"
        analysisTask = Task { await runAnalysis(file: file) }
    }

    private func runAnalysis(file: MediaFile) async {
        defer { finish() }
        let bundleManager = viewModel.engine.bundleManager
        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached { try bundleManager.locateFFmpeg().path }.value
        } catch {
            errorMessage = "FFmpeg could not be found: \(error.localizedDescription) Install FFmpeg or set its path in Settings."
            return
        }
        guard !Task.isCancelled else { return }

        // Black bars: reuse the live auto-crop pass so the smart crop is computed
        // inside the picture area (and a single `crop=` removes bars AND reframes).
        if viewModel.autoCropEnabled, viewModel.detectedCrop == nil {
            statusText = "Detecting black bars…"
            await viewModel.detectCropForSelectedFile()
        }
        guard !Task.isCancelled else { return }
        activeArea = Self.activeArea(
            from: viewModel.detectedCrop, autoCropEnabled: viewModel.autoCropEnabled,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight)

        let analyzer = SmartCropVideoAnalyzer(
            frameExtractor: FFmpegFrameExtractor(ffmpegPath: ffmpegPath),
            subjectDetector: SmartCropDetector())
        let request = SmartCropVideoRequest(videoURL: file.fileURL, duration: file.duration, sampleCount: sampleCount)
        statusText = "Analysing frame 1 of \(sampleCount)…"
        do {
            let analysis = try await analyzer.analyze(request) { p in
                Task { @MainActor in
                    self.progress = p
                    self.statusText = "Analysing frame \(min(p.completedFrames + 1, p.totalFrames)) of \(p.totalFrames)…"
                }
            }
            guard !Task.isCancelled else { return }
            result = analysis
            analysedFileURL = file.fileURL
            previewImage = analysis.previewFramePNG.flatMap { NSImage(data: $0) }
            recomputeCrop()
            viewModel.appendLog(.info, "Smart Crop: analysed \(analysis.perFrameSubjects.count) frames of \(file.fileName) — subjects in \(analysis.summary.framesWithSubjects), \(analysis.summary.faceCount) face detections", category: .filter)
        } catch is CancellationError {
            statusText = ""
        } catch {
            errorMessage = error.localizedDescription
            viewModel.appendLog(.warning, "Smart Crop analysis failed: \(error.localizedDescription)", category: .filter)
        }
    }

    /// The auto-crop rect is used as the picture area only when auto-crop is on,
    /// it actually crops, and it was measured on a frame of THESE dimensions —
    /// `detectedCrop` is not cleared when the selection changes, and carries no URL.
    static func activeArea(from detected: CropDetectionResult?, autoCropEnabled: Bool,
                           sourceWidth: Int, sourceHeight: Int) -> CropRect? {
        guard autoCropEnabled, let detected, detected.willCrop,
              detected.sourceWidth == sourceWidth, detected.sourceHeight == sourceHeight else { return nil }
        return detected.recommendedCrop
    }

    private func recomputeCrop() {
        guard let result, sourceWidth > 0, sourceHeight > 0 else { cropRect = nil; return }
        cropRect = SmartCropVideoAnalyzer.cropRect(
            summary: result.summary, sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            targetAspectRatio: selectedAspectRatio.numericValue,
            useRuleOfThirds: useRuleOfThirds, activeArea: activeArea)
        didApplyToJob = false
    }

    /// Stages the crop on `AppViewModel.pendingManualCropFilter`; the next
    /// `enqueueSelectedFile()` merges it into `videoFilterChain` (before any
    /// staged filter graph, with precedence over auto-crop) and clears it.
    private func applyCropToJob() {
        guard let cropRect else { return }
        viewModel.pendingManualCropFilter = cropRect.filterString
        viewModel.appendLog(.info, "Smart Crop: \(cropRect.filterString) will be applied to the next queued job", category: .filter)
        withAnimation { didApplyToJob = true }
    }

    private func copyFilter(_ crop: CropRect) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crop.filterString, forType: .string)
        didCopyFilter = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopyFilter = false }
    }

    private func resetResults() {
        result = nil; analysedFileURL = nil; previewImage = nil; cropRect = nil
        activeArea = nil; errorMessage = nil; didApplyToJob = false; progress = nil
    }

    private func finish() { analysisTask = nil; isAnalysing = false; progress = nil }

    private func cancel() { analysisTask?.cancel(); finish() }

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
