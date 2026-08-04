// ============================================================================
// MeedyaConverter — ProResVectorView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// SwiftUI surface for ProRes 4444 → animated SVG conversion. Binds the
// fields of `ProResToVectorConfig`, embeds the shared
// `RasterToVectorConfigEditor` for per-frame tracing settings, and
// surfaces an output-size warning when the chosen settings would produce
// very large SVG output.
//
// Layout:
//   1. Source       — ProRes variant, frame rate, time range, frame stride
//   2. Alpha        — How the ProRes alpha channel is represented in the SVG
//   3. Tracing      — Embedded RasterToVectorConfigEditor (no Animation section
//                     because the outer config has its own animation method)
//   4. Animation    — Outer-SVG animation method (separate from per-frame tracing)
//   5. Assembly     — Shape persistence + keyframe extraction toggles
//   6. Warning      — Heads-up callout when settings would produce a large SVG
//
// GitHub Issues: #377 engine (ProResToVectorConverter) / #381 / #404 UI.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ProResVectorView

/// User-facing settings for ProRes 4444 → animated SVG conversion.
struct ProResVectorView: View {

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

    /// Assembles the full `ProResToVectorConfig` for the output-size
    /// warning check. We do not persist this as a single blob — it is
    /// derived from the AppStorage values for the warning call only.
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
                Picker("Method", selection: animation) {
                    ForEach(AnimationMethod.allCases, id: \.self) { method in
                        Text(method.displayLabel).tag(method)
                    }
                }
                .accessibilityLabel("Animation method for the assembled SVG")
            }

            Section("Assembly") {
                Toggle("Shape persistence", isOn: $shapePersistence)
                    .accessibilityLabel(
                        "Track shape identity across frames for "
                        + "consistent SVG element IDs"
                    )

                Toggle("Keyframe extraction", isOn: $keyframeExtraction)
                    .accessibilityLabel(
                        "Only re-trace significant visual changes; "
                        + "animate between keyframes"
                    )
            }

            // Output-size warning. The engine's `shouldWarnAboutOutputSize`
            // needs a source duration to compute the projected frame count.
            // We don't have a selected file in this tool view, so we use
            // the engine's `recommendedMaxDurationSeconds` as the
            // reference — the warning fires when the user's settings
            // would produce more than that many seconds of output, OR
            // when they've selected photorealistic tracing (which is
            // always heavy regardless of length).
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
        }
        .formStyle(.grouped)
        .navigationTitle("ProRes to Vector")
    }

    // -----------------------------------------------------------------
    // MARK: - Output-size warning
    // -----------------------------------------------------------------

    /// Whether the warning callout should be visible. Delegates to
    /// `ProResToVectorConverter.shouldWarnAboutOutputSize(...)` with a
    /// synthetic reference duration of
    /// `ProResToVectorConverter.recommendedMaxDurationSeconds * 2` —
    /// twice the engine's "comfortable" duration — so the warning
    /// fires for any settings that would produce more than the
    /// engine's recommended cap of output.
    private var outputSizeWarningFires: Bool {
        let referenceDuration = ProResToVectorConverter
            .recommendedMaxDurationSeconds * 2
        return ProResToVectorConverter.shouldWarnAboutOutputSize(
            config: assembledConfig,
            sourceDurationSeconds: referenceDuration
        )
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
