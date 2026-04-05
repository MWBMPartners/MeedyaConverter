// ============================================================================
// MeedyaConverter — StreamInspectorView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - StreamInspectorView

/// Displays all video, audio, subtitle, and data streams from the selected
/// media file with detailed metadata for each stream.
///
/// Streams are grouped by type (video, audio, subtitle, data) in
/// collapsible sections. Each stream row shows codec, resolution/channels,
/// language, bitrate, and HDR/special format badges.
struct StreamInspectorView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        Group {
            if let file = viewModel.selectedFile {
                streamListView(for: file)
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Import and select a source file to inspect its streams.")
                )
            }
        }
        .navigationTitle("Stream Inspector")
    }

    // MARK: - Stream List

    /// The main list of streams grouped by type.
    private func streamListView(for file: MediaFile) -> some View {
        List {
            // File overview header
            fileOverviewSection(file)

            // Video streams
            if !file.videoStreams.isEmpty {
                Section("Video Streams (\(file.videoStreams.count))") {
                    ForEach(file.videoStreams) { stream in
                        VideoStreamRow(stream: stream)
                    }
                }
            }

            // Audio streams
            if !file.audioStreams.isEmpty {
                Section("Audio Streams (\(file.audioStreams.count))") {
                    ForEach(file.audioStreams) { stream in
                        AudioStreamRow(stream: stream)
                    }
                }
            }

            // Subtitle streams
            if !file.subtitleStreams.isEmpty {
                Section("Subtitle Streams (\(file.subtitleStreams.count))") {
                    ForEach(file.subtitleStreams) { stream in
                        SubtitleStreamRow(stream: stream)
                    }
                }
            }

            // Data/attachment streams
            if !file.dataStreams.isEmpty {
                Section("Data Streams (\(file.dataStreams.count))") {
                    ForEach(file.dataStreams) { stream in
                        DataStreamRow(stream: stream)
                    }
                }
            }

            // Chapters
            if !file.chapters.isEmpty {
                Section("Chapters (\(file.chapters.count))") {
                    ForEach(file.chapters) { chapter in
                        ChapterRow(chapter: chapter)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - File Overview

    /// Summary section at the top showing file-level metadata.
    private func fileOverviewSection(_ file: MediaFile) -> some View {
        Section("File Info") {
            LabeledContent("File Name", value: file.fileName)
            if let container = file.containerFormat {
                LabeledContent("Container", value: container.displayName)
            }
            if let duration = file.durationString {
                LabeledContent("Duration", value: duration)
            }
            if let size = file.fileSizeString {
                LabeledContent("File Size", value: size)
            }
            if let bitrate = file.overallBitrate {
                LabeledContent("Overall Bitrate", value: formatBitrate(bitrate))
            }
        }
    }

    // MARK: - Helpers

    /// Format a bitrate (bits per second) to a human-readable string.
    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d kbps", bps / 1000)
        }
    }
}

// MARK: - VideoStreamRow

/// Detailed display of a single video stream.
struct VideoStreamRow: View {
    let stream: MediaStream

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header line: index, codec, resolution
            HStack {
                Text("Stream #\(stream.streamIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(stream.videoCodec?.displayName ?? stream.codecName ?? "Unknown")
                    .font(.body)
                    .fontWeight(.medium)

                if let res = stream.resolutionString {
                    Text(res)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Badges
                streamBadges
            }

            // Detail line
            HStack(spacing: 12) {
                if let fps = stream.frameRate {
                    metadataChip("fps", String(format: "%.3g", fps))
                }
                if let dar = stream.displayAspectRatio {
                    metadataChip("DAR", dar)
                }
                if let depth = stream.colourProperties?.bitDepth {
                    metadataChip("depth", "\(depth)-bit")
                }
                if let bitrate = stream.bitrate {
                    metadataChip("bitrate", formatBitrate(bitrate))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video stream \(stream.streamIndex): \(stream.summaryString)")
    }

    @ViewBuilder
    private var streamBadges: some View {
        HStack(spacing: 4) {
            if stream.isDefault {
                badge("Default", .blue)
            }
            ForEach(stream.hdrFormats, id: \.self) { hdr in
                badge(hdrLabel(hdr), .purple)
            }
            if stream.isStereo3D {
                badge("3D", .orange)
            }
        }
    }

    private func hdrLabel(_ format: HDRFormat) -> String {
        switch format {
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .dolbyVision: return "DV"
        case .dolbyVisionHDR10: return "DV+HDR10"
        case .hlg: return "HLG"
        case .pq: return "PQ"
        case .sdr: return "SDR"
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func metadataChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d kbps", bps / 1000)
        }
    }
}

// MARK: - AudioStreamRow

/// Detailed display of a single audio stream.
struct AudioStreamRow: View {
    let stream: MediaStream

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Stream #\(stream.streamIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(stream.audioCodec?.displayName ?? stream.codecName ?? "Unknown")
                    .font(.body)
                    .fontWeight(.medium)

                if let layout = stream.channelLayout {
                    Text(layout.displayName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Language and flags
                HStack(spacing: 4) {
                    if let lang = stream.language {
                        Text(lang.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if stream.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            // Detail line
            HStack(spacing: 12) {
                if let sr = stream.sampleRate {
                    metadataChip("sample", "\(sr) Hz")
                }
                if let depth = stream.audioBitDepth {
                    metadataChip("depth", "\(depth)-bit")
                }
                if let bitrate = stream.bitrate {
                    metadataChip("bitrate", formatBitrate(bitrate))
                }
                if let title = stream.title {
                    metadataChip("title", title)
                }
                if let matrix = stream.matrixEncoding {
                    Text(matrix.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio stream \(stream.streamIndex): \(stream.summaryString)")
    }

    private func metadataChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else {
            return String(format: "%d kbps", bps / 1000)
        }
    }
}

// MARK: - SubtitleStreamRow

/// Display of a single subtitle stream.
struct SubtitleStreamRow: View {
    let stream: MediaStream

    var body: some View {
        HStack {
            Text("Stream #\(stream.streamIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(stream.subtitleFormat?.displayName ?? stream.codecName ?? "Unknown")
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 4) {
                if let lang = stream.language {
                    Text(lang.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                if stream.isForced {
                    Text("Forced")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                if stream.isDefault {
                    Text("Default")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subtitle stream \(stream.streamIndex): \(stream.summaryString)")
    }
}

// MARK: - DataStreamRow

/// Display of a single data/attachment stream.
struct DataStreamRow: View {
    let stream: MediaStream

    var body: some View {
        HStack {
            Text("Stream #\(stream.streamIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(stream.codecName ?? "Data")
                .font(.body)

            if let title = stream.title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ChapterRow

/// Display of a single chapter marker.
struct ChapterRow: View {
    let chapter: Chapter

    var body: some View {
        HStack {
            Text("#\(chapter.number)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            Text(chapter.title ?? "Chapter \(chapter.number)")
                .font(.body)

            Spacer()

            Text(formatTime(chapter.startTime))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text("—")
                .foregroundStyle(.quaternary)

            Text(formatTime(chapter.endTime))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter \(chapter.number): \(chapter.title ?? "Untitled"), \(formatTime(chapter.startTime)) to \(formatTime(chapter.endTime))")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
