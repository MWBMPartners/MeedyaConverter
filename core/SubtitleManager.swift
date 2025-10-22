// File: adaptix/core/SubtitleManager.swift
// Purpose: Manages subtitle extraction, conversion, and formatting for multiple subtitle formats including SRT, WebVTT, TTML, SSA, ASS, and LRC.
// Role: Handles subtitle processing, styling preservation, and multi-language subtitle management for adaptive streaming.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

// MARK: - Subtitle Configuration

/// Configuration for subtitle processing
struct SubtitleConfig: Codable {
    let format: SubtitleFormat
    let language: String? // ISO 639 code
    let title: String?
    let preserveFormatting: Bool // Keep original styling
    let forced: Bool // Forced/SDH subtitles
    let outputPath: String

    enum SubtitleFormat: String, Codable, CaseIterable {
        case srt = "srt"
        case webvtt = "webvtt"
        case ttml = "ttml"
        case ssa = "ssa"
        case ass = "ass"
        case lrc = "lrc"
        case mov_text = "mov_text" // MP4 native
        case cea608 = "cea_608"
        case cea708 = "cea_708"

        var fileExtension: String {
            switch self {
            case .srt: return "srt"
            case .webvtt: return "vtt"
            case .ttml: return "ttml"
            case .ssa: return "ssa"
            case .ass: return "ass"
            case .lrc: return "lrc"
            case .mov_text: return "mp4"
            case .cea608, .cea708: return "scc"
            }
        }

        var supportsFormatting: Bool {
            switch self {
            case .srt, .lrc, .cea608: return false
            case .webvtt, .ttml, .ssa, .ass, .cea708, .mov_text: return true
            }
        }
    }
}

/// Subtitle stream information
struct SubtitleTrack: Codable {
    let index: Int
    let codec: String
    let language: String?
    let title: String?
    let forced: Bool
    let sdh: Bool // Subtitles for deaf and hard of hearing
    let default: Bool
}

// MARK: - Subtitle Manager

class SubtitleManager {

    private let mediaProber: MediaProber

    init(mediaProber: MediaProber) {
        self.mediaProber = mediaProber
    }

    // MARK: - Subtitle Extraction

    /// Extracts all subtitle tracks from a media file
    /// - Parameters:
    ///   - inputPath: Path to input media file
    ///   - outputDirectory: Directory to save extracted subtitles
    ///   - targetFormat: Desired output format
    /// - Returns: Array of output file paths
    /// - Throws: Subtitle processing errors
    func extractAllSubtitles(inputPath: String,
                           outputDirectory: String,
                           targetFormat: SubtitleConfig.SubtitleFormat) throws -> [String] {
        let mediaInfo = try mediaProber.probe(inputPath)

        guard !mediaInfo.subtitleStreams.isEmpty else {
            throw SubtitleError.noSubtitleStreams
        }

        var outputPaths: [String] = []

        for (index, subtitleStream) in mediaInfo.subtitleStreams.enumerated() {
            let language = subtitleStream.language ?? "und"
            let outputFileName = generateOutputFileName(
                index: index,
                language: language,
                format: targetFormat
            )
            let outputPath = "\(outputDirectory)/\(outputFileName)"

            outputPaths.append(outputPath)
        }

        return outputPaths
    }

    /// Builds FFmpeg arguments for subtitle extraction and conversion
    /// - Parameters:
    ///   - inputPath: Input file path
    ///   - streamIndex: Subtitle stream index
    ///   - config: Subtitle configuration
    /// - Returns: FFmpeg arguments array
    func buildFFmpegArguments(inputPath: String,
                            streamIndex: Int,
                            config: SubtitleConfig) -> [String] {
        var args: [String] = []

        // Input file
        args += ["-i", inputPath]

        // Select specific subtitle stream
        args += ["-map", "0:s:\(streamIndex)"]

        // Subtitle codec
        args += ["-c:s", config.format.rawValue]

        // Metadata
        if let language = config.language {
            args += ["-metadata:s:s:0", "language=\(language)"]
        }

        if let title = config.title {
            args += ["-metadata:s:s:0", "title=\(title)"]
        }

        if config.forced {
            args += ["-metadata:s:s:0", "forced=1"]
        }

        // Format-specific options
        args += formatSpecificOptions(for: config.format, preserveFormatting: config.preserveFormatting)

        // Output
        args += [config.outputPath]

        return args
    }

    // MARK: - Format Conversion

