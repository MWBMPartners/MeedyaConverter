// ============================================================================
// MeedyaConverter — VideoTrimmer (Issue #318)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - TrimSegment

/// A contiguous segment of media to keep in the output.
///
/// Each segment represents a time range that will appear in the final
/// output after trimming and snipping operations. Segments are ordered
/// chronologically and do not overlap.
///
/// Phase 12 — Video Trimming and Splitting (Issue #318)
public struct TrimSegment: Identifiable, Codable, Sendable {

    /// Unique identifier for this segment.
    public let id: UUID

    /// Start time of this segment in seconds from the beginning of the source.
    public let startTime: TimeInterval

    /// End time of this segment in seconds from the beginning of the source.
    public let endTime: TimeInterval

    /// Optional user-defined label for this segment (e.g., "Chapter 1", "Intro").
    public let label: String?

    /// Duration of this segment in seconds.
    public var duration: TimeInterval {
        endTime - startTime
    }

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        label: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }
}

// MARK: - SnipRegion

/// A region of media to cut out (remove from the middle).
///
/// Snip regions define portions of the source that should be excluded
/// from the output. The inverse of snip regions produces the set of
/// ``TrimSegment`` instances that compose the final output.
///
/// Phase 12 — Video Trimming and Splitting (Issue #318)
public struct SnipRegion: Identifiable, Codable, Sendable {

    /// Unique identifier for this snip region.
    public let id: UUID

    /// Start time of the region to remove, in seconds.
    public let startTime: TimeInterval

    /// End time of the region to remove, in seconds.
    public let endTime: TimeInterval

    /// Duration of this snip region in seconds.
    public var duration: TimeInterval {
        endTime - startTime
    }

    /// Memberwise initializer.
    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - TrimConfig

/// Configuration for a video trimming, snipping, or splitting operation.
///
/// Combines head/tail trim points, interior snip regions, and split
/// options into a single configuration object. All time values are
/// in seconds from the start of the source file.
///
/// Phase 12 — Video Trimming and Splitting (Issue #318)
public struct TrimConfig: Codable, Sendable {

    /// Optional trim start time. Content before this point is discarded.
    public var trimStart: TimeInterval?

    /// Optional trim end time. Content after this point is discarded.
    public var trimEnd: TimeInterval?

    /// Regions within the media to cut out (remove from the middle).
    /// These regions are sorted by start time before processing.
    public var snipRegions: [SnipRegion]

    /// When `true`, split the output at chapter boundaries.
    /// Requires chapter metadata in the source file.
    public var splitByChapters: Bool

    /// When set, split the output into files no larger than this size in bytes.
    /// Uses FFmpeg's `-fs` flag or segment muxer for size-based splitting.
    public var splitBySize: Int64?

    /// When `true`, use stream copy (`-c copy`) for lossless trimming
    /// without re-encoding. Faster but may cause imprecise cuts at
    /// non-keyframe boundaries.
    public var copyMode: Bool

    /// Memberwise initializer with sensible defaults.
    public init(
        trimStart: TimeInterval? = nil,
        trimEnd: TimeInterval? = nil,
        snipRegions: [SnipRegion] = [],
        splitByChapters: Bool = false,
        splitBySize: Int64? = nil,
        copyMode: Bool = true
    ) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.snipRegions = snipRegions
        self.splitByChapters = splitByChapters
        self.splitBySize = splitBySize
        self.copyMode = copyMode
    }
}

// MARK: - VideoTrimmer

/// Builds FFmpeg argument arrays for video trimming, snipping, and splitting.
///
/// All methods are pure functions that produce argument arrays suitable
/// for execution via `Process` or the project's FFmpeg process controller.
/// No I/O is performed — the caller is responsible for running the commands.
///
/// Supports three primary workflows:
/// 1. **Trim** — Remove head and/or tail from a single file.
/// 2. **Snip** — Cut out interior regions, producing multiple segments
///    that are concatenated via FFmpeg's concat demuxer.
/// 3. **Split** — Divide output by chapter markers or maximum file size.
///
/// Phase 12 — Video Trimming and Splitting (Issue #318)
public struct VideoTrimmer: Sendable {

    // MARK: - Trim Arguments

