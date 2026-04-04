// ============================================================================
// MeedyaConverter — ExtendedSubtitle
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ExtendedSubtitleFormat

/// Additional subtitle formats beyond SRT/VTT/ASS/SSA.
public enum ExtendedSubtitleFormat: String, Codable, Sendable, CaseIterable {

    /// EBU STL (European Broadcasting Union Subtitle) — broadcast standard.
    case ebuSTL = "stl"

    /// SCC (Scenarist Closed Captions) — US broadcast closed captions.
    case scc

    /// MCC (MacCaption Closed Captions) — modern US closed caption format.
    case mcc

    /// EBU Teletext — European broadcast teletext subtitles.
    case teletext

    /// DVB Subtitle — digital video broadcasting bitmap subtitles.
    case dvbSub = "dvb_subtitle"

    /// PGS (Presentation Graphic Stream) — Blu-ray bitmap subtitles.
    case pgs

    /// VobSub (DVD bitmap subtitles in IDX/SUB format).
    case vobsub

    /// TTML (Timed Text Markup Language) — W3C standard for streaming.
    case ttml

    /// File extension.
    public var fileExtension: String {
        switch self {
        case .ebuSTL: return "stl"
        case .scc: return "scc"
        case .mcc: return "mcc"
        case .teletext: return "txt"
        case .dvbSub: return "sub"
        case .pgs: return "sup"
        case .vobsub: return "idx"
        case .ttml: return "ttml"
        }
    }

    /// Display name.
    public var displayName: String {
        switch self {
        case .ebuSTL: return "EBU STL (Broadcast)"
        case .scc: return "SCC (Closed Captions)"
        case .mcc: return "MCC (MacCaption)"
        case .teletext: return "EBU Teletext"
        case .dvbSub: return "DVB Subtitle"
        case .pgs: return "PGS (Blu-ray)"
        case .vobsub: return "VobSub (DVD)"
        case .ttml: return "TTML (Timed Text)"
        }
    }

    /// Whether this is a bitmap (image-based) subtitle format.
    public var isBitmap: Bool {
        switch self {
        case .dvbSub, .pgs, .vobsub: return true
        default: return false
        }
    }

    /// Whether this is a text-based subtitle format.
    public var isText: Bool { !isBitmap }

    /// FFmpeg codec/format name.
    public var ffmpegCodec: String {
        switch self {
        case .ebuSTL: return "stl"
        case .scc: return "scc"
        case .mcc: return "mcc"
        case .teletext: return "dvb_teletext"
        case .dvbSub: return "dvb_subtitle"
        case .pgs: return "hdmv_pgs_subtitle"
        case .vobsub: return "dvd_subtitle"
        case .ttml: return "ttml"
        }
    }

    /// Primary use case.
    public var useCase: String {
        switch self {
        case .ebuSTL: return "European broadcast delivery"
        case .scc: return "US broadcast/cable delivery"
        case .mcc: return "Modern US caption authoring"
        case .teletext: return "European broadcast (legacy)"
        case .dvbSub: return "Digital TV broadcast"
        case .pgs: return "Blu-ray disc"
        case .vobsub: return "DVD disc"
        case .ttml: return "Streaming (DASH, HLS)"
        }
    }

    /// Compatible container formats.
    public var compatibleContainers: [String] {
        switch self {
        case .ebuSTL: return ["stl"] // Standalone file
        case .scc: return ["scc", "mp4", "mov"]
        case .mcc: return ["mcc"]
        case .teletext: return ["ts", "mpegts"]
        case .dvbSub: return ["ts", "mpegts", "mkv"]
        case .pgs: return ["m2ts", "mkv", "sup"]
        case .vobsub: return ["idx", "mkv", "mp4"]
        case .ttml: return ["ttml", "mp4", "dash"]
        }
    }
}

// MARK: - SubtitleConversionPath

/// Known subtitle format conversion paths.
public struct SubtitleConversionPath: Sendable {

    /// Whether a direct conversion between formats is supported.
    ///
    /// - Parameters:
    ///   - from: Source format.
    ///   - to: Target format.
    /// - Returns: `true` if direct conversion is possible.
    public static func canConvert(
        from: ExtendedSubtitleFormat,
        to: ExtendedSubtitleFormat
    ) -> Bool {
        // Text-to-text conversions are generally supported
        if from.isText && to.isText { return true }

        // Bitmap-to-text requires OCR (not directly supported)
        if from.isBitmap && to.isText { return false }

        // Text-to-bitmap is not typically useful
        if from.isText && to.isBitmap { return false }

        // Bitmap-to-bitmap passthrough possible in some cases
        return from == to
    }

    /// Whether OCR is needed for this conversion.
    ///
    /// - Parameters:
    ///   - from: Source format.
    ///   - to: Target format.
    /// - Returns: `true` if OCR would be needed.
    public static func needsOCR(
        from: ExtendedSubtitleFormat,
        to: ExtendedSubtitleFormat
    ) -> Bool {
        return from.isBitmap && to.isText
    }
}

