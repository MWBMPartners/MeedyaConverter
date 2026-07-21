// ============================================================================
// MeedyaConverter — VideoTrimmerView (Issues #318, #341)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
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

    /// Success message to display after Apply genuinely completes, if any.
    @State private var successMessage: String?

    // MARK: - Apply Execution State (Issue #444)

    /// The in-flight apply task, retained so it can be cancelled when the
    /// user navigates away from this view while a trim/snip/split is
    /// running. Mirrors `LoudnessReportView.analysisTask` /
    /// `BenchmarkView.benchmarkTask`.
    @State private var applyTask: Task<Void, Never>?

    /// The FFmpeg process controller for the pass currently running,
    /// retained so `cancelApply()` can stop the running process rather
    /// than merely abandoning it.
    @State private var currentController: FFmpegProcessController?

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

    /// Whether a drag operation is hovering over this view.
    @State private var isDragTargeted = false

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
        .onDisappear { cancelApply() }
        // Drop a single video file to set as the trim source (Issue #366).
        .onDrop(
            of: [.fileURL, .movie, .video],
            isTargeted: $isDragTargeted
        ) { providers in
            DropHandler.extractURLs(from: providers) { urls in
                guard let url = urls.first else { return }
                Task {
                    await viewModel.importFiles([url])
                }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 3)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
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

            // Success display (Issue #444) — only ever set after the
            // FFmpeg process genuinely completes and its output file
            // has been verified to exist on disk.
            if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
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
    ///
    /// Mirrors the execution pattern proven in
    /// `QualityMetricsView.runAnalysis()` (Issue #434) and
    /// `BenchmarkView.runStandardBenchmarks()` (Issue #435): locate FFmpeg
    /// via `FFmpegBundleManager`, build arguments with the `VideoTrimmer`/
    /// `VideoConcatenator` builders, run them through
    /// `FFmpegProcessController.startEncoding(arguments:)`, and only report
    /// success once the process has genuinely exited zero *and* the output
    /// file has been verified to exist on disk (Issue #444).
    ///
    /// `VideoTrimmerView` is a `struct: View`, not a `@MainActor` class, so
    /// — like the sibling views in this file's neighbourhood — its methods
    /// are implicitly main-actor isolated via `View` conformance. A plain
    /// `Task { }` here therefore inherits that isolation, so `@State`
    /// mutations are direct property writes rather than `MainActor.run`
    /// hops (matching `QualityMetricsView`'s post-Issue-#434 shape). Every
    /// value captured into the task — paths, `TrimConfig`, the resulting
    /// argument arrays — is `Sendable`, so nothing unsafe crosses the
    /// closure boundary. The one genuinely blocking call —
    /// `FFmpegBundleManager.locateFFmpeg()`, which blocks synchronously on
    /// process exit — is still pulled into a `Task.detached` that returns
    /// only a `Sendable` `String` and never touches `self`/`@State`, so it
    /// never blocks the main thread.
    private func applyTrim() {
        guard let file = viewModel.selectedFile else {
            errorMessage = "No source file selected. Import a video file before applying a trim."
            return
        }

        errorMessage = nil
        successMessage = nil
        isApplying = true

        let splitBytes: Int64? = if let mb = Double(splitSizeMB), mb > 0 {
            Int64(mb * 1_048_576)
        } else {
            nil
        }

        let config = TrimConfig(
            trimStart: trimStartFraction * duration,
            trimEnd: trimEndFraction * duration,
            snipRegions: snipRegions,
            splitByChapters: splitByChapters,
            splitBySize: splitBytes,
            copyMode: copyMode
        )

        let inputPath = file.fileURL.path
        let outputDir = viewModel.outputDirectory ?? FileManager.default.temporaryDirectory
        let baseName = PathSanitizer.sanitizeFilenameComponent(
            file.fileURL.deletingPathExtension().lastPathComponent
        )
        let ext = file.fileURL.pathExtension.isEmpty ? "mp4" : file.fileURL.pathExtension
        let sourceDuration = duration

        applyTask = Task {
            let ffmpegPath: String
            do {
                ffmpegPath = try await Task.detached {
                    try FFmpegBundleManager().locateFFmpeg().path
                }.value
            } catch {
                errorMessage = "FFmpeg could not be found. Install FFmpeg or configure its location in Settings before applying a trim."
                isApplying = false
                return
            }

            do {
                // Split takes priority when configured, since FFmpeg's
                // segment muxer (buildSplitArguments) operates on the whole
                // input independently of trim/snip. Otherwise snip (which
                // itself respects the trim head/tail via buildSnipArguments)
                // runs when interior regions are marked; a plain head/tail
                // trim is the fallback.
                if config.splitBySize != nil || config.splitByChapters {
                    let outputs = try await runSplit(
                        ffmpegPath: ffmpegPath,
                        inputPath: inputPath,
                        outputDir: outputDir,
                        config: config,
                        duration: sourceDuration
                    )
                    successMessage = "Split complete. Wrote \(outputs.count) file(s) to \(outputDir.path)."
                } else if !config.snipRegions.isEmpty {
                    let output = try await runSnipAndConcat(
                        ffmpegPath: ffmpegPath,
                        inputPath: inputPath,
                        outputDir: outputDir,
                        baseName: baseName,
                        ext: ext,
                        config: config
                    )
                    successMessage = "Snip complete. Output written to \(output)."
                } else {
                    let output = try await runSimpleTrim(
                        ffmpegPath: ffmpegPath,
                        inputPath: inputPath,
                        outputDir: outputDir,
                        baseName: baseName,
                        ext: ext,
                        config: config
                    )
                    successMessage = "Trim complete. Output written to \(output)."
                }
            } catch is CancellationError {
                // Cancelled by the user (or the view disappeared) — no
                // success/error banner; cancelApply() already reset state.
            } catch {
                errorMessage = "Trim failed: \(error.localizedDescription)"
            }

            currentController = nil
            isApplying = false
        }
    }

    /// Cancel an in-progress Apply operation.
    ///
    /// Stops the currently-running FFmpeg process (if any) and cancels the
    /// apply `Task` so no process or task is left running in the
    /// background after the user navigates away from this view mid-trim.
    private func cancelApply() {
        currentController?.stopEncoding()
        currentController = nil
        applyTask?.cancel()
        applyTask = nil
        isApplying = false
    }

    /// Runs a single FFmpeg pass to completion, honouring cancellation and
    /// checking the real exit code — mirrors the pass-execution shape
    /// proven in `QualityMetricsView.runAnalysis()`'s `passLoop`.
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

    /// Runs a simple head/tail trim (`VideoTrimmer.buildTrimArguments`) and
    /// returns the produced output path. Throws if FFmpeg exits non-zero or
    /// no output file is actually written.
    private func runSimpleTrim(
        ffmpegPath: String,
        inputPath: String,
        outputDir: URL,
        baseName: String,
        ext: String,
        config: TrimConfig
    ) async throws -> String {
        let outputPath = outputDir.appendingPathComponent(
            PathSanitizer.sanitizeFilenameComponent("\(baseName)_trimmed.\(ext)")
        ).path

        let arguments = VideoTrimmer.buildTrimArguments(
            inputPath: inputPath,
            outputPath: outputPath,
            config: config
        )

        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = controller
        try await runToCompletion(controller, arguments: arguments)

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw FFmpegProcessError.processFailure(
                exitCode: controller.exitCode ?? -1,
                stderr: "FFmpeg reported success but no output file was found at \(outputPath)."
            )
        }
        return outputPath
    }

    /// Runs a snip operation: one `VideoTrimmer.buildSnipArguments` FFmpeg
    /// pass per keep-segment (written to a scratch temp directory), then
    /// joins the segments into the final output with
    /// `VideoConcatenator.buildDemuxerConcatArguments`. The scratch segment
    /// files and concat list are always removed afterwards, whether the
    /// operation succeeds or fails.
    private func runSnipAndConcat(
        ffmpegPath: String,
        inputPath: String,
        outputDir: URL,
        baseName: String,
        ext: String,
        config: TrimConfig
    ) async throws -> String {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim_snip_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }

        let segments = VideoTrimmer.buildSnipArguments(
            inputPath: inputPath,
            outputDir: scratchDir.path,
            config: config
        )
        guard !segments.isEmpty else {
            throw FFmpegProcessError.processFailure(
                exitCode: -1,
                stderr: "The configured trim/snip range leaves no content to keep."
            )
        }

        for segment in segments {
            if Task.isCancelled { throw CancellationError() }
            let controller = FFmpegProcessController(binaryPath: ffmpegPath)
            currentController = controller
            try await runToCompletion(controller, arguments: segment.arguments)
            guard FileManager.default.fileExists(atPath: segment.outputPath) else {
                throw FFmpegProcessError.processFailure(
                    exitCode: controller.exitCode ?? -1,
                    stderr: "FFmpeg reported success but no segment file was found at \(segment.outputPath)."
                )
            }
        }

        let finalOutputPath = outputDir.appendingPathComponent(
            PathSanitizer.sanitizeFilenameComponent("\(baseName)_trimmed.\(ext)")
        ).path

        let segmentURLs = segments.map { URL(fileURLWithPath: $0.outputPath) }
        let (concatListContent, concatArgsTemplate) = VideoConcatenator.buildDemuxerConcatArguments(
            files: segmentURLs,
            outputPath: finalOutputPath
        )

        let listFileURL = scratchDir.appendingPathComponent("concat_list.txt")
        try concatListContent.write(to: listFileURL, atomically: true, encoding: .utf8)

        let concatArguments = concatArgsTemplate.map {
            $0 == "<CONCAT_LIST_FILE>" ? listFileURL.path : $0
        }

        if Task.isCancelled { throw CancellationError() }
        let concatController = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = concatController
        try await runToCompletion(concatController, arguments: concatArguments)

        guard FileManager.default.fileExists(atPath: finalOutputPath) else {
            throw FFmpegProcessError.processFailure(
                exitCode: concatController.exitCode ?? -1,
                stderr: "FFmpeg reported success but no output file was found at \(finalOutputPath)."
            )
        }
        return finalOutputPath
    }

    /// Runs a size- or chapter-based split (`VideoTrimmer.buildSplitArguments`).
    /// FFmpeg's segment muxer writes every output file from a single pass,
    /// so this is one FFmpeg invocation; returns the paths of the files
    /// actually found on disk matching the segment pattern.
    private func runSplit(
        ffmpegPath: String,
        inputPath: String,
        outputDir: URL,
        config: TrimConfig,
        duration: TimeInterval
    ) async throws -> [String] {
        let jobs = VideoTrimmer.buildSplitArguments(
            inputPath: inputPath,
            outputDir: outputDir.path,
            config: config,
            duration: duration
        )
        guard let job = jobs.first else {
            throw FFmpegProcessError.processFailure(
                exitCode: -1,
                stderr: "No split configuration (chapters or max size) was set."
            )
        }

        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = controller
        try await runToCompletion(controller, arguments: job.arguments)

        // job.outputPath is a segment-muxer pattern such as
        // ".../split_%03d.mp4" — resolve which files FFmpeg actually wrote
        // by matching the literal prefix/suffix around "%03d".
        let patternURL = URL(fileURLWithPath: job.outputPath)
        let patternName = patternURL.lastPathComponent
        let patternParts = patternName.components(separatedBy: "%03d")
        let prefix = patternParts.first ?? patternName
        let suffix = patternParts.count > 1 ? patternParts[1] : ""

        let dirContents = (try? FileManager.default.contentsOfDirectory(
            at: patternURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []
        let written = dirContents
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix) }
            .map(\.path)
            .sorted()

        guard !written.isEmpty else {
            throw FFmpegProcessError.processFailure(
                exitCode: controller.exitCode ?? -1,
                stderr: "FFmpeg reported success but no split output files were found matching \(job.outputPath)."
            )
        }
        return written
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