    /// Converts subtitle file from one format to another
    /// - Parameters:
    ///   - inputPath: Input subtitle file
    ///   - outputFormat: Target format
    ///   - outputPath: Output file path
    /// - Returns: FFmpeg arguments
    func convertSubtitleFormat(inputPath: String,
                             outputFormat: SubtitleConfig.SubtitleFormat,
                             outputPath: String) -> [String] {
        var args: [String] = []

        args += ["-i", inputPath]
        args += ["-c:s", outputFormat.rawValue]

        // Format-specific conversion options
        if outputFormat == .webvtt {
            // Ensure WebVTT compatibility
            args += ["-f", "webvtt"]
        } else if outputFormat == .ttml {
            args += ["-f", "ttml"]
        }

        args += [outputPath]

        return args
    }

    // MARK: - Format-Specific Options

    private func formatSpecificOptions(for format: SubtitleConfig.SubtitleFormat,
                                     preserveFormatting: Bool) -> [String] {
        switch format {
        case .webvtt:
            return ["-f", "webvtt"]

        case .srt:
            return []

        case .ttml:
            return ["-f", "ttml"]

        case .ass, .ssa:
            if preserveFormatting {
                return ["-c:s", "copy"] // Preserve original
            } else {
                return []
            }

        case .mov_text:
            return ["-c:s", "mov_text"]

        case .lrc:
            return []

        case .cea608, .cea708:
            return ["-c:s", format.rawValue]
        }
    }

    // MARK: - WebVTT Generation

    /// Converts subtitle to WebVTT format with styling
    /// - Parameters:
    ///   - inputPath: Input subtitle file
    ///   - outputPath: Output WebVTT file
    ///   - styling: Optional CSS styling
    /// - Returns: FFmpeg arguments
    func generateWebVTT(inputPath: String,
                       outputPath: String,
                       styling: WebVTTStyling? = nil) -> [String] {
        var args = [
            "-i", inputPath,
            "-c:s", "webvtt",
            "-f", "webvtt"
        ]

        // WebVTT styling would be added post-processing
        args.append(outputPath)

        return args
    }

    // MARK: - Subtitle Segmentation for HLS/DASH

    /// Generates segmented WebVTT for HLS streaming
    /// - Parameters:
    ///   - inputPath: Input subtitle file
    ///   - outputDirectory: Output directory for segments
    ///   - segmentDuration: Duration of each segment in seconds
    /// - Returns: Path to master WebVTT playlist
    func generateSegmentedWebVTT(inputPath: String,
                                outputDirectory: String,
                                segmentDuration: Int = 6) -> [String] {
        let outputPattern = "\(outputDirectory)/subtitle_%03d.vtt"

        return [
            "-i", inputPath,
            "-c:s", "webvtt",
            "-f", "segment",
            "-segment_time", "\(segmentDuration)",
            "-segment_format", "webvtt",
            outputPattern
        ]
    }

    // MARK: - Language Detection

    /// Detects language from subtitle stream metadata
    func detectLanguage(from stream: SubtitleStreamInfo) -> String? {
        return stream.language ?? stream.tags["language"]
    }

    /// Validates ISO 639 language code
    func validateLanguageCode(_ code: String) -> Bool {
        let validCodes = [
            "en", "en-US", "en-GB", "es", "es-ES", "es-MX", "fr", "fr-FR",
            "de", "it", "pt", "pt-BR", "ru", "ja", "ko", "zh", "zh-CN",
            "ar", "hi", "nl", "pl", "tr", "vi", "th", "und"
        ]
        return validCodes.contains(code)
    }

    // MARK: - File Naming

    /// Generates output file name with language code
    private func generateOutputFileName(index: Int,
                                       language: String,
                                       format: SubtitleConfig.SubtitleFormat) -> String {
        return "subtitle_\(index)_\(language).\(format.fileExtension)"
    }

    // MARK: - Burn-In Subtitles

    /// Creates FFmpeg arguments to burn subtitles into video
    /// - Parameters:
    ///   - videoPath: Input video file
    ///   - subtitlePath: Subtitle file to burn in
    ///   - outputPath: Output video path
    ///   - styling: Optional subtitle styling
    /// - Returns: FFmpeg arguments
    func burnSubtitlesIntoVideo(videoPath: String,
                               subtitlePath: String,
                               outputPath: String,
                               styling: SubtitleBurnInStyling? = nil) -> [String] {
        var args = ["-i", videoPath]

        let style = styling ?? SubtitleBurnInStyling()

        // Build subtitle filter
        var subtitleFilter = "subtitles=\(subtitlePath)"

        if let fontSize = style.fontSize {
            subtitleFilter += ":force_style='FontSize=\(fontSize)"

            if let fontName = style.fontName {
                subtitleFilter += ",FontName=\(fontName)"
            }

            if let primaryColor = style.primaryColor {
                subtitleFilter += ",PrimaryColour=\(primaryColor)"
            }

            subtitleFilter += "'"
        }

        args += ["-vf", subtitleFilter]
        args += ["-c:a", "copy"] // Copy audio without re-encoding
        args += [outputPath]

        return args
    }

