// ============================================================================
// MeedyaConverter — VideoConcatenator (Issue #322)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ConcatMethod

/// Strategy for concatenating multiple video files.
///
/// The choice of method depends on whether the input files share the same
/// codec, resolution, and container format:
/// - Use ``.demuxer`` for lossless concatenation of identically-encoded files.
/// - Use ``.filter`` when files differ or a crossfade transition is desired.
public enum ConcatMethod: String, Codable, Sendable, CaseIterable {

    /// Lossless concatenation via the FFmpeg concat demuxer.
    ///
    /// Requires all inputs to share the same codec, resolution, frame rate,
    /// and sample rate. No re-encoding is performed — the operation is
    /// essentially a binary join of the compressed streams.
    case demuxer

    /// Re-encode concatenation via the FFmpeg concat filter.
    ///
    /// Supports inputs with different codecs, resolutions, or frame rates.
    /// Also enables crossfade transitions between segments. Requires full
    /// re-encoding of all inputs.
    case filter

    /// Human-readable label for the concatenation method.
    public var displayName: String {
        switch self {
        case .demuxer: return "Lossless (Demuxer)"
        case .filter:  return "Re-encode (Filter)"
        }
    }
}

// MARK: - ConcatConfig

/// Configuration for a video concatenation operation.
///
/// Specifies the ordered list of input files, the concatenation strategy,
/// and an optional crossfade duration (only applicable with ``.filter`` method).
///
/// Phase 9 — Video Concatenation and Joining (Issue #322)
public struct ConcatConfig: Codable, Sendable {

    /// Ordered list of input file URLs to concatenate.
    public let files: [URL]

    /// Concatenation strategy (lossless demuxer vs. re-encode filter).
    public let method: ConcatMethod

    /// Optional crossfade transition duration in seconds.
    /// Only applicable when ``method`` is ``.filter``. Ignored for ``.demuxer``.
    public let crossfadeDuration: TimeInterval?

    /// Creates a new concatenation configuration.
    ///
    /// - Parameters:
    ///   - files: Ordered list of input file URLs.
    ///   - method: Concatenation strategy.
    ///   - crossfadeDuration: Crossfade transition length in seconds (filter mode only).
    public init(
        files: [URL],
        method: ConcatMethod = .demuxer,
        crossfadeDuration: TimeInterval? = nil
    ) {
        self.files = files
        self.method = method
        self.crossfadeDuration = crossfadeDuration
    }
}

// MARK: - VideoConcatenator

/// Builds FFmpeg argument arrays for concatenating multiple video files.
///
/// Supports two concatenation workflows:
/// 1. **Demuxer mode** — lossless, stream-copy join using the ``concat``
///    demuxer protocol and a temporary file list.
/// 2. **Filter mode** — re-encode join using the ``concat`` filter with
///    optional ``xfade`` video and ``acrossfade`` audio transitions.
///
/// Phase 9 — Video Concatenation and Joining (Issue #322)
public struct VideoConcatenator: Sendable {

    // MARK: - Demuxer Concatenation

    /// Builds the concat demuxer file-list content and FFmpeg arguments
    /// for lossless concatenation.
    ///
    /// The returned ``concatListContent`` should be written to a temporary
    /// text file, whose path is then passed to FFmpeg via the
    /// ``-f concat -safe 0 -i <listFile>`` arguments.
    ///
    /// All inputs must share the same codec, resolution, frame rate, and
    /// sample rate. Use ``validateCompatibility(files:)`` to check this
    /// before invoking.
    ///
    /// - Parameters:
    ///   - files: Ordered list of input file URLs.
    ///   - outputPath: Destination path for the concatenated output.
    /// - Returns: A tuple of (file-list text content, FFmpeg argument array).
    public static func buildDemuxerConcatArguments(
        files: [URL],
        outputPath: String
    ) -> (concatListContent: String, arguments: [String]) {

        // Build the concat demuxer file list.
        // Each line: file '/absolute/path/to/video.mp4'
        let listContent = files.map { url in
            let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
            return "file '\(escapedPath)'"
        }.joined(separator: "\n")

        // The caller must write listContent to a temp file and substitute
        // the placeholder "<CONCAT_LIST_FILE>" with its actual path.
        var args: [String] = ["-y", "-nostdin"]

        // Concat demuxer input
        args += ["-f", "concat"]
        args += ["-safe", "0"]
        args += ["-i", "<CONCAT_LIST_FILE>"]

        // Stream copy (lossless)
        args += ["-c", "copy"]

        // Output
        args += [outputPath]

        return (concatListContent: listContent, arguments: args)
    }

    // MARK: - Filter Concatenation

    /// Builds FFmpeg arguments for re-encode concatenation with optional
    /// crossfade transitions.
    ///
    /// When ``crossfade`` is non-nil and positive, an ``xfade`` video filter
    /// and ``acrossfade`` audio filter are applied between each pair of
    /// adjacent segments. Otherwise, the ``concat`` filter performs a simple
    /// sequential join with re-encoding.
    ///
    /// - Parameters:
    ///   - files: Ordered list of input file URLs.
    ///   - outputPath: Destination path for the concatenated output.
    ///   - crossfade: Optional crossfade duration in seconds between segments.
    /// - Returns: FFmpeg argument array.
    public static func buildFilterConcatArguments(
        files: [URL],
        durations: [TimeInterval] = [],
        outputPath: String,
        crossfade: TimeInterval?,
        videoCodec: String = "libx264",
        audioCodec: String = "aac"
    ) -> [String] {
        guard !files.isEmpty else { return [] }

        var args: [String] = ["-y", "-nostdin"]

        // Add all input files
        for file in files {
            args += ["-i", file.path]
        }

        let n = files.count

        // Crossfade needs each clip's duration to place the transitions on the
        // running timeline (see buildCrossfadeFilterComplex). Without a full,
        // matching duration list, fall back to a plain sequential re-encode
        // join rather than emit transitions at the wrong offsets.
        if let crossfade = crossfade, crossfade > 0, n >= 2, durations.count == n {
            let filterComplex = buildCrossfadeFilterComplex(
                durations: durations,
                crossfadeDuration: crossfade
            )
            args += ["-filter_complex", filterComplex]
            args += ["-map", "[vout]", "-map", "[aout]"]
        } else {
            // Simple concat filter — sequential join with re-encoding.
            let filterComplex = buildSimpleConcatFilterComplex(fileCount: n)
            args += ["-filter_complex", filterComplex]
            args += ["-map", "[v]", "-map", "[a]"]
        }

        // The filter path RE-ENCODES, so name the output codecs explicitly
        // rather than relying on the container extension's ffmpeg defaults
        // (which can pick an undesired encoder or fail for some containers).
        args += ["-c:v", videoCodec, "-c:a", audioCodec]

        args += [outputPath]

        return args
    }

