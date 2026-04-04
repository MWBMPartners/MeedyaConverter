// ============================================================================
// MeedyaConverter — ExtendedVideoCodec
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ExtendedVideoCodecType

/// Additional video codecs beyond the core set (H.264/H.265/AV1/VP9/ProRes).
///
/// These codecs serve specialized workflows: archival, intermediate editing,
/// digital cinema, and legacy format support.
public enum ExtendedVideoCodecType: String, Codable, Sendable, CaseIterable {

    /// FFV1 — open-source lossless video codec for archival/preservation.
    case ffv1

    /// CineForm (GoPro CineForm) — visually lossless intermediate codec.
    case cineform

    /// VC-1 — Microsoft's video codec (decode only, Blu-ray/WMV).
    case vc1

    /// WMV9 — Windows Media Video 9, consumer variant of VC-1.
    case wmv9

    /// JPEG 2000 — wavelet-based codec for DCP and archival.
    case jpeg2000

    /// FFmpeg encoder name (nil = decode only).
    public var ffmpegEncoder: String? {
        switch self {
        case .ffv1: return "ffv1"
        case .cineform: return "cfhd"
        case .vc1: return nil // Decode only
        case .wmv9: return nil // Decode only
        case .jpeg2000: return "libopenjpeg"
        }
    }

    /// FFmpeg decoder name.
    public var ffmpegDecoder: String {
        switch self {
        case .ffv1: return "ffv1"
        case .cineform: return "cfhd"
        case .vc1: return "vc1"
        case .wmv9: return "wmv3"
        case .jpeg2000: return "libopenjpeg"
        }
    }

    /// Display name.
    public var displayName: String {
        switch self {
        case .ffv1: return "FFV1 (Archival Lossless)"
        case .cineform: return "GoPro CineForm"
        case .vc1: return "VC-1"
        case .wmv9: return "Windows Media Video 9"
        case .jpeg2000: return "JPEG 2000"
        }
    }

    /// Whether this codec supports encoding (not just decoding).
    public var canEncode: Bool {
        ffmpegEncoder != nil
    }

    /// Whether this codec is lossless.
    public var isLossless: Bool {
        switch self {
        case .ffv1: return true
        case .cineform: return false // Visually lossless but technically lossy
        default: return false
        }
    }

    /// Compatible container formats.
    public var compatibleContainers: [String] {
        switch self {
        case .ffv1: return ["mkv", "avi", "nut"]
        case .cineform: return ["avi", "mov"]
        case .vc1: return ["mkv", "wmv", "asf", "m2ts"]
        case .wmv9: return ["wmv", "asf", "avi"]
        case .jpeg2000: return ["mxf", "mkv", "mov", "j2k"]
        }
    }

    /// Primary use case.
    public var useCase: String {
        switch self {
        case .ffv1: return "Archival preservation"
        case .cineform: return "Editing intermediate"
        case .vc1: return "Blu-ray / legacy Windows"
        case .wmv9: return "Legacy Windows media"
        case .jpeg2000: return "Digital cinema (DCP)"
        }
    }
}

// MARK: - FFV1Config

/// Configuration for FFV1 lossless encoding.
public struct FFV1Config: Codable, Sendable {
    /// FFV1 version (1, 3). Version 3 supports multithreading and error resilience.
    public var version: Int

    /// Number of encoding slices (for multithreading). Must be power of 2.
    public var sliceCount: Int

    /// Whether to enable slice CRC error detection.
    public var sliceCRC: Bool

    /// Context model (0 = small, 1 = large/better compression).
    public var contextModel: Int

    public init(
        version: Int = 3,
        sliceCount: Int = 4,
        sliceCRC: Bool = true,
        contextModel: Int = 1
    ) {
        self.version = version
        self.sliceCount = sliceCount
        self.sliceCRC = sliceCRC
        self.contextModel = contextModel
    }
}

// MARK: - JPEG2000Config

/// Configuration for JPEG 2000 encoding.
public struct JPEG2000Config: Codable, Sendable {
    /// Compression ratio (1 = lossless, higher = more compression).
    public var compressionRatio: Int

    /// Bit depth (8, 10, 12, 16).
    public var bitDepth: Int

    /// Whether to use cinema profile constraints.
    public var cinemaProfile: JPEG2000CinemaProfile?

    /// Tile width (nil = no tiling).
    public var tileWidth: Int?

    /// Tile height.
    public var tileHeight: Int?

    /// Number of resolution levels.
    public var resolutionLevels: Int

