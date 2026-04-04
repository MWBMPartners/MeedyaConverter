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
                body: "MeedyaConverter ships with 25 built-in profiles across 7 categories:\n\n**Quick Start**: Web Standard (H.264), Web High Quality (H.265), Web Next-Gen (AV1), Quick Convert, Audio Extract (FLAC)\n\n**HDR-Aware**: 4K HDR Master, 4K HDR Compact, HDR → SDR (Tone-Map), PQ → HLG (Broadcast), PQ → DV+HLG (Max Compat)\n\n**Passthrough**: Remux to MKV, Remux to MP4 (no re-encoding)\n\n**Streaming**: 1080p CVBR, 4K CVBR (for HLS/DASH)\n\n**Professional**: ProRes Proxy, ProRes HQ, DNxHR SQ\n\n**Disc Authoring**: Blu-ray Compatible, DVD Compatible\n\n**Archival**: Lossless (FFV1/FLAC), ProRes 4444\n\n**Hardware**: Hardware H.264, Hardware H.265 (VideoToolbox)"
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
        title: "Container & Codec Compatibility",
        systemImage: "square.grid.3x3",
        summary: "Which video and audio codecs work in which container formats.",
        sections: [
            HelpSection(
                heading: "Overview",
                body: "Not every codec can be placed in every container format. For example, VP8/VP9 belong in WebM, while ProRes belongs in MOV. MeedyaConverter validates your codec/container choice before encoding and warns about incompatible combinations."
            ),
            HelpSection(
                heading: "Recommended Containers",
                body: "- **MP4**: Maximum compatibility — plays on browsers, phones, TVs, game consoles. Supports H.264, H.265, AV1, AAC, AC-3, E-AC-3.\n- **MKV**: Maximum flexibility — supports every codec, subtitle format, and chapter style. Best for archival and multi-stream content.\n- **MOV**: Professional editing — native support in Final Cut Pro, DaVinci Resolve, Premiere Pro. Supports ProRes, DNxHR.\n- **WebM**: Modern web delivery — supports VP8, VP9, AV1 video with Opus or Vorbis audio."
            ),
            HelpSection(
                heading: "TrueHD in MP4",
                body: "Dolby TrueHD is not part of the official MP4 specification, but is widely supported by major players (Plex, Jellyfin, VLC, MPC-HC, Infuse). MeedyaConverter allows TrueHD in MP4 with one important rule:\n\nIn MP4 containers only: TrueHD must NOT be the default audio stream. A fully compatible codec (AAC, AC-3, or E-AC-3) must also be present and set as default. This ensures universal playback.\n\nThis restriction applies only to MP4-family containers. In MKV and all other containers where TrueHD is officially supported, it can be set as the default audio stream with no restrictions."
            ),
            HelpSection(
                heading: "HDR & Dolby Vision",
                body: "HDR metadata (HDR10, HDR10+, HLG, Dolby Vision) requires:\n\n1. A compatible codec: H.265, AV1, or VP9\n2. 10-bit pixel format (yuv420p10le)\n3. A supported container: MP4, MKV, MOV, or TS\n\nDolby Vision is supported in MP4, MKV, MOV, and MPEG-TS containers. WebM supports HDR10 and HLG but not Dolby Vision.\n\n**PQ → HLG Conversion:** Sources mastered in PQ (SMPTE ST 2084) can be converted to HLG (ARIB STD-B67) for broadcast compatibility. This preserves HDR while changing the transfer function. Use the 'PQ → HLG (Broadcast)' profile or enable 'Convert PQ to HLG' in output settings. When hlg-tools (github.com/wswartzendruber/hlg-tools) is installed it is used automatically for higher quality; otherwise FFmpeg's zscale filter is used as fallback.\n\n**PQ → DV+HLG (Maximum Compatibility):** Combines PQ→HLG conversion with Dolby Vision Profile 8.4 RPU generation via dovi_tool. Produces a single stream with three-tier playback: Dolby Vision on DV devices, HLG on broadcast/HLG devices, and SDR on legacy displays. Requires dovi_tool, HEVC codec, and a DV-capable container (MP4, MKV, MOV, TS)."
            ),
            HelpSection(
                heading: "Chapter Support",
                body: "Chapters (markers and titles) are supported in MKV, MP4, M4V, M4B, MOV, and OGG containers. When converting to a container that doesn't support chapters (WebM, AVI, TS), chapter data is silently dropped.\n\nChapters are always copied from source to output by default."
            ),
            HelpSection(
                heading: "Subtitle Compatibility",
                body: "MKV supports all subtitle formats (SRT, ASS/SSA, PGS, VobSub, DVB-SUB, WebVTT). MP4 and MOV only support text-based subtitles (SRT). WebM supports WebVTT.\n\nWhen remuxing from MKV to MP4, image-based subtitles (PGS, VobSub) will be dropped unless converted to text first."
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
