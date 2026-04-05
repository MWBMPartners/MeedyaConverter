// ============================================================================
// MeedyaConverter — PodcastFeedView (Issue #349)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// SwiftUI interface for creating and managing podcast RSS feeds. Provides
// a form-based editor for feed metadata, an episode list with auto-population
// from encoded audio files, live feed preview, XML export, and validation.
//
// The view is organised into sections:
//   1. **Feed Metadata** — title, description, author, link, image, etc.
//   2. **Episodes** — list of episodes with add/remove/auto-populate.
//   3. **Preview** — live RSS XML preview.
//   4. **Actions** — validate and export buttons.
//
// Phase 14 — RSS/Podcast Feed Generation (Issue #349)
// ---------------------------------------------------------------------------

import SwiftUI
import UniformTypeIdentifiers
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - PodcastFeedView
// ---------------------------------------------------------------------------
/// Podcast RSS feed generation interface.
///
/// Provides a comprehensive form for defining podcast metadata, managing
/// episodes, previewing the generated RSS XML, and exporting the feed
/// to a file.
///
/// ### Usage
/// Present as a sheet or navigation destination from the main app:
/// ```swift
/// .sheet(isPresented: $showPodcastFeed) {
///     PodcastFeedView()
/// }
/// ```
struct PodcastFeedView: View {

    // MARK: - Feed Configuration State

    /// The podcast title.
    @State private var feedTitle: String = ""

    /// The podcast description.
    @State private var feedDescription: String = ""

    /// The podcast author name.
    @State private var feedAuthor: String = ""

    /// The podcast website link (as a string for text field binding).
    @State private var feedLink: String = "https://"

    /// The podcast artwork image URL (as a string for text field binding).
    @State private var feedImageURL: String = ""

    /// The podcast language code.
    @State private var feedLanguage: String = "en"

    /// The iTunes category.
    @State private var feedCategory: String = "Technology"

    /// Whether the podcast contains explicit content.
    @State private var feedExplicit: Bool = false

    // MARK: - Episode State

    /// The list of episodes in the feed.
    @State private var episodes: [PodcastEpisode] = []

    /// The ID of the currently selected episode for editing.
    @State private var selectedEpisodeID: UUID?

    /// Whether the add-episode sheet is presented.
    @State private var showAddEpisode = false

    /// Whether the file importer for auto-populating episodes is shown.
    @State private var showFileImporter = false

    // MARK: - Preview & Validation State

    /// The generated RSS XML string for preview.
    @State private var generatedXML: String = ""

    /// Validation issues found in the generated feed.
    @State private var validationIssues: [String] = []

    /// Whether the validation results sheet is presented.
    @State private var showValidation = false

    /// Whether the export save panel is active.
    @State private var showExportPanel = false