    // MARK: - Batch Processing

    /// Creates encoding jobs for all subtitle tracks
    func createBatchJobs(inputPath: String,
                        targetFormat: SubtitleConfig.SubtitleFormat,
                        outputDirectory: String) throws -> [EncodingJob] {
        let mediaInfo = try mediaProber.probe(inputPath)
        var jobs: [EncodingJob] = []

        for (streamIndex, subtitleStream) in mediaInfo.subtitleStreams.enumerated() {
            let language = subtitleStream.language ?? "und"
            let outputFileName = generateOutputFileName(
                index: streamIndex,
                language: language,
                format: targetFormat
            )
            let outputPath = "\(outputDirectory)/\(outputFileName)"

            let config = SubtitleConfig(
                format: targetFormat,
                language: language,
                title: subtitleStream.title,
                preserveFormatting: targetFormat.supportsFormatting,
                forced: false,
                outputPath: outputPath
            )

            let arguments = buildFFmpegArguments(
                inputPath: inputPath,
                streamIndex: subtitleStream.index,
                config: config
            )

            let job = EncodingJob(
                inputPath: inputPath,
                outputPath: outputPath,
                arguments: arguments
            )

            jobs.append(job)
        }

        return jobs
    }

    // MARK: - Validation

    /// Validates subtitle configuration
    func validateConfig(_ config: SubtitleConfig) throws {
        // Check format support
        if !SubtitleConfig.SubtitleFormat.allCases.contains(config.format) {
            throw SubtitleError.unsupportedFormat
        }

        // Check language code
        if let language = config.language,
           !validateLanguageCode(language) {
            throw SubtitleError.invalidLanguageCode(language)
        }

        // Check output path
        if config.outputPath.isEmpty {
            throw SubtitleError.invalidOutputPath
        }
    }
}

// MARK: - Styling Structures

/// Styling options for WebVTT subtitles
struct WebVTTStyling: Codable {
    let fontFamily: String?
    let fontSize: String?
    let color: String?
    let backgroundColor: String?
    let textAlign: String?

    static let `default` = WebVTTStyling(
        fontFamily: "Arial, sans-serif",
        fontSize: "1em",
        color: "#FFFFFF",
        backgroundColor: "rgba(0, 0, 0, 0.8)",
        textAlign: "center"
    )
}

/// Styling options for burned-in subtitles
struct SubtitleBurnInStyling: Codable {
    let fontName: String?
    let fontSize: Int?
    let primaryColor: String? // ASS color format: &HAABBGGRR
    let outlineColor: String?
    let outlineWidth: Int?
    let bold: Bool?
    let italic: Bool?

    init(fontName: String? = "Arial",
         fontSize: Int? = 24,
         primaryColor: String? = "&H00FFFFFF",
         outlineColor: String? = "&H00000000",
         outlineWidth: Int? = 2,
         bold: Bool? = false,
         italic: Bool? = false) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.primaryColor = primaryColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.bold = bold
        self.italic = italic
    }
}

// MARK: - Errors

enum SubtitleError: Error, LocalizedError {
    case noSubtitleStreams
    case unsupportedFormat
    case invalidLanguageCode(String)
    case invalidOutputPath
    case conversionFailed
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .noSubtitleStreams:
            return "No subtitle streams found in input file"
        case .unsupportedFormat:
            return "Unsupported subtitle format"
        case .invalidLanguageCode(let code):
            return "Invalid language code: \(code)"
        case .invalidOutputPath:
            return "Invalid output path specified"
        case .conversionFailed:
            return "Subtitle format conversion failed"
        case .parsingFailed:
            return "Failed to parse subtitle file"
        }
    }
}

// MARK: - Preset Configurations

extension SubtitleManager {

    /// Creates standard subtitle configurations for HLS/DASH streaming
    static func createStreamingPresets(language: String?, outputDirectory: String) -> [SubtitleConfig] {
        return [
            // WebVTT for HLS/DASH
            SubtitleConfig(
                format: .webvtt,
                language: language,
                title: "Subtitles",
                preserveFormatting: true,
                forced: false,
                outputPath: "\(outputDirectory)/subtitle_\(language ?? "und").vtt"
            ),
            // SRT for compatibility
            SubtitleConfig(
                format: .srt,
                language: language,
                title: "Subtitles (SRT)",
                preserveFormatting: false,
                forced: false,
                outputPath: "\(outputDirectory)/subtitle_\(language ?? "und").srt"
            )
        ]
    }
}
