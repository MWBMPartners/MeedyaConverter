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
/// Opened from ``ComparisonLibraryView`` for a specific ``ComparisonEntry``.
/// On appearance, probes the source file's duration, extracts several
/// source/encoded frame pairs across the clip via
/// `FrameComparisonExtractor.buildBatchExtractionArguments`, and computes
/// whole-clip SSIM/PSNR — all executed through real `FFmpegProcessController`
/// runs, mirroring `AnimatedImageView.generate()`. A failed probe or
/// extraction surfaces as an honest error rather than a fabricated result.
///
/// Phase 7.11 / Issue #329
struct ComparisonView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Input

    /// The library entry (source + encoded file pair) this view compares.
    let entry: ComparisonEntry

    // MARK: - State

    @State private var comparisonMode: ComparisonMode = .sideBySide
    @State private var selectedFrameIndex: Int = 0
    @State private var sliderPosition: CGFloat = 0.5
    @State private var showingSource: Bool = true
    @State private var ssimValue: Double?
    @State private var psnrValue: Double?
    @State private var frames: [ComparisonFrame] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    /// Difference images generated on demand, keyed by frame id, so a
    /// frame's diff is only ever computed once per session.
    @State private var diffPaths: [UUID: String] = [:]
    @State private var isGeneratingDiff = false

    /// The FFmpeg process currently running, retained so leaving the view
    /// stops it immediately rather than letting it run to completion in
    /// the background. Mirrors `AnimatedImageView.currentController`.
    @State private var currentController: FFmpegProcessController?

    /// Guards against `loadComparison()` running twice concurrently (the
    /// initial `.task` plus a `Retry` tap racing each other).
    @State private var isLoadInFlight = false

    // MARK: - Initialiser

    init(entry: ComparisonEntry) {
        self.entry = entry
        // Seed from the metrics already computed at capture time so a
        // reopened comparison shows real numbers immediately instead of
        // re-running a full-clip SSIM/PSNR pass that would recompute the
        // exact same values against the same two files.
        _ssimValue = State(initialValue: entry.ssimScore)
        _psnrValue = State(initialValue: entry.psnrScore)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector toolbar
            modeSelectorBar

            Divider()

            // Main comparison area
            if let errorMessage {
                errorState(errorMessage)
            } else if frames.isEmpty && !isLoading {
                emptyState
            } else if frames.isEmpty {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                comparisonContent
            }

            Divider()

            // Frame timeline / quality metrics
            bottomBar
        }
        .navigationTitle("A/B Comparison")
        .task {
            await loadComparison()
        }
        .onDisappear {
            currentController?.stopEncoding()
            currentController = nil
        }
        .onChange(of: comparisonMode) { _, newMode in
            if newMode == .difference {
                Task { await ensureDifference(for: currentFrame) }
            }
        }
        .onChange(of: selectedFrameIndex) { _, _ in
            if comparisonMode == .difference {
                Task { await ensureDifference(for: currentFrame) }
            }
        }
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

            if isGeneratingDiff {
                ProgressView("Generating difference…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let frame = currentFrame, let diffPath = diffPaths[frame.id] {
                frameImage(path: diffPath)
            } else {
                frameImage(path: nil)
                    .overlay {
                        Text("Difference image could not be generated for this frame.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
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
                    .accessibilityLabel("Previous frame")

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
                    .accessibilityLabel("Next frame")
                }

                // Only scrub when there is something to scrub between. Each
                // of the extraction passes can fail independently, so a short
                // or partly corrupt file can yield exactly one frame — and
                // `0...0` is a degenerate range that SwiftUI normalises by
                // dividing by its own width, producing a NaN thumb position
                // and AppKit warnings.
                if frames.count > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(selectedFrameIndex) },
                            set: { selectedFrameIndex = Int($0) }
                        ),
                        in: 0...Double(frames.count - 1),
                        step: 1
                    )
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Frame scrubber")
                    .accessibilityValue("Frame \(selectedFrameIndex + 1) of \(frames.count)")
                }
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

    // MARK: - Empty / Error States

    private var emptyState: some View {
        ContentUnavailableView(
            "No Comparison Available",
            systemImage: "rectangle.split.2x1",
            description: Text("Complete an encoding job to compare source and output quality.")
        )
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Comparison Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                errorMessage = nil
                frames = []
                Task { await loadComparison() }
            }
        }
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

    // MARK: - Loading

    /// Loads the full frame-by-frame comparison for `entry`: probes the
    /// source file's real duration (`FFmpegBackendFactory`'s `runFFprobe`,
    /// the proven pattern from `BitrateHeatmapView.analyzeBitrate()`),
    /// spreads timestamps across the clip with
    /// `FrameComparisonExtractor.calculateTimestamps`, extracts each
    /// source/encoded frame pair with
    /// `FrameComparisonExtractor.buildBatchExtractionArguments` through a
    /// fresh `FFmpegProcessController` per pass (`AnimatedImageView`'s
    /// pattern), then computes whole-clip SSIM/PSNR the same way. Any
    /// step that fails leaves `errorMessage` set instead of fabricating
    /// frames or scores.
    private func loadComparison() async {
        guard !isLoadInFlight else { return }
        isLoadInFlight = true
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            isLoadInFlight = false
            currentController = nil
        }

        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached {
                try FFmpegBundleManager().locateFFmpeg().path
            }.value
        } catch {
            errorMessage = "FFmpeg could not be found. Install FFmpeg or configure its location in Settings."
            return
        }

        guard FileManager.default.fileExists(atPath: entry.sourceFile) else {
            errorMessage = "Source file not found at \(entry.sourceFile)."
            return
        }
        guard FileManager.default.fileExists(atPath: entry.encodedFile) else {
            errorMessage = "Encoded file not found at \(entry.encodedFile)."
            return
        }

        // Probe the real source duration so frames spread across the clip.
        let backend = FFmpegBackendFactory.makeDefault()
        let probeArgs = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            entry.sourceFile,
        ]
        var duration: TimeInterval = 0
        if let probeResult = try? await backend.runFFprobe(arguments: probeArgs, timeout: 30) {
            duration = Double(probeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        guard duration > 0 else {
            errorMessage = "Could not determine the duration of \(entry.sourceFileName). The file may be unreadable or corrupt."
            return
        }

        if Task.isCancelled { return }

        let timestamps = FrameComparisonExtractor.calculateTimestamps(duration: duration, count: 8)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeedyaComparison-\(entry.id.uuidString)")
            .path
        let outputPaths = FrameComparisonExtractor.buildOutputPaths(baseDirectory: outputDirectory)
        try? FileManager.default.createDirectory(
            atPath: outputPaths.sourceDir,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: outputPaths.encodedDir,
            withIntermediateDirectories: true
        )

        let batch = FrameComparisonExtractor.buildBatchExtractionArguments(
            sourcePath: entry.sourceFile,
            encodedPath: entry.encodedFile,
            timestamps: timestamps,
            outputDirectory: outputDirectory,
            width: 960
        )

        var builtFrames: [ComparisonFrame] = []
        for pass in batch {
            if Task.isCancelled { break }

            let sourceController = FFmpegProcessController(binaryPath: ffmpegPath)
            currentController = sourceController
            guard (try? await runToCompletion(sourceController, arguments: pass.sourceArgs)) != nil else {
                continue
            }

            let encodedController = FFmpegProcessController(binaryPath: ffmpegPath)
            currentController = encodedController
            guard (try? await runToCompletion(encodedController, arguments: pass.encodedArgs)) != nil else {
                continue
            }

            guard let sourceImagePath = pass.sourceArgs.last,
                  let encodedImagePath = pass.encodedArgs.last,
                  FileManager.default.fileExists(atPath: sourceImagePath),
                  FileManager.default.fileExists(atPath: encodedImagePath) else {
                continue
            }

            builtFrames.append(
                ComparisonFrame(
                    timestamp: pass.timestamp,
                    sourceImagePath: sourceImagePath,
                    encodedImagePath: encodedImagePath
                )
            )
        }

        if Task.isCancelled { return }

        guard !builtFrames.isEmpty else {
            errorMessage = "No frames could be extracted from \(entry.sourceFileName) or "
                + "\(URL(fileURLWithPath: entry.encodedFile).lastPathComponent)."
            return
        }

        frames = builtFrames
        selectedFrameIndex = 0

        // Generate the difference image if that mode is ALREADY selected.
        // Both `ensureDifference` triggers are `onChange` handlers, and
        // neither value changes here — `selectedFrameIndex` is set to 0 when
        // it is already 0 — so a user who switched to Difference while
        // extraction was still running would otherwise be shown the honest-
        // looking but false "Difference image could not be generated for this
        // frame" for a frame that was never attempted.
        if comparisonMode == .difference {
            await ensureDifference(for: currentFrame)
        }

        // Whole-clip SSIM (FrameComparisonExtractor) — skipped if the entry
        // already carries a real value from capture time; otherwise
        // best-effort, since a failure here does not invalidate the frames
        // already extracted.
        if ssimValue == nil, !Task.isCancelled {
            let ssimController = FFmpegProcessController(binaryPath: ffmpegPath)
            currentController = ssimController
            let ssimArgs = FrameComparisonExtractor.buildSSIMArguments(
                sourcePath: entry.sourceFile,
                encodedPath: entry.encodedFile
            )
            if (try? await runToCompletion(ssimController, arguments: ssimArgs)) != nil {
                ssimValue = FrameComparisonExtractor.parseSSIM(from: ssimController.errorOutput)
            }
        }

        // Whole-clip PSNR (FrameComparisonExtractor) — likewise skipped if
        // already known, otherwise best-effort.
        if psnrValue == nil, !Task.isCancelled {
            let psnrController = FFmpegProcessController(binaryPath: ffmpegPath)
            currentController = psnrController
            let psnrArgs = FrameComparisonExtractor.buildPSNRArguments(
                sourcePath: entry.sourceFile,
                encodedPath: entry.encodedFile
            )
            if (try? await runToCompletion(psnrController, arguments: psnrArgs)) != nil {
                psnrValue = FrameComparisonExtractor.parsePSNR(from: psnrController.errorOutput)
            }
        }
    }

    /// Generates (once per frame) the pixel-difference image between a
    /// frame's source and encoded images via
    /// `FrameComparisonExtractor.buildDifferenceArguments`, run through a
    /// real `FFmpegProcessController`. Leaves the frame's entry in
    /// `diffPaths` unset on failure so the difference view shows an
    /// honest "could not be generated" state rather than a stale image.
    private func ensureDifference(for frame: ComparisonFrame?) async {
        guard let frame else { return }
        guard diffPaths[frame.id] == nil else { return }

        isGeneratingDiff = true
        defer { isGeneratingDiff = false }

        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached {
                try FFmpegBundleManager().locateFFmpeg().path
            }.value
        } catch {
            return
        }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff_\(frame.id.uuidString).png")
            .path
        let args = FrameComparisonExtractor.buildDifferenceArguments(
            sourcePath: frame.sourceImagePath,
            encodedPath: frame.encodedImagePath,
            outputPath: outputPath
        )
        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = controller
        guard (try? await runToCompletion(controller, arguments: args)) != nil else { return }

        if FileManager.default.fileExists(atPath: outputPath) {
            diffPaths[frame.id] = outputPath
        }
    }

    /// Runs an `FFmpegProcessController` pass to completion by draining
    /// its progress `AsyncStream`. Mirrors `AnimatedImageView.runToCompletion`.
    private func runToCompletion(
        _ controller: FFmpegProcessController,
        arguments: [String]
    ) async throws {
        let progressStream = try controller.startEncoding(arguments: arguments)
        for await _ in progressStream {
            if Task.isCancelled {
                controller.stopEncoding()
                break
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }
    }
}
