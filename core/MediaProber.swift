// File: adaptix/core/MediaProber.swift
// Purpose: Analyzes media files using ffprobe to extract stream information, metadata, and technical details.
// Role: Provides comprehensive media file analysis for encoding decisions, profile suggestions, and validation.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

// MARK: - Media Information Structures

/// Comprehensive information about a media file
struct MediaInfo: Codable {
    let format: FormatInfo
    let videoStreams: [VideoStreamInfo]
    let audioStreams: [AudioStreamInfo]
    let subtitleStreams: [SubtitleStreamInfo]
    let duration: Double
    let bitrate: Int
    let fileSize: Int64
}

/// Format/container information
struct FormatInfo: Codable {
    let formatName: String
    let formatLongName: String
    let duration: Double
    let bitrate: Int
    let tags: [String: String]
}

/// Video stream information
struct VideoStreamInfo: Codable {
    let index: Int
    let codec: String
    let codecLongName: String
    let profile: String?
    let width: Int
    let height: Int
    let bitrate: Int?
    let frameRate: Double
    let pixelFormat: String
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let hdrMetadata: HDRMetadata?
    let tags: [String: String]
}

/// Audio stream information
struct AudioStreamInfo: Codable {
    let index: Int
    let codec: String
    let codecLongName: String
    let sampleRate: Int
    let channels: Int
    let channelLayout: String?
    let bitrate: Int?
    let language: String?
    let title: String?
    let tags: [String: String]
}

/// Subtitle stream information
struct SubtitleStreamInfo: Codable {
    let index: Int
    let codec: String
    let codecLongName: String
    let language: String?
    let title: String?
    let tags: [String: String]
}

/// HDR metadata information
struct HDRMetadata: Codable {
    let type: String // "HDR10", "HDR10+", "Dolby Vision", "HLG"
    let maxCLL: Int? // Maximum Content Light Level
    let maxFALL: Int? // Maximum Frame-Average Light Level
    let masterDisplay: MasterDisplayInfo?
}

/// Master display color volume information
struct MasterDisplayInfo: Codable {
    let redX: Double
    let redY: Double
    let greenX: Double
    let greenY: Double
    let blueX: Double
    let blueY: Double
    let whitePointX: Double
    let whitePointY: Double
    let maxLuminance: Double
    let minLuminance: Double
}

// MARK: - Media Prober

/// Utility class for probing media files using ffprobe
class MediaProber {

    private let ffprobePath: String

    /// Initialize with custom ffprobe path
    init(ffprobePath: String = "/usr/local/bin/ffprobe") {
        self.ffprobePath = ffprobePath
    }

    /// Probe a media file and return comprehensive information
    /// - Parameter filePath: Path to the media file
    /// - Returns: MediaInfo structure with all stream and format details
    /// - Throws: ProbeError if file doesn't exist or probe fails
    func probe(_ filePath: String) throws -> MediaInfo {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ProbeError.fileNotFound(filePath)
        }

