// ============================================================================
// MeedyaConverter — TrueHDMP4Muxer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - TrueHDStreamConfig

/// Configuration for Dolby TrueHD streams in MP4 containers.
public struct TrueHDStreamConfig: Codable, Sendable {
    /// Whether TrueHD is the primary audio stream (not recommended for MP4).
    public var isPrimary: Bool

    /// Index of the compatible fallback AAC/AC-3 stream.
    public var fallbackStreamIndex: Int?

    /// Whether to include the embedded AC-3 core substream.
    public var includeAC3Core: Bool

    /// Dolby Atmos metadata present (TrueHD MAT 2.0).
    public var hasAtmos: Bool

    public init(
        isPrimary: Bool = false,
        fallbackStreamIndex: Int? = nil,
        includeAC3Core: Bool = true,
        hasAtmos: Bool = false
    ) {
        self.isPrimary = isPrimary
        self.fallbackStreamIndex = fallbackStreamIndex
        self.includeAC3Core = includeAC3Core
        self.hasAtmos = hasAtmos
    }
}

// MARK: - TrueHDMP4Muxer

/// Builds FFmpeg arguments for muxing Dolby TrueHD audio into MP4 containers.
///
/// Dolby TrueHD in MP4 is a non-standard but increasingly supported configuration:
/// - Apple TV 4K supports TrueHD passthrough in MP4/MOV
/// - Plex/Jellyfin can direct-play TrueHD in MP4 to compatible receivers
/// - The MP4 file MUST include a compatible fallback audio track (AAC or AC-3)
///   as the default stream, with TrueHD as a secondary non-default stream
///
/// This is controlled by `-strict unofficial` in FFmpeg since TrueHD in MP4
/// is not part of the MPEG-4 Part 14 specification.
///
/// Phase 3 / Issue #253
public struct TrueHDMP4Muxer: Sendable {

    // MARK: - Muxing Arguments

    /// Build FFmpeg arguments for muxing TrueHD into MP4 alongside a fallback track.
    ///
    /// The output has:
    /// - Stream 0: Video (copy)
    /// - Stream 1: AAC/AC-3 fallback (default)
    /// - Stream 2: TrueHD (non-default)
    ///
    /// - Parameters:
    ///   - inputPath: Source file with TrueHD audio.
    ///   - outputPath: Output MP4 file.
    ///   - videoStreamIndex: Video stream index in source.
    ///   - trueHDStreamIndex: TrueHD audio stream index in source.
    ///   - fallbackCodec: Fallback audio codec ("aac" or "ac3").
    ///   - fallbackBitrate: Fallback audio bitrate in kbps.
    /// - Returns: FFmpeg argument array.
    public static func buildMuxArguments(
        inputPath: String,
        outputPath: String,
        videoStreamIndex: Int = 0,
        trueHDStreamIndex: Int = 0,
        fallbackCodec: String = "aac",
        fallbackBitrate: Int = 256
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Map video (copy)
        args += ["-map", "0:v:\(videoStreamIndex)"]

        // Map TrueHD source for fallback encode
        args += ["-map", "0:a:\(trueHDStreamIndex)"]

        // Map TrueHD source for passthrough
        args += ["-map", "0:a:\(trueHDStreamIndex)"]

        // Video: copy
        args += ["-c:v", "copy"]

        // Audio stream 0: fallback (encode from TrueHD)
        args += ["-c:a:0", fallbackCodec]
        args += ["-b:a:0", "\(fallbackBitrate)k"]
        if fallbackCodec == "aac" {
            args += ["-ac:a:0", "2"] // Stereo fallback
        } else {
            args += ["-ac:a:0", "6"] // 5.1 for AC-3
        }

        // Audio stream 1: TrueHD passthrough
        args += ["-c:a:1", "copy"]

        // Set fallback as default, TrueHD as non-default
        args += ["-disposition:a:0", "default"]
        args += ["-disposition:a:1", "0"]

        // Required for TrueHD in MP4
        args += ["-strict", "unofficial"]

        args += ["-y", outputPath]

        return args
    }

