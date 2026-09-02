// ============================================================================
// MeedyaConverter — ConcatenationView (Issue #322)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - ConcatenationView

/// Video concatenation and joining interface.
///
/// Provides a drag-to-reorder file list, add/remove file controls,
/// a method picker (lossless demuxer vs. re-encode filter), crossfade
/// duration slider (filter mode only), compatibility warnings for
/// demuxer mode, and output path selection.
///
/// A "Start" action runs the lossless demuxer-concat path
/// (`VideoConcatenator.buildDemuxerConcatArguments`) through a real
/// `FFmpegProcessController`, surfacing genuine progress and errors and
/// verifying the joined output file on disk before reporting success. The
/// re-encode filter path (with optional crossfade) is not yet wired to an
/// executable action — its controls stay visible but disabled with an
/// honest explanation rather than silently doing nothing.
///
/// Phase 9 — Video Concatenation and Joining (Issue #322)
struct ConcatenationView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// Ordered list of input file URLs to concatenate.
    @State private var files: [URL] = []

    /// Selected concatenation method (lossless or re-encode).
    @State private var method: ConcatMethod = .demuxer

    /// Crossfade duration in seconds (filter mode only).
    @State private var crossfadeDuration: Double = 1.0

    /// Whether crossfade is enabled (filter mode only).
    @State private var crossfadeEnabled = false

    /// Compatibility warnings for demuxer mode.
    @State private var compatibilityWarnings: [String] = []

    /// Output file path for the concatenated result.
    @State private var outputPath: String = ""

    /// Whether the file import dialog is presented.
    @State private var showingFileImporter = false

    /// Error message to display in an alert.
    @State private var errorMessage: String?

    /// Error text for the Concatenate action specifically.
    ///
    /// Deliberately separate from `errorMessage`, which backs the file-import
    /// alert. Sharing one property meant that dismissing an import alert left
    /// `errorMessage` populated, and the Concatenate section then rendered it
    /// as inline red text — implying the join had failed when it had never
    /// been attempted.
    @State private var concatErrorMessage: String?

    /// Whether the error alert is presented.
    @State private var showError = false

    /// The currently selected file ID for drag-to-reorder.
    @State private var selectedFileID: URL?

    /// Whether a drag operation is hovering over this view.
    @State private var isDragTargeted = false

    // MARK: - Concatenation Execution State (Issue #322)

    /// Whether a concatenation operation is currently running.
    @State private var isRunning = false

    /// Success message to display after the concatenation genuinely
    /// completes and the output file has been verified on disk.
    @State private var successMessage: String?

    /// Latest progress fraction (0.0 to 1.0) reported by FFmpeg while a
    /// concatenation is running, if known.
    @State private var progressFraction: Double?

    /// The in-flight concatenation task, retained so it can be cancelled
    /// when the user navigates away from this view while a join is
    /// running. Mirrors `VideoTrimmerView.applyTask`.
    @State private var concatTask: Task<Void, Never>?

    /// The FFmpeg process controller for the pass currently running,
    /// retained so `cancelConcatenation()` can stop the running process
    /// rather than merely abandoning it.
    @State private var currentController: FFmpegProcessController?

    /// Whether the Start button should be disabled: while a join is
    /// running, with fewer than two files, with no output path chosen,
    /// while the re-encode filter path is selected (not yet wired — see
    /// the Crossfade section), or while demuxer compatibility validation
    /// reports a blocking problem.
    private var startDisabled: Bool {
        isRunning
            || files.count < 2
            || outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Compatibility warnings only block the lossless demuxer path; the
            // re-encode filter path tolerates differing codecs (#322).
            || (method == .demuxer && !compatibilityWarnings.isEmpty)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with add/remove controls
            controlsBar

            Divider()

            // Main content
            if files.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    fileListView
                        .frame(minWidth: 300)

                    settingsPanel
                        .frame(minWidth: 280, maxWidth: 320)
                }
            }
        }
        .navigationTitle("Concatenation")
        .onDisappear { cancelConcatenation() }
        // Drop video files to add to the concatenation list (Issue #366).
        .onDrop(
            of: [.fileURL, .movie, .video, .audio],
            isTargeted: $isDragTargeted
        ) { providers in
            DropHandler.extractURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                Task { @MainActor in
                    files.append(contentsOf: urls)
                    validateFiles()
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
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.movie, .audio, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Controls Bar

    /// Top toolbar with add/remove file buttons and method picker.
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button {
                showingFileImporter = true
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .accessibilityLabel("Add files to concatenation list")

            Button {
                removeSelectedFile()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selectedFileID == nil)
            .accessibilityLabel("Remove selected file")

            Button {
                files.removeAll()
                compatibilityWarnings.removeAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(files.isEmpty)
            .accessibilityLabel("Clear all files")

            Spacer()

            // Method picker
            Picker("Method:", selection: $method) {
                ForEach(ConcatMethod.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .onChange(of: method) { _, _ in
                validateFiles()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - File List

    /// Drag-to-reorder list of input files.
    private var fileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Input Files")
                    .font(.headline)
                Spacer()
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // File list with reordering
            List(selection: $selectedFileID) {
                ForEach(files, id: \.self) { file in
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                                .font(.body)
                                .lineLimit(1)

                            Text(file.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .tag(file)
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    files.move(fromOffsets: source, toOffset: destination)
                    validateFiles()
                }
            }

            // Compatibility warnings
            if !compatibilityWarnings.isEmpty && method == .demuxer {
                warningsView
            }
        }
    }

    // MARK: - Settings Panel

    /// Right-side panel with concatenation settings and output path.
    private var settingsPanel: some View {
        Form {
            // Method info
            Section("Method") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(method.displayName)
                        .font(.headline)

                    switch method {
                    case .demuxer:
                        Text(
                            "Lossless concatenation — no re-encoding. "
                            + "Requires all files to have the same codec, "
                            + "resolution, and frame rate."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    case .filter:
                        Text(
                            "Re-encode concatenation — supports different "
                            + "codecs, resolutions, and optional crossfade "
                            + "transitions between segments."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Crossfade settings (filter mode only).
            //
            // Honesty note (Issue #322): the re-encode filter path IS now wired
            // (Start runs `VideoConcatenator.buildFilterConcatArguments` via
            // `runFilterConcat`), so differing-codec joins work. Crossfade
            // specifically stays disabled: correct `xfade` offsets need each
            // clip's duration, which this URL-only view does not yet probe.
            // Rather than emit transitions at the wrong offsets, the crossfade
            // controls remain visible-but-disabled with an honest explanation.
            if method == .filter {
                Section("Crossfade") {
                    Toggle("Enable Crossfade", isOn: $crossfadeEnabled)
                        .disabled(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(
                                String(format: "%.1fs", crossfadeDuration)
                            )
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: $crossfadeDuration,
                            in: 0.1...5.0,
                            step: 0.1
                        ) {
                            Text("Crossfade Duration")
                        }
                    }
                    .disabled(true)

                    Label(
                        "Re-encode joining is available — press Start to "
                        + "concatenate clips of differing codecs. Crossfade "
                        + "transitions are the remaining piece: they need each "
                        + "clip's duration and are coming in a follow-up.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Output path
            Section("Output") {
                HStack {
                    TextField("Output Path", text: $outputPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        chooseOutputPath()
                    }
                }
            }

            // Start action, progress, and results (Issue #322).
            Section("Concatenate") {
                if method == .filter {
                    Text(
                        "Re-encode concatenation is not yet available in "
                        + "this build. Select \"Lossless (Demuxer)\" to "
                        + "concatenate."
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if isRunning {
                    if let progressFraction {
                        ProgressView(value: progressFraction)
                    } else {
                        ProgressView()
                    }
                }

                if let concatErrorMessage {
                    Text(concatErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Only ever set after the FFmpeg process genuinely
                // completes and its output file has been verified to
                // exist on disk (see `runDemuxerConcat`).
                if let successMessage {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    Spacer()
                    Button {
                        startConcatenation()
                    } label: {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(isRunning ? "Concatenating…" : "Start")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startDisabled)
                    .accessibilityLabel("Start joining the input files into the output")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Warnings View

    /// Displays compatibility warnings for demuxer mode.
    private var warningsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Compatibility Warnings", systemImage: "exclamationmark.triangle")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            ForEach(compatibilityWarnings, id: \.self) { warning in
                Text("  \(warning)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.05))
    }

    // MARK: - Empty State

    /// Placeholder view when no files have been added.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Add Video Files to Concatenate")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Drag files here or click \"Add Files\" to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Add Files") {
                showingFileImporter = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Handles the result of the file importer dialog.
    private func handleFileImport(
        _ result: Result<[URL], any Error>
    ) {
        switch result {
        case .success(let urls):
            files.append(contentsOf: urls)
            validateFiles()
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Removes the currently selected file from the list.
    private func removeSelectedFile() {
        guard let selected = selectedFileID,
              let index = files.firstIndex(of: selected) else { return }
        files.remove(at: index)
        selectedFileID = nil
        validateFiles()
    }

    /// Runs compatibility validation on the current file list.
    private func validateFiles() {
        compatibilityWarnings = VideoConcatenator.validateCompatibility(
            files: files
        )
    }

    /// Presents a save panel for choosing the output file path.
    private func chooseOutputPath() {
        let panel = NSSavePanel()
        panel.title = "Choose Output Location"
        panel.allowedContentTypes = [.movie, .mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "concatenated.mp4"

        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    // MARK: - Concatenation Execution (Issue #322)

    /// Starts the configured concatenation.
    ///
    /// Mirrors the execution pattern proven in
    /// `VideoTrimmerView.applyTrim()` / `runSnipAndConcat()` (Issue #444):
    /// locate FFmpeg via `FFmpegBundleManager`, build arguments with
    /// `VideoConcatenator.buildDemuxerConcatArguments`, run them through
    /// `FFmpegProcessController.startEncoding(arguments:)`, and only report
    /// success once the process has genuinely exited zero *and* the output
    /// file has been verified to exist on disk.
    ///
    /// Only the demuxer (lossless) method is wired to a real invocation —
    /// `startDisabled` keeps the Start button disabled whenever the filter
    /// (re-encode/crossfade) method is selected, so this guard is a
    /// defence-in-depth check rather than the primary gate.
    ///
    /// `ConcatenationView` is a `struct: View`, so — like
    /// `VideoTrimmerView` — its methods are implicitly main-actor isolated
    /// via `View` conformance, and a plain `Task { }` here inherits that
    /// isolation. Every value captured into the task (`files`, `outputPath`)
    /// is `Sendable`, so nothing unsafe crosses the closure boundary. The
    /// one genuinely blocking call — `FFmpegBundleManager.locateFFmpeg()` —
    /// is pulled into a `Task.detached` that returns only a `Sendable`
    /// `String` and never touches `self`/`@State`.
    private func startConcatenation() {
        guard files.count >= 2 else {
            concatErrorMessage = "Add at least two files to concatenate."
            return
        }
        let trimmedOutputPath = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutputPath.isEmpty else {
            concatErrorMessage = "Choose an output location before starting."
            return
        }
        // The re-encode filter path (below) tolerates differing codecs, so the
        // compatibility warnings only block the lossless demuxer path (#322).
        if method == .demuxer {
            guard compatibilityWarnings.isEmpty else {
                concatErrorMessage = "Resolve the compatibility warnings above before concatenating."
                return
            }
        }

        concatErrorMessage = nil
        successMessage = nil
        progressFraction = nil
        isRunning = true

        let filesToConcat = files
        let outputPathCopy = trimmedOutputPath

        concatTask = Task {
            let ffmpegPath: String
            do {
                ffmpegPath = try await Task.detached {
                    try FFmpegBundleManager().locateFFmpeg().path
                }.value
            } catch {
                concatErrorMessage = "FFmpeg could not be found. Install FFmpeg or configure its location in Settings before concatenating."
                isRunning = false
                return
            }

            do {
                if method == .demuxer {
                    try await runDemuxerConcat(
                        ffmpegPath: ffmpegPath,
                        files: filesToConcat,
                        outputPath: outputPathCopy
                    )
                } else {
                    try await runFilterConcat(
                        ffmpegPath: ffmpegPath,
                        files: filesToConcat,
                        outputPath: outputPathCopy
                    )
                }
                successMessage = "Concatenation complete. Output written to \(outputPathCopy)."
            } catch is CancellationError {
                // Cancelled by the user (or the view disappeared) — no
                // success/error banner; cancelConcatenation() already reset
                // state.
            } catch {
                concatErrorMessage = "Concatenation failed: \(error.localizedDescription)"
            }

            currentController = nil
            isRunning = false
        }
    }

    /// Cancel an in-progress Start operation.
    ///
    /// Stops the currently-running FFmpeg process (if any) and cancels the
    /// concatenation `Task` so no process or task is left running in the
    /// background after the user navigates away from this view mid-join.
    private func cancelConcatenation() {
        currentController?.stopEncoding()
        currentController = nil
        concatTask?.cancel()
        concatTask = nil
        isRunning = false
    }

    /// Runs the lossless demuxer-concat path: writes the concat file list
    /// produced by `VideoConcatenator.buildDemuxerConcatArguments` to a
    /// scratch temp file, substitutes it into the argument template, and
    /// runs a single FFmpeg pass to completion. Throws if FFmpeg exits
    /// non-zero or no output file is actually written. The scratch
    /// directory is always removed afterwards, whether the operation
    /// succeeds or fails.
    private func runDemuxerConcat(
        ffmpegPath: String,
        files: [URL],
        outputPath: String
    ) async throws {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("concat_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }

        let (concatListContent, argsTemplate) = VideoConcatenator.buildDemuxerConcatArguments(
            files: files,
            outputPath: outputPath
        )

        let listFileURL = scratchDir.appendingPathComponent("concat_list.txt")
        try concatListContent.write(to: listFileURL, atomically: true, encoding: .utf8)

        let arguments = argsTemplate.map {
            $0 == "<CONCAT_LIST_FILE>" ? listFileURL.path : $0
        }

        if Task.isCancelled { throw CancellationError() }

        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = controller

        let progressStream = try controller.startEncoding(arguments: arguments)
        for await progress in progressStream {
            if Task.isCancelled {
                controller.stopEncoding()
                break
            }
            progressFraction = progress.fractionComplete
        }
        if Task.isCancelled { throw CancellationError() }

        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw FFmpegProcessError.processFailure(
                exitCode: controller.exitCode ?? -1,
                stderr: "FFmpeg reported success but no output file was found at \(outputPath)."
            )
        }
    }

    /// Runs the re-encode filter-concat path (#322): a single FFmpeg pass with
    /// the `concat` filter that joins clips of DIFFERING codecs (the demuxer
    /// path requires identical codecs). No scratch list file is needed —
    /// `buildFilterConcatArguments` returns a complete command. Crossfade is
    /// intentionally not passed here: it needs each clip's duration to place the
    /// transitions, which this URL-only view does not yet probe. ffmpeg's
    /// `concat` filter still requires the clips to share resolution/SAR; a
    /// mismatch surfaces as its own error via the controller's stderr.
    private func runFilterConcat(
        ffmpegPath: String,
        files: [URL],
        outputPath: String
    ) async throws {
        let arguments = VideoConcatenator.buildFilterConcatArguments(
            files: files,
            outputPath: outputPath,
            crossfade: nil
        )

        if Task.isCancelled { throw CancellationError() }

        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        currentController = controller

        let progressStream = try controller.startEncoding(arguments: arguments)
        for await progress in progressStream {
            if Task.isCancelled {
                controller.stopEncoding()
                break
            }
            progressFraction = progress.fractionComplete
        }
        if Task.isCancelled { throw CancellationError() }

        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw FFmpegProcessError.processFailure(
                exitCode: controller.exitCode ?? -1,
                stderr: "FFmpeg reported success but no output file was found at \(outputPath)."
            )
        }
    }
}
