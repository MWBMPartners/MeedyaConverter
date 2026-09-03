// ============================================================================
// MeedyaConverter — VectorConversionView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for raster→vector (SVG) conversion. Picks a source image,
// persists tracing preferences across launches via `@AppStorage`, resolves
// potrace/vtracer/ffmpeg (bundled in Direct builds; PATH/Homebrew/Settings
// override otherwise), and runs `RasterVectorExecutor.convert` for real —
// this view is hidden in App Store builds (`NavigationItem.unavailable`,
// `#if APP_STORE`) because the sandbox cannot spawn a subprocess and potrace
// is GPL; everywhere else the Convert button is disabled with an actionable
// reason whenever a required tool can't be resolved, never a dead button.
//
// GitHub Issues: #376 engine / #381 / #402 UI / #473 executor.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - VectorConversionView

/// User-facing settings for raster→vector (SVG) conversion.
struct VectorConversionView: View {

    @Environment(AppViewModel.self) private var viewModel

    // -----------------------------------------------------------------
    // MARK: - Persisted state
    // -----------------------------------------------------------------
    //
    // One AppStorage key per RasterToVectorConfig field (aside from
    // `inputFormat`, which is derived from the chosen source image, not
    // persisted). Per-field keys (rather than a JSON-encoded blob) mean a
    // future addition to the engine config does not invalidate the user's
    // existing preferences. The keys are namespaced under `vectorConversion.`
    // so they are easy to grep for and to clear in tests.

