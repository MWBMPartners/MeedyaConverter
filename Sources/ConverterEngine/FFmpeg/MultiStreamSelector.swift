// ============================================================================
// MeedyaConverter — MultiStreamSelector
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - StreamSelection

/// Represents a user's selection of streams from a source file.
public struct StreamSelection: Codable, Sendable {
    /// Selected video stream indices (empty = default/auto).
    public var videoStreamIndices: [Int]

    /// Selected audio stream indices (empty = default/auto).
    public var audioStreamIndices: [Int]

    /// Selected subtitle stream indices (empty = none).
    public var subtitleStreamIndices: [Int]

    /// Selected data/attachment stream indices.
    public var dataStreamIndices: [Int]

    /// Whether to map all streams regardless of selection.
    public var mapAll: Bool

    public init(
        videoStreamIndices: [Int] = [],
        audioStreamIndices: [Int] = [],
        subtitleStreamIndices: [Int] = [],
        dataStreamIndices: [Int] = [],
        mapAll: Bool = false
    ) {
        self.videoStreamIndices = videoStreamIndices
        self.audioStreamIndices = audioStreamIndices
        self.subtitleStreamIndices = subtitleStreamIndices
        self.dataStreamIndices = dataStreamIndices
        self.mapAll = mapAll
    }

    /// Whether any specific stream selection has been made.
    public var hasSelection: Bool {
        mapAll || !videoStreamIndices.isEmpty || !audioStreamIndices.isEmpty ||
        !subtitleStreamIndices.isEmpty || !dataStreamIndices.isEmpty
    }

    /// Total number of selected streams.
    public var totalSelectedStreams: Int {
        videoStreamIndices.count + audioStreamIndices.count +
        subtitleStreamIndices.count + dataStreamIndices.count
    }
}

// MARK: - StreamCompatibility

/// Describes container format capabilities for multiple streams.
public struct StreamCompatibility: Sendable {
    /// Maximum number of video streams supported.
    public var maxVideoStreams: Int

    /// Maximum number of audio streams supported.
    public var maxAudioStreams: Int

    /// Maximum number of subtitle streams supported.
    public var maxSubtitleStreams: Int

    /// Whether attachments (fonts, images) are supported.
    public var supportsAttachments: Bool

    /// Whether chapters are supported.
    public var supportsChapters: Bool

    public init(
        maxVideoStreams: Int,
        maxAudioStreams: Int,
        maxSubtitleStreams: Int,
        supportsAttachments: Bool,
        supportsChapters: Bool
    ) {
        self.maxVideoStreams = maxVideoStreams
        self.maxAudioStreams = maxAudioStreams
        self.maxSubtitleStreams = maxSubtitleStreams
        self.supportsAttachments = supportsAttachments
        self.supportsChapters = supportsChapters
    }
}

// MARK: - StreamValidationError

/// Errors from stream selection validation.
public enum StreamValidationError: Error, Sendable, CustomStringConvertible {
    case tooManyVideoStreams(selected: Int, max: Int)
    case tooManyAudioStreams(selected: Int, max: Int)
    case tooManySubtitleStreams(selected: Int, max: Int)
    case attachmentsNotSupported
    case noStreamsSelected
    case invalidStreamIndex(Int)

    public var description: String {
        switch self {
        case .tooManyVideoStreams(let sel, let max):
            return "Selected \(sel) video streams but container supports max \(max)"
        case .tooManyAudioStreams(let sel, let max):
            return "Selected \(sel) audio streams but container supports max \(max)"
        case .tooManySubtitleStreams(let sel, let max):
            return "Selected \(sel) subtitle streams but container supports max \(max)"
        case .attachmentsNotSupported:
            return "Selected container does not support attachments"
        case .noStreamsSelected:
            return "No streams selected for output"
        case .invalidStreamIndex(let idx):
            return "Stream index \(idx) does not exist in source"
        }
    }
}

// MARK: - MultiStreamSelector

