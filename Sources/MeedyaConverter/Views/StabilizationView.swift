// ============================================================================
// MeedyaConverter — StabilizationView (Issue #323)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The UI + execution wiring for two-pass video stabilization. `VideoStabilizer`
// (ConverterEngine) had complete, tested-shaped `buildAnalysisArguments` /
// `buildStabilizeArguments` builders and light/medium/heavy presets, but ZERO
// callers and no screen — a dead engine. This view runs both passes through
// `FFmpegProcessController` (the same controller + AsyncStream-drain pattern
// SceneDetectorView uses), so the feature actually produces a stabilized file.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - StabilizationView

/// Two-pass video stabilization (vid.stab): an analysis pass detects camera
/// motion into a `.trf` transforms file, then a transform pass applies the
/// smoothed motion to produce a stabilized output.
///
/// Requires an FFmpeg built with `libvidstab`; if the running binary lacks it,
/// the analysis pass fails with "No such filter: 'vidstabdetect'", which this
/// view surfaces as an actionable message rather than a raw error.
///
/// Phase 10 — Video Stabilization (Issue #323)
struct StabilizationView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Preset

    /// The built-in strength presets, plus a custom mode that unlocks the
    /// individual parameters.
    private enum Preset: String, CaseIterable, Identifiable {
        case light, medium, heavy, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light:  return "Light"
            case .medium: return "Medium"
            case .heavy:  return "Heavy"
            case .custom: return "Custom"
            }
        }
        /// The engine config for a built-in preset (nil for `.custom`).
        var config: StabilizationConfig? {
            switch self {
            case .light:  return VideoStabilizer.light
            case .medium: return VideoStabilizer.medium
            case .heavy:  return VideoStabilizer.heavy
            case .custom: return nil
            }
        }
    }

    // MARK: - State

    @State private var preset: Preset = .medium

    // Individual parameters (seeded from the selected preset). Editing any of
    // them switches `preset` to `.custom`.
    @State private var shakiness: Double = 5
    @State private var accuracy: Double = 15
    @State private var stepSize: Double = 6
    @State private var zoom: Double = 0
    @State private var optzoom: Double = 1
    @State private var smoothing: Double = 10

    @State private var isStabilizing = false
    @State private var stabilizeTask: Task<Void, Never>?
    @State private var currentController: FFmpegProcessController?
    @State private var progress: Double?
    @State private var passLabel: String = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    /// The current parameters as an engine config.
    private var config: StabilizationConfig {
        StabilizationConfig(
            shakiness: Int(shakiness),
            accuracy: Int(accuracy),
            stepSize: Int(stepSize),
            zoom: zoom,
            optzoom: Int(optzoom),
            smoothing: Int(smoothing)
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                sourceSection
                presetSection
                advancedSection
                runSection
                if let statusMessage { statusRow(statusMessage, color: .green, icon: "checkmark.circle") }
                if let errorMessage { statusRow(errorMessage, color: .red, icon: "exclamationmark.triangle") }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 480)
        .onChange(of: preset) { _, newValue in
            if let c = newValue.config { seed(from: c) }
        }
        .onDisappear { cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Video Stabilization", systemImage: "hand.raised.slash")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            if let file = viewModel.selectedFile {
                LabeledContent("File", value: file.fileName)
            } else {
                Text("Select a source file in the Source tab to stabilize.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preset

    @ViewBuilder
    private var presetSection: some View {
        Section("Strength") {
            Picker("Preset", selection: $preset) {
                ForEach(Preset.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.segmented)

            Text(presetHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetHint: String {
        switch preset {
        case .light:  return "Tripod footage with minor drift — removes micro-jitter, keeps most camera motion."
        case .medium: return "Handheld footage with moderate shake — balanced, with adaptive zoom to hide borders."
        case .heavy:  return "Action-cam / extreme shake — aggressive smoothing and adaptive zoom."
        case .custom: return "Manual parameters."
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedSection: some View {
        Section("Parameters") {
            slider("Shakiness", $shakiness, 1...10, step: 1, help: "How shaky the source is (1–10).")
            slider("Accuracy", $accuracy, 1...15, step: 1, help: "Motion-detection accuracy (1–15).")
            slider("Step size", $stepSize, 1...32, step: 1, help: "Detection step size in pixels.")
            slider("Zoom %", $zoom, -20...20, step: 1, help: "Constant zoom; positive crops in to hide borders.")
            slider("Adaptive zoom", $optzoom, 0...2, step: 1, help: "0 none · 1 optimal · 2 adaptive.")
            slider("Smoothing", $smoothing, 1...60, step: 1, help: "Frames averaged for the camera path.")
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    // A manual drag moves us off a named preset. (Programmatic
                    // `seed(from:)` writes the @State directly, bypassing this
                    // setter, so switching presets does not false-trigger here.)
                    if preset != .custom { preset = .custom }
                }
            ), in: range, step: step)
            Text(help).font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(isStabilizing)
    }

    // MARK: - Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            if isStabilizing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(passLabel).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                    if let progress {
                        ProgressView(value: progress)
                    }
                }
            } else {
                Button {
                    startStabilization()
                } label: {
                    Label("Stabilize\u{2026}", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedFile == nil)
            }

            Text("Two passes (analyze motion, then apply). Requires an FFmpeg built with libvidstab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ message: String, color: Color, icon: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(message).font(.callout).textSelection(.enabled)
            }
        }
    }

    // MARK: - Actions

    private func seed(from c: StabilizationConfig) {
        shakiness = Double(c.shakiness)
        accuracy = Double(c.accuracy)
        stepSize = Double(c.stepSize)
        zoom = c.zoom
        optzoom = Double(c.optzoom)
        smoothing = Double(c.smoothing)
    }

    /// Prompt for a destination, then run both passes against the selected file.
    private func startStabilization() {
        guard let file = viewModel.selectedFile else { return }

        let panel = NSSavePanel()
        panel.title = "Save Stabilized Video"
        panel.nameFieldStringValue =
            "\(file.fileURL.deletingPathExtension().lastPathComponent)_stabilized.\(file.fileURL.pathExtension.isEmpty ? "mp4" : file.fileURL.pathExtension)"
        panel.message = "Choose where to save the stabilized video."
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        errorMessage = nil
        statusMessage = nil
        isStabilizing = true
        progress = nil
        stabilizeTask = Task { await runStabilization(file: file, outputURL: outputURL) }
    }

    private func runStabilization(file: MediaFile, outputURL: URL) async {
        let inputPath = file.fileURL.path
        // Transforms file in the system temp dir (removed in every exit path).
        let trfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meedya-vidstab-\(UUID().uuidString).trf")

        viewModel.appendLog(.info, "Stabilization started for \(file.fileName)", category: .encoding)

        // Resolve FFmpeg once, up front.
        let ffmpegPath: String
        do {
            ffmpegPath = try await Task.detached { try FFmpegBundleManager().locateFFmpeg().path }.value
        } catch {
            errorMessage = "FFmpeg could not be found: \(error.localizedDescription) Install FFmpeg or set its path in Settings."
            viewModel.appendLog(.error, "Stabilization could not start — FFmpeg lookup failed: \(error.localizedDescription)", category: .encoding)
            finish()
            return
        }

        do {
            // Pass 1 — analysis (0–50% of the bar).
            passLabel = "Analyzing motion\u{2026}"
            let analysisArgs = VideoStabilizer.buildAnalysisArguments(
                inputPath: inputPath, transformsPath: trfURL.path, config: config)
            try await runPass(ffmpegPath: ffmpegPath, arguments: analysisArgs,
                              sourceDuration: file.duration, base: 0.0, span: 0.5)

            // Pass 2 — transform (50–100%).
            passLabel = "Stabilizing\u{2026}"
            let stabilizeArgs = VideoStabilizer.buildStabilizeArguments(
                inputPath: inputPath, outputPath: outputURL.path,
                transformsPath: trfURL.path, config: config)
            try await runPass(ffmpegPath: ffmpegPath, arguments: stabilizeArgs,
                              sourceDuration: file.duration, base: 0.5, span: 0.5)

            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw FFmpegProcessError.processFailure(
                    exitCode: -1,
                    stderr: "FFmpeg reported success but wrote no output to \(outputURL.lastPathComponent).")
            }
            statusMessage = "Stabilized video saved to \(outputURL.lastPathComponent)."
            viewModel.appendLog(.info, "Stabilization complete: \(outputURL.path)", category: .encoding)
        } catch is CancellationError {
            viewModel.appendLog(.info, "Stabilization cancelled for \(file.fileName)", category: .encoding)
        } catch let FFmpegProcessError.processFailure(_, stderr) where missesVidstab(stderr) {
            errorMessage = "This FFmpeg build does not include the libvidstab filter, so stabilization can't run. Install an FFmpeg built with --enable-libvidstab (e.g. the Homebrew ffmpeg), or set its path in Settings."
            viewModel.appendLog(.error, "Stabilization failed: FFmpeg lacks libvidstab", category: .encoding)
        } catch {
            errorMessage = "Stabilization failed: \(error.localizedDescription)"
            viewModel.appendLog(.error, "Stabilization failed for \(file.fileName): \(error.localizedDescription)", category: .encoding)
        }

        try? FileManager.default.removeItem(at: trfURL)
        finish()
    }

    /// Run one FFmpeg pass to completion, mapping its progress fraction into the
    /// `[base, base+span)` slice of the overall two-pass bar.
    private func runPass(ffmpegPath: String, arguments: [String],
                         sourceDuration: TimeInterval?, base: Double, span: Double) async throws {
        let controller = FFmpegProcessController(binaryPath: ffmpegPath)
        controller.sourceDuration = sourceDuration
        currentController = controller

        let stream = try controller.startEncoding(arguments: arguments)
        for await info in stream {
            if Task.isCancelled { controller.stopEncoding(); break }
            if let fraction = info.fractionComplete { progress = base + fraction * span }
        }
        currentController = nil
        if Task.isCancelled { throw CancellationError() }
        if let code = controller.exitCode, code != 0 {
            throw FFmpegProcessError.processFailure(exitCode: code, stderr: controller.errorOutput)
        }
    }

    /// Whether stderr indicates the vidstab filters are unavailable in this build.
    private func missesVidstab(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("vidstab") && (s.contains("no such filter") || s.contains("not found") || s.contains("unknown filter"))
    }

    private func finish() {
        currentController = nil
        stabilizeTask = nil
        progress = nil
        passLabel = ""
        isStabilizing = false
    }

    private func cancel() {
        stabilizeTask?.cancel()
        currentController?.stopEncoding()
        finish()
    }
}
