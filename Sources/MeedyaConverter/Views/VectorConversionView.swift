// ============================================================================
// MeedyaConverter — VectorConversionView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for raster→vector (SVG) conversion. Binds the eight
// user-facing fields of `RasterToVectorConfig` from `ConverterEngine` and
// persists the user's preferences via `@AppStorage`.
//
// Layout:
//   1. Input    — Raster format picker (the only purely informational
//                 control: the actual format is detected from the file).
//   2. Preset   — Editability preset picker. Changing this auto-drives
//                 the tracing mode and colour count to the preset's
//                 recommended defaults, so users who pick a preset don't
//                 need to fiddle with the lower-level controls.
//   3. Tracing  — Tracing mode picker + colour count stepper. Colour
//                 count is disabled when the tracing mode doesn't use it
//                 (outline / monochrome — those produce a fixed number
//                 of regions).
//   4. Alpha    — Alpha strategy picker.
//   5. Animation — Animation method picker, hidden unless the chosen
//                  input format is animated (GIF / APNG / animated WebP).
//   6. Extras   — Preserve metadata toggle, OCR toggle, curve
//                 simplification stepper.
//
// GitHub Issues: #376 engine (RasterVectorConverter) / #381 / #402 UI.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - VectorConversionView

/// User-facing settings for raster→vector (SVG) conversion.
struct VectorConversionView: View {

    // -----------------------------------------------------------------
    // MARK: - Persisted state
    // -----------------------------------------------------------------
    //
    // One AppStorage key per RasterToVectorConfig field. Per-field keys
    // (rather than a JSON-encoded blob) mean a future addition to the
    // engine config does not invalidate the user's existing preferences.
    // The keys are namespaced under `vectorConversion.` so they are easy
    // to grep for and to clear in tests.

    /// Raster input format. Defaulted to PNG — the most common case —
    /// so the form has a stable initial state.
    @AppStorage("vectorConversion.inputFormat") private var rawInputFormat: String =
        RasterFormat.png.rawValue

    /// Editability preset. Changing this auto-drives `rawTracingMode`
    /// and `colorCount` (see `applyPreset(_:)`).
    @AppStorage("vectorConversion.preset") private var rawPreset: String =
        EditabilityPreset.illustration.rawValue

    /// Tracing mode. Initialised to the default for `illustration` so
    /// the AppStorage default agrees with the engine's RasterToVectorConfig
    /// default-init (pinned by a test in ConverterEngineTests).
    @AppStorage("vectorConversion.tracingMode") private var rawTracingMode: String =
        TracingMode.colorQuantization.rawValue

    /// Quantisation colour count.
    @AppStorage("vectorConversion.colorCount") private var colorCount: Int = 32

    /// Alpha-channel handling strategy.
    @AppStorage("vectorConversion.alpha") private var rawAlpha: String =
        AlphaStrategy.clipPathWithOpacity.rawValue

    /// Animation method used when the input is an animated raster.
    @AppStorage("vectorConversion.animation") private var rawAnimation: String =
        AnimationMethod.smil.rawValue

    /// Whether to copy EXIF / IPTC / XMP into the SVG `<metadata>` block.
    @AppStorage("vectorConversion.preserveMetadata") private var preserveMetadata: Bool = true

    /// Whether to run OCR against detected text regions and emit them
    /// as `<text>` elements instead of traced paths.
    @AppStorage("vectorConversion.ocrTextRegions") private var ocrTextRegions: Bool = false

    /// Curve-simplification tolerance. 0.0 = preserve every traced
    /// point; 10.0 = very aggressive smoothing.
    @AppStorage("vectorConversion.curveSimplification") private var curveSimplification: Double = 2.0

    // -----------------------------------------------------------------
    // MARK: - Computed bindings
    // -----------------------------------------------------------------
    //
    // Bridge between the raw-String AppStorage values and the
    // strongly-typed enums consumers actually want to manipulate. Each
    // binding falls back to the engine's default when the persisted
    // raw value is unrecognised (e.g. a future build added a case this
    // binary doesn't know).

    private var inputFormat: Binding<RasterFormat> {
        Binding(
            get: { RasterFormat(rawValue: rawInputFormat) ?? .png },
            set: { rawInputFormat = $0.rawValue }
        )
    }

    private var preset: Binding<EditabilityPreset> {
        Binding(
            get: { EditabilityPreset(rawValue: rawPreset) ?? .illustration },
            set: { newPreset in
                rawPreset = newPreset.rawValue
                applyPreset(newPreset)
            }
        )
    }

    private var tracingMode: Binding<TracingMode> {
        Binding(
            get: { TracingMode(rawValue: rawTracingMode) ?? .colorQuantization },
            set: { rawTracingMode = $0.rawValue }
        )
    }

    private var alpha: Binding<AlphaStrategy> {
        Binding(
            get: { AlphaStrategy(rawValue: rawAlpha) ?? .clipPathWithOpacity },
            set: { rawAlpha = $0.rawValue }
        )
    }

