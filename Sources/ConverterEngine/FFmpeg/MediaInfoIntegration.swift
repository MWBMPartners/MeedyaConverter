// ============================================================================
// MeedyaConverter — MediaInfoIntegration
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MediaInfoOutputFormat

/// Output format for MediaInfo command.
public enum MediaInfoOutputFormat: String, Codable, Sendable {
    /// Human-readable text output.
    case text = "text"

    /// JSON output (MediaInfo 18.03+).
    case json = "JSON"

    /// XML output.
    case xml = "XML"

    /// PBCore 2.1 XML output (for archival).
    case pbcore = "PBCore2"

    /// EBUCore XML output (for broadcast).
    case ebucore = "EBUCore"

    /// MPEG-7 XML output.
    case mpeg7 = "MPEG-7"
}

// MARK: - MediaInfoSection

/// Sections available in MediaInfo output.
public enum MediaInfoSection: String, Codable, Sendable {
    case general = "General"
    case video = "Video"
    case audio = "Audio"
    case text = "Text"
    case image = "Image"
    case menu = "Menu"
    case other = "Other"
}

// MARK: - MediaInfoField

/// Commonly used MediaInfo fields for targeted queries.
public enum MediaInfoField: String, Sendable {
    // General
    case format = "Format"
    case fileSize = "FileSize"
    case duration = "Duration"
    case overallBitRate = "OverallBitRate"
    case encodedApplication = "Encoded_Application"
    case encodedDate = "Encoded_Date"

    // Video
    case videoFormat = "Video/Format"
    case videoFormatProfile = "Format_Profile"
    case videoBitRate = "Video/BitRate"
    case width = "Width"
    case height = "Height"
    case displayAspectRatio = "DisplayAspectRatio"
    case frameRate = "FrameRate"
    case frameRateMode = "FrameRate_Mode"
    case bitDepth = "Video/BitDepth"
    case chromaSubsampling = "ChromaSubsampling"
    case colorSpace = "ColorSpace"
    case colorPrimaries = "colour_primaries"
    case transferCharacteristics = "transfer_characteristics"
    case matrixCoefficients = "matrix_coefficients"
    case hdrFormat = "HDR_Format"
    case hdrFormatCompatibility = "HDR_Format_Compatibility"
    case masteringDisplayColorPrimaries = "MasteringDisplay_ColorPrimaries"
    case masteringDisplayLuminance = "MasteringDisplay_Luminance"
    case maxCLL = "MaxCLL"
    case maxFALL = "MaxFALL"
    case scanType = "ScanType"
    case scanOrder = "ScanOrder"
    case streamSize = "StreamSize"
    case encoderSettings = "Encoded_Library_Settings"

    // Audio
    case audioFormat = "Audio/Format"
    case audioChannels = "Channel_s_"
    case audioChannelLayout = "ChannelLayout"
    case audioSamplingRate = "SamplingRate"
    case audioBitRate = "Audio/BitRate"
    case audioBitDepth = "Audio/BitDepth"
    case audioCompressionMode = "Compression_Mode"
    case audioFormatAdditionalFeatures = "Format_AdditionalFeatures"

    // Text/Subtitle
    case subtitleFormat = "Text/Format"
    case subtitleLanguage = "Language"
    case subtitleForced = "Forced"
    case subtitleDefault = "Default"
}

// MARK: - MediaInfoBuilder

/// Builds MediaInfo command-line arguments for detailed media analysis.
///
/// MediaInfo provides additional metadata beyond FFprobe, including:
/// - HDR format identification (Dolby Vision profile, HDR10+, HLG)
/// - Mastering display color volume details
/// - Encoding settings used by the original encoder
/// - Container-specific metadata (chapters, menus, attachments)
/// - Broadcast/archival metadata (PBCore, EBUCore)
///
/// Phase 1.3
public struct MediaInfoBuilder: Sendable {

    /// MediaInfo binary name.
    public static let binaryName = "mediainfo"

    // MARK: - Basic Commands

