// ============================================================================
// MeedyaConverter — MetadataEditorView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - MetadataEditorView

/// Interactive editor for file-level and per-stream metadata.
///
/// Allows editing titles, languages, disposition flags, and custom
/// metadata tags on individual streams before encoding or remuxing.
///
/// Phase 14.12
struct MetadataEditorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var globalTitle: String = ""
    @State private var globalArtist: String = ""
    @State private var globalDate: String = ""
    @State private var globalComment: String = ""
    @State private var streamEdits: [StreamEditState] = []
    @State private var hasUnsavedChanges: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Global metadata section
                globalMetadataSection

                Divider()

                // Per-stream metadata sections
                if !streamEdits.isEmpty {
                    perStreamSection
                } else {
                    ContentUnavailableView(
                        "No Source File",
                        systemImage: "doc.questionmark",
                        description: Text("Import a source file to edit its stream metadata.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Metadata Editor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Apply Changes") {
                    applyChanges()
                }
                .disabled(!hasUnsavedChanges)
            }

            ToolbarItem(placement: .automatic) {
                Button("Reset") {
                    resetEdits()
                }
                .disabled(!hasUnsavedChanges)
            }
        }
        .onAppear {
            loadCurrentMetadata()
        }
    }

    // MARK: - Global Metadata Section

    private var globalMetadataSection: some View {
        GroupBox("File Metadata") {
            VStack(alignment: .leading, spacing: 12) {
                metadataField(label: "Title", text: $globalTitle)
                metadataField(label: "Artist", text: $globalArtist)
                metadataField(label: "Date", text: $globalDate)
                metadataField(label: "Comment", text: $globalComment)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Per-Stream Section

    private var perStreamSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stream Metadata")
                .font(.headline)

            ForEach($streamEdits) { $edit in
                streamEditCard(edit: $edit)
            }
        }
    }

    private func streamEditCard(edit: Binding<StreamEditState>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Stream header
                HStack {
                    Image(systemName: streamIcon(for: edit.wrappedValue.streamType))
                        .foregroundStyle(streamColor(for: edit.wrappedValue.streamType))
                    Text("Stream \(edit.wrappedValue.streamIndex)")
                        .font(.headline)
                    Text("(\(edit.wrappedValue.streamType.rawValue))")
                        .foregroundStyle(.secondary)
                    if let codec = edit.wrappedValue.codecName {
                        Text(codec)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tertiary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                // Title
                metadataField(label: "Title", text: edit.title)

                // Language
                HStack {
                    Text("Language")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: edit.language) {
                        Text("Undetermined").tag("")
                        ForEach(StreamMetadataEditor.commonLanguages, id: \.code) { lang in
                            Text("\(lang.name) (\(lang.code))").tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                    .accessibilityLabel("Language for stream \(edit.wrappedValue.streamIndex)")
                }

                // Disposition flags
                dispositionEditor(edit: edit)
            }
            .padding(.vertical, 4)
        }
    }

    private func dispositionEditor(edit: Binding<StreamEditState>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disposition Flags")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Toggle("Default", isOn: edit.isDefault)
                Toggle("Forced", isOn: edit.isForced)

                if edit.wrappedValue.streamType == .audio {
                    Toggle("Original", isOn: edit.isOriginal)
                    Toggle("Dub", isOn: edit.isDub)
                    Toggle("Comment", isOn: edit.isComment)
                }

                if edit.wrappedValue.streamType == .subtitle {
                    Toggle("Hearing Impaired", isOn: edit.isHearingImpaired)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private func metadataField(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, _ in
                    hasUnsavedChanges = true
                }
        }
    }

    // MARK: - Helpers

    private func streamIcon(for type: StreamType) -> String {
        switch type {
        case .video: return "film"
        case .audio: return "speaker.wave.2"
        case .subtitle: return "captions.bubble"
        case .data: return "doc"
        case .attachment: return "paperclip"
        case .unknown: return "questionmark.circle"
        }
    }

    private func streamColor(for type: StreamType) -> Color {
        switch type {
        case .video: return .blue
        case .audio: return .green
        case .subtitle: return .orange
        default: return .gray
        }
    }

    private func loadCurrentMetadata() {
        guard let file = viewModel.sourceFiles.first else { return }

        globalTitle = file.metadata["title"] ?? ""

        streamEdits = file.streams.map { stream in
            StreamEditState(
                streamIndex: stream.streamIndex,
                streamType: stream.streamType,
                codecName: stream.codecName,
                title: stream.title ?? "",
                language: stream.language ?? "",
                isDefault: stream.isDefault,
                isForced: stream.isForced,
                isOriginal: false,
                isDub: false,
                isComment: false,
                isHearingImpaired: false
            )
        }

        hasUnsavedChanges = false
    }

    private func applyChanges() {
        var editSet = StreamMetadataEditSet()

        if !globalTitle.isEmpty {
            editSet.globalEdits["title"] = globalTitle
        }
        if !globalArtist.isEmpty {
            editSet.globalEdits["artist"] = globalArtist
        }
        if !globalDate.isEmpty {
            editSet.globalEdits["date"] = globalDate
        }
        if !globalComment.isEmpty {
            editSet.globalEdits["comment"] = globalComment
        }

        for edit in streamEdits {
            if !edit.title.isEmpty {
                editSet.streamEdits.append(StreamMetadataEdit(
                    streamIndex: edit.streamIndex,
                    key: "title",
                    value: edit.title
                ))
            }
            if !edit.language.isEmpty {
                editSet.streamEdits.append(StreamMetadataEdit(
                    streamIndex: edit.streamIndex,
                    key: "language",
                    value: edit.language
                ))
            }

            let disposition = StreamDisposition(
                isDefault: edit.isDefault,
                isDub: edit.isDub,
                isOriginal: edit.isOriginal,
                isComment: edit.isComment,
                isForced: edit.isForced,
                isHearingImpaired: edit.isHearingImpaired
            )
            editSet.dispositionEdits.append(DispositionEdit(
                streamIndex: edit.streamIndex,
                disposition: disposition
            ))
        }

        viewModel.appendLog(.info, "Applied metadata edits to \(editSet.streamEdits.count) streams")
        hasUnsavedChanges = false
    }

    private func resetEdits() {
        loadCurrentMetadata()
    }
}

// MARK: - StreamEditState

/// Mutable state for editing a single stream's metadata.
struct StreamEditState: Identifiable {
    let id = UUID()
    var streamIndex: Int
    var streamType: StreamType
    var codecName: String?
    var title: String
    var language: String
    var isDefault: Bool
    var isForced: Bool
    var isOriginal: Bool
    var isDub: Bool
    var isComment: Bool
    var isHearingImpaired: Bool
}
