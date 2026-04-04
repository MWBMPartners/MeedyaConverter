// ============================================================================
// MeedyaConverter — ExtendedAudioCodec
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ExtendedAudioCodecType

/// Additional audio codecs beyond the core set (AAC/AC3/EAC3/DTS/Opus/FLAC/etc.).
public enum ExtendedAudioCodecType: String, Codable, Sendable, CaseIterable {

    /// MP3surround — MPEG Surround for 5.1 in MP3 container.
    case mp3surround

    /// mp3PRO — enhanced MP3 using SBR (Spectral Band Replication).
    case mp3pro

    /// mp3HD — lossless extension to MP3.
    case mp3hd

    /// DTS:X IMAX Enhanced — object-based audio for IMAX.
    case dtsxIMAX = "dtsx_imax"

    /// IAMF (Immersive Audio Model and Formats) — Google/Alliance open immersive.
    case iamf

    /// MPEG-H Audio — 3D/immersive audio standard.
    case mpeghAudio = "mpegh"

    /// AMR-NB (Adaptive Multi-Rate Narrowband) — legacy mobile voice.
    case amrNB = "amr_nb"

    /// AMR-WB (Adaptive Multi-Rate Wideband) — mobile voice.
    case amrWB = "amr_wb"

    /// WMA Pro — Windows Media Audio Professional.
    case wmaPro = "wma_pro"

    /// WMA Lossless — Windows Media Audio Lossless.
    case wmaLossless = "wma_lossless"

    /// Speex — open-source speech codec.
    case speex

    /// ATRAC — Sony's compression for MiniDisc/PS.
    case atrac

    /// Display name.
    public var displayName: String {
        switch self {
        case .mp3surround: return "MP3surround"
        case .mp3pro: return "mp3PRO"
        case .mp3hd: return "mp3HD"
        case .dtsxIMAX: return "DTS:X IMAX Enhanced"
        case .iamf: return "IAMF (Immersive Audio)"
        case .mpeghAudio: return "MPEG-H Audio"
        case .amrNB: return "AMR-NB (Narrowband)"
        case .amrWB: return "AMR-WB (Wideband)"
        case .wmaPro: return "WMA Professional"
        case .wmaLossless: return "WMA Lossless"
        case .speex: return "Speex"
        case .atrac: return "ATRAC (Sony)"
        }
    }

    /// FFmpeg decoder name (nil if not supported by FFmpeg).
    public var ffmpegDecoder: String? {
        switch self {
        case .mp3surround: return "mp3" // MP3 decoder handles surround extension
        case .mp3pro: return "mp3"
        case .mp3hd: return "mp3"
        case .dtsxIMAX: return "dca" // DTS family decoder
        case .iamf: return nil // Not yet in FFmpeg
        case .mpeghAudio: return nil // Not yet in FFmpeg
        case .amrNB: return "amrnb"
        case .amrWB: return "amrwb"
        case .wmaPro: return "wmapro"
        case .wmaLossless: return "wmalossless"
        case .speex: return "libspeex"
        case .atrac: return "atrac3"
        }
    }

    /// FFmpeg encoder name (nil if encoding not supported).
    public var ffmpegEncoder: String? {
        switch self {
        case .amrNB: return "libopencore_amrnb"
        case .amrWB: return "libvo_amrwbenc"
        case .speex: return "libspeex"
        default: return nil // Most are decode-only in FFmpeg
        }
    }

    /// Whether FFmpeg can decode this codec.
    public var canDecode: Bool { ffmpegDecoder != nil }

    /// Whether FFmpeg can encode this codec.
    public var canEncode: Bool { ffmpegEncoder != nil }

    /// Whether this is an immersive/object-based audio format.
    public var isImmersive: Bool {
        switch self {
        case .dtsxIMAX, .iamf, .mpeghAudio, .mp3surround: return true
        default: return false
        }
    }

    /// Whether this is a lossless format.
    public var isLossless: Bool {
        switch self {
        case .mp3hd, .wmaLossless: return true
        default: return false
        }
    }

    /// Maximum channel count.
    public var maxChannels: Int {
        switch self {
        case .mp3surround: return 6    // 5.1
        case .mp3pro: return 2
        case .mp3hd: return 2
        case .dtsxIMAX: return 32      // Object-based
        case .iamf: return 128         // Object-based
        case .mpeghAudio: return 128
        case .amrNB: return 1
        case .amrWB: return 1
        case .wmaPro: return 8
        case .wmaLossless: return 8
        case .speex: return 2
        case .atrac: return 2
        }
    }

    /// Compatible container formats.
    public var compatibleContainers: [String] {
        switch self {
        case .mp3surround: return ["mp3", "mkv"]
        case .mp3pro: return ["mp3"]
        case .mp3hd: return ["mp3"]
        case .dtsxIMAX: return ["mkv", "m2ts"]
        case .iamf: return ["mp4", "mkv"]
        case .mpeghAudio: return ["mp4", "ts"]
        case .amrNB: return ["3gp", "amr"]
        case .amrWB: return ["3gp", "amr"]
        case .wmaPro: return ["wmv", "asf", "mkv"]
        case .wmaLossless: return ["wmv", "asf", "mkv"]
        case .speex: return ["ogg", "flv"]
        case .atrac: return ["oma"]
        }
    }
}