/// Handles multi-stream selection, validation, and FFmpeg argument building
/// for files with multiple video, audio, or subtitle streams.
///
/// Supports DVD multi-angle, multi-language audio, and subtitle selection
/// with container format compatibility checking.
///
/// Phase 3.4
public struct MultiStreamSelector: Sendable {

    // MARK: - Container Compatibility

    /// Get stream compatibility for a container format.
    ///
    /// - Parameter container: Container format string (e.g., "mp4", "mkv", "webm").
    /// - Returns: Stream compatibility information.
    public static func compatibility(for container: String) -> StreamCompatibility {
        switch container.lowercased() {
        case "mkv", "matroska":
            return StreamCompatibility(
                maxVideoStreams: 99,
                maxAudioStreams: 99,
                maxSubtitleStreams: 99,
                supportsAttachments: true,
                supportsChapters: true
            )
        case "mp4", "m4v":
            return StreamCompatibility(
                maxVideoStreams: 1,
                maxAudioStreams: 99,
                maxSubtitleStreams: 99,
                supportsAttachments: false,
                supportsChapters: true
            )
        case "mov":
            return StreamCompatibility(
                maxVideoStreams: 99,
                maxAudioStreams: 99,
                maxSubtitleStreams: 99,
                supportsAttachments: false,
                supportsChapters: true
            )
        case "webm":
            return StreamCompatibility(
                maxVideoStreams: 1,
                maxAudioStreams: 1,
                maxSubtitleStreams: 1,
                supportsAttachments: false,
                supportsChapters: true
            )
        case "ts", "mpegts":
            return StreamCompatibility(
                maxVideoStreams: 99,
                maxAudioStreams: 99,
                maxSubtitleStreams: 99,
                supportsAttachments: false,
                supportsChapters: false
            )
        case "avi":
            return StreamCompatibility(
                maxVideoStreams: 1,
                maxAudioStreams: 99,
                maxSubtitleStreams: 0,
                supportsAttachments: false,
                supportsChapters: false
            )
        default:
            return StreamCompatibility(
                maxVideoStreams: 1,
                maxAudioStreams: 99,
                maxSubtitleStreams: 99,
                supportsAttachments: false,
                supportsChapters: true
            )
        }
    }

    // MARK: - Validation

    /// Validate a stream selection against a container format.
    ///
    /// - Parameters:
    ///   - selection: User's stream selection.
    ///   - container: Target container format.
    ///   - sourceStreamCount: Total number of streams in the source.
    /// - Returns: Array of validation errors (empty = valid).
    public static func validate(
        selection: StreamSelection,
        container: String,
        sourceStreamCount: Int
    ) -> [StreamValidationError] {
        guard !selection.mapAll else { return [] }

        var errors: [StreamValidationError] = []
        let compat = compatibility(for: container)

        if selection.videoStreamIndices.count > compat.maxVideoStreams {
            errors.append(.tooManyVideoStreams(
                selected: selection.videoStreamIndices.count,
                max: compat.maxVideoStreams
            ))
        }

        if selection.audioStreamIndices.count > compat.maxAudioStreams {
            errors.append(.tooManyAudioStreams(
                selected: selection.audioStreamIndices.count,
                max: compat.maxAudioStreams
            ))
        }

        if selection.subtitleStreamIndices.count > compat.maxSubtitleStreams {
            errors.append(.tooManySubtitleStreams(
                selected: selection.subtitleStreamIndices.count,
                max: compat.maxSubtitleStreams
            ))
        }

        if !selection.dataStreamIndices.isEmpty && !compat.supportsAttachments {
            errors.append(.attachmentsNotSupported)
        }

        // Validate stream indices
        let allIndices = selection.videoStreamIndices + selection.audioStreamIndices +
                         selection.subtitleStreamIndices + selection.dataStreamIndices
        for index in allIndices where index >= sourceStreamCount || index < 0 {
            errors.append(.invalidStreamIndex(index))
        }

        return errors
    }

    // MARK: - FFmpeg Argument Building