    /// Whether the preview pane is visible.
    @State private var showPreview = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            feedMetadataForm
        } detail: {
            episodeListView
        }
        .navigationTitle("Podcast Feed Generator")
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                feedToolbar
            }
        }
        .sheet(isPresented: $showAddEpisode) {
            addEpisodeSheet
        }
        .sheet(isPresented: $showValidation) {
            validationSheet
        }
        .sheet(isPresented: $showPreview) {
            previewSheet
        }
        .onChange(of: feedTitle) { _, _ in regenerateXML() }
        .onChange(of: feedDescription) { _, _ in regenerateXML() }
        .onChange(of: feedAuthor) { _, _ in regenerateXML() }
        .onChange(of: episodes) { _, _ in regenerateXML() }
    }

    // MARK: - Feed Metadata Form

    /// Left-column form for feed-level metadata.
    private var feedMetadataForm: some View {
        Form {
            Section("Podcast Information") {
                TextField("Title", text: $feedTitle)
                    .accessibilityLabel("Podcast title")

                TextField("Author", text: $feedAuthor)
                    .accessibilityLabel("Podcast author")

                TextField("Website URL", text: $feedLink)
                    .accessibilityLabel("Podcast website URL")

                TextField("Artwork Image URL", text: $feedImageURL)
                    .accessibilityLabel("Podcast artwork URL")
            }

            Section("Description") {
                TextEditor(text: $feedDescription)
                    .frame(minHeight: 80)
                    .accessibilityLabel("Podcast description")
            }

            Section("Settings") {
                Picker("Language", selection: $feedLanguage) {
                    Text("English").tag("en")
                    Text("English (US)").tag("en-us")
                    Text("English (UK)").tag("en-gb")
                    Text("German").tag("de")
                    Text("French").tag("fr")
                    Text("Spanish").tag("es")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }

                Picker("Category", selection: $feedCategory) {
                    Text("Technology").tag("Technology")
                    Text("Arts").tag("Arts")
                    Text("Business").tag("Business")
                    Text("Comedy").tag("Comedy")
                    Text("Education").tag("Education")
                    Text("Health & Fitness").tag("Health & Fitness")
                    Text("Music").tag("Music")
                    Text("News").tag("News")
                    Text("Science").tag("Science")
                    Text("Society & Culture").tag("Society & Culture")
                    Text("Sports").tag("Sports")
                    Text("True Crime").tag("True Crime")
                }

                Toggle("Explicit Content", isOn: $feedExplicit)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 300)
    }

    // MARK: - Episode List

    /// Right-column episode list with add/remove controls.
    private var episodeListView: some View {
        VStack(spacing: 0) {
            if episodes.isEmpty {
                ContentUnavailableView(
                    "No Episodes",
                    systemImage: "mic.badge.plus",
                    description: Text("Add episodes manually or import audio files to auto-populate episode metadata.")
                )
            } else {
                List(selection: $selectedEpisodeID) {
                    ForEach(episodes) { episode in
                        episodeRow(episode)
                            .tag(episode.id)
                    }
                    .onDelete { indexSet in
                        episodes.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Episode controls.
            HStack {
                Button {
                    showAddEpisode = true
                } label: {
                    Label("Add Episode", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Import from File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.audio, .mpeg4Audio, .mp3],
                    allowsMultipleSelection: true
                ) { result in
                    handleAudioImport(result)
                }

                Spacer()

                if let selectedID = selectedEpisodeID {
                    Button(role: .destructive) {
                        episodes.removeAll { $0.id == selectedID }
                        selectedEpisodeID = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
        }
    }

    /// A single episode row showing title, duration, and publish date.
    ///
    /// - Parameter episode: The episode to display.
    /// - Returns: A row view with episode metadata.
    private func episodeRow(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let season = episode.season, let ep = episode.episode {
                    Text("S\(season)E\(ep)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                }
                Text(episode.title)
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Label(formatDuration(episode.duration), systemImage: "clock")
                Label(formatFileSize(episode.fileSize), systemImage: "doc")
                Label(episode.publishDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Episode Sheet

    /// Sheet for manually adding a new episode.
    private var addEpisodeSheet: some View {
        AddEpisodeView { episode in
            episodes.append(episode)
            showAddEpisode = false
        } onCancel: {
            showAddEpisode = false
        }
    }

    // MARK: - Validation Sheet

    /// Sheet displaying feed validation results.
    private var validationSheet: some View {
        NavigationStack {
            List {
                if validationIssues.isEmpty {
                    Label("Feed is valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(Array(validationIssues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: issue.hasPrefix("Warning") ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                            .foregroundStyle(issue.hasPrefix("Warning") ? .orange : .red)
                    }
                }
            }
            .navigationTitle("Feed Validation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showValidation = false }
                }
            }
        }
        .frame(width: 500, height: 300)
    }

    // MARK: - Preview Sheet

    /// Sheet displaying the generated RSS XML.
    private var previewSheet: some View {
        NavigationStack {
            ScrollView {
                Text(generatedXML)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("RSS Feed Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showPreview = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(generatedXML, forType: .string)
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
    }

    // MARK: - Toolbar

    /// Toolbar items for preview, validate, and export actions.
    @ViewBuilder
    private var feedToolbar: some View {
        Button {
            regenerateXML()
            showPreview = true
        } label: {
            Label("Preview", systemImage: "eye")
        }
        .disabled(feedTitle.isEmpty)

        Button {
            regenerateXML()
            validationIssues = PodcastFeedGenerator.validateFeed(generatedXML)
            showValidation = true
        } label: {
            Label("Validate", systemImage: "checkmark.shield")
        }
        .disabled(feedTitle.isEmpty)

        Button {
            exportFeed()
        } label: {
            Label("Export XML", systemImage: "square.and.arrow.up")
        }
        .disabled(feedTitle.isEmpty)
    }

    // MARK: - Actions

    /// Regenerates the RSS XML from current state.
    private func regenerateXML() {
        guard !feedTitle.isEmpty else {
            generatedXML = ""
            return
        }

        let config = PodcastFeedConfig(
            title: feedTitle,
            description: feedDescription,
            author: feedAuthor,
            link: URL(string: feedLink) ?? URL(string: "https://example.com")!,
            imageURL: feedImageURL.isEmpty ? nil : URL(string: feedImageURL),
            language: feedLanguage,
            category: feedCategory,
            explicit: feedExplicit
        )

        generatedXML = PodcastFeedGenerator.generateRSSFeed(
            config: config,
            episodes: episodes
        )
    }

    /// Handles audio file import for auto-populating episodes.
    ///
    /// - Parameter result: The file importer result.
    private func handleAudioImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let title = url.deletingPathExtension().lastPathComponent
                if let episode = PodcastFeedGenerator.episodeFromFile(url: url, title: title) {
                    episodes.append(episode)
                }
            }
        case .failure:
            break
        }
    }

    /// Exports the generated RSS XML to a file via a save panel.
    private func exportFeed() {
        regenerateXML()

        let panel = NSSavePanel()
        panel.title = "Export Podcast Feed"
        panel.nameFieldStringValue = "\(feedTitle.isEmpty ? "podcast" : feedTitle).xml"
        panel.allowedContentTypes = [UTType.xml]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try generatedXML.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // In production, surface this error via an alert.
        }
    }

    // MARK: - Formatting Helpers

    /// Formats a duration in seconds as MM:SS or HH:MM:SS.
    ///
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A formatted duration string.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Formats a file size in bytes as a human-readable string.
    ///
    /// - Parameter bytes: The file size in bytes.
    /// - Returns: A formatted string (e.g., "12.3 MB").
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AddEpisodeView
// ---------------------------------------------------------------------------
/// A sheet view for manually adding a new podcast episode.
///
/// Provides text fields for episode metadata and calls the `onSave`
/// closure with the constructed ``PodcastEpisode`` when the user
/// taps "Add Episode".
private struct AddEpisodeView: View {

    // MARK: - State

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var audioURLString: String = "https://"
    @State private var duration: String = "0"
    @State private var fileSize: String = "0"
    @State private var publishDate: Date = Date()
    @State private var season: String = ""
    @State private var episodeNumber: String = ""
    @State private var mimeType: String = "audio/mpeg"

    // MARK: - Callbacks

    /// Called when the user saves the new episode.
    let onSave: (PodcastEpisode) -> Void

    /// Called when the user cancels.
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Episode Information") {
                    TextField("Title", text: $title)
                    TextField("Audio URL", text: $audioURLString)
                    DatePicker("Publish Date", selection: $publishDate, displayedComponents: .date)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 60)
                }

                Section("Details") {
                    TextField("Duration (seconds)", text: $duration)
                    TextField("File Size (bytes)", text: $fileSize)

                    Picker("MIME Type", selection: $mimeType) {
                        Text("MP3 (audio/mpeg)").tag("audio/mpeg")
                        Text("AAC (audio/mp4)").tag("audio/mp4")
                        Text("OGG (audio/ogg)").tag("audio/ogg")
                        Text("WAV (audio/x-wav)").tag("audio/x-wav")
                        Text("FLAC (audio/flac)").tag("audio/flac")
                    }
                }

                Section("Numbering (Optional)") {
                    TextField("Season", text: $season)
                    TextField("Episode", text: $episodeNumber)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Episode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Episode") {
                        let episode = PodcastEpisode(
                            title: title,
                            description: description,
                            audioURL: URL(string: audioURLString) ?? URL(string: "https://example.com/episode.mp3")!,
                            duration: TimeInterval(duration) ?? 0,
                            fileSize: Int64(fileSize) ?? 0,
                            publishDate: publishDate,
                            season: Int(season),
                            episode: Int(episodeNumber),
                            mimeType: mimeType
                        )
                        onSave(episode)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 550)
    }
}
