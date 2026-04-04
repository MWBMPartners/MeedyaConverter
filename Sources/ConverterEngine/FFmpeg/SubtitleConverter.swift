// ============================================================================
// MeedyaConverter — SubtitleConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SubtitleConverterError

/// Errors from subtitle conversion operations.
public enum SubtitleConverterError: LocalizedError, Sendable {
    /// The input subtitle format is not supported for conversion.
    case unsupportedInputFormat(String)
    /// The output format is not supported for this conversion path.
    case unsupportedOutputFormat(String)
    /// Bitmap subtitles require OCR which is not available.
    case ocrUnavailable
    /// The conversion failed.
    case conversionFailed(String)
    /// Tesseract OCR is not installed.
    case tesseractNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedInputFormat(let f): return "Unsupported input subtitle format: \(f)"
        case .unsupportedOutputFormat(let f): return "Unsupported output subtitle format: \(f)"
        case .ocrUnavailable: return "OCR is required for bitmap subtitle conversion but is not available"
        case .conversionFailed(let msg): return "Subtitle conversion failed: \(msg)"
        case .tesseractNotFound: return "Tesseract OCR is not installed (brew install tesseract)"
        }
    }
}

// MARK: - SubtitleConverter

/// Converts between subtitle formats using FFmpeg and optional OCR.
///
/// Supports three conversion paths:
/// 1. **Text → Text**: Direct FFmpeg conversion (SRT ↔ WebVTT ↔ TTML ↔ SSA/ASS)
/// 2. **Text → Bitmap**: Rendering text into bitmap overlays (burn-in)
/// 3. **Bitmap → Text**: OCR extraction using Tesseract (PGS/VobSub/DVB-SUB → SRT)
///
/// Phase 5.4-5.11
public struct SubtitleConverter: Sendable {

    // MARK: - Text-to-Text Conversion

    /// Build FFmpeg arguments to convert between text subtitle formats.
    ///
    /// - Parameters:
    ///   - inputURL: Source file containing subtitles.
    ///   - outputURL: Output subtitle file.
    ///   - inputFormat: Source subtitle format.
    ///   - outputFormat: Target subtitle format.
    ///   - streamIndex: Subtitle stream index in the source (nil = first).
    /// - Returns: FFmpeg argument array.
    public static func buildTextConversionArguments(
        inputURL: URL,
        outputURL: URL,
        inputFormat: SubtitleFormat,
        outputFormat: SubtitleFormat,
        streamIndex: Int? = nil
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]

        args += ["-i", inputURL.path]

        // Map the specific subtitle stream
        if let idx = streamIndex {
            args += ["-map", "0:s:\(idx)"]
        } else {
            args += ["-map", "0:s:0"]
        }

        // Set the output subtitle codec
        args += ["-c:s", ffmpegSubtitleCodec(for: outputFormat)]

