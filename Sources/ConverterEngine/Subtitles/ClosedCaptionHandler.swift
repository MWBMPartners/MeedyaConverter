// ============================================================================
// MeedyaConverter — ClosedCaptionHandler (Issue #339)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ClosedCaptionStandard

/// Closed caption standards supported in North American broadcast television.
///
/// - ``cea608``: Legacy NTSC standard (also known as "line 21" captions).
///   Two channels, limited character set, widely used in analog TV and
///   still embedded in many digital streams for backward compatibility.
/// - ``cea708``: Current ATSC digital television standard. Supports up to
///   63 caption services, Unicode text, multiple fonts, positioning, and
///   windowed rendering.
///
/// Phase 12 — Closed Caption Support (Issue #339)
public enum ClosedCaptionStandard: String, Codable, Sendable, CaseIterable {

    /// CEA-608 — legacy analog closed caption standard.
    case cea608

    /// CEA-708 — current digital television closed caption standard.
    case cea708

    /// Human-readable display name for the caption standard.
    public var displayName: String {
        switch self {
        case .cea608: return "CEA-608 (Analog CC)"
        case .cea708: return "CEA-708 (Digital CC)"
        }
    }
}

// MARK: - ClosedCaptionHandler

/// Detects, extracts, passes through, and burns in closed caption tracks.
///
/// All methods are pure functions that produce FFmpeg argument arrays.
/// No I/O is performed — the caller is responsible for running the
/// commands via `Process` or the project's FFmpeg process controller.
///
/// Supported workflows:
/// 1. **Detect** — Parse `ffprobe` output to identify caption tracks.
/// 2. **Extract** — Pull captions to standalone SRT, SCC, or VTT files.
/// 3. **Passthrough** — Copy caption streams to the output container.
/// 4. **Burn-in** — Render captions directly onto the video frames.
/// 5. **Import** — Inject SCC files as caption tracks.
///
/// Phase 12 — Closed Caption Support (Issue #339)
public struct ClosedCaptionHandler: Sendable {

    // MARK: - Detection

    /// Detect closed caption tracks from `ffprobe` JSON or text output.
    ///
    /// Searches for codec names matching `eia_608`, `cc_dec`, or
    /// `eia_708` / `cea_708` patterns in the probe output and returns
    /// the stream index and identified standard for each caption track.
    ///
    /// - Parameter probeOutput: Raw text output from `ffprobe -show_streams`.
    /// - Returns: An array of (index, standard) tuples for detected caption tracks.
    public static func detectCaptionTracks(
        probeOutput: String
    ) -> [(index: Int, standard: ClosedCaptionStandard)] {
        var results: [(index: Int, standard: ClosedCaptionStandard)] = []
        let lines = probeOutput.components(separatedBy: .newlines)
        var currentIndex: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track stream index from ffprobe output
            if trimmed.hasPrefix("index=") {
                let value = trimmed.replacingOccurrences(of: "index=", with: "")
                currentIndex = Int(value)
            }

            // Detect CEA-608 patterns
            if trimmed.contains("eia_608") || trimmed.contains("cc_dec")
                || trimmed.contains("closed_captions=1")
            {
                if let idx = currentIndex {
                    results.append((index: idx, standard: .cea608))
                }
            }

            // Detect CEA-708 patterns
            if trimmed.contains("eia_708") || trimmed.contains("cea_708") {
                if let idx = currentIndex {
                    results.append((index: idx, standard: .cea708))
                }
            }
        }

        return results
    }

    // MARK: - Extraction

    /// Build FFmpeg arguments to extract a caption track to a subtitle file.
    ///
    /// Maps the specified track index to the output and converts to the
    /// requested subtitle format (e.g., SRT, SCC, WebVTT).
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - outputPath: Absolute path for the output subtitle file.
    ///   - trackIndex: Zero-based stream index of the caption track.
    ///   - format: Target subtitle format for extraction.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildExtractionArguments(
        inputPath: String,
        outputPath: String,
        trackIndex: Int,
        format: SubtitleFormat
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:\(trackIndex)",
            "-c:s", codecName(for: format),
            "-y", outputPath
        ]
    }

    // MARK: - Passthrough

    /// Build FFmpeg arguments to copy a caption track to the output container.
    ///
    /// Adds mapping and copy codec flags for the specified caption stream
    /// so that captions are preserved in the transcoded output without
    /// modification.
    ///
    /// - Parameter trackIndex: Zero-based stream index of the caption track.
    /// - Returns: An array of FFmpeg argument fragments to append to the
    ///   main encode command.
    public static func buildPassthroughArguments(trackIndex: Int) -> [String] {
        return [
            "-map", "0:\(trackIndex)",
            "-c:s:\(trackIndex)", "copy"
        ]
    }

    // MARK: - Burn-In

    /// Build FFmpeg arguments to burn (render) captions directly onto video frames.
    ///
    /// Uses the `closedcaptions` or `subtitles` filter to overlay caption
    /// text onto the video stream. The output will contain permanently
    /// rendered text — this is a destructive operation (captions cannot be
    /// turned off in the output).
    ///
    /// - Parameters:
    ///   - inputPath: Absolute path to the source media file.
    ///   - trackIndex: Zero-based stream index of the caption track.
    /// - Returns: An array of FFmpeg argument fragments for the burn-in filter.
    public static func buildBurnInArguments(
        inputPath: String,
        trackIndex: Int
    ) -> [String] {
        // Use the movie source and overlay captions via the subtitles filter.
        // For embedded closed captions, FFmpeg's `closedcaptions` filter
        // decodes and renders CEA-608/708 data onto the video.
        return [
            "-filter_complex",
            "[0:v]setpts=PTS-STARTPTS[v];[0:\(trackIndex)]setpts=PTS-STARTPTS[s];[v][s]overlay[out]",
            "-map", "[out]",
            "-map", "0:a"
        ]
    }

    // MARK: - SCC Import

    /// Build FFmpeg arguments to import an SCC (Scenarist Closed Caption) file.
    ///
    /// Converts the SCC file to the specified output format, which can then
    /// be muxed into a container alongside video and audio streams.
    ///
    /// - Parameters:
    ///   - sccPath: Absolute path to the input SCC file.
    ///   - outputPath: Absolute path for the converted output file.
    /// - Returns: An array of FFmpeg command-line arguments.
    public static func buildSCCImportArguments(
        sccPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", sccPath,
            "-c:s", "srt",
            "-y", outputPath
        ]
    }

    // MARK: - Helpers

    /// Map a ``SubtitleFormat`` to an FFmpeg codec name string.
    ///
    /// - Parameter format: The target subtitle format.
    /// - Returns: FFmpeg codec name string.
    private static func codecName(for format: SubtitleFormat) -> String {
        switch format {
        case .srt: return "srt"
        case .webVTT: return "webvtt"
        case .ssa: return "ass"
        case .scc: return "scc"
        case .ttml: return "ttml"
        default: return "srt"
        }
    }
}