// MARK: - IMAXEnhancedConfig

/// Configuration for IMAX Enhanced audio processing.
public struct IMAXEnhancedConfig: Codable, Sendable {
    /// Whether to apply IMAX Enhanced bass management.
    public var enhancedBass: Bool

    /// Whether to apply IMAX signature sound processing.
    public var signatureSound: Bool

    /// Target peak loudness in dBFS.
    public var targetLoudness: Double

    /// Whether to preserve DTS:X object metadata.
    public var preserveObjects: Bool

    public init(
        enhancedBass: Bool = true,
        signatureSound: Bool = true,
        targetLoudness: Double = -1.0,
        preserveObjects: Bool = true
    ) {
        self.enhancedBass = enhancedBass
        self.signatureSound = signatureSound
        self.targetLoudness = targetLoudness
        self.preserveObjects = preserveObjects
    }
}

// MARK: - ExtendedAudioCodecBuilder

/// Builds FFmpeg arguments for extended audio codec operations.
///
/// Phase 3.21–3.22
public struct ExtendedAudioCodecBuilder: Sendable {

    // MARK: - Decode and Transcode

    /// Build FFmpeg arguments to transcode from an extended audio codec.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - targetCodec: FFmpeg encoder name for output (e.g., "aac", "flac").
    ///   - bitrate: Output bitrate in kbps (for lossy codecs).
    ///   - channels: Output channel count (nil = preserve).
    /// - Returns: FFmpeg argument array.
    public static func buildTranscodeArguments(
        inputPath: String,
        outputPath: String,
        targetCodec: String,
        bitrate: Int? = nil,
        channels: Int? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        args += ["-c:a", targetCodec]

        if let br = bitrate {
            args += ["-b:a", "\(br)k"]
        }

        if let ch = channels {
            args += ["-ac", "\(ch)"]
        }

        // Copy video if present
        args += ["-c:v", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - AMR

    /// Build FFmpeg arguments for AMR-NB encoding (mobile voice).
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - outputPath: Output .amr or .3gp file.
    ///   - bitrate: AMR bitrate in kbps (4.75, 5.15, 5.9, 6.7, 7.4, 7.95, 10.2, 12.2).
    /// - Returns: FFmpeg argument array.
    public static func buildAMRNBEncodeArguments(
        inputPath: String,
        outputPath: String,
        bitrate: Double = 12.2
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:a", "libopencore_amrnb",
            "-b:a", "\(bitrate)k",
            "-ar", "8000",
            "-ac", "1",
            "-y", outputPath,
        ]
    }

    /// Build FFmpeg arguments for AMR-WB encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - outputPath: Output file.
    ///   - bitrate: AMR-WB bitrate in kbps.
    /// - Returns: FFmpeg argument array.
    public static func buildAMRWBEncodeArguments(
        inputPath: String,
        outputPath: String,
        bitrate: Double = 23.85
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:a", "libvo_amrwbenc",
            "-b:a", "\(bitrate)k",
            "-ar", "16000",
            "-ac", "1",
            "-y", outputPath,
        ]
    }

    // MARK: - DTS:X IMAX Enhanced

    /// Build FFmpeg arguments for DTS:X passthrough with IMAX metadata.
    ///
    /// DTS:X IMAX Enhanced requires passthrough since FFmpeg cannot encode
    /// object-based DTS:X. The IMAX metadata is preserved via stream copy.
    ///
    /// - Parameters:
    ///   - inputPath: Source file with DTS:X IMAX audio.
    ///   - outputPath: Output file.
    /// - Returns: FFmpeg argument array.
    public static func buildDTSXPassthroughArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:a", "copy",
            "-c:v", "copy",
            "-y", outputPath,
        ]
    }

    // MARK: - Speex

    /// Build FFmpeg arguments for Speex voice encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source audio file.
    ///   - outputPath: Output .ogg file.
    ///   - bitrate: Bitrate in kbps.
    ///   - quality: Quality level (0-10).
    /// - Returns: FFmpeg argument array.
    public static func buildSpeexEncodeArguments(
        inputPath: String,
        outputPath: String,
        bitrate: Int = 32,
        quality: Int = 5
    ) -> [String] {
        return [
            "-i", inputPath,
            "-c:a", "libspeex",
            "-b:a", "\(bitrate)k",
            "-compression_level", "\(min(10, max(0, quality)))",
            "-ar", "16000",
            "-ac", "1",
            "-y", outputPath,
        ]
    }

    // MARK: - Detection

    /// Check if an audio stream uses an extended codec that requires special handling.
    ///
    /// - Parameter codecName: FFmpeg codec name from probe.
    /// - Returns: The extended codec type if recognized.
    public static func detectExtendedCodec(_ codecName: String) -> ExtendedAudioCodecType? {
        let lower = codecName.lowercased()
        if lower.contains("wma") && lower.contains("pro") { return .wmaPro }
        if lower.contains("wma") && lower.contains("lossless") { return .wmaLossless }
        if lower == "amrnb" || lower == "amr_nb" { return .amrNB }
        if lower == "amrwb" || lower == "amr_wb" { return .amrWB }
        if lower == "speex" { return .speex }
        if lower.contains("atrac") { return .atrac }
        return nil
    }
}
