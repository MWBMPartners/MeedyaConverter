// ============================================================================
// MeedyaConverter — ProfileManagementView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - ProfileManagementView

/// Full profile management interface for creating, editing, deleting,
/// importing, and exporting encoding profiles.
///
/// Presented as a sheet from the Output Settings view. Shows all
/// built-in and user profiles with search/filter, and allows CRUD
/// operations plus JSON import/export.
struct ProfileManagementView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedCategory: ProfileCategory?
    @State private var selectedProfileID: UUID?
    @State private var isEditing = false
    @State private var editingProfile: EncodingProfile?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: EncodingProfile?
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            profileListSidebar
        } detail: {
            profileDetailView
        }
        .navigationTitle("Encoding Profiles")
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                profileToolbar
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let profile = editingProfile {
                ProfileEditorView(
                    profile: profile,
                    isNew: editingProfile?.id != selectedProfileID,
                    onSave: { saved in
                        saveProfile(saved)
                        isEditing = false
                    },
                    onCancel: {
                        isEditing = false
                    }
                )
            }
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    viewModel.engine.profileStore.deleteProfile(id: profile.id)
                    if selectedProfileID == profile.id {
                        selectedProfileID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete \"\(profile.name)\"? This cannot be undone.")
            }
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage)
        }
    }

    // MARK: - Profile List Sidebar

    private var profileListSidebar: some View {
        List(selection: $selectedProfileID) {
            // Category filter
            Section("Categories") {
                Button {
                    selectedCategory = nil
                } label: {
                    Label("All Profiles", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .fontWeight(selectedCategory == nil ? .semibold : .regular)

                ForEach(ProfileCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.displayName, systemImage: categoryIcon(category))
                    }
                    .buttonStyle(.plain)
                    .fontWeight(selectedCategory == category ? .semibold : .regular)
                }
            }

            // Profile list
            Section("Profiles") {
                ForEach(filteredProfiles) { profile in
                    ProfileListRow(profile: profile)
                        .tag(profile.id)
                        .contextMenu {
                            profileContextMenu(for: profile)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search profiles...")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var profileDetailView: some View {
        if let profileID = selectedProfileID,
           let profile = viewModel.engine.profileStore.profile(id: profileID) {
            ProfileDetailView(profile: profile) {
                applyProfile(profile)
            }
        } else {
            ContentUnavailableView(
                "Select a Profile",
                systemImage: "slider.horizontal.3",
                description: Text("Choose a profile from the list to view its settings.")
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var profileToolbar: some View {
        // New profile
        Button("New Profile", systemImage: "plus") {
            editingProfile = EncodingProfile(name: "New Profile", description: "", category: .custom)
            isEditing = true
        }
        .help("Create a new encoding profile")

        // Import
        Button("Import", systemImage: "square.and.arrow.down") {
            importProfile()
        }
        .help("Import a profile from a JSON file")

        // Export
        Button("Export", systemImage: "square.and.arrow.up") {
            if let id = selectedProfileID,
               let profile = viewModel.engine.profileStore.profile(id: id) {
                exportProfile(profile)
            }
        }
        .disabled(selectedProfileID == nil)
        .help("Export selected profile as JSON")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func profileContextMenu(for profile: EncodingProfile) -> some View {
        Button("Apply to Current Job") {
            applyProfile(profile)
        }

        Button("Duplicate") {
            duplicateProfile(profile)
        }

        if !profile.isBuiltIn {
            Button("Edit") {
                editingProfile = profile
                isEditing = true
            }
        }

        Button("Export") {
            exportProfile(profile)
        }

        if !profile.isBuiltIn {
            Divider()
            Button("Delete", role: .destructive) {
                profileToDelete = profile
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Filtering

    private var filteredProfiles: [EncodingProfile] {
        viewModel.engine.profileStore.profiles.filter { profile in
            // Category filter
            if let category = selectedCategory, profile.category != category {
                return false
            }
            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return profile.name.lowercased().contains(query) ||
                       profile.description.lowercased().contains(query)
            }
            return true
        }
    }

    // MARK: - Actions

    private func applyProfile(_ profile: EncodingProfile) {
        viewModel.selectedProfile = profile
        viewModel.appendLog(.info, "Applied profile: \(profile.name)")
        dismiss()
    }

    private func duplicateProfile(_ profile: EncodingProfile) {
        let copy = EncodingProfile(
            name: "\(profile.name) (Copy)",
            description: profile.description,
            category: .custom,
            isBuiltIn: false,
            videoCodec: profile.videoCodec,
            videoPassthrough: profile.videoPassthrough,
            videoCRF: profile.videoCRF,
            videoQP: profile.videoQP,
            videoBitrate: profile.videoBitrate,
            videoMaxBitrate: profile.videoMaxBitrate,
            videoPreset: profile.videoPreset,
            videoTune: profile.videoTune,
            outputWidth: profile.outputWidth,
            outputHeight: profile.outputHeight,
            outputFrameRate: profile.outputFrameRate,
            pixelFormat: profile.pixelFormat,
            useHardwareEncoding: profile.useHardwareEncoding,
            encodingPasses: profile.encodingPasses,
            preserveHDR: profile.preserveHDR,
            audioCodec: profile.audioCodec,
            audioPassthrough: profile.audioPassthrough,
            audioBitrate: profile.audioBitrate,
            audioSampleRate: profile.audioSampleRate,
            audioChannels: profile.audioChannels,
            subtitlePassthrough: profile.subtitlePassthrough,
            containerFormat: profile.containerFormat,
            keyframeIntervalSeconds: profile.keyframeIntervalSeconds,
            videoBufferSize: profile.videoBufferSize
        )
        viewModel.engine.profileStore.addProfile(copy)
        selectedProfileID = copy.id
        viewModel.appendLog(.info, "Duplicated profile: \(profile.name)")
    }

    private func saveProfile(_ profile: EncodingProfile) {
        if viewModel.engine.profileStore.profile(id: profile.id) != nil {
            viewModel.engine.profileStore.updateProfile(profile)
        } else {
            viewModel.engine.profileStore.addProfile(profile)
        }
        selectedProfileID = profile.id
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Encoding Profile"
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try viewModel.engine.profileStore.importProfile(from: data)
            selectedProfileID = imported.id
            viewModel.appendLog(.info, "Imported profile: \(imported.name)")
        } catch {
            importErrorMessage = "Could not import profile: \(error.localizedDescription)"
            showImportError = true
        }
    }

    private func exportProfile(_ profile: EncodingProfile) {
        let panel = NSSavePanel()
        panel.title = "Export Encoding Profile"
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try viewModel.engine.profileStore.exportProfile(profile)
            try data.write(to: url, options: .atomic)
            viewModel.appendLog(.info, "Exported profile: \(profile.name) to \(url.lastPathComponent)")
        } catch {
            viewModel.appendLog(.error, "Failed to export profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ category: ProfileCategory) -> String {
        switch category {
        case .quickStart: return "bolt"
        case .streaming: return "play.tv"
        case .disc: return "opticaldisc"
        case .archival: return "archivebox"
        case .custom: return "wrench"
        }
    }
}

// MARK: - ProfileListRow

/// A single row in the profile list showing name, category, and built-in badge.
struct ProfileListRow: View {
    let profile: EncodingProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(profile.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if profile.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Text(profile.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)\(profile.isBuiltIn ? ", built-in" : ""): \(profile.description)")
    }
}

// MARK: - ProfileDetailView

/// Detailed view of a single profile showing all encoding settings.
struct ProfileDetailView: View {
    let profile: EncodingProfile
    let onApply: () -> Void

    var body: some View {
        ScrollView {
            Form {
                // Identity
                Section("Profile") {
                    LabeledContent("Name", value: profile.name)
                    LabeledContent("Category", value: profile.category.displayName)
                    if !profile.description.isEmpty {
                        LabeledContent("Description", value: profile.description)
                    }
                    LabeledContent("Type", value: profile.isBuiltIn ? "Built-in (read-only)" : "Custom")
                }

                // Video
                Section("Video Settings") {
                    if profile.videoPassthrough {
                        LabeledContent("Mode", value: "Passthrough (copy)")
                    } else if let codec = profile.videoCodec {
                        LabeledContent("Codec", value: codec.displayName)
                        if let crf = profile.videoCRF {
                            LabeledContent("Quality (CRF)", value: "\(crf)")
                        }
                        if let qp = profile.videoQP {
                            LabeledContent("QP", value: "\(qp)")
                        }
                        if let bitrate = profile.videoBitrate {
                            LabeledContent("Bitrate", value: formatBitrate(bitrate))
                        }
                        if let preset = profile.videoPreset {
                            LabeledContent("Preset", value: preset)
                        }
                        if let tune = profile.videoTune {
                            LabeledContent("Tune", value: tune)
                        }
                        if let w = profile.outputWidth, let h = profile.outputHeight {
                            LabeledContent("Resolution", value: "\(w)x\(h)")
                        }
                        if let fps = profile.outputFrameRate {
                            LabeledContent("Frame Rate", value: String(format: "%.3g fps", fps))
                        }
                        if let pf = profile.pixelFormat {
                            LabeledContent("Pixel Format", value: pf)
                        }
                        LabeledContent("Hardware Encoding", value: profile.useHardwareEncoding ? "Yes" : "No")
                        LabeledContent("Passes", value: "\(profile.encodingPasses)")
                        LabeledContent("Preserve HDR", value: profile.preserveHDR ? "Yes" : "No")
                    } else {
                        Text("No video encoding")
                            .foregroundStyle(.secondary)
                    }
                }

                // Audio
                Section("Audio Settings") {
                    if profile.audioPassthrough {
                        LabeledContent("Mode", value: "Passthrough (copy)")
                    } else if let codec = profile.audioCodec {
                        LabeledContent("Codec", value: codec.displayName)
                        if let bitrate = profile.audioBitrate {
                            LabeledContent("Bitrate", value: formatBitrate(bitrate))
                        }
                        if let sr = profile.audioSampleRate {
                            LabeledContent("Sample Rate", value: "\(sr) Hz")
                        }
                        if let ch = profile.audioChannels {
                            LabeledContent("Channels", value: "\(ch)")
                        }
                    } else {
                        Text("No audio encoding")
                            .foregroundStyle(.secondary)
                    }
                }

                // Container & Subtitles
                Section("Container & Subtitles") {
                    LabeledContent("Container", value: profile.containerFormat.displayName)
                    LabeledContent("Subtitle Passthrough", value: profile.subtitlePassthrough ? "Yes" : "No")
                    if let kf = profile.keyframeIntervalSeconds {
                        LabeledContent("Keyframe Interval", value: String(format: "%.1f sec", kf))
                    }
                }

                // Apply button
                Section {
                    Button {
                        onApply()
                    } label: {
                        Label("Apply Profile", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle(profile.name)
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d kbps", bps / 1000)
        }
    }
}

// MARK: - ProfileEditorView

/// Form-based editor for creating or editing an encoding profile.
struct ProfileEditorView: View {
    @State var profile: EncodingProfile
    let isNew: Bool
    let onSave: (EncodingProfile) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Profile" : "Edit Profile")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { onSave(profile) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Editor form
            Form {
                Section("Identity") {
                    TextField("Name", text: $profile.name)
                    TextField("Description", text: $profile.description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Category", selection: $profile.category) {
                        ForEach(ProfileCategory.allCases, id: \.self) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                }

                Section("Video") {
                    Toggle("Video Passthrough", isOn: $profile.videoPassthrough)

                    if !profile.videoPassthrough {
                        Picker("Codec", selection: $profile.videoCodec) {
                            Text("None").tag(nil as VideoCodec?)
                            ForEach(VideoCodec.allCases.filter { $0.canEncode }, id: \.self) { codec in
                                Text(codec.displayName).tag(codec as VideoCodec?)
                            }
                        }

                        HStack {
                            Text("CRF")
                            Slider(value: Binding(
                                get: { Double(profile.videoCRF ?? 22) },
                                set: { profile.videoCRF = Int($0) }
                            ), in: 0...51, step: 1)
                            Text("\(profile.videoCRF ?? 22)")
                                .monospacedDigit()
                                .frame(width: 30)
                        }

                        TextField("Preset", text: Binding(
                            get: { profile.videoPreset ?? "" },
                            set: { profile.videoPreset = $0.isEmpty ? nil : $0 }
                        ))

                        TextField("Tune", text: Binding(
                            get: { profile.videoTune ?? "" },
                            set: { profile.videoTune = $0.isEmpty ? nil : $0 }
                        ))

                        Toggle("Hardware Encoding", isOn: $profile.useHardwareEncoding)
                        Toggle("Preserve HDR", isOn: $profile.preserveHDR)

                        Picker("Passes", selection: $profile.encodingPasses) {
                            Text("1-pass").tag(1)
                            Text("2-pass").tag(2)
                        }
                    }
                }

                Section("Audio") {
                    Toggle("Audio Passthrough", isOn: $profile.audioPassthrough)

                    if !profile.audioPassthrough {
                        Picker("Codec", selection: $profile.audioCodec) {
                            Text("None").tag(nil as AudioCodec?)
                            ForEach(AudioCodec.allCases.filter { $0.canEncode }, id: \.self) { codec in
                                Text(codec.displayName).tag(codec as AudioCodec?)
                            }
                        }

                        TextField("Bitrate (bps)", value: $profile.audioBitrate, format: .number)
                        TextField("Sample Rate (Hz)", value: $profile.audioSampleRate, format: .number)
                        TextField("Channels", value: $profile.audioChannels, format: .number)
                    }
                }

                Section("Container & Subtitles") {
                    Picker("Container", selection: $profile.containerFormat) {
                        ForEach(ContainerFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Toggle("Subtitle Passthrough", isOn: $profile.subtitlePassthrough)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 550, minHeight: 500)
    }
}