    /// Build FFmpeg `-map` arguments for a stream selection.
    ///
    /// - Parameters:
    ///   - selection: User's stream selection.
    ///   - inputIndex: FFmpeg input file index (default 0).
    /// - Returns: FFmpeg argument array.
    public static func buildMapArguments(
        selection: StreamSelection,
        inputIndex: Int = 0
    ) -> [String] {
        if selection.mapAll {
            return ["-map", "\(inputIndex)"]
        }

        var args: [String] = []

        // Map selected video streams
        for idx in selection.videoStreamIndices {
            args += ["-map", "\(inputIndex):v:\(idx)"]
        }

        // Map selected audio streams
        for idx in selection.audioStreamIndices {
            args += ["-map", "\(inputIndex):a:\(idx)"]
        }

        // Map selected subtitle streams
        for idx in selection.subtitleStreamIndices {
            args += ["-map", "\(inputIndex):s:\(idx)"]
        }

        // Map selected data/attachment streams
        for idx in selection.dataStreamIndices {
            args += ["-map", "\(inputIndex):t:\(idx)"]
        }

        // If nothing selected, map defaults
        if args.isEmpty {
            args += ["-map", "\(inputIndex):v:0?"]
            args += ["-map", "\(inputIndex):a:0?"]
        }

        return args
    }

    /// Build FFmpeg arguments for per-stream codec settings.
    ///
    /// When multiple streams of the same type are selected, each may need
    /// individual codec settings.
    ///
    /// - Parameters:
    ///   - audioCodecs: Map of output audio stream index to codec name.
    ///   - subtitleCodecs: Map of output subtitle stream index to codec name.
    /// - Returns: FFmpeg argument array.
    public static func buildPerStreamCodecArguments(
        audioCodecs: [Int: String] = [:],
        subtitleCodecs: [Int: String] = [:]
    ) -> [String] {
        var args: [String] = []

        for (index, codec) in audioCodecs.sorted(by: { $0.key < $1.key }) {
            args += ["-c:a:\(index)", codec]
        }

        for (index, codec) in subtitleCodecs.sorted(by: { $0.key < $1.key }) {
            args += ["-c:s:\(index)", codec]
        }

        return args
    }

    /// Build FFmpeg arguments to set disposition on specific output streams.
    ///
    /// - Parameters:
    ///   - defaultAudioIndex: Index of the default audio stream in output.
    ///   - defaultSubtitleIndex: Index of the default subtitle stream in output (nil = none).
    /// - Returns: FFmpeg argument array.
    public static func buildDispositionArguments(
        defaultAudioIndex: Int = 0,
        defaultSubtitleIndex: Int? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-disposition:a:\(defaultAudioIndex)", "default"]

        if let subIdx = defaultSubtitleIndex {
            args += ["-disposition:s:\(subIdx)", "default"]
        }

        return args
    }

    // MARK: - Stream Filtering

    /// Filter streams by type from a list of MediaStream objects.
    ///
    /// - Parameters:
    ///   - streams: All streams from the source file.
    ///   - type: Stream type to filter for.
    /// - Returns: Streams matching the specified type, sorted by index.
    public static func filterStreams(
        _ streams: [MediaStream],
        type: StreamType
    ) -> [MediaStream] {
        streams.filter { $0.streamType == type }
              .sorted { $0.streamIndex < $1.streamIndex }
    }

    /// Create a default stream selection from a source file's streams.
    ///
    /// Selects the first video stream, all audio streams, and all subtitle streams.
    ///
    /// - Parameter streams: All streams from the source file.
    /// - Returns: Default stream selection.
    public static func defaultSelection(
        from streams: [MediaStream]
    ) -> StreamSelection {
        let video = filterStreams(streams, type: .video)
        let audio = filterStreams(streams, type: .audio)
        let subtitle = filterStreams(streams, type: .subtitle)

        return StreamSelection(
            videoStreamIndices: video.isEmpty ? [] : [0],
            audioStreamIndices: audio.enumerated().map(\.offset),
            subtitleStreamIndices: subtitle.enumerated().map(\.offset)
        )
    }
}