    /// Build FFmpeg arguments for a simple head/tail trim.
    ///
    /// Uses `-ss` for seek-to-start and `-to` for end time. When
    /// ``TrimConfig/copyMode`` is enabled, adds `-c copy` for lossless
    /// stream copying (no re-encode).
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - outputPath: Absolute path for the trimmed output file.
    ///   - config: Trim configuration specifying start/end times and copy mode.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildTrimArguments(
        inputPath: String,
        outputPath: String,
        config: TrimConfig
    ) -> [String] {
        var args: [String] = []

        // Seek to start time (placed before -i for input seeking — faster)
        if let start = config.trimStart {
            args += ["-ss", formatTimestamp(start)]
        }

        args += ["-i", inputPath]

        // End time (relative to the start of the input after seeking)
        if let end = config.trimEnd {
            args += ["-to", formatTimestamp(end)]
        }

        // Stream copy for lossless, no re-encode
        if config.copyMode {
            args += ["-c", "copy"]
        }

        // Avoid negative timestamps when stream copying
        if config.copyMode {
            args += ["-avoid_negative_ts", "make_zero"]
        }

        args += ["-y", outputPath]
        return args
    }

    // MARK: - Snip Arguments

    /// Build FFmpeg arguments for snip operations (cutting out interior regions).
    ///
    /// Creates one output per keep-segment. The caller should then use the
    /// FFmpeg concat demuxer to join the segments into the final output.
    /// Each tuple contains the FFmpeg arguments and the output file path
    /// for that segment.
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - outputDir: Directory where segment files will be written.
    ///   - config: Trim configuration with snip regions defined.
    /// - Returns: An array of (arguments, outputPath) tuples, one per keep-segment.
    public static func buildSnipArguments(
        inputPath: String,
        outputDir: String,
        config: TrimConfig
    ) -> [(arguments: [String], outputPath: String)] {
        let effectiveStart = config.trimStart ?? 0
        let effectiveEnd = config.trimEnd ?? .infinity

        // Sort snip regions by start time
        let sorted = config.snipRegions.sorted { $0.startTime < $1.startTime }

        // Build keep-regions from snip-regions
        var keepRegions: [(start: TimeInterval, end: TimeInterval)] = []
        var cursor = effectiveStart

        for snip in sorted {
            let snipStart = max(snip.startTime, effectiveStart)
            let snipEnd = min(snip.endTime, effectiveEnd)

            if cursor < snipStart {
                keepRegions.append((start: cursor, end: snipStart))
            }
            cursor = max(cursor, snipEnd)
        }

        // Final region after last snip
        if cursor < effectiveEnd {
            keepRegions.append((start: cursor, end: effectiveEnd))
        }

        let ext = (inputPath as NSString).pathExtension
        var results: [(arguments: [String], outputPath: String)] = []

        for (index, region) in keepRegions.enumerated() {
            let segmentPath = (outputDir as NSString).appendingPathComponent(
                "segment_\(String(format: "%03d", index)).\(ext)"
            )

            var args: [String] = [
                "-ss", formatTimestamp(region.start),
                "-i", inputPath,
                "-to", formatTimestamp(region.end - region.start)
            ]

            if config.copyMode {
                args += ["-c", "copy"]
                args += ["-avoid_negative_ts", "make_zero"]
            }

            args += ["-y", segmentPath]
            results.append((arguments: args, outputPath: segmentPath))
        }

        return results
    }

    // MARK: - Split Arguments

    /// Build FFmpeg arguments for splitting media by size or chapter markers.
    ///
    /// - **Size-based**: Uses FFmpeg's segment muxer with a size limit.
    /// - **Chapter-based**: Generates one output per chapter, using `-ss`/`-to`
    ///   boundaries derived from chapter metadata (the caller must supply the
    ///   total duration).
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - outputDir: Directory where split files will be written.
    ///   - config: Trim configuration with split options.
    ///   - duration: Total duration of the source media in seconds.
    /// - Returns: An array of (arguments, outputPath) tuples, one per split segment.
    public static func buildSplitArguments(
        inputPath: String,
        outputDir: String,
        config: TrimConfig,
        duration: TimeInterval
    ) -> [(arguments: [String], outputPath: String)] {
        let ext = (inputPath as NSString).pathExtension
        var results: [(arguments: [String], outputPath: String)] = []

        if let maxSize = config.splitBySize {
            // Size-based splitting via the segment muxer
            let pattern = (outputDir as NSString).appendingPathComponent(
                "split_%03d.\(ext)"
            )

            var args: [String] = ["-i", inputPath]

            if config.copyMode {
                args += ["-c", "copy"]
            }

            args += [
                "-f", "segment",
                "-segment_size", String(maxSize),
                "-reset_timestamps", "1",
                "-y", pattern
            ]

            results.append((arguments: args, outputPath: pattern))

        } else if config.splitByChapters {
            // Chapter-based splitting: one file per chapter.
            // The segment muxer can split on chapters natively.
            let pattern = (outputDir as NSString).appendingPathComponent(
                "chapter_%03d.\(ext)"
            )

            var args: [String] = ["-i", inputPath]

            if config.copyMode {
                args += ["-c", "copy"]
            }

            args += [
                "-f", "segment",
                "-segment_chapters", "1",
                "-reset_timestamps", "1",
                "-y", pattern
            ]

            results.append((arguments: args, outputPath: pattern))
        }

        return results
    }

    // MARK: - Segment Calculation

    /// Compute keep-regions from snip-regions over a given duration.
    ///
    /// Inverts the snip regions to produce a set of ``TrimSegment``
    /// instances representing the portions of the source that will
    /// appear in the final output.
    ///
    /// - Parameters:
    ///   - duration: Total duration of the source media in seconds.
    ///   - snipRegions: Regions to cut out.
    /// - Returns: An array of ``TrimSegment`` instances representing kept content.
    public static func calculateSegments(
        duration: TimeInterval,
        snipRegions: [SnipRegion]
    ) -> [TrimSegment] {
        guard !snipRegions.isEmpty else {
            return [TrimSegment(startTime: 0, endTime: duration, label: "Full")]
        }

        let sorted = snipRegions.sorted { $0.startTime < $1.startTime }
        var segments: [TrimSegment] = []
        var cursor: TimeInterval = 0
        var segmentIndex = 1

        for snip in sorted {
            if cursor < snip.startTime {
                segments.append(TrimSegment(
                    startTime: cursor,
                    endTime: snip.startTime,
                    label: "Segment \(segmentIndex)"
                ))
                segmentIndex += 1
            }
            cursor = max(cursor, snip.endTime)
        }

        if cursor < duration {
            segments.append(TrimSegment(
                startTime: cursor,
                endTime: duration,
                label: "Segment \(segmentIndex)"
            ))
        }

        return segments
    }

    // MARK: - Helpers

    /// Format a time interval as an FFmpeg-compatible timestamp string.
    ///
    /// Produces `HH:MM:SS.mmm` format suitable for `-ss` and `-to` arguments.
    ///
    /// - Parameter time: Time in seconds.
    /// - Returns: Formatted timestamp string.
    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = time.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
    }
}