    /// Build FFmpeg arguments for remuxing TrueHD from MKV to MP4.
    ///
    /// Copies all streams, adding `-strict unofficial` to allow TrueHD.
    /// Assumes the source already has a compatible fallback track.
    ///
    /// - Parameters:
    ///   - inputPath: Source MKV file.
    ///   - outputPath: Output MP4 file.
    /// - Returns: FFmpeg argument array.
    public static func buildRemuxArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0",
            "-c", "copy",
            "-strict", "unofficial",
            "-y", outputPath,
        ]
    }

    /// Build FFmpeg arguments to extract the AC-3 core from TrueHD.
    ///
    /// TrueHD streams contain an embedded AC-3 (Dolby Digital) core substream
    /// that can be extracted without re-encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source file with TrueHD audio.
    ///   - outputPath: Output file for AC-3 core.
    ///   - trueHDStreamIndex: TrueHD stream index.
    /// - Returns: FFmpeg argument array.
    public static func buildAC3CoreExtractArguments(
        inputPath: String,
        outputPath: String,
        trueHDStreamIndex: Int = 0
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:a:\(trueHDStreamIndex)",
            "-c:a", "ac3",
            "-b:a", "640k",
            "-ac", "6",
            "-y", outputPath,
        ]
    }

    // MARK: - Validation

    /// Validate that an MP4 file with TrueHD has a compatible fallback track.
    ///
    /// - Parameters:
    ///   - audioCodecs: List of audio codec names in the file.
    ///   - audioDefaults: List of whether each audio track is the default.
    /// - Returns: Array of validation warnings. Empty means valid.
    public static func validate(
        audioCodecs: [String],
        audioDefaults: [Bool]
    ) -> [String] {
        var warnings: [String] = []

        let hasTrueHD = audioCodecs.contains { $0.lowercased().contains("truehd") || $0.lowercased().contains("mlp") }
        guard hasTrueHD else { return [] }

        let hasCompatibleFallback = audioCodecs.contains {
            let lower = $0.lowercased()
            return lower.contains("aac") || lower.contains("ac3") || lower.contains("eac3")
        }

        if !hasCompatibleFallback {
            warnings.append("MP4 with TrueHD must include a compatible fallback audio track (AAC or AC-3)")
        }

        // Check that TrueHD is not the default stream
        for (i, codec) in audioCodecs.enumerated() {
            let isTrueHD = codec.lowercased().contains("truehd") || codec.lowercased().contains("mlp")
            let isDefault = i < audioDefaults.count ? audioDefaults[i] : (i == 0)
            if isTrueHD && isDefault {
                warnings.append("TrueHD should not be the default audio stream in MP4 — incompatible players will fail")
            }
        }

        return warnings
    }

    /// Check if a container supports TrueHD audio.
    ///
    /// - Parameter container: Container format identifier.
    /// - Returns: Support level.
    public static func trueHDSupport(container: String) -> TrueHDContainerSupport {
        let lower = container.lowercased()
        switch lower {
        case "mkv", "mka":
            return .native
        case "mp4", "m4v":
            return .unofficial
        case "mov":
            return .unofficial
        case "ts", "m2ts":
            return .native
        default:
            return .unsupported
        }
    }
}

// MARK: - TrueHDContainerSupport

/// Level of TrueHD support in a container format.
public enum TrueHDContainerSupport: String, Sendable {
    /// Natively supported per spec (MKV, M2TS).
    case native = "native"

    /// Supported with `-strict unofficial` (MP4, MOV).
    case unofficial = "unofficial"

    /// Not supported.
    case unsupported = "unsupported"

    /// Display name.
    public var displayName: String {
        switch self {
        case .native: return "Natively Supported"
        case .unofficial: return "Unofficial (requires -strict unofficial)"
        case .unsupported: return "Not Supported"
        }
    }
}