    @AppStorage("vectorConversion.preset") private var rawPreset: String =
        EditabilityPreset.illustration.rawValue
    @AppStorage("vectorConversion.tracingMode") private var rawTracingMode: String =
        TracingMode.colorQuantization.rawValue
    @AppStorage("vectorConversion.colorCount") private var colorCount: Int = 32
    @AppStorage("vectorConversion.alpha") private var rawAlpha: String =
        AlphaStrategy.clipPathWithOpacity.rawValue
    @AppStorage("vectorConversion.animation") private var rawAnimation: String =
        AnimationMethod.smil.rawValue
    @AppStorage("vectorConversion.preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("vectorConversion.ocrTextRegions") private var ocrTextRegions: Bool = false
    @AppStorage("vectorConversion.curveSimplification") private var curveSimplification: Double = 2.0

    /// Custom tool overrides — `SettingsView.PathSettingsTab`'s "Vector
    /// Tracing Tools" section. Empty means "auto-detect".
    @AppStorage("customPotracePath") private var customPotracePath = ""
    @AppStorage("customVTracerPath") private var customVTracerPath = ""

    // -----------------------------------------------------------------
    // MARK: - Source
    // -----------------------------------------------------------------

    @State private var selectedImageURL: URL?

    /// The raster format the executor will actually be told to expect —
    /// derived from the chosen file's extension, never persisted (a
    /// different file next launch may be a different format entirely).
    private var detectedFormat: RasterFormat? {
        selectedImageURL.flatMap { RasterFormat.from(fileExtension: $0.pathExtension) }
    }

    // -----------------------------------------------------------------
    // MARK: - Tool resolution + run state
    // -----------------------------------------------------------------

    @State private var toolPaths: VectorToolPaths?
    @State private var isConverting = false
    @State private var convertTask: Task<Void, Never>?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var requiredTool: String {
        RasterVectorConverter.preferredTracingTool(for: config.wrappedValue.tracingMode)
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

    // -----------------------------------------------------------------
    // MARK: - Computed bindings
    // -----------------------------------------------------------------

    /// Assembles the AppStorage values into a single
    /// `Binding<RasterToVectorConfig>` for the shared editor. The
    /// editor mutates fields on the value type; our setter splits
    /// the new value back across the AppStorage keys.
    private var config: Binding<RasterToVectorConfig> {
        Binding(
            get: {
                RasterToVectorConfig(
                    inputFormat: detectedFormat ?? .png,
                    outputFormat: .svg2,
                    tracingMode: TracingMode(rawValue: rawTracingMode) ?? .colorQuantization,
                    preset: EditabilityPreset(rawValue: rawPreset) ?? .illustration,
                    colorCount: colorCount,
                    alpha: AlphaStrategy(rawValue: rawAlpha) ?? .clipPathWithOpacity,
                    animation: AnimationMethod(rawValue: rawAnimation) ?? .smil,
                    preserveMetadata: preserveMetadata,
                    ocrTextRegions: ocrTextRegions,
                    curveSimplification: curveSimplification
                )
            },
            set: { newValue in
                // The editor only mutates the user-facing fields; we
                // do not need to round-trip `inputFormat` or
                // `outputFormat` here (`inputFormat` is derived from
                // the Source picker below, and `outputFormat` is fixed).
                rawTracingMode = newValue.tracingMode.rawValue
                rawPreset = newValue.preset.rawValue
                colorCount = newValue.colorCount
                rawAlpha = newValue.alpha.rawValue
                rawAnimation = newValue.animation.rawValue
                preserveMetadata = newValue.preserveMetadata
                ocrTextRegions = newValue.ocrTextRegions
                curveSimplification = newValue.curveSimplification
            }
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Body
    // -----------------------------------------------------------------

    var body: some View {
        Form {
            sourceSection

            // All other sections come from the shared editor. Raster
            // inputs are traced first-frame-only — animation is not
            // implemented for a still raster source (`RasterVectorExecutor`
            // never loops frames), so the Animation section is hidden here
            // regardless of the chosen file.
            RasterToVectorConfigEditor(
                config: config,
                inputFormat: detectedFormat ?? .png,
                showAnimationSection: false
            )

            runSection

            if let statusMessage {
                statusRow(statusMessage, color: .green, icon: "checkmark.circle")
            }
            if let errorMessage {
                statusRow(errorMessage, color: .red, icon: "exclamationmark.triangle")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vector Conversion")
        .task { await resolveTools() }
        .onChange(of: customPotracePath) { _, _ in Task { await resolveTools() } }
        .onChange(of: customVTracerPath) { _, _ in Task { await resolveTools() } }
        .onChange(of: rawTracingMode) { _, _ in Task { await resolveTools() } }
        .onDisappear { cancel() }
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            if let selectedImageURL {
                LabeledContent("File", value: selectedImageURL.lastPathComponent)
                if let detectedFormat {
                    LabeledContent("Detected format", value: detectedFormat.displayLabel)
                } else {
                    Text("Unrecognised raster format.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Choose a raster image to trace.")
                    .foregroundStyle(.secondary)
            }
            Button("Choose Image…") { chooseImage() }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedImageURL = url
        statusMessage = nil
        errorMessage = nil
    }

    // MARK: - Run

    @ViewBuilder
    private var runSection: some View {
        Section {
            if isConverting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Tracing with \(requiredTool)\u{2026}").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel, action: cancel)
                }
            } else {
                Button {
                    startConversion()
                } label: {
                    Label("Convert\u{2026}", systemImage: "scribble.variable")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImageURL == nil || detectedFormat == nil || requiredToolPath == nil)
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
        guard let selectedImageURL, let tools = toolPaths else { return }

        let panel = NSSavePanel()
        panel.title = "Save Traced SVG"
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(selectedImageURL.deletingPathExtension().lastPathComponent).svg"
        panel.message = "Choose where to save the traced SVG."
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        statusMessage = nil
        errorMessage = nil
        isConverting = true
        let runConfig = config.wrappedValue
        viewModel.appendLog(.info, "Vector conversion started for \(selectedImageURL.lastPathComponent)", category: .encoding)
        convertTask = Task {
            await runConversion(inputURL: selectedImageURL, outputURL: outputURL, config: runConfig, tools: tools)
        }
    }

    private func runConversion(
        inputURL: URL, outputURL: URL, config: RasterToVectorConfig, tools: VectorToolPaths
    ) async {
        do {
            try await RasterVectorExecutor.convert(
                inputURL: inputURL, outputURL: outputURL, config: config,
                tools: tools, runner: ExternalToolRunner()
            )
            statusMessage = "Traced SVG saved to \(outputURL.lastPathComponent)."
            viewModel.appendLog(.info, "Vector conversion complete: \(outputURL.path)", category: .encoding)
        } catch is CancellationError {
            viewModel.appendLog(.info, "Vector conversion cancelled for \(inputURL.lastPathComponent)", category: .encoding)
        } catch {
            errorMessage = "Vector conversion failed: \(error.localizedDescription)"
            viewModel.appendLog(.error, "Vector conversion failed for \(inputURL.lastPathComponent): \(error.localizedDescription)", category: .encoding)
        }
        isConverting = false
        convertTask = nil
    }

    private func cancel() {
        convertTask?.cancel()
        convertTask = nil
        isConverting = false
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
