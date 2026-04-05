// ============================================================================
// MeedyaConverter — PipelineEditorView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - PipelineEditorView

/// Editor for creating and modifying encoding pipelines.
///
/// Presents a list of pipeline steps with drag-to-reorder support,
/// step configuration panels, and the ability to save/load pipeline
/// presets from the built-in template library.
struct PipelineEditorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var pipeline: EncodingPipeline
    @State private var selectedStepID: UUID?
    @State private var showTemplatePicker = false

    /// Callback invoked when the user saves the pipeline.
    var onSave: ((EncodingPipeline) -> Void)?

    // MARK: - Initialiser

    /// Create a pipeline editor.
    ///
    /// - Parameters:
    ///   - pipeline: The pipeline to edit (defaults to an empty pipeline).
    ///   - onSave: Callback when the user taps Save.
    init(
        pipeline: EncodingPipeline = EncodingPipeline(name: "New Pipeline"),
        onSave: ((EncodingPipeline) -> Void)? = nil
    ) {
        self._pipeline = State(initialValue: pipeline)
        self.onSave = onSave
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            stepListSidebar
        } detail: {
            stepDetailView
        }
        .navigationTitle("Pipeline Editor")
        .frame(minWidth: 700, minHeight: 450)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }
    }

    // MARK: - Step List Sidebar

    private var stepListSidebar: some View {
        List(selection: $selectedStepID) {
            // Pipeline name
            Section("Pipeline") {
                TextField("Name", text: $pipeline.name)
                    .textFieldStyle(.roundedBorder)

                Toggle("Clean Intermediate Files", isOn: $pipeline.cleanIntermediateFiles)
                    .font(.caption)
            }

            // Steps list with drag-to-reorder
            Section("Steps (\(pipeline.steps.count))") {
                ForEach(pipeline.steps) { step in
                    stepRow(step)
                        .tag(step.id)
                }
                .onMove { source, destination in
                    pipeline.steps.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    pipeline.steps.remove(atOffsets: offsets)
                    if let first = pipeline.steps.first {
                        selectedStepID = first.id
                    } else {
                        selectedStepID = nil
                    }
                }
            }

            // Add step button
            Section {
                addStepMenu
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    }

    // MARK: - Step Row

    /// A single row displaying a pipeline step in the sidebar list.
    private func stepRow(_ step: PipelineStep) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.body)
                Text(step.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: step.type.systemImage)
                .foregroundStyle(.accent)
        }
    }

    // MARK: - Add Step Menu

    /// Menu button to add a new step of any type.
    private var addStepMenu: some View {
        Menu {
            ForEach(PipelineStepType.allCases, id: \.self) { stepType in
                Button(stepType.displayName) {
                    addStep(type: stepType)
                }
            }
        } label: {
            Label("Add Step", systemImage: "plus.circle")
        }
    }

    /// Add a new step of the given type to the pipeline.
    private func addStep(type: PipelineStepType) {
        let step = PipelineStep(
            name: type.displayName,
            type: type,
            profile: type == .encode ? viewModel.selectedProfile : nil,
            config: defaultConfig(for: type)
        )
        pipeline.steps.append(step)
        selectedStepID = step.id
    }

    /// Provide default configuration values for a new step of the given type.
    private func defaultConfig(for type: PipelineStepType) -> [String: String] {
        switch type {
        case .encode:
            return ["extension": "mkv"]
        case .extractThumbnail:
            return ["timestamp": "00:00:05"]
        case .generatePreviewGIF:
            return [
                "startTime": "00:00:05",
                "duration": "5",
                "fps": "10",
                "width": "480",
            ]
        case .extractAudio:
            return ["format": "flac"]
        case .probe:
            return ["format": "json"]
        }
    }

    // MARK: - Step Detail View

    /// Configuration panel for the currently selected step.
    @ViewBuilder
    private var stepDetailView: some View {
        if let stepID = selectedStepID,
           let stepIndex = pipeline.steps.firstIndex(where: { $0.id == stepID }) {
            let step = pipeline.steps[stepIndex]
            Form {
                Section("Step Configuration") {
                    TextField("Step Name", text: Binding(
                        get: { pipeline.steps[stepIndex].name },
                        set: { pipeline.steps[stepIndex].name = $0 }
                    ))

                    LabeledContent("Type", value: step.type.displayName)
                }

                // Type-specific configuration
                switch step.type {
                case .encode:
                    encodeStepConfig(stepIndex: stepIndex)
                case .extractThumbnail:
                    thumbnailStepConfig(stepIndex: stepIndex)
                case .generatePreviewGIF:
                    gifStepConfig(stepIndex: stepIndex)
                case .extractAudio:
                    audioStepConfig(stepIndex: stepIndex)
                case .probe:
                    probeStepConfig(stepIndex: stepIndex)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(step.name)
        } else {
            ContentUnavailableView(
                "No Step Selected",
                systemImage: "square.stack.3d.up",
                description: Text("Select a step from the sidebar or add a new one.")
            )
        }
    }

    // MARK: - Encode Step Configuration

    private func encodeStepConfig(stepIndex: Int) -> some View {
        Section("Encoding") {
            // Profile picker
            Picker("Profile", selection: Binding(
                get: { pipeline.steps[stepIndex].profile ?? .webStandard },
                set: { pipeline.steps[stepIndex].profile = $0 }
            )) {
                ForEach(viewModel.engine.profileStore.profiles) { profile in
                    Text(profile.name).tag(profile)
                }
            }

            TextField("Output Extension", text: configBinding(
                stepIndex: stepIndex, key: "extension", default: "mkv"
            ))
        }
    }

    // MARK: - Thumbnail Step Configuration

    private func thumbnailStepConfig(stepIndex: Int) -> some View {
        Section("Thumbnail") {
            TextField("Timestamp (HH:MM:SS)", text: configBinding(
                stepIndex: stepIndex, key: "timestamp", default: "00:00:05"
            ))
            .help("The time position at which to extract the still frame.")
        }
    }

    // MARK: - GIF Step Configuration

    private func gifStepConfig(stepIndex: Int) -> some View {
        Section("Preview GIF") {
            TextField("Start Time (HH:MM:SS)", text: configBinding(
                stepIndex: stepIndex, key: "startTime", default: "00:00:05"
            ))
            TextField("Duration (seconds)", text: configBinding(
                stepIndex: stepIndex, key: "duration", default: "5"
            ))
            TextField("Frame Rate (fps)", text: configBinding(
                stepIndex: stepIndex, key: "fps", default: "10"
            ))
            TextField("Width (pixels)", text: configBinding(
                stepIndex: stepIndex, key: "width", default: "480"
            ))
        }
    }

    // MARK: - Audio Extraction Configuration

    private func audioStepConfig(stepIndex: Int) -> some View {
        Section("Audio Extraction") {
            Picker("Format", selection: configBinding(
                stepIndex: stepIndex, key: "format", default: "flac"
            )) {
                Text("FLAC").tag("flac")
                Text("WAV").tag("wav")
                Text("AAC").tag("aac")
            }

            if pipeline.steps[stepIndex].config["format"] == "aac" {
                TextField("Bitrate", text: configBinding(
                    stepIndex: stepIndex, key: "bitrate", default: "256k"
                ))
            }
        }
    }

    // MARK: - Probe Step Configuration

    private func probeStepConfig(stepIndex: Int) -> some View {
        Section("Probe Output") {
            Picker("Output Format", selection: configBinding(
                stepIndex: stepIndex, key: "format", default: "json"
            )) {
                Text("JSON").tag("json")
                Text("Flat").tag("flat")
            }
        }
    }

    // MARK: - Config Binding Helper

    /// Create a two-way binding into a step's config dictionary.
    private func configBinding(
        stepIndex: Int,
        key: String,
        default defaultValue: String
    ) -> Binding<String> {
        Binding(
            get: { pipeline.steps[stepIndex].config[key] ?? defaultValue },
            set: { pipeline.steps[stepIndex].config[key] = $0 }
        )
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        Button("Load Template") {
            showTemplatePicker = true
        }

        Button("Save") {
            onSave?(pipeline)
            dismiss()
        }
        .keyboardShortcut("s", modifiers: .command)
    }

    // MARK: - Template Picker

    private var templatePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(EncodingPipeline.builtInTemplates) { template in
                    Button {
                        pipeline = template
                        pipeline = EncodingPipeline(
                            id: UUID(),
                            name: template.name,
                            steps: template.steps,
                            cleanIntermediateFiles: template.cleanIntermediateFiles
                        )
                        showTemplatePicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                            Text("\(template.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(template.steps) { step in
                                    Label(step.type.displayName, systemImage: step.type.systemImage)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Pipeline Templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTemplatePicker = false }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
