// ============================================================================
// MeedyaConverter — RasterToVectorConfigEditor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Reusable SwiftUI editor for a `RasterToVectorConfig`. Renders the Preset,
// Tracing, Alpha, optional Animation, and Other sections — the parts of the
// raster→vector configuration surface that are common to:
//
//   * `VectorConversionView` (Tools → Vector Conversion)
//   * `ProResVectorView`     (Tools → ProRes Vector) — embeds this editor
//                                                     for per-frame tracing
//
// Persistence is intentionally OUT of scope here — the editor is purely
// binding-driven. Callers are responsible for storing the underlying
// `RasterToVectorConfig` (whether in AppStorage, in a parent config, or
// in a profile JSON blob).
//
// GitHub Issues: #376 engine / #381 / #402 (Vector Conversion) / #404
// (ProRes Vector — the consumer that drove the refactor).
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - RasterToVectorConfigEditor

/// Sections of the raster→vector configuration that are shared between
/// the stand-alone Vector Conversion tool and the per-frame tracing
/// stage of the ProRes Vector tool.
struct RasterToVectorConfigEditor: View {

    // -----------------------------------------------------------------
    // MARK: - Inputs
    // -----------------------------------------------------------------

    /// The config the editor mutates. The parent owns persistence.
    @Binding var config: RasterToVectorConfig

    /// The current input raster format. The editor only needs this to
    /// decide whether the Animation section is meaningful (it's only
    /// rendered for animated raster inputs in the stand-alone view).
    /// For ProRes use, the parent always passes `.png` and disables
    /// the Animation section via `showAnimationSection: false` anyway.
    let inputFormat: RasterFormat

    /// Whether to render the Animation section. The stand-alone Vector
    /// Conversion tool drives this from `inputFormat.isAnimated`; the
    /// ProRes Vector tool sets it to `false` because the outer
    /// `ProResToVectorConfig` has its own animation method that takes
    /// precedence.
    let showAnimationSection: Bool

    // -----------------------------------------------------------------
    // MARK: - Body
    // -----------------------------------------------------------------

    var body: some View {
        Section("Preset") {
            Picker("Editability preset", selection: presetBinding) {
                ForEach(EditabilityPreset.allCases, id: \.self) { preset in
                    Text(preset.displayLabel).tag(preset)
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
            Picker("Mode", selection: $config.tracingMode) {
                ForEach(TracingMode.allCases, id: \.self) { mode in
                    Text(mode.displayLabel).tag(mode)
                }
            }
            .accessibilityLabel("Tracing algorithm")

            Stepper(
                value: $config.colorCount,
                in: 2...256,
                step: 1
            ) {
                HStack {
                    Text("Colour count")
                    Spacer()
                    Text("\(config.colorCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Number of colours for quantisation tracing")
            .disabled(!colorCountApplies(to: config.tracingMode))
        }

        Section("Alpha") {
            Picker("Strategy", selection: $config.alpha) {
                ForEach(AlphaStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayLabel).tag(strategy)
                }
            }
            .pickerStyle(.inline)
            .accessibilityLabel("Alpha-channel handling strategy")
        }

        if showAnimationSection {
            Section("Animation") {
                // NOTE: an explicit binding closure here works around a
                // collision between `RasterToVectorConfig.animation`
                // (the field we want to mutate) and SwiftUI's
                // `Binding.animation(_:)` method, which the dynamic-
                // member-lookup machinery prefers on `$config.animation`.
                Picker("Method", selection: animationBinding) {
                    ForEach(AnimationMethod.allCases, id: \.self) { method in
                        Text(method.displayLabel).tag(method)
                    }
                }
                .accessibilityLabel("Animation method for animated input")
            }
        }

        Section("Other") {
            Toggle("Preserve EXIF / IPTC / XMP metadata", isOn: $config.preserveMetadata)
                .accessibilityLabel(
                    "Copy source metadata into the SVG metadata block"
                )

            Toggle("OCR text regions", isOn: $config.ocrTextRegions)
                .accessibilityLabel(
                    "Detect text regions and emit them as SVG text "
                    + "elements instead of traced paths"
                )

            Stepper(
                value: $config.curveSimplification,
                in: 0.0...10.0,
                step: 0.5
            ) {
                HStack {
                    Text("Curve simplification")
                    Spacer()
                    Text(String(format: "%.1f", config.curveSimplification))
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

    // -----------------------------------------------------------------
    // MARK: - Preset auto-drive
    // -----------------------------------------------------------------

    /// Explicit binding for `config.animation`. See the note in the
    /// Animation section above for why `$config.animation` cannot be
    /// used directly.
    private var animationBinding: Binding<AnimationMethod> {
        Binding(
            get: { config.animation },
            set: { config.animation = $0 }
        )
    }

    /// Bridging binding for the preset picker. Reading is straightforward;
    /// writing triggers the auto-drive of `tracingMode` and `colorCount`
    /// (except for `.custom`, which preserves the user's hand-tuned
    /// values).
    private var presetBinding: Binding<EditabilityPreset> {
        Binding(
            get: { config.preset },
            set: { newPreset in
                config.preset = newPreset
                if newPreset != .custom {
                    config.tracingMode = newPreset.defaultTracingMode
                    config.colorCount = newPreset.defaultColorCount
                }
            }
        )
    }

    /// Whether the colour-count stepper has any effect under the given
    /// tracing mode. Outline and monochrome ignore colour count by
    /// construction; colour-quantisation and photorealistic respect it.
    private func colorCountApplies(to mode: TracingMode) -> Bool {
        switch mode {
        case .outline, .monochrome:               return false
        case .colorQuantization, .photorealistic: return true
        }
    }
}

// MARK: - Display-name helpers
//
// User-facing labels for the engine enums. Centralised here so both
// `VectorConversionView` and `ProResVectorView` use identical strings.
// `internal` visibility — these are intentionally not part of the
// engine's public API.

extension RasterFormat {
    /// User-facing label. `RasterFormat` covers ~30 cases (common web
    /// formats plus raw camera formats like CR2/NEF/ARW and Netpbm
    /// variants), so an exhaustive switch is more churn than it's worth.
    /// We uppercase the raw value and append "(animated)" for formats
    /// that carry frames over time.
    var displayLabel: String {
        let upper = rawValue.uppercased()
        return isAnimated ? "\(upper) (animated)" : upper
    }
}

extension EditabilityPreset {
    var displayLabel: String {
        switch self {
        case .logoIcon:         return "Logo / Icon"
        case .illustration:     return "Illustration"
        case .photorealistic:   return "Photorealistic"
        case .technicalDiagram: return "Technical Diagram"
        case .handDrawnSketch:  return "Hand-drawn Sketch"
        case .custom:           return "Custom"
        }
    }
}

extension TracingMode {
    var displayLabel: String {
        switch self {
        case .outline:           return "Outline"
        case .colorQuantization: return "Colour Quantisation"
        case .monochrome:        return "Monochrome"
        case .photorealistic:    return "Photorealistic"
        }
    }
}

extension AlphaStrategy {
    var displayLabel: String {
        switch self {
        case .clipPathWithOpacity: return "Clip-path with opacity"
        case .flatten:             return "Flatten against background"
        case .discard:             return "Discard alpha"
        }
    }
}

extension AnimationMethod {
    var displayLabel: String {
        switch self {
        case .smil:                return "SMIL"
        case .cssKeyframes:        return "CSS @keyframes"
        case .hybrid:              return "Hybrid (SMIL + CSS)"
        case .staticFrameSequence: return "Static frame sequence"
        }
    }
}
