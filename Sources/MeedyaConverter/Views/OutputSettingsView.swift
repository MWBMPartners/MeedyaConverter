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
/// Provides profile selection, passthrough toggles, container/codec
/// configuration, quality settings, HDR awareness, stream selection,
/// and output directory selection.
struct OutputSettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var showProfileManager = false
    @State private var showStreamMetadataEditor = false

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
        .sheet(isPresented: $showStreamMetadataEditor) {
            if let file = viewModel.selectedFile {
                StreamMetadataEditorView(mediaFile: file)
            }
        }
    }

    // MARK: - Settings Form

    private var settingsForm: some View {
        @Bindable var vm = viewModel

        return Form {
            // Profile selection
            Section("Encoding Profile") {
                profilePicker
                profileDescription
                Button("Manage Profiles...") {
                    showProfileManager = true
                }
                .font(.caption)
            }

            // Passthrough options (Phase 3.1–3.3)
            Section("Passthrough") {
                passthroughToggles
            }

            // Video settings
            Section("Video") {
                videoSettingsSummary
                hdrWarning
            }

            // Audio settings
            Section("Audio") {
                audioSettingsSummary
            }

            // Stream selection
            if let file = viewModel.selectedFile {
                Section("Stream Selection") {
                    streamSelectionControls(file: file)
                }
            }

            // Output destination
            Section("Output") {
                outputDirectoryPicker
                containerInfo
            }

            // Actions
            Section {
                HStack {
                    addToQueueButton
                    Spacer()
                    Button("Edit Stream Metadata...") {
                        showStreamMetadataEditor = true
                    }
                    .disabled(viewModel.selectedFile == nil)
                }
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
    }

    @ViewBuilder
    private var profileDescription: some View {
        if !viewModel.selectedProfile.description.isEmpty {
            Text(viewModel.selectedProfile.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Passthrough Toggles (Phase 3.1–3.3)

    @ViewBuilder
    private var passthroughToggles: some View {
        @Bindable var vm = viewModel

        Toggle("Video Passthrough (copy without re-encoding)", isOn: $vm.selectedProfile.videoPassthrough)
            .accessibilityLabel("Copy video stream without re-encoding")

        Toggle("Audio Passthrough (copy without re-encoding)", isOn: $vm.selectedProfile.audioPassthrough)
            .accessibilityLabel("Copy audio stream without re-encoding")

        Toggle("Subtitle Passthrough (copy to output)", isOn: $vm.selectedProfile.subtitlePassthrough)
            .accessibilityLabel("Copy subtitle streams to output")

        if viewModel.selectedProfile.videoPassthrough && viewModel.selectedProfile.audioPassthrough {
            Text("Both video and audio are set to passthrough — the output will be a remux (no re-encoding).")
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
            if let video = viewModel.selectedFile?.primaryVideoStream {
                LabeledContent("Source Codec", value: video.videoCodec?.displayName ?? video.codecName ?? "Unknown")
                if let res = video.resolutionString {
                    LabeledContent("Resolution", value: res)
                }
            }
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

    // MARK: - HDR Warning (Phase 3.7, 3.9c)

    @ViewBuilder
    private var hdrWarning: some View {
        if let file = viewModel.selectedFile, file.hasHDR {
            let profile = viewModel.selectedProfile

            // Show HDR badge
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.purple)
                Text("Source contains HDR content")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.purple)

                if file.hasDolbyVision {
                    Text("DV")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.2))
                        .clipShape(Capsule())
                }
                if file.hasHDR10Plus {
                    Text("HDR10+")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            // Warn if encoding to non-HDR codec without passthrough
            if !profile.videoPassthrough && !profile.preserveHDR {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("HDR will not be preserved. Enable 'Preserve HDR' in the profile or use video passthrough.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Warn if encoding to H.264 (doesn't support HDR well)
            if !profile.videoPassthrough, let codec = profile.videoCodec,
               !codec.supportsHDR && profile.preserveHDR {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(codec.displayName) has limited HDR support. Consider H.265, AV1, or video passthrough.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Audio Settings

    @ViewBuilder
    private var audioSettingsSummary: some View {
        let profile = viewModel.selectedProfile

        if profile.audioPassthrough {
            LabeledContent("Mode", value: "Passthrough (copy)")
            if let audio = viewModel.selectedFile?.primaryAudioStream {
                LabeledContent("Source Codec", value: audio.audioCodec?.displayName ?? audio.codecName ?? "Unknown")
                if let layout = audio.channelLayout {
                    LabeledContent("Channels", value: layout.displayName)
                }
            }
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

    // MARK: - Stream Selection (Phase 3.4–3.5)

    @ViewBuilder
    private func streamSelectionControls(file: MediaFile) -> some View {
        @Bindable var vm = viewModel

        // Video stream picker
        if file.videoStreams.count > 1 {
            Picker("Video Stream", selection: $vm.selectedVideoStreamIndex) {
                Text("Default").tag(nil as Int?)
                ForEach(file.videoStreams, id: \.streamIndex) { stream in
                    Text("#\(stream.streamIndex): \(stream.summaryString)")
                        .tag(stream.streamIndex as Int?)
                }
            }
            .accessibilityLabel("Select video stream")
        }

        // Audio stream picker
        if file.audioStreams.count > 1 {
            Picker("Audio Stream", selection: $vm.selectedAudioStreamIndex) {
                Text("Default").tag(nil as Int?)
                ForEach(file.audioStreams, id: \.streamIndex) { stream in
                    Text("#\(stream.streamIndex): \(stream.summaryString)")
                        .tag(stream.streamIndex as Int?)
                }
            }
            .accessibilityLabel("Select audio stream")
        }

        // Subtitle stream picker
        if !file.subtitleStreams.isEmpty {
            Picker("Subtitle Stream", selection: $vm.selectedSubtitleStreamIndex) {
                Text("None").tag(nil as Int?)
                ForEach(file.subtitleStreams, id: \.streamIndex) { stream in
                    Text("#\(stream.streamIndex): \(stream.summaryString)")
                        .tag(stream.streamIndex as Int?)
                }
            }
            .accessibilityLabel("Select subtitle stream")
        }

        // Map all streams toggle
        Toggle("Map all streams to output", isOn: $vm.mapAllStreams)
            .accessibilityLabel("Include all streams from source in output")
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

// MARK: - StreamMetadataEditorView (Phase 3.6)

/// Editor for per-stream metadata: title, language, default/forced flags.
struct StreamMetadataEditorView: View {
    let mediaFile: MediaFile
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    @State private var streamMetadata: [Int: StreamMetadataEntry] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Stream Metadata Editor")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Apply") {
                    applyMetadata()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Stream list
            List {
                ForEach(mediaFile.streams) { stream in
                    streamMetadataRow(stream)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { loadExistingMetadata() }
    }

    private func streamMetadataRow(_ stream: MediaStream) -> some View {
        let entry = binding(for: stream.streamIndex)

        return VStack(alignment: .leading, spacing: 8) {
            // Stream header
            HStack {
                Text("\(stream.streamType.rawValue.capitalized) #\(stream.streamIndex)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(stream.summaryString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Editable fields
            HStack {
                TextField("Title", text: entry.title,
                          prompt: Text(stream.title ?? "Untitled"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                TextField("Language (BCP 47)", text: entry.language,
                          prompt: Text(stream.language ?? "und"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)

                Toggle("Default", isOn: entry.isDefault)
                Toggle("Forced", isOn: entry.isForced)
            }
        }
        .padding(.vertical, 4)
    }

    private func binding(for index: Int) -> Binding<StreamMetadataEntry> {
        Binding(
            get: { streamMetadata[index] ?? StreamMetadataEntry() },
            set: { streamMetadata[index] = $0 }
        )
    }

    private func loadExistingMetadata() {
        for stream in mediaFile.streams {
            streamMetadata[stream.streamIndex] = StreamMetadataEntry(
                title: stream.title ?? "",
                language: stream.language ?? "",
                isDefault: stream.isDefault,
                isForced: stream.isForced
            )
        }
    }

    private func applyMetadata() {
        var metadata: [String: [String: String]] = [:]

        for (index, entry) in streamMetadata {
            let stream = mediaFile.streams.first { $0.streamIndex == index }
            guard let streamType = stream?.streamType else { continue }

            let spec: String
            switch streamType {
            case .video: spec = "s:v:\(index)"
            case .audio: spec = "s:a:\(index)"
            case .subtitle: spec = "s:s:\(index)"
            default: spec = "s:\(index)"
            }

            var tags: [String: String] = [:]
            if !entry.title.isEmpty { tags["title"] = entry.title }
            if !entry.language.isEmpty { tags["language"] = entry.language }

            if !tags.isEmpty {
                metadata[spec] = tags
            }
        }

        viewModel.streamMetadataOverrides = metadata
        viewModel.appendLog(.info, "Applied stream metadata overrides for \(metadata.count) streams",
                            category: .metadata)
    }
}

/// Editable metadata for a single stream.
struct StreamMetadataEntry {
    var title: String = ""
    var language: String = ""
    var isDefault: Bool = false
    var isForced: Bool = false
}
