// ============================================================================
// MeedyaConverter — FFmpegProbe
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegProbeError

/// Errors that can occur during media file probing.
public enum FFmpegProbeError: LocalizedError, Sendable {
    /// The input file does not exist or cannot be accessed.
    case fileNotFound(path: String)

    /// FFprobe returned invalid or unparseable JSON output.
    case invalidOutput(details: String)

    /// FFprobe process failed with a non-zero exit code.
    case probeFailed(exitCode: Int32, stderr: String)

    /// FFprobe binary is not available.
    case ffprobeNotAvailable

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidOutput(let details):
            return "Failed to parse FFprobe output: \(details)"
        case .probeFailed(let code, let stderr):
            return "FFprobe exited with code \(code): \(stderr.prefix(300))"
        case .ffprobeNotAvailable:
            return "FFprobe is not available. Ensure FFmpeg is installed."
        }
    }
}

// MARK: - FFmpegProbe

/// Probes media files using FFprobe to extract stream, format, and chapter information.
///
/// Runs FFprobe with JSON output format and parses the result into the
/// ConverterEngine data model types (MediaFile, MediaStream, Chapter).
///
/// Usage:
/// ```swift
/// let probe = FFmpegProbe(ffprobePath: "/opt/homebrew/bin/ffprobe")
/// let mediaFile = try await probe.analyze(url: fileURL)
/// print(mediaFile.videoStreams.count) // Number of video streams
/// ```
public final class FFmpegProbe: Sendable {

    // MARK: - Properties

    /// Path to the FFprobe binary.
    private let ffprobePath: String

    // MARK: - Initialiser

    /// Create a new FFmpegProbe instance.
    ///
    /// - Parameter ffprobePath: Full path to the FFprobe executable.
    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    // MARK: - Public API

    /// Analyse a media file and return its complete metadata.
    ///
    /// Runs FFprobe with JSON output, parsing the result into a `MediaFile`
    /// instance with all streams, chapters, and format metadata.
    ///
    /// - Parameter url: The file URL of the media file to analyse.
    /// - Returns: A fully populated `MediaFile` instance.
    /// - Throws: `FFmpegProbeError` if the file cannot be probed.
    public func analyze(url: URL) async throws -> MediaFile {
        // Verify the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FFmpegProbeError.fileNotFound(path: url.path)
        }

        // Run FFprobe with JSON output for streams, format, and chapters
        let arguments = [
            "-v", "quiet",                    // Suppress log output
            "-print_format", "json",           // Output as JSON
            "-show_format",                    // Include format/container info
            "-show_streams",                   // Include all stream details
            "-show_chapters",                  // Include chapter markers
            "-show_entries",                   // Additional metadata entries
            "stream=index,codec_name,codec_long_name,codec_type,profile,bit_rate,"
            + "sample_rate,channels,channel_layout,width,height,coded_width,coded_height,"
            + "display_aspect_ratio,sample_aspect_ratio,r_frame_rate,avg_frame_rate,"
            + "pix_fmt,color_range,color_space,color_transfer,color_primaries,"
            + "bits_per_raw_sample,duration,nb_frames,"
            + "disposition",
            "-show_entries", "stream_tags=language,title,BPS,BPS-eng,NUMBER_OF_FRAMES",
            "-show_entries", "format_tags=title,artist,album,date,comment,genre,track,encoder",
            "-show_entries", "stream_side_data=side_data_type",
            url.path
        ]

        let jsonOutput = try runFFprobe(arguments: arguments)

