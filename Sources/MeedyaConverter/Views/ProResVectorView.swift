// ============================================================================
// MeedyaConverter — ProResVectorView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for ProRes 4444 → animated SVG conversion. Binds the
// fields of `ProResToVectorConfig`, embeds the shared
// `RasterToVectorConfigEditor` for per-frame tracing settings, resolves
// potrace/vtracer/ffmpeg, and runs `ProResVectorExecutor.convert` for real.
// This view is hidden in App Store builds (`NavigationItem.unavailable`,
// `#if APP_STORE`); everywhere else the Convert button is disabled with an
// actionable reason whenever a required tool or source can't be resolved.
//
// Layout:
//   1. Source       — the selected file (Source tab), ProRes variant, frame
//                      rate, time range, frame stride
//   2. Alpha        — How the ProRes alpha channel is represented in the SVG
//   3. Tracing      — Embedded RasterToVectorConfigEditor (no Animation section
//                     because the outer config has its own animation method)
//   4. Animation    — Outer-SVG animation method (SMIL only — the only method
//                     `ProResVectorExecutor` implements)
//   5. Warning      — Heads-up callout when settings would produce a large SVG
//   6. Run          — Convert/Cancel, staged progress, result
//
// GitHub Issues: #377 engine (ProResToVectorConverter) / #381 / #404 UI /
// #473 executor.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ProResVectorView

/// User-facing settings for ProRes 4444 → animated SVG conversion.
struct ProResVectorView: View {

    @Environment(AppViewModel.self) private var viewModel

    // -----------------------------------------------------------------
    // MARK: - Persisted state
    // -----------------------------------------------------------------
    //
    // One AppStorage key per ProResToVectorConfig field (top-level
    // + the nested tracing fields). Per-field keys (rather than a
    // JSON-encoded blob) mean a future addition to the engine config
    // does not invalidate the user's existing preferences. All keys
    // are namespaced under `proresVector.` so they are easy to grep
    // for, clear in tests, and distinguish from `vectorConversion.`
    // keys (which back the stand-alone Vector Conversion tool).
    //
    // The tracing-config fields live alongside the ProRes fields in
    // the same `proresVector.` namespace because the user's
    // tracing-related preferences for ProRes work may legitimately
    // differ from their stand-alone Vector Conversion preferences
    // (different source material, different goals).

    // ProRes-specific fields
    @AppStorage("proresVector.sourceVariant") private var rawSourceVariant: String =
        ProResVariant.proRes4444.rawValue
    @AppStorage("proresVector.frameRate") private var rawFrameRate: String =
        ProResFrameRate.fps24.rawValue
    @AppStorage("proresVector.startTimeSeconds") private var startTimeSeconds: Double = 0.0
    /// Sentinel value -1 means "unbounded — until end of clip". A real
    /// end-time of -1 is impossible in this domain, so the sentinel is
    /// unambiguous and avoids storing an optional in AppStorage (which
    /// does not natively support `Optional<Double>`).
    @AppStorage("proresVector.endTimeSeconds") private var endTimeSeconds: Double = -1.0
    @AppStorage("proresVector.frameStride") private var frameStride: Int = 1
    @AppStorage("proresVector.alphaHandling") private var rawAlphaHandling: String =
        ProResAlphaHandling.preservePerFrame.rawValue
    @AppStorage("proresVector.animation") private var rawAnimation: String =
        AnimationMethod.smil.rawValue
    // Kept for JSON/AppStorage compatibility only — the Assembly section that
    // edited these was removed (see `runSection`'s neighbour below): neither
    // toggle is implemented by `ProResVectorExecutor`.
    @AppStorage("proresVector.shapePersistence") private var shapePersistence: Bool = true
    @AppStorage("proresVector.keyframeExtraction") private var keyframeExtraction: Bool = true

