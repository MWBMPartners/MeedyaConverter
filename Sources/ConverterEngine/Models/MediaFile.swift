// ============================================================================
// MeedyaConverter — MediaFile
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MediaFile

/// Represents a complete media file with all its streams and metadata.
///
/// This is the primary data model populated by media probing (ffprobe + MediaInfo).
/// It contains all information needed to make encoding decisions and display
/// source file details in the UI.
public struct MediaFile: Identifiable, Codable, Sendable {

    // MARK: - Identification

    /// Unique identifier for this media file instance.
    public let id: UUID

    /// The file URL on disk.
    public var fileURL: URL

    /// The file name without path (e.g., "movie.mkv").
    public var fileName: String {
        return fileURL.lastPathComponent
    }

    /// The file size in bytes.
    public var fileSize: UInt64?

    // MARK: - Container

    /// The detected container format of this file.
    public var containerFormat: ContainerFormat?

    /// The raw container format name as reported by ffprobe (e.g., "matroska,webm").
    public var containerFormatName: String?

    // MARK: - Streams

    /// All streams (video, audio, subtitle, data) found in this file.
    public var streams: [MediaStream]

    // MARK: - File-Level Metadata

    /// Total duration of the file in seconds.
    public var duration: TimeInterval?

    /// Overall bitrate of the file in bits per second.
    public var overallBitrate: Int?

    /// File-level metadata tags (title, artist, album, date, etc.).
    public var metadata: [String: String]

    /// Chapter markers in the file.
    public var chapters: [Chapter]

    // MARK: - Probe Information

    /// Timestamp when this file was last probed/analysed.
    public var probedAt: Date?

    /// The probe tool versions used (for cache invalidation).
    public var probeVersions: [String: String]?

    // MARK: - Initialiser

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        fileSize: UInt64? = nil,
        containerFormat: ContainerFormat? = nil,
        containerFormatName: String? = nil,
        streams: [MediaStream] = [],
        duration: TimeInterval? = nil,
        overallBitrate: Int? = nil,
        metadata: [String: String] = [:],
        chapters: [Chapter] = [],
        probedAt: Date? = nil,
        probeVersions: [String: String]? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.containerFormat = containerFormat
        self.containerFormatName = containerFormatName
        self.streams = streams
        self.duration = duration
        self.overallBitrate = overallBitrate
        self.metadata = metadata
        self.chapters = chapters
        self.probedAt = probedAt
        self.probeVersions = probeVersions
    }

    // MARK: - Stream Access Helpers

    /// All video streams in this file.
    public var videoStreams: [MediaStream] {
        return streams.filter { $0.streamType == .video }
    }

    /// All audio streams in this file.
    public var audioStreams: [MediaStream] {
        return streams.filter { $0.streamType == .audio }
    }

    /// All subtitle streams in this file.
    public var subtitleStreams: [MediaStream] {
        return streams.filter { $0.streamType == .subtitle }
    }

    /// All data/attachment streams in this file.
    public var dataStreams: [MediaStream] {
        return streams.filter { $0.streamType == .data || $0.streamType == .attachment }
    }

    /// The primary (first/default) video stream, if any.
    public var primaryVideoStream: MediaStream? {
        return videoStreams.first { $0.isDefault } ?? videoStreams.first
    }

    /// The primary (first/default) audio stream, if any.
    public var primaryAudioStream: MediaStream? {
        return audioStreams.first { $0.isDefault } ?? audioStreams.first
    }

    /// Whether this file contains any video streams.
    public var hasVideo: Bool {
        return !videoStreams.isEmpty
    }

    /// Whether this file contains any audio streams.
    public var hasAudio: Bool {
        return !audioStreams.isEmpty
    }

    /// Whether this file is audio-only (has audio but no video).
    public var isAudioOnly: Bool {
        return hasAudio && !hasVideo
    }

    /// Whether any video stream contains HDR content.
    public var hasHDR: Bool {
        return videoStreams.contains { !$0.hdrFormats.isEmpty }
    }

    /// Whether any video stream contains Dolby Vision metadata.
    public var hasDolbyVision: Bool {
        return videoStreams.contains { $0.hdrFormats.contains(.dolbyVision) }
    }

    /// Whether any video stream contains HDR10+ dynamic metadata.
    public var hasHDR10Plus: Bool {
        return videoStreams.contains { $0.hdrFormats.contains(.hdr10Plus) }
    }

    /// Whether any video stream contains HLG content.
    public var hasHLG: Bool {
        return videoStreams.contains { $0.hdrFormats.contains(.hlg) }
    }

    /// Whether any video stream contains 3D/stereoscopic content.
    public var hasStereo3D: Bool {
        return videoStreams.contains { $0.isStereo3D }
    }

    /// Whether any audio stream has matrix encoding metadata.
    public var hasMatrixEncoding: Bool {
        return audioStreams.contains { $0.matrixEncoding != nil }
    }

    // MARK: - Display Helpers

    /// A formatted file size string (e.g., "1.5 GB", "350 MB").
    public var fileSizeString: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// A formatted duration string (e.g., "1:23:45", "0:05:30").
    public var durationString: String? {
        guard let dur = duration else { return nil }
        let hours = Int(dur) / 3600
        let minutes = (Int(dur) % 3600) / 60
        let seconds = Int(dur) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// A concise summary of this file for display (e.g., "MKV • 1920×1080 • H.265 HDR • 5.1 AC-3 • 1:23:45").
    public var summaryString: String {
        var parts: [String] = []

        // Container
        if let container = containerFormat {
            parts.append(container.displayName)
        }

        // Primary video
        if let video = primaryVideoStream {
            parts.append(video.summaryString)
        }

        // Primary audio
        if let audio = primaryAudioStream {
            parts.append(audio.summaryString)
        }

        // Duration
        if let dur = durationString {
            parts.append(dur)
        }

        return parts.joined(separator: " • ")
    }
}

// MARK: - Chapter

/// A chapter marker within a media file.
public struct Chapter: Identifiable, Codable, Sendable {
    /// Unique identifier for this chapter.
    public let id: UUID

    /// Chapter number (1-based).
    public var number: Int

    /// Chapter title (e.g., "Opening Credits", "Chapter 1").
    public var title: String?

    /// Start time of this chapter in seconds from the beginning of the file.
    public var startTime: TimeInterval

    /// End time of this chapter in seconds.
    public var endTime: TimeInterval

    /// Duration of this chapter in seconds.
    public var duration: TimeInterval {
        return endTime - startTime
    }

    /// Chapter-level metadata tags.
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        number: Int,
        title: String? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.metadata = metadata
    }
}