        args += [outputURL.path]
        return args
    }

    /// Build FFmpeg arguments to extract subtitles from a media file.
    ///
    /// - Parameters:
    ///   - inputURL: Source media file.
    ///   - outputURL: Output subtitle file.
    ///   - streamIndex: Subtitle stream index (nil = first).
    ///   - outputFormat: Target subtitle format.
    /// - Returns: FFmpeg argument array.
    public static func buildExtractionArguments(
        inputURL: URL,
        outputURL: URL,
        streamIndex: Int? = nil,
        outputFormat: SubtitleFormat = .srt
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]
        args += ["-i", inputURL.path]

        if let idx = streamIndex {
            args += ["-map", "0:s:\(idx)"]
        } else {
            args += ["-map", "0:s:0"]
        }

        // No video, no audio — subtitle only
        args += ["-vn", "-an"]

        args += ["-c:s", ffmpegSubtitleCodec(for: outputFormat)]
        args += [outputURL.path]

        return args
    }

    // MARK: - Burn-In (Hardcode Subtitles)

    /// Build FFmpeg arguments to burn (hardcode) subtitles into the video.
    ///
    /// Burns subtitles directly into the video frame, making them permanent
    /// and visible on all players regardless of subtitle support.
    ///
    /// - Parameters:
    ///   - subtitlePath: Path to the subtitle file (SRT, ASS, etc.).
    ///   - charEncoding: Character encoding of the subtitle file.
    ///   - fontSize: Font size override (nil = default).
    ///   - fontName: Font name override (nil = default).
    /// - Returns: Video filter string for the subtitles filter.
    public static func buildBurnInFilter(
        subtitlePath: String,
        charEncoding: String = "UTF-8",
        fontSize: Int? = nil,
        fontName: String? = nil
    ) -> String {
        // Escape colons and backslashes in the path for FFmpeg filter syntax
        let escapedPath = subtitlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")

        var filter = "subtitles='\(escapedPath)':charenc=\(charEncoding)"

        if let size = fontSize {
            filter += ":force_style='FontSize=\(size)"
            if let font = fontName {
                filter += ",FontName=\(font)"
            }
            filter += "'"
        } else if let font = fontName {
            filter += ":force_style='FontName=\(font)'"
        }

        return filter
    }

    // MARK: - Bitmap OCR (Tesseract)

    /// Build arguments for Tesseract OCR of bitmap subtitles.
    ///
    /// Workflow:
    /// 1. Extract bitmap subtitle images from the source via FFmpeg
    /// 2. Run Tesseract OCR on each extracted image
    /// 3. Assemble timed SRT output from OCR results
    ///
    /// This is a multi-step process — the returned arguments handle step 1 only.
    /// Steps 2-3 require the TesseractWrapper.
    ///
    /// - Parameters:
    ///   - inputURL: Source file with bitmap subtitles.
    ///   - outputDirectory: Directory for extracted bitmap images.
    ///   - streamIndex: Subtitle stream index.
    /// - Returns: FFmpeg arguments for bitmap extraction.
    public static func buildBitmapExtractionArguments(
        inputURL: URL,
        outputDirectory: URL,
        streamIndex: Int? = nil
    ) -> [String] {
        var args: [String] = ["-y", "-nostdin"]
        args += ["-i", inputURL.path]

        if let idx = streamIndex {
            args += ["-map", "0:s:\(idx)"]
        } else {
            args += ["-map", "0:s:0"]
        }

        // Extract as individual PNG images with timestamps
        args += ["-c:s", "png"]
        args += [outputDirectory.appendingPathComponent("sub_%05d.png").path]

        return args
    }

    /// Check whether Tesseract OCR is available on the system.
    public static func isTesseractAvailable() -> Bool {
        let paths = [
            "/usr/local/bin/tesseract",
            "/opt/homebrew/bin/tesseract",
            "/usr/bin/tesseract",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Locate the Tesseract binary on the system.
    public static func locateTesseract() -> String? {
        let paths = [
            "/opt/homebrew/bin/tesseract",
            "/usr/local/bin/tesseract",
            "/usr/bin/tesseract",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Conversion Matrix

    /// Check whether a direct conversion between two subtitle formats is supported.
    ///
    /// - Parameters:
    ///   - from: Source subtitle format.
    ///   - to: Target subtitle format.
    /// - Returns: Whether the conversion is supported.
    public static func canConvert(from: SubtitleFormat, to: SubtitleFormat) -> Bool {
        if from == to { return true }

        // Text → Text: all text formats are interconvertible via FFmpeg
        if from.isText && to.isText { return true }

        // Bitmap → Text: requires OCR (Tesseract)
        if from.isBitmap && to.isText { return true }

        // Text → Bitmap: burn-in only (not direct conversion)
        return false
    }

    /// Check whether a conversion requires OCR.
    public static func requiresOCR(from: SubtitleFormat, to: SubtitleFormat) -> Bool {
        return from.isBitmap && to.isText
    }

    // MARK: - FFmpeg Codec Mapping

    /// Get the FFmpeg subtitle codec name for a given format.
    public static func ffmpegSubtitleCodec(for format: SubtitleFormat) -> String {
        switch format {
        case .srt: return "srt"
        case .ttml: return "ttml"
        case .webVTT: return "webvtt"
        case .ssa: return "ass"
        case .sami: return "sami"
        case .lrc: return "srt" // LRC not directly supported — fall back to SRT
        case .cc608: return "cc_dec" // Decode CC608
        case .cc708: return "cc_dec"
        case .dvbSub: return "dvbsub"
        case .pgs: return "hdmv_pgs_subtitle"
        case .vobSub: return "dvdsub"
        case .ebuSTL: return "stl"
        case .scc: return "scc"
        case .mcc: return "mcc"
        case .teletext: return "libzvbi_teletextdec"
        }
    }
}