    public init(
        compressionRatio: Int = 1,
        bitDepth: Int = 12,
        cinemaProfile: JPEG2000CinemaProfile? = nil,
        tileWidth: Int? = nil,
        tileHeight: Int? = nil,
        resolutionLevels: Int = 6
    ) {
        self.compressionRatio = compressionRatio
        self.bitDepth = bitDepth
        self.cinemaProfile = cinemaProfile
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.resolutionLevels = resolutionLevels
    }
}

// MARK: - JPEG2000CinemaProfile

/// JPEG 2000 Digital Cinema profiles.
public enum JPEG2000CinemaProfile: String, Codable, Sendable {
    case cinema2K = "cinema2k"
    case cinema4K = "cinema4k"

    /// Maximum bitrate in Mbps per the DCI specification.
    public var maxBitrateMbps: Int {
        switch self {
        case .cinema2K: return 250
        case .cinema4K: return 500
        }
    }

    /// Expected resolution.
    public var resolution: (width: Int, height: Int) {
        switch self {
        case .cinema2K: return (2048, 1080)
        case .cinema4K: return (4096, 2160)
        }
    }
}

// MARK: - ExtendedVideoCodecBuilder

/// Builds FFmpeg arguments for extended video codec operations.
///
/// Phase 3.23
public struct ExtendedVideoCodecBuilder: Sendable {

    // MARK: - FFV1

    /// Build FFmpeg arguments for FFV1 lossless encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - outputPath: Output file (typically .mkv).
    ///   - config: FFV1 configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildFFV1EncodeArguments(
        inputPath: String,
        outputPath: String,
        config: FFV1Config = FFV1Config()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:v", "ffv1"]
        args += ["-level", "\(config.version)"]
        args += ["-slices", "\(config.sliceCount)"]
        args += ["-context", "\(config.contextModel)"]

        if config.sliceCRC {
            args += ["-slicecrc", "1"]
        }

        // Multithreading for FFV1 v3
        if config.version >= 3 {
            args += ["-threads", "0"]
        }

        // Copy audio
        args += ["-c:a", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - CineForm

    /// Build FFmpeg arguments for CineForm encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - outputPath: Output file (typically .avi or .mov).
    ///   - quality: Quality level (0 = lowest, 12 = filmscan).
    /// - Returns: FFmpeg argument array.
    public static func buildCineFormEncodeArguments(
        inputPath: String,
        outputPath: String,
        quality: Int = 5
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:v", "cfhd"]
        args += ["-quality", "\(min(12, max(0, quality)))"]

        // Copy audio
        args += ["-c:a", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - JPEG 2000

    /// Build FFmpeg arguments for JPEG 2000 encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - outputPath: Output file (typically .mxf for DCP or .mkv).
    ///   - config: JPEG 2000 configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildJPEG2000EncodeArguments(
        inputPath: String,
        outputPath: String,
        config: JPEG2000Config = JPEG2000Config()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:v", "libopenjpeg"]

        // Compression ratio
        if config.compressionRatio > 1 {
            args += ["-compression_level", "\(config.compressionRatio)"]
        }

        // Number of resolutions
        args += ["-numresolution", "\(config.resolutionLevels)"]

        // Cinema profile
        if let cinema = config.cinemaProfile {
            args += ["-cinema_mode", cinema.rawValue]
        }

        // Copy audio
        args += ["-c:a", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Decode/Transcode

    /// Build FFmpeg arguments to transcode from any extended codec to a standard codec.
    ///
    /// - Parameters:
    ///   - inputPath: Source file with extended codec.
    ///   - outputPath: Output file.
    ///   - sourceCodec: Source extended codec type.
    ///   - targetEncoder: Target FFmpeg encoder name (e.g., "libx265").
    ///   - crf: CRF value for lossy encoding.
    /// - Returns: FFmpeg argument array.
    public static func buildTranscodeArguments(
        inputPath: String,
        outputPath: String,
        sourceCodec: ExtendedVideoCodecType,
        targetEncoder: String,
        crf: Int = 18
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Use specific decoder if needed
        if sourceCodec == .jpeg2000 {
            args = ["-c:v", sourceCodec.ffmpegDecoder] + args
        }

        args += ["-c:v", targetEncoder]
        args += ["-crf", "\(crf)"]
        args += ["-c:a", "copy"]
        args += ["-y", outputPath]

        return args
    }

    // MARK: - Passthrough

    /// Build FFmpeg arguments for codec passthrough (remux).
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output container.
    /// - Returns: FFmpeg argument array.
    public static func buildPassthroughArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c", "copy",
            "-y", outputPath,
        ]
    }
}