// MARK: - ExtendedSubtitleBuilder

/// Builds FFmpeg arguments for extended subtitle format operations.
///
/// Phase 3.25
public struct ExtendedSubtitleBuilder: Sendable {

    // MARK: - Extraction

    /// Build FFmpeg arguments to extract subtitles from a container.
    ///
    /// - Parameters:
    ///   - inputPath: Source media file.
    ///   - outputPath: Output subtitle file.
    ///   - streamIndex: Subtitle stream index.
    ///   - format: Target subtitle format.
    /// - Returns: FFmpeg argument array.
    public static func buildExtractArguments(
        inputPath: String,
        outputPath: String,
        streamIndex: Int = 0,
        format: ExtendedSubtitleFormat? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-map", "0:s:\(streamIndex)"]

        if let fmt = format {
            args += ["-c:s", fmt.ffmpegCodec]
        } else {
            args += ["-c:s", "copy"]
        }

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Conversion

    /// Build FFmpeg arguments to convert between text subtitle formats.
    ///
    /// - Parameters:
    ///   - inputPath: Source subtitle file.
    ///   - outputPath: Output subtitle file.
    ///   - outputFormat: Target subtitle format.
    /// - Returns: FFmpeg argument array.
    public static func buildConvertArguments(
        inputPath: String,
        outputPath: String,
        outputFormat: ExtendedSubtitleFormat
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:s", outputFormat.ffmpegCodec,
            "-y", outputPath,
        ]
    }

    // MARK: - SCC Specific

    /// Build FFmpeg arguments for SCC closed caption embedding.
    ///
    /// SCC captions use CEA-608 encoding and are embedded in the
    /// video stream's user data or as a separate caption track.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - sccPath: SCC caption file.
    ///   - outputPath: Output file with embedded captions.
    /// - Returns: FFmpeg argument array.
    public static func buildSCCEmbedArguments(
        inputPath: String,
        sccPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-i", sccPath,
            "-map", "0:v",
            "-map", "0:a",
            "-map", "1:s",
            "-c:v", "copy",
            "-c:a", "copy",
            "-c:s", "mov_text",
            "-y", outputPath,
        ]
    }

    // MARK: - Teletext

    /// Build FFmpeg arguments to extract teletext subtitles from MPEG-TS.
    ///
    /// Teletext subtitles are embedded in VBI (Vertical Blanking Interval)
    /// data within MPEG transport streams.
    ///
    /// - Parameters:
    ///   - inputPath: Source MPEG-TS file.
    ///   - outputPath: Output SRT file.
    ///   - teletextPage: Teletext page number (e.g., 888 for subtitles).
    /// - Returns: FFmpeg argument array.
    public static func buildTeletextExtractArguments(
        inputPath: String,
        outputPath: String,
        teletextPage: Int = 888
    ) -> [String] {
        return [
            "-txt_page", "\(teletextPage)",
            "-i", inputPath,
            "-map", "0:s:0",
            "-c:s", "srt",
            "-y", outputPath,
        ]
    }

    // MARK: - PGS/VobSub

    /// Build FFmpeg arguments to extract PGS bitmap subtitles.
    ///
    /// PGS subtitles are kept as bitmap (SUP) since text conversion
    /// requires OCR.
    ///
    /// - Parameters:
    ///   - inputPath: Source Blu-ray/MKV file.
    ///   - outputPath: Output SUP file.
    ///   - streamIndex: PGS stream index.
    /// - Returns: FFmpeg argument array.
    public static func buildPGSExtractArguments(
        inputPath: String,
        outputPath: String,
        streamIndex: Int = 0
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:s:\(streamIndex)",
            "-c:s", "copy",
            "-y", outputPath,
        ]
    }

    // MARK: - TTML

    /// Build FFmpeg arguments for TTML subtitle output.
    ///
    /// TTML is used in DASH and HLS streaming workflows.
    ///
    /// - Parameters:
    ///   - inputPath: Source subtitle file.
    ///   - outputPath: Output TTML file.
    /// - Returns: FFmpeg argument array.
    public static func buildTTMLArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:s", "ttml",
            "-y", outputPath,
        ]
    }

    // MARK: - Burn-In

    /// Build FFmpeg video filter to burn bitmap subtitles into video.
    ///
    /// This is the only way to include PGS/VobSub/DVB subtitles in
    /// containers that don't support bitmap subtitle tracks.
    ///
    /// - Parameters:
    ///   - streamIndex: Subtitle stream index.
    /// - Returns: FFmpeg video filter string.
    public static func buildBurnInFilter(streamIndex: Int = 0) -> String {
        return "subtitles=si=\(streamIndex)"
    }

    /// Build FFmpeg overlay filter to burn PGS/DVB bitmap subtitles.
    ///
    /// - Parameter streamIndex: Subtitle stream index.
    /// - Returns: FFmpeg filter_complex string.
    public static func buildBitmapOverlayFilter(streamIndex: Int = 0) -> String {
        return "[0:v][0:s:\(streamIndex)]overlay"
    }
}
