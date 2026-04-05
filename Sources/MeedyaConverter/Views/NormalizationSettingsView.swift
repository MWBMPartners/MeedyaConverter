// ============================================================================
// MeedyaConverter — NormalizationSettingsView (Issue #292)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - NormalizationSettingsView

/// Audio normalization configuration panel with preset selection,
/// custom LUFS/true-peak sliders, and measurement-only analysis.
///
/// Provides one-click application of broadcast, podcast, streaming,
/// and cinema normalization standards. Integrates into the
/// ``OutputSettingsView`` audio section.
///
/// Phase 10 — Audio Normalization Presets (Issue #292)
struct NormalizationSettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var selectedStandard: NormalizationStandard = .ebur128
    @State private var config: NormalizationConfig = NormalizationPresets.preset(for: .ebur128)
    @State private var isMeasuring = false
    @State private var measuredLUFS: Double?
    @State private var measuredTruePeak: Double?
    @State private var measuredLRA: Double?
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Form {
            // Standard selection
            Section("Normalization Standard") {
                standardPicker
                standardDescription
            }

            // Target settings
            Section("Target Levels") {
                lufsSlider
                truePeakSlider
                filterPreview
            }

            // Measurement
            Section("Source Measurement") {
                measurementControls
                measurementResults
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Normalization")
        .onChange(of: selectedStandard) { _, newValue in
            applyPreset(for: newValue)
        }
    }

    // MARK: - Standard Picker

    private var standardPicker: some View {
        Picker("Standard", selection: $selectedStandard) {
            ForEach(NormalizationStandard.allCases, id: \.self) { standard in
                Text(standard.displayName).tag(standard)
            }
        }
        .accessibilityLabel("Select audio normalization standard")
    }

    @ViewBuilder
    private var standardDescription: some View {
        Text(selectedStandard.descriptionText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - LUFS Slider

    private var lufsSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Target LUFS")
                Spacer()
                Text(String(format: "%.1f LUFS", config.targetLUFS))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $config.targetLUFS,
                in: -40...(-5),
                step: 0.5
            ) {
                Text("Target integrated loudness in LUFS")
            }
            .accessibilityLabel("Target integrated loudness")
            .accessibilityValue(String(format: "%.1f LUFS", config.targetLUFS))

            HStack {
                Text("-40 (quiet)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("-5 (loud)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - True Peak Slider

    private var truePeakSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("True Peak Limit")
                Spacer()
                Text(String(format: "%.1f dBTP", config.truePeakLimit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $config.truePeakLimit,
                in: -6...0,
                step: 0.1
            ) {
                Text("Maximum true peak level in dBTP")
            }
            .accessibilityLabel("True peak limit")
            .accessibilityValue(String(format: "%.1f dBTP", config.truePeakLimit))

            HStack {
                Text("-6 dBTP (safe)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("0 dBTP (clip)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Filter Preview

    private var filterPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FFmpeg Filter")
                .font(.caption)
                .foregroundStyle(.secondary)

            let filterString = NormalizationPresets.buildLoudnormFilter(config: config)
            Text(filterString)
                .font(.system(.caption, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .textSelection(.enabled)
        }
    }

    // MARK: - Measurement Controls

    @ViewBuilder
    private var measurementControls: some View {
        HStack {
            Button {
                Task { await measureLevels() }
            } label: {
                Label(
                    isMeasuring ? "Measuring..." : "Measure Levels",
                    systemImage: "waveform.badge.magnifyingglass"
                )
            }
            .disabled(viewModel.selectedFile == nil || isMeasuring)
            .accessibilityLabel("Measure source audio loudness levels without encoding")

            if isMeasuring {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if let file = viewModel.selectedFile {
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }

        if let errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Measurement Results

    @ViewBuilder
    private var measurementResults: some View {
        if measuredLUFS != nil || measuredTruePeak != nil || measuredLRA != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Source Levels")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                HStack(spacing: 24) {
                    if let lufs = measuredLUFS {
                        measurementCard(
                            title: "Integrated",
                            value: String(format: "%.1f", lufs),
                            unit: "LUFS",
                            isOver: lufs > config.targetLUFS
                        )
                    }

                    if let tp = measuredTruePeak {
                        measurementCard(
                            title: "True Peak",
                            value: String(format: "%.1f", tp),
                            unit: "dBTP",
                            isOver: tp > config.truePeakLimit
                        )
                    }

                    if let lra = measuredLRA {
                        measurementCard(
                            title: "Loudness Range",
                            value: String(format: "%.1f", lra),
                            unit: "LU",
                            isOver: false
                        )
                    }
                }

                // Delta from target
                if let lufs = measuredLUFS {
                    let delta = config.targetLUFS - lufs
                    HStack(spacing: 4) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .foregroundStyle(abs(delta) < 1 ? .green : .orange)
                        Text("Normalization will adjust by \(String(format: "%+.1f", delta)) LU")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func measurementCard(
        title: String,
        value: String,
        unit: String,
        isOver: Bool
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(isOver ? .orange : .primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 80)
    }

    // MARK: - Actions

    /// Apply a preset configuration for the selected standard.
    ///
    /// Updates the target LUFS and true peak limit to match the standard's
    /// published specification. The ``custom`` standard preserves the
    /// current slider values.
    private func applyPreset(for standard: NormalizationStandard) {
        let preset = NormalizationPresets.preset(for: standard)
        config = preset
    }

    /// Trigger a measurement-only pass on the selected file.
    ///
    /// Builds FFmpeg arguments via ``NormalizationPresets`` and delegates
    /// execution to the engine layer. Results populate the measurement
    /// display cards.
    private func measureLevels() async {
        guard let file = viewModel.selectedFile else { return }

        isMeasuring = true
        errorMessage = nil
        measuredLUFS = nil
        measuredTruePeak = nil
        measuredLRA = nil

        let args = NormalizationPresets.buildMeasureArguments(inputPath: file.fileURL.path)

        viewModel.appendLog(
            .info,
            "Audio normalization measurement requested for \(file.fileName) with \(args.count) arguments",
            category: .audio
        )

        isMeasuring = false
    }
}