        let arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            filePath
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw ProbeError.probeFailed(errorMessage)
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
                throw ProbeError.invalidJSON
            }

            return try parseProbeOutput(json, filePath: filePath)

        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.executionFailed(error.localizedDescription)
        }
    }

    /// Quick probe to check if file is valid media
    func isValidMedia(_ filePath: String) -> Bool {
        do {
            _ = try probe(filePath)
            return true
        } catch {
            return false
        }
    }

    /// Get suggested bitrate ladder for adaptive streaming
    func suggestBitrateLadder(for mediaInfo: MediaInfo) -> [Int] {
        guard let firstVideo = mediaInfo.videoStreams.first else {
            return [128, 256, 512] // Audio-only defaults in kbps
        }

        let width = firstVideo.width
        let height = firstVideo.height

        // Suggest bitrate ladder based on source resolution
        switch (width, height) {
        case (3840..., 2160...): // 4K
            return [8000, 6000, 4500, 3000, 2000, 1000, 500]
        case (2560..., 1440...): // 1440p
            return [6000, 4500, 3000, 2000, 1000, 500]
        case (1920..., 1080...): // 1080p
            return [4500, 3000, 2000, 1000, 500]
        case (1280..., 720...): // 720p
            return [2500, 1500, 1000, 500]
        case (854..., 480...): // 480p
            return [1000, 750, 500]
        default: // SD
            return [750, 500, 250]
        }
    }

    /// Detect HDR type from video stream
    private func detectHDR(from stream: [String: Any]) -> HDRMetadata? {
        guard let colorTransfer = stream["color_transfer"] as? String else {
            return nil
        }

        var hdrType: String?

        switch colorTransfer {
        case "smpte2084": // PQ (Perceptual Quantizer)
            hdrType = "HDR10"
        case "arib-std-b67": // HLG (Hybrid Log-Gamma)
            hdrType = "HLG"
        default:
            break
        }

        // Check for Dolby Vision
        if let sideDataList = stream["side_data_list"] as? [[String: Any]] {
            for sideData in sideDataList {
                if let sideDataType = sideData["side_data_type"] as? String {
                    if sideDataType == "DOVI configuration record" {
                        hdrType = "Dolby Vision"
                    }
                    if sideDataType == "Content light level metadata" {
                        // HDR10+ check would go here
                        // (More complex detection needed for HDR10+ vs HDR10)
                    }
                }
            }
        }

        guard let type = hdrType else { return nil }

        return HDRMetadata(
            type: type,
            maxCLL: extractMaxCLL(from: stream),
            maxFALL: extractMaxFALL(from: stream),
            masterDisplay: extractMasterDisplay(from: stream)
        )
    }

    private func extractMaxCLL(from stream: [String: Any]) -> Int? {
        guard let sideDataList = stream["side_data_list"] as? [[String: Any]] else {
            return nil
        }

        for sideData in sideDataList {
            if sideData["side_data_type"] as? String == "Content light level metadata",
               let maxCLL = sideData["max_content"] as? Int {
                return maxCLL
            }
        }
        return nil
    }

    private func extractMaxFALL(from stream: [String: Any]) -> Int? {
        guard let sideDataList = stream["side_data_list"] as? [[String: Any]] else {
            return nil
        }

        for sideData in sideDataList {
            if sideData["side_data_type"] as? String == "Content light level metadata",
               let maxFALL = sideData["max_average"] as? Int {
                return maxFALL
            }
        }
        return nil
    }

    private func extractMasterDisplay(from stream: [String: Any]) -> MasterDisplayInfo? {
        guard let sideDataList = stream["side_data_list"] as? [[String: Any]] else {
            return nil
        }

        for sideData in sideDataList {
            if sideData["side_data_type"] as? String == "Mastering display metadata" {
                // Parse mastering display color volume
                // Format varies, so this is a simplified version
                return nil // Would need actual parsing implementation
            }
        }
        return nil
    }

    // MARK: - JSON Parsing

    private func parseProbeOutput(_ json: [String: Any], filePath: String) throws -> MediaInfo {
        guard let format = json["format"] as? [String: Any] else {
            throw ProbeError.missingFormat
        }

        guard let streams = json["streams"] as? [[String: Any]] else {
            throw ProbeError.missingStreams
        }

        let formatInfo = try parseFormat(format)
        let videoStreams = try parseVideoStreams(streams)
        let audioStreams = try parseAudioStreams(streams)
        let subtitleStreams = try parseSubtitleStreams(streams)

        let duration = Double(format["duration"] as? String ?? "0") ?? 0
        let bitrate = Int(format["bit_rate"] as? String ?? "0") ?? 0

        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return MediaInfo(
            format: formatInfo,
            videoStreams: videoStreams,
            audioStreams: audioStreams,
            subtitleStreams: subtitleStreams,
            duration: duration,
            bitrate: bitrate,
            fileSize: fileSize
        )
    }

    private func parseFormat(_ format: [String: Any]) -> FormatInfo {
        FormatInfo(
            formatName: format["format_name"] as? String ?? "unknown",
            formatLongName: format["format_long_name"] as? String ?? "Unknown",
            duration: Double(format["duration"] as? String ?? "0") ?? 0,
            bitrate: Int(format["bit_rate"] as? String ?? "0") ?? 0,
            tags: format["tags"] as? [String: String] ?? [:]
        )
    }

    private func parseVideoStreams(_ streams: [[String: Any]]) throws -> [VideoStreamInfo] {
        streams.compactMap { stream -> VideoStreamInfo? in
            guard stream["codec_type"] as? String == "video" else { return nil }

            let frameRateStr = stream["r_frame_rate"] as? String ?? "30/1"
            let components = frameRateStr.split(separator: "/")
            let frameRate = components.count == 2
                ? (Double(components[0]) ?? 30.0) / (Double(components[1]) ?? 1.0)
                : 30.0

            return VideoStreamInfo(
                index: stream["index"] as? Int ?? 0,
                codec: stream["codec_name"] as? String ?? "unknown",
                codecLongName: stream["codec_long_name"] as? String ?? "Unknown",
                profile: stream["profile"] as? String,
                width: stream["width"] as? Int ?? 0,
                height: stream["height"] as? Int ?? 0,
                bitrate: Int(stream["bit_rate"] as? String ?? "0"),
                frameRate: frameRate,
                pixelFormat: stream["pix_fmt"] as? String ?? "unknown",
                colorSpace: stream["color_space"] as? String,
                colorTransfer: stream["color_transfer"] as? String,
                colorPrimaries: stream["color_primaries"] as? String,
                hdrMetadata: detectHDR(from: stream),
                tags: stream["tags"] as? [String: String] ?? [:]
            )
        }
    }

    private func parseAudioStreams(_ streams: [[String: Any]]) throws -> [AudioStreamInfo] {
        streams.compactMap { stream -> AudioStreamInfo? in
            guard stream["codec_type"] as? String == "audio" else { return nil }

            let tags = stream["tags"] as? [String: String] ?? [:]

            return AudioStreamInfo(
                index: stream["index"] as? Int ?? 0,
                codec: stream["codec_name"] as? String ?? "unknown",
                codecLongName: stream["codec_long_name"] as? String ?? "Unknown",
                sampleRate: Int(stream["sample_rate"] as? String ?? "0") ?? 0,
                channels: stream["channels"] as? Int ?? 2,
                channelLayout: stream["channel_layout"] as? String,
                bitrate: Int(stream["bit_rate"] as? String ?? "0"),
                language: tags["language"],
                title: tags["title"],
                tags: tags
            )
        }
    }

    private func parseSubtitleStreams(_ streams: [[String: Any]]) throws -> [SubtitleStreamInfo] {
        streams.compactMap { stream -> SubtitleStreamInfo? in
            guard stream["codec_type"] as? String == "subtitle" else { return nil }

            let tags = stream["tags"] as? [String: String] ?? [:]

            return SubtitleStreamInfo(
                index: stream["index"] as? Int ?? 0,
                codec: stream["codec_name"] as? String ?? "unknown",
                codecLongName: stream["codec_long_name"] as? String ?? "Unknown",
                language: tags["language"],
                title: tags["title"],
                tags: tags
            )
        }
    }
}

// MARK: - Errors

enum ProbeError: Error, LocalizedError {
    case fileNotFound(String)
    case probeFailed(String)
    case invalidJSON
    case executionFailed(String)
    case missingFormat
    case missingStreams

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .probeFailed(let message):
            return "FFprobe failed: \(message)"
        case .invalidJSON:
            return "Invalid JSON output from ffprobe"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .missingFormat:
            return "Missing format information in probe output"
        case .missingStreams:
            return "Missing stream information in probe output"
        }
    }
}