    // Nested tracing-config fields (mirrors RasterToVectorConfig's fields)
    @AppStorage("proresVector.tracing.preset") private var rawTracingPreset: String =
        EditabilityPreset.illustration.rawValue
    @AppStorage("proresVector.tracing.tracingMode") private var rawTracingMode: String =
        TracingMode.colorQuantization.rawValue
    @AppStorage("proresVector.tracing.colorCount") private var tracingColorCount: Int = 32
    @AppStorage("proresVector.tracing.alpha") private var rawTracingAlpha: String =
        AlphaStrategy.clipPathWithOpacity.rawValue
    @AppStorage("proresVector.tracing.preserveMetadata") private var tracingPreserveMetadata: Bool = true
    @AppStorage("proresVector.tracing.ocrTextRegions") private var tracingOcrTextRegions: Bool = false
    @AppStorage("proresVector.tracing.curveSimplification") private var tracingCurveSimplification: Double = 2.0

    /// Custom tool overrides — `SettingsView.PathSettingsTab`'s "Vector
    /// Tracing Tools" section. Empty means "auto-detect".
    @AppStorage("customPotracePath") private var customPotracePath = ""
    @AppStorage("customVTracerPath") private var customVTracerPath = ""

    // -----------------------------------------------------------------
    // MARK: - Tool resolution + run state
    // -----------------------------------------------------------------

    @State private var toolPaths: VectorToolPaths?
    @State private var isConverting = false
    @State private var convertTask: Task<Void, Never>?
    @State private var progress: Double?
    @State private var stageLabel: String = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    /// The tool `ProResVectorExecutor` will actually invoke: a monochrome
    /// alpha matte is always traced with potrace, regardless of the tracing
    /// mode picker (a matte is monochrome by definition — see
    /// `ProResVectorExecutor.convert`).
    private var requiredTool: String {
        alphaHandling.wrappedValue == .alphaMatteOnly
            ? "potrace"
            : RasterVectorConverter.preferredTracingTool(for: tracingConfig.wrappedValue.tracingMode)
    }

    private var requiredToolPath: String? {
        toolPaths?.path(for: requiredTool)
    }

    private var toolStatusCaption: String {
        guard let toolPaths else {
            return "FFmpeg was not found — set its path in Settings › Paths."
        }
        guard let path = toolPaths.path(for: requiredTool) else {
            return "\(requiredTool) was not found. The Direct build bundles it in "
                + "Contents/Helpers; a dev/Homebrew build needs it on PATH or a path "
                + "in Settings › Paths."
        }
        return "Tracing with \(requiredTool) at \(path)"
    }

    /// The source file's video dimensions, or nil when no file is selected
    /// or it carries no video stream — the SVG `viewBox` needs real pixels.
    private var sourceDimensions: (width: Int, height: Int)? {
        guard let stream = viewModel.selectedFile?.primaryVideoStream,
              let width = stream.width, let height = stream.height else { return nil }
        return (width, height)
    }

    // -----------------------------------------------------------------
    // MARK: - Computed bindings
    // -----------------------------------------------------------------

    private var sourceVariant: Binding<ProResVariant> {
        Binding(
            get: { ProResVariant(rawValue: rawSourceVariant) ?? .proRes4444 },
            set: { rawSourceVariant = $0.rawValue }
        )
    }

    private var frameRate: Binding<ProResFrameRate> {
        Binding(
            get: { ProResFrameRate(rawValue: rawFrameRate) ?? .fps24 },
            set: { rawFrameRate = $0.rawValue }
        )
    }

    private var alphaHandling: Binding<ProResAlphaHandling> {
        Binding(
            get: { ProResAlphaHandling(rawValue: rawAlphaHandling) ?? .preservePerFrame },
            set: { rawAlphaHandling = $0.rawValue }
        )
    }

    private var animation: Binding<AnimationMethod> {
        Binding(
            get: { AnimationMethod(rawValue: rawAnimation) ?? .smil },
            set: { rawAnimation = $0.rawValue }
        )
    }

