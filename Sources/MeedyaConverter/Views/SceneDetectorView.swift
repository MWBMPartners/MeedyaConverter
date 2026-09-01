// ============================================================================
// MeedyaConverter — SceneDetectorView (Issue #288)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - SceneDetectorView

/// Scene detection and chapter generation interface.
///
/// Provides a threshold slider for tuning detection sensitivity, a scene
/// list with timestamps and confidence scores, chapter file generation
/// in OGM/Matroska/FFmetadata formats, and manual chapter editing
/// (add/remove markers).
///
/// Phase 11 — Scene Detection for Chapter Generation (Issue #288)
struct SceneDetectorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var threshold: Double = 0.3
    @State private var detectedScenes: [DetectedScene] = []
    @State private var isDetecting = false
    @State private var selectedSceneID: UUID?
    @State private var chapterFormat: ChapterFormat = .ffmetadata
    @State private var manualTimestamp: String = ""
    @State private var errorMessage: String?

    /// Fractional progress (0.0–1.0) of the in-flight detection pass, taken
    /// from `FFmpegProgressInfo.fractionComplete` as FFmpeg's `-progress`
    /// output arrives. `nil` while no run is active, or before the first
    /// progress tick with a known fraction arrives (an indeterminate
    /// spinner is shown in that case instead).
    @State private var detectionProgress: Double?

    /// The in-flight detection task, retained so it can be cancelled if
    /// the user clicks Cancel or navigates away mid-detection. Mirrors
    /// `AnimatedImageView.generationTask`.
    @State private var detectionTask: Task<Void, Never>?

    /// The FFmpeg process currently running the scene-detection pass,
    /// retained so `cancelDetection()` can stop it. Mirrors
    /// `AnimatedImageView.currentController`.
    @State private var currentController: FFmpegProcessController?

    /// Why "Apply to Job" is permanently disabled (Issue #288).
    ///
    /// `EncodingJobConfig`/`EncodingProfile` (`ConverterEngine/Encoding
    /// /EncodingJob.swift`, `EncodingProfile.swift`) have no field for
    /// attaching an external chapters/FFmetadata file to a job — the
    /// closest mechanisms are `EncodingJobConfig.extraArguments` /
    /// `FFmpegArgumentBuilder.additionalInputs`, but `FFmpegArgumentBuilder
    /// .build()` already hard-codes `-map_chapters 0` whenever
    /// `copySourceMetadata` is true (its default), and nothing exposes an
    /// override for that from `EncodingJobConfig`. There is also no
    /// live "current job" object in `AppViewModel` for this view to reach
    /// into: jobs are materialised only once, inside
    /// `AppViewModel.enqueueSelectedFile()`, built fresh from
    /// `selectedFile` + `selectedProfile` at that moment. Wiring this up
    /// properly needs a staged value on `AppViewModel` — mirroring
    /// `pendingManualCropFilter` — consumed there, which is out of this
    /// view's scope. Rather than fake success (the original bug), the
    /// button stays disabled and honestly labelled until that lands.
    private let applyToJobUnavailableReason =
        "Chapters can't be attached to a job yet — the encoding job model has no field for external chapter metadata. Use \"Export Chapters\" above and inject the file manually."

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Detection controls
            controlsBar

            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            Divider()

            // Main content
            if isDetecting {
                detectingView
            } else if !detectedScenes.isEmpty {
                HSplitView {
                    sceneListView
                        .frame(minWidth: 300)

                    sceneDetailView
                        .frame(minWidth: 300)
                }
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Scene Detection")
        .onDisappear {
            cancelDetection()
        }
    }

    /// Banner shown when scene detection fails or finds nothing, mirroring
    /// `BitrateHeatmapView.exportErrorBanner(message:)`.
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Threshold slider
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Threshold")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", threshold))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $threshold, in: 0.1...0.9, step: 0.05) {
                    Text("Scene detection sensitivity threshold")
                }
                .frame(maxWidth: 200)
                .accessibilityLabel("Scene detection threshold")
                .accessibilityValue(String(format: "%.2f", threshold))

                HStack {
                    Text("More scenes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Fewer scenes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 200)
            }

            // Detect button
            Button {
                detectionTask = Task { await detectScenes() }
            } label: {
                Label("Detect Scenes", systemImage: "film.stack")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedFile == nil || isDetecting)
            .accessibilityLabel("Run scene detection on selected file")

            if isDetecting {
                Button("Cancel", action: cancelDetection)
                    .accessibilityLabel("Cancel scene detection")
            }

            Spacer()

            // Scene count badge
            if !detectedScenes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .foregroundStyle(.blue)
                    Text("\(detectedScenes.count) scenes detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let file = viewModel.selectedFile {
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Detecting State

    private var detectingView: some View {
        VStack(spacing: 12) {
            if let detectionProgress {
                ProgressView(value: detectionProgress)
                    .frame(maxWidth: 240)
                Text("\(Int((detectionProgress * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text("Detecting scene changes...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Analysing frame-to-frame differences with threshold \(String(format: "%.2f", threshold)).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Scenes Detected",
            systemImage: "film.stack",
            description: Text("Select a video file and click \"Detect Scenes\" to identify scene changes and generate chapter markers.")
        )
    }

    // MARK: - Scene List

    private var sceneListView: some View {
        VStack(spacing: 0) {
            // List header
            HStack {
                Text("Detected Scenes")
                    .font(.headline)
                Spacer()

                // Add manual marker
                HStack(spacing: 4) {
                    TextField("HH:MM:SS", text: $manualTimestamp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .font(.caption.monospaced())

                    Button {
                        addManualMarker()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(manualTimestamp.isEmpty)
                    .accessibilityLabel("Add manual chapter marker at specified timestamp")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Scene list
            List(selection: $selectedSceneID) {
                ForEach(detectedScenes) { scene in
                    sceneRow(scene: scene)
                        .tag(scene.id)
                }
                .onDelete { indexSet in
                    removeScenes(at: indexSet)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func sceneRow(scene: DetectedScene) -> some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
            if let thumbnailPath = scene.thumbnailPath {
                AsyncImage(url: URL(fileURLWithPath: thumbnailPath)) { image in
                    image
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                .frame(width: 80)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(width: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Scene info
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.formattedTimestamp)
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Confidence badge
                    confidenceBadge(score: scene.score)

                    Text("Score: \(String(format: "%.3f", scene.score))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Visual badge indicating scene detection confidence level.
    private func confidenceBadge(score: Double) -> some View {
        let label: String
        let color: Color

        if score >= 0.7 {
            label = "High"
            color = .green
        } else if score >= 0.4 {
            label = "Medium"
            color = .orange
        } else {
            label = "Low"
            color = .red
        }

        return Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Scene Detail / Chapter Export

    private var sceneDetailView: some View {
        VStack(spacing: 0) {
            // Chapter generation header
            HStack {
                Text("Chapter Generation")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Form {
                // Format picker
                Section("Output Format") {
                    Picker("Format", selection: $chapterFormat) {
                        ForEach(ChapterFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .accessibilityLabel("Chapter file output format")

                    Text("File extension: .\(chapterFormat.fileExtension)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Chapter preview
                Section("Preview") {
                    chapterPreview
                }

                // Actions
                Section {
                    HStack {
                        Button {
                            generateAndExportChapters()
                        } label: {
                            Label("Export Chapters", systemImage: "square.and.arrow.down")
                        }
                        .disabled(detectedScenes.isEmpty)
                        .accessibilityLabel("Export chapter file to disk")

                        Spacer()

                        // Permanently disabled — see `applyToJobUnavailableReason`.
                        // `EncodingJobConfig`/`EncodingProfile` have no field to
                        // carry external chapter metadata into an encode, so this
                        // is left honestly non-functional rather than logging a
                        // fake "applied" message (the original issue #288 bug).
                        Button {
                            // Intentionally empty: permanently disabled below.
                        } label: {
                            Label("Apply to Job (Unavailable)", systemImage: "exclamationmark.circle")
                        }
                        .disabled(true)
                        .help(applyToJobUnavailableReason)
                        .accessibilityLabel(applyToJobUnavailableReason)
                    }

                    Text(applyToJobUnavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Chapter Preview

    private var chapterPreview: some View {
        let preview = SceneDetector.generateChapterFile(
            scenes: detectedScenes,
            format: chapterFormat
        )

        return ScrollView {
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 150, maxHeight: 250)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    /// Run scene detection on the currently selected file.
    ///
    /// Builds FFmpeg arguments via ``SceneDetector/buildDetectionArguments(inputPath:threshold:outputPath:)``
    /// and actually executes them through ``FFmpegProcessController`` —
    /// the same runner/`AsyncStream`-draining pattern
    /// `AnimatedImageView.generate()` / `BitrateHeatmapView.analyzeBitrate()`
    /// use (see `runToCompletion(_:arguments:)` below). That builder's
    /// filter chain (`select='gt(scene,T)',metadata=print:file=…`) is the
    /// standard FFmpeg scene-detection idiom, and `SceneDetector
    /// .parseSceneOutput(_:)` already parses exactly the `pts_time:` /
    /// `lavfi.scene_score=` key/value pairs that filter writes to
    /// `outputPath` — so once the process exits cleanly, that file is read
    /// back and parsed straight into ``detectedScenes``. No changes to
    /// `SceneDetector`'s argument-building or parsing were needed.
    ///
    /// A real failure (missing FFmpeg, non-zero exit, cancellation, or a
    /// clean run that simply found nothing above `threshold`) is surfaced
    /// via ``errorMessage`` instead of silently clearing the in-progress
    /// flag, which was the original issue #288 bug.
    ///
    /// `SceneDetectorView` is a `struct: View`, so this `async` method
    /// (and the `Task` that invokes it from `controlsBar`) is implicitly
    /// main-actor isolated via `View` conformance — `@State` writes below
    /// are direct property mutations, matching `AnimatedImageView.generate()`'s
    /// shape.
    private func detectScenes() async {
        guard let file = viewModel.selectedFile else { return }
        guard !isDetecting else { return }

        isDetecting = true
        errorMessage = nil
        detectionProgress = nil

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("meedya_scenes_\(UUID().uuidString).txt")
        let outputPath = outputURL.path

        let args = SceneDetector.buildDetectionArguments(
            inputPath: file.fileURL.path,
            threshold: threshold,
            outputPath: outputPath
        )

        viewModel.appendLog(
            .info,
            "Scene detection started for \(file.fileName) with threshold \(String(format: "%.2f", threshold))",
            category: .general
        )

        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached {
                try FFmpegBundleManager().locateFFmpeg().path
            }.value
        } catch {
            // Surface the underlying FFmpegBundleError rather than a generic
            // string — it distinguishes "no binary found" from "found but not
            // executable" and from a version-detection failure, which is the
            // difference between three quite different user actions. Logged as
            // well, matching every other failure path in this method.
            errorMessage = "FFmpeg could not be found: \(error.localizedDescription) "
                + "Install FFmpeg or configure its location in Settings."
            viewModel.appendLog(
                .error,
                "Scene detection could not start — FFmpeg lookup failed: \(error.localizedDescription)",
                category: .general
            )
            isDetecting = false
            return
        }

        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        controller.sourceDuration = file.duration
        currentController = controller

        do {
            try await runToCompletion(controller, arguments: args)

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw FFmpegProcessError.processFailure(
                    exitCode: controller.exitCode ?? -1,
                    stderr: "FFmpeg reported success but wrote no scene metadata to \(outputPath)."
                )
            }

            let output = try String(contentsOf: outputURL, encoding: .utf8)
            let parsed = SceneDetector.parseSceneOutput(output)
            try? FileManager.default.removeItem(at: outputURL)

            detectedScenes = parsed

            if parsed.isEmpty {
                errorMessage = "No scene changes detected above threshold \(String(format: "%.2f", threshold)) for \(file.fileName). Try lowering the threshold."
            } else {
                viewModel.appendLog(
                    .info,
                    "Scene detection complete for \(file.fileName): \(parsed.count) scene(s) found at threshold \(String(format: "%.2f", threshold))",
                    category: .general
                )
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            viewModel.appendLog(.info, "Scene detection cancelled for \(file.fileName)", category: .general)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            errorMessage = "Scene detection failed for \(file.fileName): \(error.localizedDescription)"
            viewModel.appendLog(
                .error,
                "Scene detection failed for \(file.fileName): \(error.localizedDescription)",
                category: .general
            )
        }

        currentController = nil
        // Release the finished Task too. cancelDetection() clears it, but a run
        // that completes normally otherwise leaves a dead Task retained until
        // the next run — harmless, but it is state that no longer means
        // anything, and a stale non-nil value invites a future reader to treat
        // "detectionTask != nil" as "a detection is in flight".
        detectionTask = nil
        detectionProgress = nil
        isDetecting = false
    }

    /// Runs an `FFmpegProcessController` detection pass to completion by
    /// draining its progress `AsyncStream`, updating ``detectionProgress``
    /// as fractions become available. Mirrors
    /// `AnimatedImageView.runToCompletion(_:arguments:)`.
    private func runToCompletion(
        _ controller: FFmpegProcessController,
        arguments: [String]
    ) async throws {
        let progressStream = try controller.startEncoding(arguments: arguments)
        for await progress in progressStream {
            if Task.isCancelled {
                controller.stopEncoding()
                break
            }
            if let fraction = progress.fractionComplete {
                detectionProgress = fraction
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }
    }

    /// Cancel an in-progress scene detection. Mirrors
    /// `AnimatedImageView.cancelGeneration()`.
    private func cancelDetection() {
        detectionTask?.cancel()
        currentController?.stopEncoding()
        currentController = nil
        detectionTask = nil
        isDetecting = false
    }

    /// Add a manual chapter marker at the user-specified timestamp.
    private func addManualMarker() {
        guard !manualTimestamp.isEmpty else { return }

        let seconds = parseTimestamp(manualTimestamp)
        guard seconds > 0 else {
            errorMessage = "Invalid timestamp format. Use HH:MM:SS or seconds."
            return
        }

        let newScene = DetectedScene(
            timestamp: seconds,
            score: 1.0
        )

        detectedScenes.append(newScene)
        detectedScenes.sort { $0.timestamp < $1.timestamp }
        manualTimestamp = ""
    }

    /// Remove scenes at the given index set (for false positive removal).
    private func removeScenes(at indexSet: IndexSet) {
        detectedScenes.remove(atOffsets: indexSet)
    }

    /// Export the generated chapter file to disk.
    private func generateAndExportChapters() {
        let content = SceneDetector.generateChapterFile(
            scenes: detectedScenes,
            format: chapterFormat
        )

        let panel = NSSavePanel()
        panel.title = "Export Chapter File"
        panel.nameFieldStringValue = "chapters.\(chapterFormat.fileExtension)"

        // Set allowed content types based on format
        switch chapterFormat {
        case .ogm, .ffmetadata:
            panel.allowedContentTypes = [.plainText]
        case .matroskaXML:
            panel.allowedContentTypes = [.xml]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            viewModel.appendLog(
                .info,
                "Exported \(detectedScenes.count) chapters in \(chapterFormat.displayName) format to \(url.lastPathComponent)",
                category: .metadata
            )
        } catch {
            errorMessage = "Failed to export chapters: \(error.localizedDescription)"
        }
    }

    // MARK: - Timestamp Parsing

    /// Parse a timestamp string in HH:MM:SS, MM:SS, or raw seconds format.
    private func parseTimestamp(_ input: String) -> TimeInterval {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Try raw seconds first
        if let seconds = Double(trimmed) {
            return seconds
        }

        // Try HH:MM:SS or MM:SS
        let components = trimmed.components(separatedBy: ":")
        if components.count == 3,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2,
                  let minutes = Double(components[0]),
                  let seconds = Double(components[1]) {
            return minutes * 60 + seconds
        }

        return 0
    }
}