    // MARK: - Compatibility Validation

    /// Validates that the given files are compatible for lossless demuxer
    /// concatenation.
    ///
    /// Returns an array of human-readable warning strings describing any
    /// incompatibilities (e.g., different codecs, resolutions, or frame rates).
    /// An empty array indicates all files are compatible.
    ///
    /// - Note: This method performs a static check based on file extensions
    ///   only. For full validation, probe each file with ``FFmpegProbe``
    ///   and compare stream properties.
    ///
    /// - Parameter files: The list of file URLs to validate.
    /// - Returns: Array of warning messages; empty if compatible.
    public static func validateCompatibility(files: [URL]) -> [String] {
        var warnings: [String] = []

        guard files.count >= 2 else {
            if files.isEmpty {
                warnings.append("No files provided for concatenation.")
            }
            return warnings
        }

        // Check file extensions match (basic heuristic).
        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        if extensions.count > 1 {
            warnings.append(
                "Files have different extensions (\(extensions.sorted().joined(separator: ", "))). "
                + "Demuxer concatenation requires identical codecs and containers."
            )
        }

        // Check that all files exist
        let fileManager = FileManager.default
        for file in files {
            if !fileManager.fileExists(atPath: file.path) {
                warnings.append("File not found: \(file.lastPathComponent)")
            }
        }

        return warnings
    }

    // MARK: - Private Filter Builders

    /// Builds a simple ``concat`` filter complex string for sequential joining.
    ///
    /// - Parameter fileCount: Number of input files.
    /// - Returns: FFmpeg ``-filter_complex`` string.
    private static func buildSimpleConcatFilterComplex(fileCount: Int) -> String {
        // Build input labels: [0:v][0:a][1:v][1:a]...
        var inputs = ""
        for i in 0..<fileCount {
            inputs += "[\(i):v][\(i):a]"
        }
        return "\(inputs)concat=n=\(fileCount):v=1:a=1[v][a]"
    }

    /// Builds an ``xfade`` + ``acrossfade`` filter-complex string for
    /// crossfade transitions between segments, placing each transition at the
    /// correct point on the running output timeline.
    ///
    /// The `xfade` filter's `offset` is the time IN THE FIRST INPUT at which the
    /// transition begins. For a chain, each xfade's first input is the
    /// already-crossfaded accumulation, whose timeline starts at 0, so:
    ///
    ///   L(0) = d0
    ///   offset for joining clip k+1 = L(k) - crossfade
    ///   L(k+1) = L(k) + d(k+1) - crossfade
    ///
    /// The previous implementation hard-coded `offset=0`, which fired every
    /// transition at t=0 — visually broken for any clip longer than the
    /// crossfade (Issue #322).
    ///
    /// - Parameters:
    ///   - durations: Per-clip durations in seconds, parallel to the inputs.
    ///   - crossfadeDuration: Duration of each crossfade in seconds.
    /// - Returns: FFmpeg ``-filter_complex`` string (empty for < 2 clips).
    private static func buildCrossfadeFilterComplex(
        durations: [TimeInterval],
        crossfadeDuration: TimeInterval
    ) -> String {
        let fileCount = durations.count
        guard fileCount >= 2 else { return "" }

        let dur = String(format: "%.3f", crossfadeDuration)
        func off(_ value: Double) -> String { String(format: "%.3f", max(0, value)) }

        var filterParts: [String] = []

        // First pair: [0][1]. offset = d0 - crossfade.
        let firstOutV = fileCount == 2 ? "vout" : "xv0"
        let firstOutA = fileCount == 2 ? "aout" : "xa0"
        filterParts.append(
            "[0:v][1:v]xfade=transition=fade:duration=\(dur):offset=\(off(durations[0] - crossfadeDuration))[\(firstOutV)]"
        )
        filterParts.append("[0:a][1:a]acrossfade=d=\(dur)[\(firstOutA)]")

        // Running accumulated timeline length after joining clips 0..1.
        var accumulated = durations[0] + durations[1] - crossfadeDuration

        for i in 2..<fileCount {
            let prevV = "xv\(i - 2)"
            let prevA = "xa\(i - 2)"
            let outV = i == fileCount - 1 ? "vout" : "xv\(i - 1)"
            let outA = i == fileCount - 1 ? "aout" : "xa\(i - 1)"

            filterParts.append(
                "[\(prevV)][\(i):v]xfade=transition=fade:duration=\(dur):offset=\(off(accumulated - crossfadeDuration))[\(outV)]"
            )
            filterParts.append("[\(prevA)][\(i):a]acrossfade=d=\(dur)[\(outA)]")

            accumulated += durations[i] - crossfadeDuration
        }

        return filterParts.joined(separator: ";")
    }
}