    /// Build MediaInfo arguments for full text output.
    ///
    /// - Parameter inputPath: Path to the media file.
    /// - Returns: Argument array.
    public static func buildFullReportArguments(inputPath: String) -> [String] {
        return ["-f", inputPath]
    }

    /// Build MediaInfo arguments for specific output format.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the media file.
    ///   - format: Desired output format.
    /// - Returns: Argument array.
    public static func buildFormattedArguments(
        inputPath: String,
        format: MediaInfoOutputFormat
    ) -> [String] {
        switch format {
        case .text:
            return [inputPath]
        case .json:
            return ["--Output=JSON", inputPath]
        case .xml:
            return ["--Output=XML", inputPath]
        case .pbcore:
            return ["--Output=PBCore2", inputPath]
        case .ebucore:
            return ["--Output=EBUCore", inputPath]
        case .mpeg7:
            return ["--Output=MPEG-7", inputPath]
        }
    }

    // MARK: - Targeted Queries

    /// Build MediaInfo arguments to query a specific field.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the media file.
    ///   - section: MediaInfo section (General, Video, Audio, etc.).
    ///   - field: Field name to query.
    ///   - streamIndex: Stream index (0-based, for multi-stream).
    /// - Returns: Argument array.
    public static func buildFieldQueryArguments(
        inputPath: String,
        section: MediaInfoSection,
        field: String,
        streamIndex: Int = 0
    ) -> [String] {
        let inform = "--Inform=\(section.rawValue);\(streamIndex);%\(field)%"
        return [inform, inputPath]
    }

    /// Build MediaInfo arguments to query multiple fields.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the media file.
    ///   - section: MediaInfo section.
    ///   - fields: Field names to query.
    ///   - separator: Separator between field values.
    /// - Returns: Argument array.
    public static func buildMultiFieldQueryArguments(
        inputPath: String,
        section: MediaInfoSection,
        fields: [String],
        separator: String = "|"
    ) -> [String] {
        let fieldStr = fields.map { "%\($0)%" }.joined(separator: separator)
        let inform = "--Inform=\(section.rawValue);\(fieldStr)"
        return [inform, inputPath]
    }

    // MARK: - HDR Analysis

    /// Build MediaInfo arguments for HDR metadata extraction.
    ///
    /// Queries all HDR-related fields from the video stream.
    ///
    /// - Parameter inputPath: Path to the media file.
    /// - Returns: Argument array.
    public static func buildHDRAnalysisArguments(inputPath: String) -> [String] {
        let fields = [
            "HDR_Format",
            "HDR_Format_Version",
            "HDR_Format_Profile",
            "HDR_Format_Level",
            "HDR_Format_Settings",
            "HDR_Format_Compatibility",
            "MasteringDisplay_ColorPrimaries",
            "MasteringDisplay_Luminance",
            "MaxCLL",
            "MaxFALL",
            "colour_primaries",
            "transfer_characteristics",
            "matrix_coefficients",
        ]
        let fieldStr = fields.map { "%\($0)%" }.joined(separator: "\\n")
        let inform = "--Inform=Video;\(fieldStr)"
        return [inform, inputPath]
    }

    /// Build MediaInfo arguments for Dolby Vision detection.
    ///
    /// - Parameter inputPath: Path to the media file.
    /// - Returns: Argument array.
    public static func buildDolbyVisionArguments(inputPath: String) -> [String] {
        let fields = [
            "HDR_Format",
            "HDR_Format_Version",
            "HDR_Format_Profile",
            "HDR_Format_Level",
            "HDR_Format_Compatibility",
        ]
        let fieldStr = fields.map { "%\($0)%" }.joined(separator: "|")
        let inform = "--Inform=Video;\(fieldStr)"
        return [inform, inputPath]
    }

    // MARK: - Audio Analysis

    /// Build MediaInfo arguments for detailed audio stream analysis.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the media file.
    ///   - streamIndex: Audio stream index.
    /// - Returns: Argument array.
    public static func buildAudioAnalysisArguments(
        inputPath: String,
        streamIndex: Int = 0
    ) -> [String] {
        let fields = [
            "Format", "Format_Profile", "Format_AdditionalFeatures",
            "Channel_s_", "ChannelLayout", "ChannelPositions",
            "SamplingRate", "BitRate", "BitDepth",
            "Compression_Mode", "StreamSize",
        ]
        let fieldStr = fields.map { "%\($0)%" }.joined(separator: "|")
        let inform = "--Inform=Audio;\(streamIndex);\(fieldStr)"
        return [inform, inputPath]
    }