    /// Assembles the per-frame tracing AppStorage values into a
    /// `Binding<RasterToVectorConfig>` for the shared editor. The input
    /// format is hard-coded to PNG because the ProRes pipeline always
    /// extracts intermediate PNG frames.
    private var tracingConfig: Binding<RasterToVectorConfig> {
        Binding(
            get: {
                RasterToVectorConfig(
                    inputFormat: .png,
                    outputFormat: .svg2,
                    tracingMode: TracingMode(rawValue: rawTracingMode) ?? .colorQuantization,
                    preset: EditabilityPreset(rawValue: rawTracingPreset) ?? .illustration,
                    colorCount: tracingColorCount,
                    alpha: AlphaStrategy(rawValue: rawTracingAlpha) ?? .clipPathWithOpacity,
                    animation: .smil, // tracing's animation is unused in ProRes mode
                    preserveMetadata: tracingPreserveMetadata,
                    ocrTextRegions: tracingOcrTextRegions,
                    curveSimplification: tracingCurveSimplification
                )
            },
            set: { newValue in
                rawTracingMode = newValue.tracingMode.rawValue
                rawTracingPreset = newValue.preset.rawValue
                tracingColorCount = newValue.colorCount
                rawTracingAlpha = newValue.alpha.rawValue
                tracingPreserveMetadata = newValue.preserveMetadata
                tracingOcrTextRegions = newValue.ocrTextRegions
                tracingCurveSimplification = newValue.curveSimplification
            }
        )
    }

