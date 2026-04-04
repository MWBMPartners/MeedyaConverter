// ============================================================================
// MeedyaConverter — OutputSettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - OutputSettingsView

/// The output settings view for configuring encoding parameters.
///
/// Provides profile selection, container/codec configuration, quality
/// settings, and output directory selection. Settings are applied to
/// the next encoding job created from the selected source file.
struct OutputSettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var showProfileManager = false

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.selectedFile != nil {
                settingsForm
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "gearshape.2",
                    description: Text("Import and select a source file to configure output settings.")
                )
            }
        }
        .navigationTitle("Output Settings")
        .sheet(isPresented: $showProfileManager) {
            ProfileManagementView()
        }
    }

    // MARK: - Settings Form

    private var settingsForm: some View {
        Form {
            // Profile selection
            Section("Encoding Profile") {
                profilePicker
                profileDescription
                Button("Manage Profiles...") {
                    showProfileManager = true
                }
                .font(.caption)
            }

            // Video settings summary (read-only from profile)
            Section("Video") {
                videoSettingsSummary
            }

            // Audio settings summary (read-only from profile)
            Section("Audio") {
                audioSettingsSummary
            }

            // Output destination
            Section("Output") {
                outputDirectoryPicker
                containerInfo
            }

            // Action
            Section {
                addToQueueButton
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Profile Picker

    private var profilePicker: some View {
        @Bindable var vm = viewModel

        return Picker("Profile", selection: $vm.selectedProfile) {
            ForEach(ProfileCategory.allCases, id: \.self) { category in
                let categoryProfiles = viewModel.engine.profileStore.profiles.filter {
                    $0.category == category
                }
                if !categoryProfiles.isEmpty {
                    Section(category.displayName) {
                        ForEach(categoryProfiles) { profile in
                            Text(profile.name).tag(profile)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Encoding profile")
        .accessibilityHint("Select a preset for encoding settings")
    }

    @ViewBuilder
    private var profileDescription: some View {
        if !viewModel.selectedProfile.description.isEmpty {
            Text(viewModel.selectedProfile.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Video Settings

    @ViewBuilder
    private var videoSettingsSummary: some View {
        let profile = viewModel.selectedProfile

        if profile.videoPassthrough {
            LabeledContent("Mode", value: "Passthrough (copy)")
        } else if let codec = profile.videoCodec {
            LabeledContent("Codec", value: codec.displayName)

            if let crf = profile.videoCRF {
                LabeledContent("Quality (CRF)", value: "\(crf)")
            }
            if let preset = profile.videoPreset {
                LabeledContent("Preset", value: preset)
            }
            if profile.useHardwareEncoding {
                LabeledContent("Acceleration", value: "Hardware (VideoToolbox)")
            }
            if profile.preserveHDR {
                LabeledContent("HDR", value: "Preserve")
            }
            if profile.encodingPasses > 1 {
                LabeledContent("Passes", value: "\(profile.encodingPasses)")
            }
        } else {
            Text("No video encoding")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Audio Settings

    @ViewBuilder
    private var audioSettingsSummary: some View {
        let profile = viewModel.selectedProfile

        if profile.audioPassthrough {
            LabeledContent("Mode", value: "Passthrough (copy)")
        } else if let codec = profile.audioCodec {
            LabeledContent("Codec", value: codec.displayName)

            if let bitrate = profile.audioBitrate {
                LabeledContent("Bitrate", value: formatBitrate(bitrate))
            }
            if let channels = profile.audioChannels {
                LabeledContent("Channels", value: "\(channels)")
            }
        } else {
            Text("No audio encoding")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Output Directory

    private var outputDirectoryPicker: some View {
        HStack {
            LabeledContent("Destination") {
                Text(viewModel.outputDirectory?.lastPathComponent ?? "Not set")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button("Choose...") {
                chooseOutputDirectory()
            }
        }
        .accessibilityLabel("Output destination directory")
    }

    private var containerInfo: some View {
        LabeledContent("Container", value: viewModel.selectedProfile.containerFormat.displayName)
    }

    // MARK: - Queue Button

    private var addToQueueButton: some View {
        Button {
            viewModel.enqueueSelectedFile()
        } label: {
            Label("Add to Queue", systemImage: "plus.circle")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.selectedFile == nil)
        .accessibilityLabel("Add selected file to encoding queue")
    }

    // MARK: - Helpers

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if let current = viewModel.outputDirectory {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.outputDirectory = url
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d kbps", bps / 1000)
        }
    }
}