    // MARK: - Comparison (FFprobe vs MediaInfo)

    /// Build both FFprobe and MediaInfo arguments for cross-referencing.
    ///
    /// Returns a tuple with both sets of arguments.
    ///
    /// - Parameter inputPath: Path to the media file.
    /// - Returns: Tuple of (ffprobeArgs, mediaInfoArgs).
    public static func buildDualAnalysisArguments(
        inputPath: String
    ) -> (ffprobeArgs: [String], mediaInfoArgs: [String]) {
        let ffprobe = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-show_chapters",
            inputPath,
        ]
        let mediaInfo = buildFormattedArguments(inputPath: inputPath, format: .json)
        return (ffprobe, mediaInfo)
    }

    // MARK: - Search Paths

    /// Common installation paths for MediaInfo.
    public static func searchPaths() -> [String] {
        #if os(macOS)
        return [
            "/usr/local/bin/mediainfo",
            "/opt/homebrew/bin/mediainfo",
            "/opt/local/bin/mediainfo",
        ]
        #elseif os(Linux)
        return [
            "/usr/bin/mediainfo",
            "/usr/local/bin/mediainfo",
            "/snap/bin/mediainfo",
        ]
        #elseif os(Windows)
        return [
            "C:\\Program Files\\MediaInfo\\MediaInfo.exe",
            "C:\\Program Files (x86)\\MediaInfo\\MediaInfo.exe",
        ]
        #else
        return ["/usr/local/bin/mediainfo"]
        #endif
    }

    // MARK: - Output Parsing Helpers

    /// Parse a MediaInfo HDR format string into an HDRFormat enum.
    ///
    /// MediaInfo outputs strings like:
    /// - "Dolby Vision, Version 1.0, Profile 8.1, dvhe.08.06, BL+RPU"
    /// - "SMPTE ST 2086, HDR10 compatible"
    /// - "SMPTE ST 2094 App 4, HDR10+ Profile A compatible"
    ///
    /// - Parameter hdrFormatString: Raw HDR_Format value from MediaInfo.
    /// - Returns: Detected HDR format.
    public static func parseHDRFormat(_ hdrFormatString: String?) -> HDRFormat {
        guard let str = hdrFormatString, !str.isEmpty else {
            return .sdr
        }

        let lower = str.lowercased()

        if lower.contains("dolby vision") {
            if lower.contains("hdr10") || lower.contains("smpte st 2086") {
                return .dolbyVisionHDR10
            }
            return .dolbyVision
        }

        if lower.contains("hdr10+") || lower.contains("st 2094") {
            return .hdr10Plus
        }

        if lower.contains("hdr10") || lower.contains("st 2086") || lower.contains("smpte2084") {
            return .hdr10
        }

        if lower.contains("hlg") || lower.contains("arib") || lower.contains("std-b67") {
            return .hlg
        }

        return .sdr
    }

    /// Parse Dolby Vision profile from MediaInfo string.
    ///
    /// - Parameter profileString: Raw HDR_Format_Profile value.
    /// - Returns: Dolby Vision profile number (e.g., 5, 7, 8) or nil.
    public static func parseDolbyVisionProfile(_ profileString: String?) -> Int? {
        guard let str = profileString else { return nil }
        // Match "Profile X.Y" or "dvhe.0X"
        if let range = str.range(of: "Profile (\\d+)", options: .regularExpression) {
            let match = str[range]
            let digits = match.filter { $0.isNumber }
            return Int(digits)
        }
        if let range = str.range(of: "dvhe\\.(\\d{2})", options: .regularExpression) {
            let match = str[range]
            let digits = match.filter { $0.isNumber }
            if let num = Int(digits) {
                return num < 10 ? num : num / 10 // dvhe.08 → 8
            }
        }
        return nil
    }
}