    /// Assembles the full `ProResToVectorConfig` used both for the
    /// output-size warning check and for the real conversion. We do not
    /// persist this as a single blob — it is derived from the AppStorage
    /// values.
    private var assembledConfig: ProResToVectorConfig {
        ProResToVectorConfig(
            sourceVariant: sourceVariant.wrappedValue,
            frameRate: frameRate.wrappedValue,
            startTimeSeconds: startTimeSeconds > 0 ? startTimeSeconds : nil,
            endTimeSeconds: endTimeSeconds >= 0 ? endTimeSeconds : nil,
            frameStride: frameStride,
            alphaHandling: alphaHandling.wrappedValue,
            tracing: tracingConfig.wrappedValue,
            animation: animation.wrappedValue,
            shapePersistence: shapePersistence,
            keyframeExtraction: keyframeExtraction
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Body
    // -----------------------------------------------------------------

    var body: some View {
        Form {
            Section("Source") {
                if let file = viewModel.selectedFile {
                    LabeledContent("File", value: file.fileName)
                    if sourceDimensions == nil {
                        Text("Source has no video dimensions.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Select a source file in the Source tab to convert.")
                        .foregroundStyle(.secondary)
                }

                Picker("ProRes variant", selection: sourceVariant) {
                    ForEach(ProResVariant.allCases, id: \.self) { variant in
                        Text(variant.displayName).tag(variant)
                    }
                }
                .accessibilityLabel("ProRes variant of the source file")

                Picker("Frame rate", selection: frameRate) {
                    ForEach(ProResFrameRate.allCases, id: \.self) { rate in
                        Text("\(rate.rawValue) fps").tag(rate)
                    }
                }
                .accessibilityLabel("Frame rate at which to sample the source")

                Stepper(
                    value: $startTimeSeconds,
                    in: 0...3600,
                    step: 0.5
                ) {
                    HStack {
                        Text("Start time")
                        Spacer()
                        Text(String(format: "%.1f s", startTimeSeconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Start timecode in seconds; 0 means clip start")

                Stepper(
                    value: $endTimeSeconds,
                    in: -1...3600,
                    step: 0.5
                ) {
                    HStack {
                        Text("End time")
                        Spacer()
                        Text(endTimeSeconds < 0
                             ? "until end of clip"
                             : String(format: "%.1f s", endTimeSeconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(
                    "End timecode in seconds; -1 means run until end of clip"
                )

                Stepper(
                    value: $frameStride,
                    in: 1...10,
                    step: 1
                ) {
                    HStack {
                        Text("Frame stride")
                        Spacer()
                        Text("every \(frameStride) frame\(frameStride == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(
                    "Process every Nth frame; 1 means every frame"
                )
            }

            Section("Alpha") {
                Picker("Handling", selection: alphaHandling) {
                    ForEach(ProResAlphaHandling.allCases, id: \.self) { strategy in
                        Text(strategy.displayLabel).tag(strategy)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("How to handle the ProRes alpha channel")
            }

            // Embedded per-frame tracing editor. We pass `.png` as the
            // input format because the ProRes pipeline always extracts
            // PNG intermediate frames. `showAnimationSection: false`
            // because the outer ProRes config has its own animation
            // method (see the Animation section below).
            RasterToVectorConfigEditor(
                config: tracingConfig,
                inputFormat: .png,
                showAnimationSection: false
            )

            Section("Animation") {
                // Only SMIL is implemented by `ProResVectorExecutor`
                // (`assembleAnimatedSVG` throws `.invalidConfiguration` for
                // every other method) — the picker offers no other choice so
                // the UI can never select a method the executor will reject.
                Picker("Method", selection: animation) {
                    ForEach([AnimationMethod.smil], id: \.self) { method in
                        Text(method.displayLabel).tag(method)
                    }
                }
                .accessibilityLabel("Animation method for the assembled SVG")

                Text("CSS/hybrid/frame-sequence assembly are not implemented in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The "Assembly" section (shape persistence / keyframe
            // extraction toggles) was removed: `ProResVectorExecutor` traces
            // every frame independently and does not track shape identity or
            // skip unchanged frames — those toggles controlled nothing.
            // The AppStorage keys are kept (still threaded into
            // `ProResToVectorConfig` for JSON/AppStorage compatibility) but
            // no longer editable here.

            // Output-size warning. Uses the real selected file's duration
            // when one is chosen; otherwise falls back to a synthetic
            // reference (twice the engine's "comfortable" duration) so the
            // warning still means something before a file is picked.
            if outputSizeWarningFires {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Output size may be large")
                                .font(.subheadline.bold())
                            Text(
                                "These settings can produce very large SVG "
                                + "files. Consider increasing the frame "
                                + "stride, narrowing the time range, or "
                                + "switching to a non-photorealistic "
                                + "tracing mode."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            runSection

            if let statusMessage {
                statusRow(statusMessage, color: .green, icon: "checkmark.circle")
            }
            if let errorMessage {
                statusRow(errorMessage, color: .red, icon: "exclamationmark.triangle")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("ProRes to Vector")
        .task {
            // Migrate a persisted non-SMIL selection from before this build
            // restricted the picker — the executor implements SMIL only.
            if rawAnimation != AnimationMethod.smil.rawValue {
                rawAnimation = AnimationMethod.smil.rawValue
            }
            await resolveTools()
        }
        .onChange(of: customPotracePath) { _, _ in Task { await resolveTools() } }
        .onChange(of: customVTracerPath) { _, _ in Task { await resolveTools() } }
        .onChange(of: rawTracingMode) { _, _ in Task { await resolveTools() } }
        .onChange(of: rawAlphaHandling) { _, _ in Task { await resolveTools() } }
        .onDisappear { cancel() }
    }

    // -----------------------------------------------------------------
    // MARK: - Output-size warning
    // -----------------------------------------------------------------

    /// Whether the warning callout should be visible. Uses the real source
    /// file's duration when one is selected; otherwise falls back to
    /// `ProResToVectorConverter.recommendedMaxDurationSeconds * 2` — twice
    /// the engine's "comfortable" duration — so the warning fires for any
    /// settings that would produce more than the engine's recommended cap
    /// of output even before a file is chosen.
    private var outputSizeWarningFires: Bool {
        let referenceDuration = viewModel.selectedFile?.duration
            ?? (ProResToVectorConverter.recommendedMaxDurationSeconds * 2)
        return ProResToVectorConverter.shouldWarnAboutOutputSize(
            config: assembledConfig,
            sourceDurationSeconds: referenceDuration
        )
    }

    // MARK: - Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            if isConverting {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(stageLabel).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                    if let progress {
                        ProgressView(value: progress)
                    }
                }
            } else {
                Button {
                    startConversion()
                } label: {
                    Label("Convert\u{2026}", systemImage: "film.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedFile == nil || sourceDimensions == nil || requiredToolPath == nil)
            }

            Text(toolStatusCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tool resolution

    private func resolveTools() async {
        let bundleManager = viewModel.engine.bundleManager
        let potraceOverride = customPotracePath.isEmpty ? nil : customPotracePath
        let vtracerOverride = customVTracerPath.isEmpty ? nil : customVTracerPath
        let resolved: VectorToolPaths? = await Task.detached {
            guard let ffmpeg = try? bundleManager.locateFFmpeg().path else { return nil }
            return VectorToolPaths(
                ffmpeg: ffmpeg,
                potrace: try? BundledToolLocator(toolName: "potrace", userOverridePath: potraceOverride).locate(),
                vtracer: try? BundledToolLocator(toolName: "vtracer", userOverridePath: vtracerOverride).locate()
            )
        }.value
        toolPaths = resolved
    }

    // MARK: - Actions

    private func startConversion() {
        guard let file = viewModel.selectedFile, let dims = sourceDimensions, let tools = toolPaths else { return }

        let panel = NSSavePanel()
        panel.title = "Save Animated SVG"
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(file.fileURL.deletingPathExtension().lastPathComponent).svg"
        panel.message = "Choose where to save the animated SVG."
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        statusMessage = nil
        errorMessage = nil
        isConverting = true
        progress = 0
        stageLabel = "Extracting frames\u{2026}"
        let runConfig = assembledConfig
        viewModel.appendLog(.info, "ProRes vector conversion started for \(file.fileName)", category: .encoding)
        convertTask = Task {
            await runConversion(
                inputURL: file.fileURL, outputURL: outputURL,
                width: dims.width, height: dims.height, config: runConfig, tools: tools
            )
        }
    }

    private func runConversion(
        inputURL: URL, outputURL: URL, width: Int, height: Int,
        config: ProResToVectorConfig, tools: VectorToolPaths
    ) async {
        do {
            let frameCount = try await ProResVectorExecutor.convert(
                inputURL: inputURL, outputURL: outputURL,
                sourceWidth: width, sourceHeight: height,
                config: config, tools: tools, runner: ExternalToolRunner(),
                progress: { progressEvent in
                    Task { @MainActor in
                        self.progress = progressEvent.fraction
                        self.stageLabel = Self.label(for: progressEvent.stage)
                    }
                }
            )
            statusMessage = "Animated SVG (\(frameCount) frames) saved to \(outputURL.lastPathComponent)."
            viewModel.appendLog(.info, "ProRes vector conversion complete: \(outputURL.path)", category: .encoding)
        } catch is CancellationError {
            viewModel.appendLog(.info, "ProRes vector conversion cancelled for \(inputURL.lastPathComponent)", category: .encoding)
        } catch {
            errorMessage = "ProRes vector conversion failed: \(error.localizedDescription)"
            viewModel.appendLog(.error, "ProRes vector conversion failed for \(inputURL.lastPathComponent): \(error.localizedDescription)", category: .encoding)
        }
        isConverting = false
        convertTask = nil
        progress = nil
    }

    private static func label(for stage: ProResVectorProgress.Stage) -> String {
        switch stage {
        case .extractingFrames: return "Extracting frames\u{2026}"
        case .tracing(let frame, let total): return "Tracing frame \(frame) of \(total)\u{2026}"
        case .assembling: return "Assembling animated SVG\u{2026}"
        }
    }

    private func cancel() {
        convertTask?.cancel()
        convertTask = nil
        isConverting = false
        progress = nil
    }

    private func statusRow(_ message: String, color: Color, icon: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(message).font(.callout).textSelection(.enabled)
            }
        }
    }
}

// MARK: - Display-name helpers
//
// Engine enums that don't already have a `displayName` or `displayLabel`
// helper from RasterToVectorConfigEditor.swift get their UI labels here.

private extension ProResAlphaHandling {
    var displayLabel: String {
        switch self {
        case .preservePerFrame: return "Preserve per-frame (clip-paths)"
        case .alphaMatteOnly:   return "Alpha matte only (monochrome)"
        case .flatten:          return "Flatten against background"
        }
    }
}
