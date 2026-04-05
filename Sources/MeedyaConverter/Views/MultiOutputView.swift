// ============================================================================
// MeedyaConverter — MultiOutputView (Issue #335)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MultiOutputView

/// Configuration view for encoding a single source file to multiple output formats.
///
/// Displays the source file, a list of output profiles with add/remove
/// controls, per-output enable toggles, a "Use tee muxer" option with
/// an automatic compatibility check, and the generated FFmpeg arguments.
///
/// Phase 11.3 — Multiple Output Formats per Job (Issue #335)
struct MultiOutputView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The source file URL selected by the user.
    @State private var sourceURL: URL?

    /// The list of output specifications.
    @State private var outputs: [OutputSpec] = []

    /// Whether to use the FFmpeg tee muxer for simultaneous encoding.
    @State private var useTee = false

    /// Whether tee muxer is compatible with the current output set.
    @State private var teeCompatible = true

    /// The encoding profile selected for the next added output.
    @State private var selectedProfile: EncodingProfile?

    /// Whether the add-output sheet is presented.
    @State private var showAddSheet = false

    // MARK: - Body

    var body: some View {
        Form {
            sourceSection
            outputsSection
            teeSection
            argumentsPreviewSection
        }
        .formStyle(.grouped)
        .navigationTitle("Multi-Output Encoding")
        .onChange(of: outputs) { _, _ in
            updateTeeCompatibility()
        }
    }

    // MARK: - Source File

    /// Section displaying the selected source file.
    @ViewBuilder
    private var sourceSection: some View {
        Section("Source File") {
            if let url = sourceURL {
                LabeledContent("File") {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Path") {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Button("Select Source File...") {
                browseForSource()
            }
        }
    }

    // MARK: - Outputs List

    /// Section listing all configured outputs with enable toggles.
    @ViewBuilder
    private var outputsSection: some View {
        Section {
            if outputs.isEmpty {
                ContentUnavailableView(
                    "No Outputs",
                    systemImage: "doc.on.doc",
                    description: Text("Add output profiles to encode the source into multiple formats.")
                )
            } else {
                ForEach($outputs) { $spec in
                    HStack {
                        Toggle(isOn: $spec.enabled) {
                            VStack(alignment: .leading) {
                                Text(spec.profile.name)
                                    .font(.headline)
                                Text(spec.outputURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Spacer()

                        Button(role: .destructive) {
                            removeOutput(spec.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            HStack {
                Text("Outputs (\(outputs.count))")
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Output", systemImage: "plus")
                }
                .sheet(isPresented: $showAddSheet) {
                    addOutputSheet
                }
            }
        }
    }

    // MARK: - Tee Muxer

    /// Section for the tee muxer toggle and compatibility status.
    @ViewBuilder
    private var teeSection: some View {
        Section("Encoding Strategy") {
            Toggle("Use FFmpeg Tee Muxer (simultaneous encoding)", isOn: $useTee)
                .disabled(!teeCompatible)

            if !teeCompatible {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("Tee muxer is not compatible with the current outputs. All outputs must use the same video and audio codec.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if useTee {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("All outputs are compatible for simultaneous tee muxing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Arguments Preview

    /// Section displaying the generated FFmpeg arguments.
    @ViewBuilder
    private var argumentsPreviewSection: some View {
        if let source = sourceURL, !outputs.isEmpty {
            Section("FFmpeg Arguments Preview") {
                let config = MultiOutputConfig(sourceURL: source, outputs: outputs)

                if useTee && teeCompatible {
                    let args = MultiOutputEncoder.buildTeeArguments(config: config)
                    argumentsText(args)
                } else {
                    let allArgs = MultiOutputEncoder.buildSequentialArguments(config: config)
                    ForEach(Array(allArgs.enumerated()), id: \.offset) { index, args in
                        VStack(alignment: .leading) {
                            Text("Output \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            argumentsText(args)
                        }
                    }
                }
            }
        }
    }

    /// A monospaced text view for displaying FFmpeg arguments.
    @ViewBuilder
    private func argumentsText(_ args: [String]) -> some View {
        Text(args.joined(separator: " "))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Add Output Sheet

    /// Sheet for adding a new output specification.
    @ViewBuilder
    private var addOutputSheet: some View {
        VStack(spacing: 16) {
            Text("Add Output")
                .font(.headline)

            Picker("Profile", selection: $selectedProfile) {
                Text("Select a profile...")
                    .tag(EncodingProfile?.none)
                ForEach(viewModel.engine.profileStore.profiles) { profile in
                    Text(profile.name)
                        .tag(EncodingProfile?.some(profile))
                }
            }

            HStack {
                Button("Cancel") {
                    showAddSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addOutput()
                    showAddSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProfile == nil || sourceURL == nil)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    // MARK: - Actions

    /// Open a file browser to select the source media file.
    private func browseForSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the source media file"

        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
        }
    }

    /// Add a new output specification using the selected profile.
    private func addOutput() {
        guard let profile = selectedProfile, let source = sourceURL else { return }

        let ext = profile.containerFormat.rawValue
        let baseName = source.deletingPathExtension().lastPathComponent
        let outputDir = source.deletingLastPathComponent()
        let outputURL = outputDir
            .appendingPathComponent("\(baseName)_\(profile.name.replacingOccurrences(of: " ", with: "_"))")
            .appendingPathExtension(ext)

        let spec = OutputSpec(
            profile: profile,
            outputURL: outputURL
        )
        outputs.append(spec)
        selectedProfile = nil
    }

    /// Remove an output specification by ID.
    private func removeOutput(_ id: UUID) {
        outputs.removeAll { $0.id == id }
    }

    /// Update the tee compatibility flag based on current outputs.
    private func updateTeeCompatibility() {
        teeCompatible = MultiOutputEncoder.canUseTee(outputs: outputs)
        if !teeCompatible {
            useTee = false
        }
    }
}
