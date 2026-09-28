// ============================================================================
// MeedyaConverter — OutputSettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine
import MediaLanguagePolicy

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
    @State private var showPerStreamSettings = false
    @State private var showNormalizationSettings = false
    @State private var showFFmpegPreview = false
    @State private var showQualityPreview = false

    // MARK: - AppStorage (Issue #272)

    /// User-configured output filename template.
    @AppStorage("filenameTemplate") private var filenameTemplate = "{title}_converted"

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
        .sheet(isPresented: $showPerStreamSettings) {
            if let file = viewModel.selectedFile {
                PerStreamSettingsView(mediaFile: file)
            }
        }
        .sheet(isPresented: $showNormalizationSettings) {
            NormalizationSettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showFFmpegPreview) {
            FFmpegPreviewView()
        }
        .sheet(isPresented: $showQualityPreview) {
            if let file = viewModel.selectedFile {
                QualityPreviewView(sourceFile: file, profile: viewModel.selectedProfile)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showPipelineEditor },
            set: { viewModel.showPipelineEditor = $0 }
        )) {
            PipelineEditorView(onSave: { viewModel.savePipeline($0) })
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showScheduleView },
            set: { viewModel.showScheduleView = $0 }
        )) {
            ScheduleView()
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
                if let file = viewModel.selectedFile {
                    ProfileSuggestionView(
                        sourceFile: file,
                        profiles: viewModel.engine.profileStore.profiles,
                        onSelectProfile: { profile in viewModel.selectedProfile = profile }
                    )
                    .id(file.id)   // REQUIRED: resets the view's @State suggestions/hasComputed when the file changes
                }
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
                pqToHLGControls
                hardwareEncoderInfo
                cropDetectionControls
                deinterlacePicker
            }

            // Audio settings
            Section("Audio") {
                audioSettingsSummary

                // Audio normalization (Issue #292)
                Button("Normalization Settings...") {
                    showNormalizationSettings = true
                }
                .font(.caption)
            }

            // Subtitle tone-mapping (Issues #369 engine, #381 / #396 UI)
            Section("Subtitles") {
                subtitleTonemapControls
            }

            // Stream selection
            if let file = viewModel.selectedFile {
                Section("Stream Selection") {
                    streamSelectionControls(file: file)
                }

                // Per-stream encoding settings (Phase 3.5 / Issue #41)
                Section("Per-Stream Encoding") {
                    perStreamSettingsSummary(file: file)

                    Button("Configure Per-Stream Settings...") {
                        showPerStreamSettings = true
                    }
                    .font(.caption)
                }
            }

            // Compatibility warnings
            if !compatibilityWarnings.isEmpty {
                Section("Compatibility") {
                    ForEach(compatibilityWarnings, id: \.self) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Output destination
            Section("Output") {
                outputDirectoryPicker
                outputModePicker
                containerInfo
                trackOrderToggle
                filenameTemplateField
            }

            // Size estimate (Issue #274)
            if let file = viewModel.selectedFile {
                Section("Size Estimate") {
                    sizeEstimateView(file: file)
                }
            }

            // Pipeline & Scheduling (Issues #278, #279)
            Section("Automation") {
                HStack {
                    Button("Pipeline Editor...") {
                        viewModel.showPipelineEditor = true
                    }
                    .help("Configure multi-step encoding pipelines.")

                    Button("Schedule Encoding...") {
                        viewModel.showScheduleView = true
                    }
                    .disabled(viewModel.selectedFile == nil)
                    .help("Schedule this job to run at a specific time.")
                }
            }

            // Actions
            Section {
                HStack {
                    addToQueueButton
                    Spacer()
                    Button("Preview FFmpeg Command...") {
                        showFFmpegPreview = true
                    }
                    .disabled(viewModel.selectedFile == nil)
                    .accessibilityLabel("Preview the FFmpeg command that will be generated")
                    Button("Quality Preview...") {
                        showQualityPreview = true
                    }
                    .disabled(viewModel.selectedFile == nil)
                    .accessibilityLabel("Preview quality comparison between source and encoded output")
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
        // A custom binding so a user picking a profile registers an undoable
        // change (#330). Undo restores the previous profile via the manager's
        // key-path write, which does NOT come back through this setter, so
        // there is no re-registration loop.
        let selection = Binding<EncodingProfile>(
            get: { viewModel.selectedProfile },
            set: { newProfile in
                let old = viewModel.selectedProfile
                guard old != newProfile else { return }
                viewModel.selectedProfile = newProfile
                viewModel.settingsUndoManager.registerUndo(
                    for: \.selectedProfile,
                    on: viewModel,
                    oldValue: old,
                    newValue: newProfile,
                    description: "Profile Change"
                )
            }
        )

        return Picker("Profile", selection: selection) {
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

    // MARK: - Subtitle Tone-Mapping (Issues #369 engine / #381 / #396 UI)
    //
    // HDR subtitle tone-mapping converts the colour values of PGS / VobSub
    // / ASS subtitles from the HDR source's gamut into an SDR-friendly
    // gamut, so that subtitles remain legible when the rest of the
    // pipeline tone-maps the video. The engine is `SubtitleTonemapWrapper`
    // in `ConverterEngine.Utilities` — see issue #369.
    //
    // UI design:
    //  * Master toggle binds to `EncodingProfile.subtitleTonemap != nil`.
    //    Turning it on installs a default `SubtitleTonemapConfig`;
    //    turning it off clears the config to `nil` so the profile JSON
    //    on disk stays small for users who don't need this.
    //  * The picker / stepper / alpha toggle are only rendered when the
    //    master is on, so the section stays visually quiet by default.
    //  * Each subordinate control is bound through a non-optional
    //    `Binding<SubtitleTonemapConfig>` that round-trips through the
    //    optional on the profile.

    @ViewBuilder
    private var subtitleTonemapControls: some View {
        @Bindable var vm = viewModel

        // Master enable toggle — flips the optional config on/off.
        // When the user turns it on we install a default config so the
        // subordinate controls have something to bind against.
        let isEnabled = Binding<Bool>(
            get: { vm.selectedProfile.subtitleTonemap != nil },
            set: { newValue in
                vm.selectedProfile.subtitleTonemap =
                    newValue ? SubtitleTonemapConfig() : nil
            }
        )

        Toggle("Tone-map HDR subtitle colours", isOn: isEnabled)
            .accessibilityLabel("Enable HDR-to-SDR subtitle colour tone-mapping")
            .help(
                "When enabled, PGS / VobSub / ASS subtitles are passed through "
                + "subtitle_tonemap to remap their colour values from the HDR "
                + "source's gamut into an SDR-friendly gamut, keeping them "
                + "legible on tone-mapped output."
            )

        if vm.selectedProfile.subtitleTonemap != nil {
            // Non-optional binding into the wrapped config. The setter
            // never sees a nil because the surrounding `if` already
            // guaranteed the config exists when these controls render;
            // the getter has a defensive default to satisfy the type
            // system in the unlikely case the optional flips during
            // a SwiftUI redraw race.
            let config = Binding<SubtitleTonemapConfig>(
                get: { vm.selectedProfile.subtitleTonemap ?? SubtitleTonemapConfig() },
                set: { vm.selectedProfile.subtitleTonemap = $0 }
            )

            // Picker — HDR source profile. `SubtitleHDRSourceProfile`
            // conforms to `CaseIterable` and `Identifiable` via its
            // raw value, so we iterate over `allCases` and use the
            // case itself as the tag.
            Picker("HDR source profile", selection: config.sourceProfile) {
                ForEach(SubtitleHDRSourceProfile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .accessibilityLabel("HDR source profile for subtitle tone-mapping")

            // Stepper — target SDR peak luminance in nits.
            // The acceptance criteria pin the range to 50–200 with a
            // step of 10. The default of 100 matches the engine config
            // default (`SubtitleTonemapConfig.targetLuminanceNits`).
            Stepper(
                value: config.targetLuminanceNits,
                in: 50...200,
                step: 10
            ) {
                HStack {
                    Text("Target luminance")
                    Spacer()
                    Text("\(Int(config.wrappedValue.targetLuminanceNits)) nits")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(
                "Target SDR peak luminance in nits — typically 100"
            )

            // Toggle — preserve alpha on PGS. Important for PGS
            // subtitles which carry per-pixel alpha; users colour-
            // grading their output to dark levels will usually want
            // this on so subtitle edges don't develop hard halos.
            Toggle("Preserve alpha on PGS", isOn: config.preserveAlpha)
                .accessibilityLabel(
                    "Preserve per-pixel alpha on PGS subtitles during tone-mapping"
                )
        }
    }

    // MARK: - Video Settings

    /// Deinterlace preset picker (Issue #324), bound to the profile's
    /// `deinterlace`. `DeinterlacePresets.buildFilterString` is applied as the
    /// first `-vf` stage at encode. "Best" (nnedi) is omitted — it needs an
    /// external nnedi3 weights file the bundled ffmpeg may lack; yadif/bwdif
    /// are built in. Disabled for passthrough (a copied stream can't be
    /// filtered).
    private var deinterlacePicker: some View {
        @Bindable var vm = viewModel
        return Picker("Deinterlace", selection: $vm.selectedProfile.deinterlace) {
            Text("Off").tag(Optional<DeinterlaceConfig>.none)
            Text("Fast (yadif)").tag(Optional(DeinterlacePresets.fast))
            Text("Quality (bwdif, 2x fps)").tag(Optional(DeinterlacePresets.quality))
        }
        .disabled(viewModel.selectedProfile.videoPassthrough)
    }

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

    // MARK: - PQ → HLG Controls (Issue #254)

    @ViewBuilder
    private var pqToHLGControls: some View {
        @Bindable var vm = viewModel

        if let file = viewModel.selectedFile, file.hasPQ,
           !viewModel.selectedProfile.videoPassthrough,
           !viewModel.selectedProfile.toneMapToSDR {

            Toggle("Convert PQ to HLG (broadcast HDR)", isOn: $vm.selectedProfile.convertPQToHLG)
                .accessibilityLabel("Convert PQ HDR to HLG HDR for broadcast compatibility")

            if viewModel.selectedProfile.convertPQToHLG {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.cyan)
                    Text("PQ (ST 2084) → HLG (ARIB STD-B67) — preserves HDR, changes transfer for broadcast")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }

                // DV+HLG combined option (Issue #255)
                if viewModel.selectedProfile.videoCodec == .h265,
                   viewModel.selectedProfile.containerFormat.supportsDolbyVision {
                    Toggle("Add Dolby Vision Profile 8.4 (DV + HLG + SDR fallback)", isOn: $vm.selectedProfile.convertPQToDVHLG)
                        .accessibilityLabel("Generate Dolby Vision metadata for three-tier compatibility")

                    if viewModel.selectedProfile.convertPQToDVHLG {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("Three-tier output: Dolby Vision → HLG → SDR fallback")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }

                        if !viewModel.engine.doviTool.isAvailable {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("dovi_tool not found — DV metadata will be skipped, HLG output only.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if viewModel.engine.isHlgToolsAvailable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using hlg-tools for higher quality PQ→HLG conversion")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if let version = viewModel.engine.hlgToolsVersion {
                        Text("hlg-tools \(version) detected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Force FFmpeg zscale filter instead", isOn: Binding(
                        get: { !vm.selectedProfile.useHlgTools },
                        set: { vm.selectedProfile.useHlgTools = !$0 }
                    ))
                    .font(.caption)
                } else {
                    Text("Using FFmpeg zscale filter. Install hlg-tools (github.com/wswartzendruber/hlg-tools) for higher quality.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Hardware Encoder Info (Phase 3.10)

    @ViewBuilder
    private var hardwareEncoderInfo: some View {
        let profile = viewModel.selectedProfile

        if !profile.videoPassthrough, profile.useHardwareEncoding {
            if let codec = profile.videoCodec {
                let hwEncoders = viewModel.availableHardwareEncoders.filter { $0.codec == codec }
                if let hw = hwEncoders.first {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.green)
                        Text(hw.displayName)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else if codec.supportsVideoToolbox {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Hardware encoding requested but \(codec.displayName) hardware encoder not detected on this system.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Crop Detection (Phase 3.14)

    @ViewBuilder
    private var cropDetectionControls: some View {
        @Bindable var vm = viewModel

        if viewModel.selectedFile != nil, !viewModel.selectedProfile.videoPassthrough {
            Toggle("Auto-crop black bars", isOn: $vm.autoCropEnabled)
                .accessibilityLabel("Automatically detect and remove letterbox/pillarbox black bars")

            if viewModel.autoCropEnabled {
                if viewModel.isDetectingCrop {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Detecting black bars...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let crop = viewModel.detectedCrop {
                    if crop.willCrop {
                        HStack(spacing: 4) {
                            Image(systemName: "crop")
                                .foregroundStyle(.blue)
                            Text("Crop: \(crop.recommendedCrop.displayString) — removes \(String(format: "%.1f", crop.cropPercentage))% black bars")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Text("No black bars detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Detect Now") {
                    Task { await viewModel.detectCropForSelectedFile() }
                }
                .font(.caption)
                .disabled(viewModel.isDetectingCrop || viewModel.selectedFile == nil)
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

    // MARK: - Per-Stream Settings Summary (Phase 3.5 / Issue #41)

    @ViewBuilder
    private func perStreamSettingsSummary(file: MediaFile) -> some View {
        let perStream = viewModel.selectedProfile.perStreamSettings

        if let perStream, perStream.hasOverrides {
            let videoCount = perStream.videoOverrides.count
            let audioCount = perStream.audioOverrides.count
            let subtitleCount = perStream.subtitleOverrides.count

            HStack(spacing: 4) {
                Image(systemName: "tuningfork")
                    .foregroundStyle(.blue)
                Text("\(videoCount) video, \(audioCount) audio, \(subtitleCount) subtitle override(s) configured")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        } else {
            Text("All streams use profile defaults. Configure per-stream overrides to set different codecs, bitrates, or quality per stream.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Compatibility Validation

    /// Computed warnings for incompatible codec/container combinations.
    private var compatibilityWarnings: [String] {
        let profile = viewModel.selectedProfile
        var warnings: [String] = []

        // Video codec vs container
        if !profile.videoPassthrough, let codec = profile.videoCodec {
            if !profile.containerFormat.supportsVideoCodec(codec) {
                warnings.append("\(codec.displayName) is not compatible with \(profile.containerFormat.displayName). Choose a different container or codec.")
            }
        }

        // Audio codec vs container
        if !profile.audioPassthrough, let codec = profile.audioCodec {
            if !profile.containerFormat.supportsAudioCodec(codec) {
                warnings.append("\(codec.displayName) is not compatible with \(profile.containerFormat.displayName). Choose a different container or audio codec.")
            }

            // TrueHD non-default warning (MP4 only)
            if profile.containerFormat.requiresNonDefault(codec) {
                warnings.append("\(codec.displayName) in \(profile.containerFormat.displayName) must not be the default audio stream. A compatible fallback (AAC, AC-3, or E-AC-3) is required.")
            }
        }

        // Chapter support
        if let file = viewModel.selectedFile, !file.chapters.isEmpty,
           !profile.containerFormat.supportsChapters {
            warnings.append("Source has \(file.chapters.count) chapter(s) but \(profile.containerFormat.displayName) does not support chapters. They will be dropped.")
        }

        // Subtitle compatibility
        if profile.subtitlePassthrough, !profile.containerFormat.supportsSubtitles {
            warnings.append("\(profile.containerFormat.displayName) has limited or no subtitle support. Subtitles may be dropped.")
        }

        return warnings
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

    // MARK: - Track Order (language policy MWBM-MEDIA-LANG, TRACK-050/060)

    /// Whether the output puts its tracks in the language policy's standard
    /// order — video, audio, subtitles; the original language first, then by
    /// role and language — or keeps the source's order. A setting of the
    /// selected profile (`EncodingProfile.orderTracksCanonically`, where
    /// `nil` means on), so it travels with the profile like the passthrough
    /// switches do.
    private var trackOrderToggle: some View {
        @Bindable var vm = viewModel
        return VStack(alignment: .leading, spacing: 2) {
            Toggle("Put tracks in the standard order", isOn: Binding(
                get: { vm.selectedProfile.orderTracksCanonically ?? true },
                set: { vm.selectedProfile.orderTracksCanonically = $0 }
            ))
            .accessibilityHint("When off, the output keeps the source file's track order")
            Text("Video, then audio, then subtitles; the original language first, then main tracks before description and commentary. Turn off to keep each kind of track in the order the source file has them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Output Mode (Issue #275)

    private var outputModePicker: some View {
        @Bindable var vm = viewModel

        return Picker("Folder Structure", selection: $vm.outputMode) {
            ForEach(OutputMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .accessibilityLabel("Output folder structure mode")
    }

    // MARK: - Filename Template (Issue #272)

    @ViewBuilder
    private var filenameTemplateField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Filename Template", text: $filenameTemplate)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Output filename template")

            if let file = viewModel.selectedFile {
                let template = FilenameTemplate(template: filenameTemplate)
                let preview = template.resolve(sourceFile: file, profile: viewModel.selectedProfile)
                let ext = viewModel.selectedProfile.containerFormat.fileExtensions.first ?? "mkv"
                Text("Preview: \(preview).\(ext)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Variables: {title}, {resolution}, {codec}, {container}, {profile}, {date}, {date:FORMAT}, {width}, {height}, {fps}, {channels}")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Size Estimate (Issue #274)

    @ViewBuilder
    private func sizeEstimateView(file: MediaFile) -> some View {
        let estimate = FileSizeEstimator.estimateOutputSize(
            profile: viewModel.selectedProfile,
            duration: file.duration ?? 0,
            sourceFileSize: file.fileSize
        )

        LabeledContent("Estimated Size", value: estimate.formattedSize)
            .accessibilityLabel("Estimated output file size: \(estimate.formattedSize)")

        HStack(spacing: 4) {
            Image(systemName: confidenceIcon(estimate.confidenceLevel))
                .foregroundStyle(confidenceColor(estimate.confidenceLevel))
            Text("Confidence: \(estimate.confidenceLevel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: estimate.fitsOnDVD ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(estimate.fitsOnDVD ? .green : .red)
                Text("DVD (4.7 GB)")
                    .font(.caption)
            }
            .accessibilityLabel(estimate.fitsOnDVD ? "Fits on DVD" : "Does not fit on DVD")

            HStack(spacing: 4) {
                Image(systemName: estimate.fitsOnBluRay ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(estimate.fitsOnBluRay ? .green : .red)
                Text("Blu-ray (25 GB)")
                    .font(.caption)
            }
            .accessibilityLabel(estimate.fitsOnBluRay ? "Fits on Blu-ray" : "Does not fit on Blu-ray")
        }
    }

    /// SF Symbol icon for the confidence level.
    private func confidenceIcon(_ level: String) -> String {
        switch level {
        case "high": return "gauge.with.dots.needle.100percent"
        case "medium": return "gauge.with.dots.needle.50percent"
        default: return "gauge.with.dots.needle.0percent"
        }
    }

    /// Colour for the confidence level indicator.
    private func confidenceColor(_ level: String) -> Color {
        switch level {
        case "high": return .green
        case "medium": return .orange
        default: return .red
        }
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

/// Editor for per-stream metadata: title, language and roles.
///
/// Languages follow the shared language policy (MWBM-MEDIA-LANG,
/// docs/standards/media-language-bcp47-policy.md):
/// - the field holds a language — a BCP 47 TAG such as `en`, `en-GB`,
///   `zh-Hant`, `es-419`, or an old three-letter code, read the way a file's
///   value is read (LANG-002: `eng` is saved as `en`) — shown in canonical
///   form; anything unreadable is refused with a plain message and
///   examples, and Apply stays off until it is fixed;
/// - an empty field means "not set": nothing is written and the file's own
///   value is kept (the ✕ button empties it);
/// - when the output's file type cannot store all of a tag (Matroska and MP4
///   hold three letters only), the editor says what will be lost BEFORE
///   Apply, and the job's log says it again;
/// - beside it, the language's NAME in the interface language (UI-010), so
///   the raw tag and the readable name are both visible (the policy expects
///   raw tags in editor views);
/// - quick picks come in menu order: the person's own languages first, then
///   alphabetical by name (UI-020 to UI-040).
/// Roles (default, forced, original, commentary, SDH, audio description) are
/// real toggles that reach the output as dispositions (TRACK-010). Before the
/// policy work the language field accepted only two or three letters and the
/// Default/Forced toggles were never written at all.
///
/// A stream with no title of its own may get an automatic one (its
/// language's own name and roles — see `FFmpegArgumentBuilder
/// .automaticTitle`); the "Name it after its language" switch turns that off
/// for one stream.
struct StreamMetadataEditorView: View {
    let mediaFile: MediaFile
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    @State private var streamMetadata: [Int: StreamMetadataEntry] = [:]

    /// The interface language (names are shown in it — UI-010).
    private var interfaceLocale: Locale { LocalizationManager.shared.currentLocale }

    /// The output's container (the selected profile's), which decides what
    /// a language field can store and whether automatic titles are written.
    private var outputContainer: ContainerFormat { viewModel.selectedProfile.containerFormat }

    /// Quick-pick languages in menu order for this person.
    private var suggestions: [String] {
        StreamMetadataEditor.orderedLanguageSuggestions(
            interfaceLocale: interfaceLocale,
            preferences: Locale.preferredLanguages
        )
    }

    /// Whether any language field holds something that is not a tag.
    private var hasInvalidLanguage: Bool {
        streamMetadata.values.contains {
            if case .invalid = StreamMetadataEditor.checkLanguageEntry($0.language) { return true }
            return false
        }
    }

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
                .disabled(hasInvalidLanguage)
                .accessibilityHint(hasInvalidLanguage
                    ? "Unavailable until every language field holds a language tag"
                    : "Applies the changes to the next encode of this file")
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
        .frame(minWidth: 680, minHeight: 420)
        .onAppear { loadExistingMetadata() }
    }

    private func streamMetadataRow(_ stream: MediaStream) -> some View {
        let entry = binding(for: stream.streamIndex)
        let label = "\(stream.streamType.rawValue.capitalized) #\(stream.streamIndex)"

        return VStack(alignment: .leading, spacing: 8) {
            // Stream header
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(stream.summaryString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The file's own value could not be read as a language: say so,
            // with the text, rather than hide it (COMPAT-040).
            if let unreadable = stream.unrecognisedLanguage {
                Text("The file says “\(unreadable)”, which is not a language code, so it is treated as not known (und). Type the right tag to fix it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Editable fields
            HStack {
                TextField("Title", text: entry.title, prompt: Text(titlePrompt(for: stream)))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Title for \(label)")

                TextField("Language (BCP 47)", text: entry.language,
                          prompt: Text(stream.language ?? "not set"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Language tag for \(label)")
                    .accessibilityHint("A language code such as en, pt-BR or zh-Hant, or und if not known. Leave empty to keep the file's own.")

                // Empties the field: "not set" — nothing is written and the
                // file's own language is kept.
                Button {
                    entry.wrappedValue.language = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(entry.wrappedValue.language.isEmpty)
                .help("Clear: keep the file's own language")
                .accessibilityLabel("Clear the language for \(label), keeping the file's own")

                Menu("Common") {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("\(languageName(tag)) — \(tag)") { entry.wrappedValue.language = tag }
                    }
                }
                .fixedSize()
                .accessibilityLabel("Choose a common language for \(label)")
            }

            languageCheck(entry.wrappedValue.language)

            // The automatic title can be switched off for this stream.
            // Shown only where one could be written: audio or subtitles with
            // no title of their own.
            if stream.streamType == .audio || stream.streamType == .subtitle,
               entry.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle("Name it after its language", isOn: entry.automaticTitle)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Where the file type keeps track titles, a track with no title of its own is named after its language and roles, such as “English — SDH”.")
                    .accessibilityLabel("Automatic title for \(label)")
            }

            roleToggles(for: stream, disposition: entry.disposition, label: label)
        }
        .padding(.vertical, 4)
    }

    /// The canonical tag and its name, a note, or a plain refusal.
    @ViewBuilder
    private func languageCheck(_ text: String) -> some View {
        switch StreamMetadataEditor.checkLanguageEntry(text) {
        case .empty:
            Text("Not set — the file's own language is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .valid(let tag, let note):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(languageName(tag)) · \(tag)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                // What this output's file type cannot store of the tag,
                // said BEFORE Apply (the job's log says it again).
                if let limit = StreamMetadataEditor.storageNote(for: tag, in: outputContainer) {
                    Text(limit)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
        case .invalid(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Problem: \(message)")
        }
    }

    /// The role toggles that make sense for this kind of stream.
    @ViewBuilder
    private func roleToggles(for stream: MediaStream, disposition: Binding<StreamDisposition>, label: String) -> some View {
        HStack(spacing: 12) {
            Toggle("Default", isOn: disposition.isDefault)
                .accessibilityLabel("Default track: \(label)")
            switch stream.streamType {
            case .audio:
                Toggle("Original language", isOn: disposition.isOriginal)
                    .accessibilityLabel("Original language: \(label)")
                Toggle("Commentary", isOn: disposition.isComment)
                    .accessibilityLabel("Commentary: \(label)")
                Toggle("Audio description", isOn: disposition.isVisualImpaired)
                    .accessibilityLabel("Audio description: \(label)")
            case .subtitle:
                Toggle("Forced", isOn: disposition.isForced)
                    .accessibilityLabel("Forced subtitles: \(label)")
                Toggle("SDH", isOn: disposition.isHearingImpaired)
                    .accessibilityLabel("Subtitles for the deaf and hard of hearing: \(label)")
                Toggle("Commentary", isOn: disposition.isComment)
                    .accessibilityLabel("Commentary: \(label)")
                Toggle("Original language", isOn: disposition.isOriginal)
                    .accessibilityLabel("Original language: \(label)")
            default:
                EmptyView()
            }
        }
        .toggleStyle(.checkbox)
    }

    /// The language's name in the interface language, or the tag itself.
    private func languageName(_ tag: String) -> String {
        LanguageNames.localizedName(of: tag, in: interfaceLocale) ?? tag
    }

    /// The title field's placeholder: the file's title, or — for an audio or
    /// subtitle stream with none, in a file type that keeps track titles —
    /// the automatic title the encode may write (NAME-010: the language's
    /// own name and the roles). Whether it is actually written also depends
    /// on the tracks chosen (a lone audio track in an audio-only file gets
    /// none), which this sheet does not know, hence "may".
    private func titlePrompt(for stream: MediaStream) -> String {
        if let title = stream.title, !title.isEmpty { return title }
        if stream.streamType == .audio || stream.streamType == .subtitle,
           TrackLanguage.keepsStreamTitlesSeparately(outputContainer),
           let language = stream.language,
           let automatic = TrackLanguage.automaticTitle(
               for: language, disposition: sourceDisposition(stream), type: stream.streamType
           ) {
            return "\(automatic) (automatic)"
        }
        return "Untitled"
    }

    private func binding(for index: Int) -> Binding<StreamMetadataEntry> {
        Binding(
            get: { streamMetadata[index] ?? StreamMetadataEntry() },
            set: { streamMetadata[index] = $0 }
        )
    }

    /// The roles the file gives a stream (all of them when probed with the
    /// policy work; just default/forced for older data).
    private func sourceDisposition(_ stream: MediaStream) -> StreamDisposition {
        stream.disposition ?? StreamDisposition(isDefault: stream.isDefault, isForced: stream.isForced)
    }

    private func loadExistingMetadata() {
        // Start from what the file says, then lay any earlier edits for THIS
        // file on top (edits for another file are never shown here: stream
        // numbers only mean something within one file).
        let saved = viewModel.sourceStreamEdits(for: mediaFile)
        for stream in mediaFile.streams {
            let edit = saved[stream.streamIndex]
            streamMetadata[stream.streamIndex] = StreamMetadataEntry(
                title: edit?.title ?? stream.title ?? "",
                language: edit?.language ?? stream.language ?? "",
                disposition: edit?.disposition ?? sourceDisposition(stream),
                automaticTitle: edit?.writesAutomaticTitle ?? true
            )
        }
    }

    /// Records the edits, keyed by each stream's WHOLE-FILE number (#530).
    ///
    /// This used to build ffmpeg specifiers such as `s:a:<whole-file number>`
    /// here — which ffmpeg reads as "the Nth AUDIO stream of the output" — so
    /// an edit landed on the wrong track, or on none. The argument builder now
    /// works out the output stream for each source stream itself. Only fields
    /// that differ from the file are recorded ("leave as it is" otherwise);
    /// a language is recorded in canonical form; roles are recorded whole
    /// (the entry started from ALL of the file's roles, so none is lost).
    private func applyMetadata() {
        var edits: [Int: SourceStreamEdit] = [:]

        for stream in mediaFile.streams {
            guard let entry = streamMetadata[stream.streamIndex] else { continue }
            var edit = SourceStreamEdit()
            if entry.title != (stream.title ?? "") { edit.title = entry.title }
            if case .valid(let tag, _) = StreamMetadataEditor.checkLanguageEntry(entry.language),
               tag != (stream.language ?? "") {
                edit.language = tag
            }
            if entry.disposition != sourceDisposition(stream) {
                edit.disposition = entry.disposition
            }
            // Recorded only when switched OFF; on is the default rule.
            if !entry.automaticTitle {
                edit.writesAutomaticTitle = false
            }
            if !edit.isEmpty {
                edits[stream.streamIndex] = edit
            }
        }

        viewModel.sourceStreamEdits = edits
        viewModel.sourceStreamEditsFileURL = mediaFile.fileURL
        viewModel.appendLog(.info, "Applied stream metadata changes to \(edits.count) stream(s) of \(mediaFile.fileName)",
                            category: .metadata)
    }
}

/// Editable metadata for a single stream.
struct StreamMetadataEntry {
    var title: String = ""
    /// The language as typed (checked and canonicalised on Apply).
    var language: String = ""
    /// Every role flag, starting from the file's own.
    var disposition = StreamDisposition()
    /// Whether this stream may get an automatic title (on unless switched off).
    var automaticTitle = true
}
