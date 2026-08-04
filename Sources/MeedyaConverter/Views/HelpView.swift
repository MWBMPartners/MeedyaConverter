// ============================================================================
// MeedyaConverter — HelpView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - HelpTopic

/// A help documentation topic with a title and one or more sections.
struct HelpTopic: Identifiable, Hashable {
    /// Stable identity — the source filename for bundled topics, or the title
    /// for the hardcoded fallback topics.
    let id: String
    let title: String
    let systemImage: String
    let summary: String
    /// Lower values sort earlier in the sidebar.
    let sortOrder: Int
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A section within a help topic.
struct HelpSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
    /// When `true`, the body is rendered verbatim in a monospaced font because
    /// it contains a pipe table or fenced code that `AttributedString` cannot
    /// render faithfully.
    let isPreformatted: Bool

    init(heading: String, body: String, isPreformatted: Bool = false) {
        self.heading = heading
        self.body = body
        self.isPreformatted = isPreformatted
    }
}

// MARK: - HelpView

/// In-app help system with searchable documentation.
///
/// Topics are loaded from the Markdown files bundled under `Help/` in the
/// app's resource bundle (`Bundle.module`) — the single source of truth for
/// user documentation. Each file is parsed with ``HelpTopicParser`` and
/// rendered in a sidebar-detail layout. If the bundled Help directory is
/// absent (a build/packaging regression) the view falls back to a small set
/// of built-in topics so Help is never blank.
struct HelpView: View {

    // MARK: - State

