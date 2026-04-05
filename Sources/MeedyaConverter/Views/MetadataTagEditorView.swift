// ============================================================================
// MeedyaConverter — MetadataTagEditorView (Issue #320)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// MARK: - MetadataTagEditorView

/// Full metadata tag editing interface for media files.
///
/// Provides a table of key-value pairs with add/edit/remove capabilities,
/// artwork preview and change, batch tag editing, tag templates for
/// common workflows, and common tag suggestions via auto-complete.
///
/// Phase 6 — Full Metadata Tag Editor (Issue #320)
struct MetadataTagEditorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    /// The current list of metadata tags being edited.
    @State private var tags: [MediaTag] = []

    /// The currently selected tag ID in the table.
    @State private var selectedTagID: UUID?

    /// Path to the artwork image file, if any.
    @State private var artworkPath: String?

    /// The artwork image for preview display.
    @State private var artworkImage: NSImage?

    /// Key field for the new/edit tag form.
    @State private var editKey: String = ""

    /// Value field for the new/edit tag form.
    @State private var editValue: String = ""

    /// Whether the tag edit sheet is presented.
    @State private var showingEditor = false

    /// Whether editing an existing tag (true) or adding a new one (false).
    @State private var isEditingExisting = false

    /// ID of the tag being edited (when editing existing).
    @State private var editingTagID: UUID?

    /// Whether the artwork file importer is presented.
    @State private var showingArtworkImporter = false

    /// Selected template name for batch application.
    @State private var selectedTemplate: String = "None"

    /// Available tag templates for quick population.
    private let templates = [
        "None",
        "Movie",
        "TV Episode",
        "Music Album",
        "Podcast",
    ]

    /// Error message for the alert.
    @State private var errorMessage: String?

    /// Whether the error alert is shown.
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            controlsBar

            Divider()

            // Main content
            HSplitView {
                tagTableView
                    .frame(minWidth: 350)

                detailPanel
                    .frame(minWidth: 280, maxWidth: 320)
            }
        }
        .navigationTitle("Metadata Tag Editor")
        .sheet(isPresented: $showingEditor) {
            tagEditorSheet
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $showingArtworkImporter,
            allowedContentTypes: [.jpeg, .png, .bmp],
            allowsMultipleSelection: false
        ) { result in
            handleArtworkImport(result)
        }
    }

    // MARK: - Controls Bar

    /// Top toolbar with tag management actions.
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button {
                prepareAddTag()
            } label: {
                Label("Add Tag", systemImage: "plus")
            }
            .accessibilityLabel("Add metadata tag")

            Button {
                editSelectedTag()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(selectedTagID == nil)
            .accessibilityLabel("Edit selected tag")

            Button {
                removeSelectedTag()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selectedTagID == nil)
            .accessibilityLabel("Remove selected tag")

            Divider()
                .frame(height: 16)

            Button {
                tags.removeAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(tags.isEmpty)
            .accessibilityLabel("Clear all metadata tags")

            Spacer()

            // Template picker
            Picker("Template:", selection: $selectedTemplate) {
                ForEach(templates, id: \.self) { template in
                    Text(template).tag(template)
                }
            }
            .frame(maxWidth: 180)
            .onChange(of: selectedTemplate) { _, newValue in
                applyTemplate(newValue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Tag Table

    /// Table of metadata key-value pairs.
    private var tagTableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tags")
                    .font(.headline)
                Spacer()
                Text("\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if tags.isEmpty {
                emptyTagsView
            } else {
                List(selection: $selectedTagID) {
                    ForEach(tags) { tag in
                        HStack {
                            Text(tag.key)
                                .font(.body.bold())
                                .frame(width: 120, alignment: .leading)

                            Divider()
                                .frame(height: 16)

                            Text(tag.value)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer()
                        }
                        .tag(tag.id)
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        tags.remove(atOffsets: offsets)
                    }
                }
            }

            // Common tags suggestions
            suggestionsBar
        }
    }

    // MARK: - Detail Panel

    /// Right-side panel with artwork preview and batch actions.
    private var detailPanel: some View {
        Form {
            // Artwork section
            Section("Artwork") {
                VStack(spacing: 12) {
                    if let image = artworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 200, height: 200)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .foregroundStyle(.tertiary)
                                    Text("No Artwork")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                    }

                    HStack {
                        Button("Choose...") {
                            showingArtworkImporter = true
                        }

                        if artworkPath != nil {
                            Button("Remove") {
                                artworkPath = nil
                                artworkImage = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            // FFmpeg preview
            Section("FFmpeg Arguments") {
                let args = MetadataTagEditor.buildWriteArguments(
                    tags: tags,
                    artworkPath: artworkPath
                )

                if args.isEmpty {
                    Text("No arguments generated.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(args.joined(separator: " "))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tag Editor Sheet

    /// Modal sheet for adding or editing a metadata tag.
    private var tagEditorSheet: some View {
        VStack(spacing: 16) {
            Text(isEditingExisting ? "Edit Tag" : "Add Tag")
                .font(.headline)

            Form {
                // Key field with auto-complete suggestions
                LabeledContent("Key") {
                    TextField("e.g., title", text: $editKey)
                        .textFieldStyle(.roundedBorder)
                }

                // Common keys quick-pick
                LabeledContent("Suggestions") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(
                                MetadataTagEditor.commonTags.filter { tag in
                                    !tags.contains { $0.key == tag }
                                },
                                id: \.self
                            ) { suggestion in
                                Button(suggestion) {
                                    editKey = suggestion
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                LabeledContent("Value") {
                    TextField("e.g., My Movie", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    showingEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditingExisting ? "Save" : "Add") {
                    saveTag()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editKey.isEmpty || editValue.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
    }

    // MARK: - Suggestions Bar

    /// Quick-add bar for common metadata tags.
    private var suggestionsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Common Tags")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(
                        MetadataTagEditor.commonTags.filter { tag in
                            !tags.contains { $0.key == tag }
                        },
                        id: \.self
                    ) { tag in
                        Button(tag) {
                            editKey = tag
                            editValue = ""
                            isEditingExisting = false
                            editingTagID = nil
                            showingEditor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Empty Tags View

    /// Placeholder when no tags have been added.
    private var emptyTagsView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tag")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)

            Text("No Metadata Tags")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(
                "Add tags manually, use a template, or click a "
                + "common tag suggestion below."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Prepares the editor sheet for adding a new tag.
    private func prepareAddTag() {
        editKey = ""
        editValue = ""
        isEditingExisting = false
        editingTagID = nil
        showingEditor = true
    }

    /// Prepares the editor sheet for editing the selected tag.
    private func editSelectedTag() {
        guard let id = selectedTagID,
              let tag = tags.first(where: { $0.id == id }) else { return }
        editKey = tag.key
        editValue = tag.value
        isEditingExisting = true
        editingTagID = id
        showingEditor = true
    }

    /// Saves the current tag (add or update).
    private func saveTag() {
        if isEditingExisting, let id = editingTagID,
           let index = tags.firstIndex(where: { $0.id == id }) {
            tags[index] = MediaTag(id: id, key: editKey, value: editValue)
        } else {
            tags.append(MediaTag(key: editKey, value: editValue))
        }
        showingEditor = false
    }

    /// Removes the currently selected tag.
    private func removeSelectedTag() {
        guard let id = selectedTagID,
              let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags.remove(at: index)
        selectedTagID = nil
    }

    /// Handles the result of the artwork file importer.
    private func handleArtworkImport(
        _ result: Result<[URL], any Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            artworkPath = url.path
            artworkImage = NSImage(contentsOf: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Applies a tag template, populating common fields.
    private func applyTemplate(_ template: String) {
        switch template {
        case "Movie":
            applyTemplateTags([
                ("title", ""), ("date", ""), ("genre", ""),
                ("description", ""), ("copyright", ""),
            ])
        case "TV Episode":
            applyTemplateTags([
                ("title", ""), ("artist", ""), ("album", ""),
                ("track", ""), ("date", ""), ("genre", ""),
                ("description", ""),
            ])
        case "Music Album":
            applyTemplateTags([
                ("title", ""), ("artist", ""), ("album", ""),
                ("album_artist", ""), ("track", ""), ("disc", ""),
                ("date", ""), ("genre", ""),
            ])
        case "Podcast":
            applyTemplateTags([
                ("title", ""), ("artist", ""), ("album", ""),
                ("date", ""), ("genre", "Podcast"),
                ("comment", ""), ("description", ""),
            ])
        default:
            break
        }
    }

    /// Adds template tags, skipping keys that already exist.
    private func applyTemplateTags(_ templateTags: [(String, String)]) {
        for (key, value) in templateTags {
            if !tags.contains(where: { $0.key == key }) {
                tags.append(MediaTag(key: key, value: value))
            }
        }
    }
}
