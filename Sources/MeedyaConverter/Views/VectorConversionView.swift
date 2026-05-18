// ============================================================================
// MeedyaConverter — VectorConversionView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for raster→vector (SVG) conversion. Persists the user's
// preferences across launches via `@AppStorage`, then assembles them into a
// `RasterToVectorConfig` binding consumed by the reusable
// `RasterToVectorConfigEditor` (shared with `ProResVectorView`).
//
// GitHub Issues: #376 engine / #381 / #402 UI.
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
    // The keys are namespaced under `vectorConversion.` so they are
    // easy to grep for and to clear in tests.
    //
    // The values here are the *AppStorage representation* — String for
    // enum rawValues, primitive for everything else. They are bridged
    // into a `Binding<RasterToVectorConfig>` for the shared editor.

    @AppStorage("vectorConversion.inputFormat") private var rawInputFormat: String =
        RasterFormat.png.rawValue
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

    // -----------------------------------------------------------------
    // MARK: - Computed bindings
    // -----------------------------------------------------------------

    /// Input-format binding with corrupt-rawValue fallback.
    private var inputFormat: Binding<RasterFormat> {
        Binding(
            get: { RasterFormat(rawValue: rawInputFormat) ?? .png },
            set: { rawInputFormat = $0.rawValue }
        )
    }

    /// Assembles the nine AppStorage values into a single
    /// `Binding<RasterToVectorConfig>` for the shared editor. The
    /// editor mutates fields on the value type; our setter splits
    /// the new value back across the nine keys.
    private var config: Binding<RasterToVectorConfig> {
        Binding(
            get: {
                RasterToVectorConfig(
                    inputFormat: RasterFormat(rawValue: rawInputFormat) ?? .png,
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
                // `outputFormat` here (those are set by the Input
                // picker below, and `outputFormat` is fixed).
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
            // The Input picker is specific to the stand-alone tool —
            // ProResVectorView always uses PNG (extracted frames) so
            // its embedded editor doesn't need this section.
            Section("Input") {
                Picker("Raster format", selection: inputFormat) {
                    ForEach(RasterFormat.allCases, id: \.self) { format in
                        Text(format.displayLabel).tag(format)
                    }
                }
                .accessibilityLabel("Input raster format")
            }

            // All other sections come from the shared editor.
            RasterToVectorConfigEditor(
                config: config,
                inputFormat: inputFormat.wrappedValue,
                showAnimationSection: inputFormat.wrappedValue.isAnimated
            )
        }
        .formStyle(.grouped)
        .navigationTitle("Vector Conversion")
    }
}