    @State private var topics: [HelpTopic] = []
    @State private var selectedTopic: HelpTopic?
    @State private var searchText = ""

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopic) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    .tag(topic)
                    .accessibilityLabel(topic.title)
                    .accessibilityHint(topic.summary)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search help…")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let topic = selectedTopic {
                topicDetailView(topic)
            } else {
                ContentUnavailableView(
                    "MeedyaConverter Help",
                    systemImage: "questionmark.circle",
                    description: Text("Select a topic from the sidebar.")
                )
            }
        }
        .navigationTitle("Help")
        .frame(minWidth: 700, minHeight: 450)
        .task {
            if topics.isEmpty {
                topics = Self.loadTopics()
            }
            if selectedTopic == nil {
                selectedTopic = topics.first
            }
        }
    }

    // MARK: - Topic Detail

    private func topicDetailView(_ topic: HelpTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: topic.systemImage)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(topic.title)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(topic.title)
                .accessibilityAddTraits(.isHeader)

                if !topic.summary.isEmpty {
                    Text(topic.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Sections
                ForEach(topic.sections) { section in
                    sectionView(section)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !section.heading.isEmpty {
                Text(section.heading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            if section.isPreformatted {
                // Tables and fenced code render verbatim, monospaced, and
                // scroll horizontally so wide tables stay legible.
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(section.body)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(Self.attributedMarkdown(section.body))
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Markdown rendering

    /// Render inline Markdown (bold, italic, links, inline code) while
    /// preserving line breaks. Falls back to the raw string if parsing fails.
    static func attributedMarkdown(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(markdown)
    }

    // MARK: - Filtering

    private var filteredTopics: [HelpTopic] {
        if searchText.isEmpty { return topics }
        let query = searchText.lowercased()
        return topics.filter { topic in
            topic.title.lowercased().contains(query) ||
            topic.summary.lowercased().contains(query) ||
            topic.sections.contains {
                $0.heading.lowercased().contains(query) || $0.body.lowercased().contains(query)
            }
        }
    }

    // MARK: - Topic Loading

    /// Load help topics from the bundled Markdown, or fall back to the
    /// built-in topics if the Help resource directory is unavailable.
    static func loadTopics() -> [HelpTopic] {
        loadBundledTopics() ?? fallbackTopics
    }

    /// Enumerate and parse the Markdown help files bundled under `Help/`.
    ///
    /// Returns `nil` (not an empty array) when the Help directory is absent,
    /// so callers can distinguish "no bundle" from "bundle present but empty"
    /// and choose the fallback path accordingly.
    private static func loadBundledTopics() -> [HelpTopic]? {
        guard let urls = Bundle.module.urls(
            forResourcesWithExtension: "md",
            subdirectory: "Help"
        ), !urls.isEmpty else {
            return nil
        }

        var topics: [HelpTopic] = []
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let document = HelpTopicParser.parse(text)
            let filename = url.lastPathComponent
            let meta = HelpTopicRegistry.metadata(for: filename, parsedTitle: document.title)
            let sections = document.sections.map {
                HelpSection(
                    heading: $0.heading,
                    body: $0.body,
                    isPreformatted: $0.requiresMonospace
                )
            }
            topics.append(
                HelpTopic(
                    id: filename,
                    title: meta.title,
                    systemImage: meta.systemImage,
                    summary: meta.summary,
                    sortOrder: meta.sortOrder,
                    sections: sections
                )
            )
        }

        return topics.sorted {
            ($0.sortOrder, $0.title.lowercased()) < ($1.sortOrder, $1.title.lowercased())
        }
    }
}

// MARK: - Help Topic Registry

/// Presentation metadata for the bundled Markdown help topics.
///
/// Maps a source filename to a display title, SF Symbol, one-line summary and
/// sidebar sort order. Any file without an explicit entry is given a sensible
/// default derived from its parsed title (or filename), so newly added help
/// files appear in the sidebar automatically without a code change.
enum HelpTopicRegistry {

    struct Metadata {
        let title: String
        let systemImage: String
        let summary: String
        let sortOrder: Int
    }

    /// Known topics, keyed by bundled filename. Sort order follows a natural
    /// onboarding-to-reference progression.
    static let entries: [String: Metadata] = [
        "getting-started.md": Metadata(
            title: "Getting Started",
            systemImage: "play.circle",
            summary: "Learn the basics of importing, configuring and encoding media files.",
            sortOrder: 10
        ),
        "encoding-guide.md": Metadata(
            title: "Encoding Guide",
            systemImage: "slider.horizontal.3",
            summary: "Detailed reference for video and audio encoding settings.",
            sortOrder: 20
        ),
        "container-codec-compatibility.md": Metadata(
            title: "Container & Codec Compatibility",
            systemImage: "square.grid.3x3",
            summary: "Which video and audio codecs work in which container formats.",
            sortOrder: 30
        ),
        "audio-format-compatibility.md": Metadata(
            title: "Audio Format Compatibility",
            systemImage: "waveform",
            summary: "The audio conversion matrix — what converts to what.",
            sortOrder: 40
        ),
        "adaptive-streaming.md": Metadata(
            title: "Adaptive Streaming",
            systemImage: "dot.radiowaves.left.and.right",
            summary: "Prepare HLS and MPEG-DASH packages for adaptive delivery.",
            sortOrder: 50
        ),
        "subtitle-tonemapping.md": Metadata(
            title: "Subtitles & Tone-Mapping",
            systemImage: "captions.bubble",
            summary: "Subtitle handling and HDR-to-SDR tone-mapping options.",
            sortOrder: 60
        ),
        "vector-conversion.md": Metadata(
            title: "Vector Conversion",
            systemImage: "scribble.variable",
            summary: "Convert vector artwork and rasterise for delivery.",
            sortOrder: 70
        ),
        "render-farm.md": Metadata(
            title: "Render Farm",
            systemImage: "server.rack",
            summary: "Distribute encoding jobs across multiple machines.",
            sortOrder: 80
        ),
        "cli-reference.md": Metadata(
            title: "CLI Reference",
            systemImage: "terminal",
            summary: "Command-line usage for the meedya-convert tool.",
            sortOrder: 90
        ),
        "faq.md": Metadata(
            title: "FAQ",
            systemImage: "questionmark.circle",
            summary: "Answers to frequently asked questions.",
            sortOrder: 100
        ),
        "troubleshooting.md": Metadata(
            title: "Troubleshooting",
            systemImage: "wrench.and.screwdriver",
            summary: "Solutions for common issues.",
            sortOrder: 110
        ),
        "updates.md": Metadata(
            title: "Updates",
            systemImage: "arrow.down.circle",
            summary: "How MeedyaConverter checks for and delivers updates.",
            sortOrder: 120
        ),
    ]

    /// Return the metadata for `filename`, synthesising a sensible default for
    /// any file not present in ``entries``.
    static func metadata(for filename: String, parsedTitle: String) -> Metadata {
        if let known = entries[filename] {
            return known
        }
        let fallbackTitle = parsedTitle.isEmpty ? titleFromFilename(filename) : parsedTitle
        return Metadata(
            title: fallbackTitle,
            systemImage: "doc.text",
            summary: "",
            // Unmapped files sort after all known topics, alphabetically.
            sortOrder: 1_000
        )
    }

    /// Derive a human-readable title from a filename, e.g.
    /// `colour-management.md` → `Colour Management`.
    private static func titleFromFilename(_ filename: String) -> String {
        let base = filename
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return base
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Fallback Help Topics

/// Built-in help topics used ONLY when the bundled `Help/` resource directory
/// is unavailable (a build/packaging regression). Ensures Help is never blank.
private let fallbackTopics: [HelpTopic] = [
    HelpTopic(
        id: "fallback-getting-started",
        title: "Getting Started",
        systemImage: "play.circle",
        summary: "Learn the basics of importing, configuring and encoding media files.",
        sortOrder: 10,
        sections: [
            HelpSection(
                heading: "Import Source Files",
                body: "Drag and drop media files onto the Source view, or use File > Import Media Files (Cmd+O) to browse. MeedyaConverter supports most video and audio formats including MP4, MKV, MOV, AVI, FLAC, and many more."
            ),
            HelpSection(
                heading: "Inspect Streams",
                body: "After importing, switch to the Streams tab to see all video, audio, subtitle, and data streams in your file. Each stream shows codec, resolution, channels, language, and special format badges (HDR, Dolby Vision, 3D)."
            ),
            HelpSection(
                heading: "Configure Output",
                body: "In the Output tab, select an encoding profile and choose an output directory. Profiles define the video codec, audio codec, quality settings, and container format."
            ),
            HelpSection(
                heading: "Start Encoding",
                body: "Click 'Add to Queue' to queue your file, then switch to the Queue tab and click 'Start Queue'. You can monitor progress, pause, resume, or cancel encoding at any time."
            ),
        ]
    ),

    HelpTopic(
        id: "fallback-encoding-profiles",
        title: "Encoding Profiles",
        systemImage: "slider.horizontal.3",
        summary: "Understand and manage encoding presets for different use cases.",
        sortOrder: 20,
        sections: [
            HelpSection(
                heading: "Built-in Profiles",
                body: "MeedyaConverter ships with built-in profiles across several categories including Quick Start, HDR-Aware, Passthrough, Streaming, Professional, Disc Authoring, Archival, and Hardware."
            ),
            HelpSection(
                heading: "Custom Profiles",
                body: "Open the Profile Manager from Output Settings > Manage Profiles. You can create new profiles, duplicate built-in ones, and configure all video/audio/container settings. Profiles are saved as JSON and can be imported/exported for sharing."
            ),
            HelpSection(
                heading: "CRF Quality Scale",
                body: "CRF (Constant Rate Factor) controls quality vs file size. Lower values = higher quality, larger files. 18–20 is visually lossless; 20–23 is high quality (recommended); 23–28 is good quality with smaller files."
            ),
        ]
    ),

    HelpTopic(
        id: "fallback-queue",
        title: "Encoding Queue",
        systemImage: "list.number",
        summary: "Manage batch encoding of multiple files.",
        sortOrder: 30,
        sections: [
            HelpSection(
                heading: "Queue Management",
                body: "Add multiple files to the queue from the Source or Output views. Jobs are processed sequentially. Drag to reorder pending jobs. Use the toolbar to start, pause, or cancel the queue."
            ),
            HelpSection(
                heading: "Job States",
                body: "Each job shows its current state: Queued, Encoding, Paused, Completed, Failed, or Cancelled."
            ),
        ]
    ),

    HelpTopic(
        id: "fallback-shortcuts",
        title: "Keyboard Shortcuts",
        systemImage: "keyboard",
        summary: "Speed up your workflow with keyboard shortcuts.",
        sortOrder: 40,
        sections: [
            HelpSection(
                heading: "File Operations",
                body: "Cmd+O: Import media files\nCmd+N: New window\nCmd+W: Close window\nCmd+,: Open Settings"
            ),
            HelpSection(
                heading: "Encoding",
                body: "Cmd+Return: Add selected file to queue\nCmd+.: Cancel current operation"
            ),
        ]
    ),

    HelpTopic(
        id: "fallback-troubleshooting",
        title: "Troubleshooting",
        systemImage: "wrench.and.screwdriver",
        summary: "Solutions for common issues.",
        sortOrder: 110,
        sections: [
            HelpSection(
                heading: "FFmpeg Not Found",
                body: "MeedyaConverter requires FFmpeg to encode media. If FFmpeg is not detected automatically, you can set a custom path in Settings > Paths."
            ),
            HelpSection(
                heading: "Encoding Fails Immediately",
                body: "Check the Activity Log for the FFmpeg error output. Common causes: a corrupted input file, an unwritable output directory, insufficient disk space, or an unsupported codec/container combination."
            ),
            HelpSection(
                heading: "Poor Encoding Quality",
                body: "Try lowering the CRF value (e.g., from 23 to 18) or switching to a slower preset. For HDR content, ensure 'Preserve HDR' is enabled in your profile."
            ),
        ]
    ),
]