        // Parse the JSON output into our data model
        return try parseProbeOutput(jsonData: jsonOutput, fileURL: url)
    }

    // MARK: - FFprobe Execution

    /// Run FFprobe and capture its JSON output.
    private func runFFprobe(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw FFmpegProbeError.ffprobeNotAvailable
        }

        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // Check exit code
        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8) ?? "unknown error"
            throw FFmpegProbeError.probeFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        guard !outputData.isEmpty else {
            throw FFmpegProbeError.invalidOutput(details: "FFprobe produced no output")
        }

        return outputData
    }

    // MARK: - JSON Parsing

    /// Parse FFprobe's JSON output into a MediaFile instance.
    private func parseProbeOutput(jsonData: Data, fileURL: URL) throws -> MediaFile {
        // Decode the raw JSON into intermediate structures
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw FFmpegProbeError.invalidOutput(details: "Root is not a JSON object")
            }
            json = parsed
        } catch let error as FFmpegProbeError {
            throw error
        } catch {
            throw FFmpegProbeError.invalidOutput(details: error.localizedDescription)
        }

        // Parse format (container) information
        let formatDict = json["format"] as? [String: Any]
        let containerFormatName = formatDict?["format_name"] as? String
        let containerFormat = detectContainerFormat(from: containerFormatName, fileExtension: fileURL.pathExtension)

        let duration: TimeInterval?
        if let durStr = formatDict?["duration"] as? String {
            duration = TimeInterval(durStr)
        } else {
            duration = nil
        }

        let overallBitrate: Int?
        if let brStr = formatDict?["bit_rate"] as? String {
            overallBitrate = Int(brStr)
        } else {
            overallBitrate = nil
        }

        // Parse format-level metadata tags
        let formatTags = formatDict?["tags"] as? [String: Any] ?? [:]
        var metadata: [String: String] = [:]
        for (key, value) in formatTags {
            metadata[key] = "\(value)"
        }

        // Get file size
        let fileSize: UInt64?
        if let sizeStr = formatDict?["size"] as? String {
            fileSize = UInt64(sizeStr)
        } else {
            // Fallback: get file size from filesystem
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attrs?[.size] as? UInt64
        }

        // Parse streams
        let streamsArray = json["streams"] as? [[String: Any]] ?? []
        let streams = streamsArray.compactMap { parseStream(from: $0) }

        // Parse chapters
        let chaptersArray = json["chapters"] as? [[String: Any]] ?? []
        let chapters = chaptersArray.enumerated().compactMap { index, dict in
            parseChapter(from: dict, number: index + 1)
        }

        return MediaFile(
            fileURL: fileURL,
            fileSize: fileSize,
            containerFormat: containerFormat,
            containerFormatName: containerFormatName,
            streams: streams,
            duration: duration,
            overallBitrate: overallBitrate,
            metadata: metadata,
            chapters: chapters,
            probedAt: Date()
        )
    }

    /// Parse a single stream from FFprobe's JSON output.
    private func parseStream(from dict: [String: Any]) -> MediaStream? {
        guard let index = dict["index"] as? Int,
              let codecTypeStr = dict["codec_type"] as? String else {
            return nil
        }

        // Determine stream type
        let streamType: StreamType
        switch codecTypeStr {
        case "video": streamType = .video
        case "audio": streamType = .audio
        case "subtitle": streamType = .subtitle
        case "data": streamType = .data
        case "attachment": streamType = .attachment
        default: streamType = .unknown
        }

        let codecName = dict["codec_name"] as? String
        let codecLongName = dict["codec_long_name"] as? String

        // Parse bitrate
        let bitrate: Int?
        if let brStr = dict["bit_rate"] as? String {
            bitrate = Int(brStr)
        } else {
            bitrate = nil
        }

        // Parse duration
        let duration: TimeInterval?
        if let durStr = dict["duration"] as? String {
            duration = TimeInterval(durStr)
        } else {
            duration = nil
        }

        // Parse tags
        let tags = dict["tags"] as? [String: Any] ?? [:]
        let language = tags["language"] as? String
        let title = tags["title"] as? String

        // Parse disposition (default, forced, etc.)
        let disposition = dict["disposition"] as? [String: Any] ?? [:]
        let isDefault = (disposition["default"] as? Int) == 1
        let isForced = (disposition["forced"] as? Int) == 1

        // Video-specific parsing
        var width: Int?
        var height: Int?
        var frameRate: Double?
        var pixelAspectRatio: String?
        var displayAspectRatio: String?
        var hdrFormats: [HDRFormat] = []
        var colourProperties: ColourProperties?
        var videoCodec: VideoCodec?

        if streamType == .video {
            width = dict["width"] as? Int ?? dict["coded_width"] as? Int
            height = dict["height"] as? Int ?? dict["coded_height"] as? Int
            pixelAspectRatio = dict["sample_aspect_ratio"] as? String
            displayAspectRatio = dict["display_aspect_ratio"] as? String

            // Parse frame rate from "r_frame_rate" (e.g., "24000/1001")
            if let frStr = dict["r_frame_rate"] as? String ?? dict["avg_frame_rate"] as? String {
                frameRate = parseFrameRate(frStr)
            }

            // Parse colour properties
            let colorPrimaries = dict["color_primaries"] as? String
            let colorTransfer = dict["color_transfer"] as? String
            let colorSpace = dict["color_space"] as? String
            let bitDepth = dict["bits_per_raw_sample"] as? String
            let pixFmt = dict["pix_fmt"] as? String

            colourProperties = ColourProperties(
                primaries: colorPrimaries,
                transferCharacteristics: colorTransfer,
                matrixCoefficients: colorSpace,
                bitDepth: bitDepth.flatMap(Int.init) ?? detectBitDepth(from: pixFmt),
                chromaSubsampling: detectChromaSubsampling(from: pixFmt)
            )

            // Detect HDR formats from colour metadata
            hdrFormats = detectHDRFormats(
                transfer: colorTransfer,
                primaries: colorPrimaries,
                codecName: codecName,
                sideData: dict["side_data_list"] as? [[String: Any]]
            )

            // Map codec name to VideoCodec enum
            videoCodec = mapToVideoCodec(codecName)
        }

        // Audio-specific parsing
        var sampleRate: Int?
        var channelLayout: ChannelLayout?
        var audioBitDepth: Int?
        var audioCodec: AudioCodec?

        if streamType == .audio {
            if let srStr = dict["sample_rate"] as? String {
                sampleRate = Int(srStr)
            }

            let channelCount = dict["channels"] as? Int ?? 0
            let layoutName = dict["channel_layout"] as? String
            channelLayout = ChannelLayout(channelCount: channelCount, layoutName: layoutName)

            if let bpsStr = dict["bits_per_raw_sample"] as? String {
                audioBitDepth = Int(bpsStr)
            }

            audioCodec = mapToAudioCodec(codecName)
        }

        // Subtitle-specific parsing
        var subtitleFormat: SubtitleFormat?
        if streamType == .subtitle {
            subtitleFormat = mapToSubtitleFormat(codecName)
        }

        return MediaStream(
            streamIndex: index,
            streamType: streamType,
            codecName: codecName,
            codecLongName: codecLongName,
            bitrate: bitrate,
            duration: duration,
            language: language,
            title: title,
            isDefault: isDefault,
            isForced: isForced,
            width: width,
            height: height,
            frameRate: frameRate,
            pixelAspectRatio: pixelAspectRatio,
            displayAspectRatio: displayAspectRatio,
            hdrFormats: hdrFormats,
            colourProperties: colourProperties,
            videoCodec: videoCodec,
            sampleRate: sampleRate,
            channelLayout: channelLayout,
            audioBitDepth: audioBitDepth,
            audioCodec: audioCodec,
            subtitleFormat: subtitleFormat
        )
    }

    /// Parse a chapter from FFprobe's JSON output.
    private func parseChapter(from dict: [String: Any], number: Int) -> Chapter? {
        guard let startStr = dict["start_time"] as? String,
              let endStr = dict["end_time"] as? String,
              let start = TimeInterval(startStr),
              let end = TimeInterval(endStr) else {
            return nil
        }

        let tags = dict["tags"] as? [String: Any] ?? [:]
        let title = tags["title"] as? String

        var chapterMeta: [String: String] = [:]
        for (key, value) in tags {
            chapterMeta[key] = "\(value)"
        }

        return Chapter(
            number: number,
            title: title,
            startTime: start,
            endTime: end,
            metadata: chapterMeta
        )
    }

    // MARK: - Format Detection Helpers

    /// Detect the ContainerFormat enum value from FFprobe's format_name string.
    private func detectContainerFormat(from formatName: String?, fileExtension: String) -> ContainerFormat? {
        // Try file extension first (more reliable for ambiguous format names)
        if let fromExt = ContainerFormat.from(fileExtension: fileExtension) {
            return fromExt
        }

        // Fall back to format name matching
        guard let name = formatName?.lowercased() else { return nil }
        if name.contains("matroska") { return .mkv }
        if name.contains("mov") || name.contains("mp4") { return .mp4 }
        if name.contains("avi") { return .avi }
        if name.contains("mpegts") { return .mpegTS }
        if name.contains("webm") { return .webm }
        if name.contains("ogg") { return .ogg }
        if name.contains("flv") { return .flv }
        if name.contains("mxf") { return .mxf }
        if name.contains("3gp") { return .threeGP }
        return nil
    }

    /// Parse a frame rate fraction string (e.g., "24000/1001") into a Double.
    private func parseFrameRate(_ frStr: String) -> Double? {
        let parts = frStr.split(separator: "/")
        if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
            return num / den
        }
        return Double(frStr)
    }

    /// Detect HDR formats from colour metadata and side data.
    private func detectHDRFormats(
        transfer: String?,
        primaries: String?,
        codecName: String?,
        sideData: [[String: Any]]?
    ) -> [HDRFormat] {
        var formats: [HDRFormat] = []

        // Check for PQ transfer function (HDR10, HDR10+, DV)
        if let tc = transfer?.lowercased() {
            if tc.contains("2084") || tc.contains("smpte2084") || tc == "smpte_st2084" {
                formats.append(.pq)
                formats.append(.hdr10) // PQ implies at least HDR10
            }
            if tc.contains("b67") || tc.contains("hlg") || tc.contains("arib") {
                formats.append(.hlg)
            }
        }

        // Check for HDR10+ dynamic metadata in side data
        if let sideDataList = sideData {
            for sd in sideDataList {
                if let sdType = sd["side_data_type"] as? String {
                    if sdType.contains("HDR10+") || sdType.contains("HDR Dynamic") {
                        formats.append(.hdr10Plus)
                    }
                    if sdType.contains("Dolby Vision") {
                        formats.append(.dolbyVision)
                    }
                }
            }
        }

        // Check for Dolby Vision codec profiles
        if let codec = codecName?.lowercased() {
            if codec.contains("dvhe") || codec.contains("dvh1") || codec.contains("dvav") {
                if !formats.contains(.dolbyVision) {
                    formats.append(.dolbyVision)
                }
            }
        }

        return formats
    }

    /// Detect bit depth from FFmpeg pixel format string.
    private func detectBitDepth(from pixFmt: String?) -> Int? {
        guard let fmt = pixFmt?.lowercased() else { return nil }
        if fmt.contains("10le") || fmt.contains("10be") || fmt.contains("p010") { return 10 }
        if fmt.contains("12le") || fmt.contains("12be") { return 12 }
        if fmt.contains("16le") || fmt.contains("16be") { return 16 }
        return 8 // Default for most formats
    }

    /// Detect chroma subsampling from pixel format string.
    private func detectChromaSubsampling(from pixFmt: String?) -> String? {
        guard let fmt = pixFmt?.lowercased() else { return nil }
        if fmt.contains("444") { return "4:4:4" }
        if fmt.contains("422") { return "4:2:2" }
        if fmt.contains("420") || fmt.contains("yuv420") || fmt.contains("p010") { return "4:2:0" }
        return nil
    }

    /// Map FFprobe codec name to VideoCodec enum.
    private func mapToVideoCodec(_ codecName: String?) -> VideoCodec? {
        guard let name = codecName?.lowercased() else { return nil }
        switch name {
        case "h264", "avc": return .h264
        case "hevc", "h265": return .h265
        case "vp8": return .vp8
        case "vp9": return .vp9
        case "av1": return .av1
        case "prores": return .prores
        case "mpeg2video": return .mpeg2
        case "mpeg4": return .mpeg4
        case "theora": return .theora
        case "ffv1": return .ffv1
        case "dnxhd": return .dnxhr
        case "vc1", "wmv3": return .vc1
        case "cfhd": return .cineform
        case "jpeg2000", "libopenjpeg": return .jpeg2000
        default: return nil
        }
    }

    /// Map FFprobe codec name to AudioCodec enum.
    private func mapToAudioCodec(_ codecName: String?) -> AudioCodec? {
        guard let name = codecName?.lowercased() else { return nil }
        switch name {
        case "aac": return .aacLC
        case "ac3": return .ac3
        case "eac3": return .eac3
        case "truehd": return .trueHD
        case "ac4": return .ac4
        case "dts": return .dts
        case "dca": return .dts
        case "mp3": return .mp3
        case "mp2": return .mp2
        case "flac": return .flac
        case "alac": return .alac
        case "opus": return .opus
        case "vorbis": return .vorbis
        case "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_s16be", "pcm_s24be":
            return .pcm
        case "wavpack": return .wavpack
        case "ape": return .ape
        case "tta": return .tta
        case "wmav2", "wmapro": return .wma
        case "musepack7", "musepack8": return .musepack
        case "atrac3p", "atrac3", "atrac1": return .atrac
        default: return nil
        }
    }

    /// Map FFprobe codec name to SubtitleFormat enum.
    private func mapToSubtitleFormat(_ codecName: String?) -> SubtitleFormat? {
        guard let name = codecName?.lowercased() else { return nil }
        switch name {
        case "subrip", "srt": return .srt
        case "ass", "ssa": return .ssa
        case "webvtt": return .webVTT
        case "dvb_subtitle": return .dvbSub
        case "hdmv_pgs_subtitle", "pgssub": return .pgs
        case "dvd_subtitle": return .vobSub
        case "mov_text": return .srt // MP4 text subs treated as SRT-like
        case "ttml": return .ttml
        case "sami": return .sami
        case "eia_608": return .cc608
        case "cc_dec": return .cc708
        default: return nil
        }
    }
}