    private var animation: Binding<AnimationMethod> {
        Binding(
            get: { AnimationMethod(rawValue: rawAnimation) ?? .smil },
            set: { rawAnimation = $0.rawValue }
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Body
    // -----------------------------------------------------------------

    var body: some View {
        Form {
            Section("Input") {
                Picker("Raster format", selection: inputFormat) {
                    ForEach(RasterFormat.allCases, id: \.self) { format in
                        Text(format.displayLabel).tag(format)
                    }
                }
                .accessibilityLabel("Input raster format")
            }

            Section("Preset") {
                Picker("Editability preset", selection: preset) {
                    ForEach(EditabilityPreset.allCases, id: \.self) { p in
                        Text(p.displayLabel).tag(p)
                    }
                }
                .accessibilityLabel("Editability preset for the traced SVG")

                Text(
                    "Picking a preset auto-fills tracing mode and colour "
                    + "count. Choose Custom to keep your manual values."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Tracing") {
                Picker("Mode", selection: tracingMode) {
                    ForEach(TracingMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .accessibilityLabel("Tracing algorithm")

                // Colour count only applies to colour-quantisation tracing
                // (and to photorealistic mode, which is a higher-cost
                // variant). Disable it for outline and monochrome so
                // users don't waste time tweaking a value that has no
                // effect on the output.
                Stepper(
                    value: $colorCount,
                    in: 2...256,
                    step: 1
                ) {
                    HStack {
                        Text("Colour count")
                        Spacer()
                        Text("\(colorCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Number of colours for quantisation tracing")
                .disabled(!colorCountApplies(to: tracingMode.wrappedValue))
            }

            Section("Alpha") {
                Picker("Strategy", selection: alpha) {
                    ForEach(AlphaStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayLabel).tag(strategy)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Alpha-channel handling strategy")
            }

            // Animation picker is meaningless for static inputs. Render
            // it only when the chosen input format is animated.
            if inputFormat.wrappedValue.isAnimated {
                Section("Animation") {
                    Picker("Method", selection: animation) {
                        ForEach(AnimationMethod.allCases, id: \.self) { method in
                            Text(method.displayLabel).tag(method)
                        }
                    }
                    .accessibilityLabel("Animation method for animated input")
                }
            }

            Section("Other") {
                Toggle("Preserve EXIF / IPTC / XMP metadata", isOn: $preserveMetadata)
                    .accessibilityLabel(
                        "Copy source metadata into the SVG metadata block"
                    )

                Toggle("OCR text regions", isOn: $ocrTextRegions)
                    .accessibilityLabel(
                        "Detect text regions and emit them as SVG text "
                        + "elements instead of traced paths"
                    )

                Stepper(
                    value: $curveSimplification,
                    in: 0.0...10.0,
                    step: 0.5
                ) {
                    HStack {
                        Text("Curve simplification")
                        Spacer()
                        Text(String(format: "%.1f", curveSimplification))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(
                    "Curve-simplification tolerance; 0 preserves every "
                    + "point, 10 smooths aggressively"
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vector Conversion")
    }

    // -----------------------------------------------------------------
    // MARK: - Preset auto-drive
    // -----------------------------------------------------------------

    /// When a preset is selected, push its recommended tracing mode and
    /// colour count into the corresponding AppStorage keys so the lower
    /// controls reflect the preset's intent. We deliberately do NOT
    /// auto-drive when the preset is `.custom` — that case exists so
    /// the user can keep their hand-tuned values without losing them
    /// every time they revisit this view.
    private func applyPreset(_ newPreset: EditabilityPreset) {
        guard newPreset != .custom else { return }
        rawTracingMode = newPreset.defaultTracingMode.rawValue
        colorCount = newPreset.defaultColorCount
    }

    /// Whether the colour-count stepper has any effect under the given
    /// tracing mode. Outline and monochrome ignore colour count by
    /// construction; colour-quantisation and photorealistic respect it.
    private func colorCountApplies(to mode: TracingMode) -> Bool {
        switch mode {
        case .outline, .monochrome:           return false
        case .colorQuantization, .photorealistic: return true
        }
    }
}

// MARK: - Display-name helpers
//
// User-facing labels for the engine enums. Kept here rather than as
// `displayName` properties on the engine types because they are purely
// UI strings — making them part of the engine's public API would force
// us to keep them in lockstep with translations and SwiftUI conventions.

private extension RasterFormat {
    /// User-facing label. RasterFormat covers ~30 cases (common web
    /// formats plus raw camera formats like CR2/NEF/ARW and Netpbm
    /// variants), so an exhaustive switch is more churn than it's
    /// worth. We uppercase the raw value and append "(animated)" for
    /// formats that carry frames over time — enough information for
    /// the picker without a translation table.
    var displayLabel: String {
        let upper = rawValue.uppercased()
        return isAnimated ? "\(upper) (animated)" : upper
    }
}

private extension EditabilityPreset {
    var displayLabel: String {
        switch self {
        case .logoIcon:          return "Logo / Icon"
        case .illustration:      return "Illustration"
        case .photorealistic:    return "Photorealistic"
        case .technicalDiagram:  return "Technical Diagram"
        case .handDrawnSketch:   return "Hand-drawn Sketch"
        case .custom:            return "Custom"
        }
    }
}

private extension TracingMode {
    var displayLabel: String {
        switch self {
        case .outline:           return "Outline"
        case .colorQuantization: return "Colour Quantisation"
        case .monochrome:        return "Monochrome"
        case .photorealistic:    return "Photorealistic"
        }
    }
}

private extension AlphaStrategy {
    var displayLabel: String {
        switch self {
        case .clipPathWithOpacity: return "Clip-path with opacity"
        case .flatten:             return "Flatten against background"
        case .discard:             return "Discard alpha"
        }
    }
}

private extension AnimationMethod {
    var displayLabel: String {
        switch self {
        case .smil:                 return "SMIL"
        case .cssKeyframes:         return "CSS @keyframes"
        case .hybrid:               return "Hybrid (SMIL + CSS)"
        case .staticFrameSequence:  return "Static frame sequence"
        }
    }
}
