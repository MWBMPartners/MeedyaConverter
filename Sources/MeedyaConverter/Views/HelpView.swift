// ============================================================================
// MeedyaConverter — HelpView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// MARK: - HelpTopic

/// A help documentation topic with title and content.
struct HelpTopic: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let summary: String
    let sections: [HelpSection]
}

/// A section within a help topic.
struct HelpSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

// MARK: - HelpView

/// In-app help system with searchable documentation.
///
/// Displays help topics in a sidebar-detail layout. Topics cover
/// getting started, encoding, profiles, the job queue, keyboard
/// shortcuts, and troubleshooting.
struct HelpView: View {

    // MARK: - State

    @State private var selectedTopic: HelpTopic?
    @State private var searchText = ""

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopic) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search help...")
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
        .onAppear {
            if selectedTopic == nil {
                selectedTopic = helpTopics.first
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
                        .foregroundStyle(.accent)
                    Text(topic.title)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 4)

                Text(topic.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                // Sections
                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.headline)
                        Text(section.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Filtering

    private var filteredTopics: [HelpTopic] {
        if searchText.isEmpty { return helpTopics }
        let query = searchText.lowercased()
        return helpTopics.filter { topic in
            topic.title.lowercased().contains(query) ||
            topic.summary.lowercased().contains(query) ||
            topic.sections.contains { $0.heading.lowercased().contains(query) || $0.body.lowercased().contains(query) }
        }
    }
}

// MARK: - Help Topics Data

/// All built-in help topics.
private let helpTopics: [HelpTopic] = [
    HelpTopic(
        title: "Getting Started",
        systemImage: "play.circle",
        summary: "Learn the basics of importing, configuring, and encoding media files.",
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
        title: "Encoding Profiles",
        systemImage: "slider.horizontal.3",
        summary: "Understand and manage encoding presets for different use cases.",
        sections: [
            HelpSection(
                heading: "Built-in Profiles",
                body: "MeedyaConverter ships with 7 built-in profiles:\n\n- Web Standard: H.264/AAC in MP4 for maximum compatibility\n- Web High Quality: H.265/AAC in MP4 for better compression\n- Web Next-Gen: AV1/Opus in WebM for modern browsers\n- 4K HDR Master: H.265 HDR with E-AC-3 in MKV\n- Audio Extract: Lossless FLAC extraction\n- Quick Convert: Fast H.264 encoding\n- Archive Lossless: FFV1/FLAC for preservation"
            ),
            HelpSection(
                heading: "Custom Profiles",
                body: "Open the Profile Manager from Output Settings > Manage Profiles. You can create new profiles, duplicate built-in ones, and configure all video/audio/container settings. Profiles are saved as JSON and can be imported/exported for sharing."
            ),
            HelpSection(
                heading: "CRF Quality Scale",
                body: "CRF (Constant Rate Factor) controls quality vs file size. Lower values = higher quality, larger files. Typical ranges:\n\n- 18–20: Visually lossless\n- 20–23: High quality (recommended)\n- 23–28: Good quality, smaller files\n- 28+: Lower quality, smallest files"
            ),
        ]
    ),

    HelpTopic(
        title: "Encoding Queue",
        systemImage: "list.number",
        summary: "Manage batch encoding of multiple files.",
        sections: [
            HelpSection(
                heading: "Queue Management",
                body: "Add multiple files to the queue from the Source or Output views. Jobs are processed sequentially. Drag to reorder pending jobs. Use the toolbar to start, pause, or cancel the queue."
            ),
            HelpSection(
                heading: "Job States",
                body: "Each job shows its current state:\n\n- Queued (grey clock): Waiting to be processed\n- Encoding (blue bolt): Currently encoding with progress bar\n- Paused (orange pause): Encoding suspended\n- Completed (green checkmark): Successfully finished\n- Failed (red X): Encoding error occurred\n- Cancelled (grey dash): Stopped by user"
            ),
        ]
    ),

    HelpTopic(
        title: "Keyboard Shortcuts",
        systemImage: "keyboard",
        summary: "Speed up your workflow with keyboard shortcuts.",
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
        title: "Troubleshooting",
        systemImage: "wrench",
        summary: "Solutions for common issues.",
        sections: [
            HelpSection(
                heading: "FFmpeg Not Found",
                body: "MeedyaConverter requires FFmpeg to encode media. If FFmpeg is not detected automatically, you can set a custom path in Settings > Paths. Download FFmpeg from https://ffmpeg.org or install via Homebrew: brew install ffmpeg"
            ),
            HelpSection(
                heading: "Encoding Fails Immediately",
                body: "Check the Activity Log for the FFmpeg error output. Common causes:\n\n- Input file is corrupted or incomplete\n- Output directory is not writable\n- Insufficient disk space\n- Unsupported codec/container combination"
            ),
            HelpSection(
                heading: "Poor Encoding Quality",
                body: "Try lowering the CRF value (e.g., from 23 to 18) or switching to a slower preset (e.g., from 'medium' to 'slow'). For HDR content, ensure 'Preserve HDR' is enabled in your profile."
            ),
        ]
    ),
]

// MARK: - HelpTopic Hashable Conformance

extension HelpTopic: Hashable {
    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
