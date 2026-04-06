// ============================================================================
// MeedyaConverter — DualDynamicHDRView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - DualDynamicHDRView

/// Configuration and execution view for dual dynamic HDR conversion.
///
/// Allows the user to convert Dolby Vision content into a dual-metadata stream
/// carrying both DV RPU and HDR10+ SEI, enabling maximum device compatibility.
/// Displays the detected source profile, target selection, pipeline preview,
/// tool availability, and per-step progress during conversion.
///
/// Phase 3.9 / Issue #370
struct DualDynamicHDRView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The detected source Dolby Vision profile from the imported file.
    @State private var detectedProfile: DoviProfile = .profile5

    /// The selected dual dynamic HDR target format.
    @State private var selectedTarget: DualHDRTarget = .dvPlusHDR10Plus

    /// Whether to preserve existing DV dynamic metadata during conversion.
    @State private var preserveDynamicMetadata: Bool = true

    /// The generated pipeline steps for preview.
    @State private var pipelineSteps: [PipelineStepDescriptor] = []

    /// Whether the dovi_tool binary is available.
    @State private var doviToolAvailable: Bool = false

    /// Whether the hdr10plus_tool binary is available.
    @State private var hdr10PlusToolAvailable: Bool = false

    /// Whether a conversion is currently running.
    @State private var isConverting: Bool = false

    /// The index of the currently executing pipeline step (0-based).
    @State private var currentStepIndex: Int = 0

    /// Status message for the current operation.
    @State private var statusMessage: String = ""

    /// Error message if conversion fails.
    @State private var errorMessage: String?

    /// Whether both required tools are available.
    private var toolsReady: Bool {
        doviToolAvailable && hdr10PlusToolAvailable
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                toolAvailabilitySection
                sourceProfileSection
                targetSelectionSection
                fallbackVisualizationSection
                pipelinePreviewSection

                if isConverting {
                    progressSection
                }

                if let error = errorMessage {
                    errorSection(message: error)
                }

                convertButtonSection
            }
            .padding()
        }
        .navigationTitle("Dual Dynamic HDR")
        .onAppear {
            checkToolAvailability()
            updatePipelinePreview()
        }
    }

    // MARK: - Header

    /// Title and description header for the dual dynamic HDR feature.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dual Dynamic HDR Conversion")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Convert Dolby Vision content to carry both DV and HDR10+ metadata in a single stream. This enables the widest possible device compatibility with automatic fallback across display types.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tool Availability

    /// Shows whether dovi_tool and hdr10plus_tool are installed and available.
    private var toolAvailabilitySection: some View {
        GroupBox("Required Tools") {
            VStack(alignment: .leading, spacing: 8) {
                toolStatusRow(
                    name: "dovi_tool",
                    available: doviToolAvailable,
                    purpose: "Dolby Vision RPU extraction, conversion, and injection"
                )
                toolStatusRow(
                    name: "hdr10plus_tool",
                    available: hdr10PlusToolAvailable,
                    purpose: "HDR10+ metadata injection and validation"
                )

                if !toolsReady {
                    Text("Both tools must be installed to use dual dynamic HDR conversion. Install via Homebrew: brew install dovi_tool hdr10plus_tool")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A single row showing a tool's availability status.
    private func toolStatusRow(name: String, available: Bool, purpose: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .red)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(available ? "Available" : "Not Found")
                .font(.caption)
                .foregroundStyle(available ? .green : .red)
        }
    }

    // MARK: - Source Profile

    /// Displays the detected source Dolby Vision profile.
    private var sourceProfileSection: some View {
        GroupBox("Source Profile") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected Dolby Vision Profile")
                        .font(.body)
                    Text(detectedProfile.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Picker("Source Profile", selection: $detectedProfile) {
                    ForEach(DoviProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: detectedProfile) {
            updatePipelinePreview()
        }
    }

    // MARK: - Target Selection

    /// Picker for selecting the dual dynamic HDR target format.
    private var targetSelectionSection: some View {
        GroupBox("Target Format") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(DualHDRTarget.allCases, id: \.self) { target in
                    targetOptionRow(target: target)
                }

                Toggle("Preserve DV dynamic metadata", isOn: $preserveDynamicMetadata)
                    .font(.body)
                    .padding(.top, 4)

                Text(preserveDynamicMetadata
                     ? "Existing per-frame DV data will be converted and used to generate HDR10+ metadata."
                     : "New RPU metadata will be generated from static MaxCLL/MaxFALL values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: selectedTarget) {
            updatePipelinePreview()
        }
        .onChange(of: preserveDynamicMetadata) {
            updatePipelinePreview()
        }
    }

    /// A selectable row for a dual HDR target option.
    private func targetOptionRow(target: DualHDRTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedTarget == target ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selectedTarget == target ? Color.blue : Color.secondary)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(target.fallbackChain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(target.tierCount)-tier")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTarget = target
        }
    }

    // MARK: - Fallback Visualization

    /// Visual representation of the compatibility fallback chain.
    private var fallbackVisualizationSection: some View {
        GroupBox("Compatibility Chain") {
            HStack(spacing: 0) {
                let tiers = fallbackTiers(for: selectedTarget)
                ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                    VStack(spacing: 4) {
                        Image(systemName: tier.icon)
                            .font(.title3)
                            .foregroundStyle(tier.color)
                        Text(tier.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text(tier.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    if index < tiers.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Pipeline Preview

    /// Shows the ordered list of pipeline steps that will be executed.
    private var pipelinePreviewSection: some View {
        GroupBox("Pipeline Steps") {
            if pipelineSteps.isEmpty {
                Text("Select source and target to preview pipeline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pipelineSteps) { step in
                        pipelineStepRow(step: step)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// A single pipeline step row with tool badge and description.
    private func pipelineStepRow(step: PipelineStepDescriptor) -> some View {
        HStack(spacing: 12) {
            // Step number
            Text("\(step.stepNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(stepBackground(for: step))
                .foregroundStyle(.white)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.tool)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(toolBadgeColor(for: step.tool).opacity(0.15))
                        .foregroundStyle(toolBadgeColor(for: step.tool))
                        .clipShape(Capsule())

                    Text(step.description)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            if isConverting {
                stepStatusIcon(for: step)
            }
        }
    }

    /// Background colour for a pipeline step number circle.
    private func stepBackground(for step: PipelineStepDescriptor) -> Color {
        if isConverting {
            if step.stepNumber - 1 < currentStepIndex {
                return .green
            } else if step.stepNumber - 1 == currentStepIndex {
                return .blue
            }
        }
        return .secondary
    }

    /// Status icon for a pipeline step during conversion.
    @ViewBuilder
    private func stepStatusIcon(for step: PipelineStepDescriptor) -> some View {
        if step.stepNumber - 1 < currentStepIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if step.stepNumber - 1 == currentStepIndex {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    /// Badge colour for a tool name.
    private func toolBadgeColor(for tool: String) -> Color {
        switch tool {
        case "dovi_tool": return .purple
        case "hdr10plus_tool": return .orange
        case "ffmpeg": return .blue
        case "internal": return .gray
        default: return .secondary
        }
    }

    // MARK: - Progress

    /// Progress display during active conversion.
    private var progressSection: some View {
        GroupBox("Progress") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(
                    value: Double(currentStepIndex),
                    total: Double(pipelineSteps.count)
                )

                HStack {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Step \(currentStepIndex + 1) of \(pipelineSteps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Error

    /// Error message display.
    private func errorSection(message: String) -> some View {
        GroupBox {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.red)
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Convert Button

    /// The main action button for starting conversion.
    private var convertButtonSection: some View {
        HStack {
            Spacer()
            Button(action: startConversion) {
                Label(
                    isConverting ? "Converting..." : "Convert",
                    systemImage: isConverting ? "gear" : "wand.and.stars"
                )
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!toolsReady || isConverting)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    /// Check whether dovi_tool and hdr10plus_tool are available on this system.
    private func checkToolAvailability() {
        let doviTool = DoviToolWrapper()
        let hdr10PlusTool = HDR10PlusToolWrapper()
        doviToolAvailable = doviTool.isAvailable
        hdr10PlusToolAvailable = hdr10PlusTool.isAvailable
    }

    /// Rebuild the pipeline preview when configuration changes.
    private func updatePipelinePreview() {
        let config = DualDynamicHDRConfig(
            sourceProfile: detectedProfile,
            target: selectedTarget,
            preserveDVDynamicMetadata: preserveDynamicMetadata
        )

        pipelineSteps = DualDynamicHDRPipeline.buildPipelineSteps(
            config: config,
            inputPath: "<source>.hevc",
            outputPath: "<output>.hevc"
        )
    }

    /// Start the dual dynamic HDR conversion pipeline.
    private func startConversion() {
        guard toolsReady else { return }
        isConverting = true
        currentStepIndex = 0
        errorMessage = nil
        statusMessage = "Starting pipeline..."

        // Actual execution would be performed by the EncodingEngine.
        // This view coordinates the UI state; the engine handles process
        // orchestration and temp file management.
    }

    // MARK: - Fallback Tier Data

    /// Tier data for the fallback chain visualization.
    private struct FallbackTier {
        let name: String
        let detail: String
        let icon: String
        let color: Color
    }

    /// Build the fallback tier list for a given target.
    private func fallbackTiers(for target: DualHDRTarget) -> [FallbackTier] {
        switch target {
        case .dvPlusHDR10Plus:
            return [
                FallbackTier(name: "Dolby Vision", detail: "Profile 8.1", icon: "sparkles.tv", color: .purple),
                FallbackTier(name: "HDR10+", detail: "Dynamic", icon: "sun.max.fill", color: .orange),
                FallbackTier(name: "HDR10", detail: "Static", icon: "sun.min.fill", color: .yellow),
                FallbackTier(name: "SDR", detail: "Fallback", icon: "tv", color: .gray),
            ]
        case .dvPlusHDR10PlusHLG:
            return [
                FallbackTier(name: "Dolby Vision", detail: "Profile 8.4", icon: "sparkles.tv", color: .purple),
                FallbackTier(name: "HDR10+", detail: "Dynamic", icon: "sun.max.fill", color: .orange),
                FallbackTier(name: "HLG", detail: "Broadcast", icon: "antenna.radiowaves.left.and.right", color: .teal),
                FallbackTier(name: "HDR10", detail: "Static", icon: "sun.min.fill", color: .yellow),
                FallbackTier(name: "SDR", detail: "Fallback", icon: "tv", color: .gray),
            ]
        }
    }
}
