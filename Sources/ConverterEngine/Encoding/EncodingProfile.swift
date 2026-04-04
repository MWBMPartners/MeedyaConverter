// ============================================================================
// MeedyaConverter — EncodingProfile
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodingProfile

/// A reusable encoding preset that defines video, audio, and container settings.
///
/// Profiles can be built-in (shipped with the app), user-created, or imported.
/// They are serialised as JSON for persistence and sharing.
public struct EncodingProfile: Identifiable, Codable, Sendable, Hashable {

    // MARK: - Identity

    /// Unique identifier for this profile.
    public let id: UUID

    /// Human-readable name for this profile (e.g., "Web Standard", "4K HDR Master").
    public var name: String

    /// Description of what this profile is optimised for.
    public var description: String

    /// Category for UI grouping (e.g., "Quick Start", "Streaming", "Disc", "Custom").
    public var category: ProfileCategory

    /// Whether this is a built-in (non-deletable) profile.
    public var isBuiltIn: Bool

    // MARK: - Video Settings

    /// The video codec for encoding.
    public var videoCodec: VideoCodec?

    /// Whether to passthrough video without re-encoding.
    public var videoPassthrough: Bool

    /// CRF value for quality-based VBR encoding (software encoders).
    public var videoCRF: Int?

    /// QP value for hardware encoders.
    public var videoQP: Int?

    /// Target video bitrate in bits per second (for CBR/CVBR modes).
    public var videoBitrate: Int?

    /// Maximum video bitrate for CVBR mode.
    public var videoMaxBitrate: Int?

    /// Video encoder preset (e.g., "medium", "slow").
    public var videoPreset: String?

    /// Video encoder tune (e.g., "film", "animation").
    public var videoTune: String?

    /// Output resolution width. Nil means match source.
    public var outputWidth: Int?

    /// Output resolution height. Nil means match source.
    public var outputHeight: Int?

    /// Output frame rate. Nil means match source.
    public var outputFrameRate: Double?

    /// Pixel format (e.g., "yuv420p", "yuv420p10le").
    public var pixelFormat: String?

    /// Whether to use hardware encoding when available.
    public var useHardwareEncoding: Bool

    /// Number of encoding passes (1 or 2).
    public var encodingPasses: Int

    /// Whether to preserve HDR metadata when source is HDR.
    public var preserveHDR: Bool

    /// Whether to apply HDR-to-SDR tone mapping when source is HDR.
    /// When true, the zscale/tonemap filter chain is applied automatically.
    public var toneMapToSDR: Bool

    /// Tone mapping algorithm (hable, reinhard, mobius, bt2390, clip).
    public var toneMapAlgorithm: String?

    /// Whether to convert PQ (SMPTE ST 2084) HDR to HLG (ARIB STD-B67) HDR.
    /// This preserves HDR but changes the transfer function for broadcast compatibility.
    /// When true, a zscale filter chain converts PQ→HLG while maintaining BT.2020 colour.
    public var convertPQToHLG: Bool

    /// Whether to use external hlg-tools (pq2hlg) for PQ→HLG conversion.
    /// When true and hlg-tools is available, uses the external binary for higher quality.
    /// When false or hlg-tools unavailable, falls back to FFmpeg zscale filter.
    public var useHlgTools: Bool

    /// Peak brightness of the source in nits for tone mapping. Nil means auto-detect.
    public var toneMapPeakNits: Double?

    /// Desaturation strength for tone mapping (0.0 = none, 1.0 = full).
    public var toneMapDesaturation: Double?

    /// Whether to convert PQ (HDR10) to Dolby Vision Profile 8.4 + HLG.
    /// Chains PQ→HLG conversion with DV RPU generation for three-tier playback:
    /// Dolby Vision → HLG → SDR fallback from a single stream.
    public var convertPQToDVHLG: Bool

    /// Display aspect ratio override (e.g., "16:9", "2.35:1").
    /// When set, applies -aspect to the output. When nil, preserves source aspect ratio.
    public var displayAspectRatio: String?

    // MARK: - Audio Settings

    /// The audio codec for encoding.
    public var audioCodec: AudioCodec?

    /// Whether to passthrough audio without re-encoding.
    public var audioPassthrough: Bool

    /// Audio bitrate in bits per second.
    public var audioBitrate: Int?

    /// Audio sample rate in Hz. Nil means match source.
    public var audioSampleRate: Int?

    /// Number of audio channels. Nil means match source.
    public var audioChannels: Int?

    /// Loudness normalization standard. Nil means no normalization.
    public var loudnessNormalization: String?

    /// Whether to apply peak limiting to the audio output.
    public var applyPeakLimiter: Bool

    // MARK: - Subtitle Settings

    /// Whether to passthrough subtitles.
    public var subtitlePassthrough: Bool

    // MARK: - Container

    /// The output container format.
    public var containerFormat: ContainerFormat

    // MARK: - Streaming (CVBR settings for HLS/DASH)

    /// Keyframe interval in seconds (for adaptive streaming).
    public var keyframeIntervalSeconds: Double?

    /// VBV buffer size in bits (for CVBR mode).
    public var videoBufferSize: Int?

    // MARK: - Initialiser

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        category: ProfileCategory = .custom,
        isBuiltIn: Bool = false,
        videoCodec: VideoCodec? = .h265,
        videoPassthrough: Bool = false,
        videoCRF: Int? = 22,
        videoQP: Int? = nil,
        videoBitrate: Int? = nil,
        videoMaxBitrate: Int? = nil,
        videoPreset: String? = "medium",
        videoTune: String? = nil,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil,
        outputFrameRate: Double? = nil,
        pixelFormat: String? = nil,
        useHardwareEncoding: Bool = false,
        encodingPasses: Int = 1,
        preserveHDR: Bool = true,
        toneMapToSDR: Bool = false,
        toneMapAlgorithm: String? = nil,
        convertPQToHLG: Bool = false,
        useHlgTools: Bool = false,
        toneMapPeakNits: Double? = nil,
        toneMapDesaturation: Double? = nil,
        convertPQToDVHLG: Bool = false,
        displayAspectRatio: String? = nil,
        audioCodec: AudioCodec? = .aacLC,
        audioPassthrough: Bool = false,
        audioBitrate: Int? = 160_000,
        audioSampleRate: Int? = nil,
        audioChannels: Int? = nil,
        loudnessNormalization: String? = nil,
        applyPeakLimiter: Bool = false,
        subtitlePassthrough: Bool = true,
        containerFormat: ContainerFormat = .mkv,
        keyframeIntervalSeconds: Double? = nil,
        videoBufferSize: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.videoCodec = videoCodec
        self.videoPassthrough = videoPassthrough
        self.videoCRF = videoCRF
        self.videoQP = videoQP
        self.videoBitrate = videoBitrate
        self.videoMaxBitrate = videoMaxBitrate
        self.videoPreset = videoPreset
        self.videoTune = videoTune
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.outputFrameRate = outputFrameRate
        self.pixelFormat = pixelFormat
        self.useHardwareEncoding = useHardwareEncoding
        self.encodingPasses = encodingPasses
        self.preserveHDR = preserveHDR
        self.toneMapToSDR = toneMapToSDR
        self.toneMapAlgorithm = toneMapAlgorithm
        self.convertPQToHLG = convertPQToHLG
        self.useHlgTools = useHlgTools
        self.toneMapPeakNits = toneMapPeakNits
        self.toneMapDesaturation = toneMapDesaturation
        self.convertPQToDVHLG = convertPQToDVHLG
        self.displayAspectRatio = displayAspectRatio
        self.audioCodec = audioCodec
        self.audioPassthrough = audioPassthrough
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.loudnessNormalization = loudnessNormalization
        self.applyPeakLimiter = applyPeakLimiter
        self.subtitlePassthrough = subtitlePassthrough
        self.containerFormat = containerFormat
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
        self.videoBufferSize = videoBufferSize
    }

    // MARK: - Computed Properties

    /// The preferred file extension for the output container format.
    public var preferredExtension: String {
        containerFormat.fileExtensions.first ?? "mkv"
    }

    // MARK: - Argument Builder Conversion

    /// Convert this profile into an FFmpegArgumentBuilder with the settings applied.
    ///
    /// - Parameters:
    ///   - inputURL: The source file URL.
    ///   - outputURL: The destination file URL.
    /// - Returns: A configured FFmpegArgumentBuilder ready to build() arguments.
    public func toArgumentBuilder(inputURL: URL, outputURL: URL) -> FFmpegArgumentBuilder {
        var builder = FFmpegArgumentBuilder()
        builder.inputURL = inputURL
        builder.outputURL = outputURL

        // Video
        builder.videoPassthrough = videoPassthrough
        builder.videoCodec = videoPassthrough ? nil : videoCodec
        builder.videoCRF = videoCRF
        builder.videoQP = videoQP
        builder.videoBitrate = videoBitrate
        builder.videoMaxBitrate = videoMaxBitrate
        builder.videoBufferSize = videoBufferSize
        builder.videoWidth = outputWidth
        builder.videoHeight = outputHeight
        builder.videoFrameRate = outputFrameRate
        builder.pixelFormat = pixelFormat
        builder.videoPreset = videoPreset
        builder.videoTune = videoTune
        builder.useHardwareEncoding = useHardwareEncoding
        builder.encodingPasses = encodingPasses
        builder.keyframeInterval = keyframeIntervalSeconds

        // Audio
        builder.audioPassthrough = audioPassthrough
        builder.audioCodec = audioPassthrough ? nil : audioCodec
        builder.audioBitrate = audioBitrate
        builder.audioSampleRate = audioSampleRate
        builder.audioChannels = audioChannels

        // Tone mapping
        builder.toneMap = toneMapToSDR
        if let algorithm = toneMapAlgorithm,
           let tmAlgo = FFmpegArgumentBuilder.ToneMapAlgorithm(rawValue: algorithm) {
            builder.toneMapAlgorithm = tmAlgo
        }
        builder.toneMapPeakNits = toneMapPeakNits
        builder.toneMapDesaturation = toneMapDesaturation

        // Audio normalization (Phase 5)
        if let normStd = loudnessNormalization,
           let standard = LoudnessStandard(rawValue: normStd) {
            let chain = AudioProcessor.buildProcessingChain(
                normalize: true,
                standard: standard,
                limit: applyPeakLimiter
            )
            builder.audioFilterChain = chain
        } else if applyPeakLimiter {
            builder.audioFilterChain = AudioProcessor.buildPeakLimiterFilter()
        }

        // PQ → HLG conversion
        builder.convertPQToHLG = convertPQToHLG

        // Display aspect ratio
        builder.displayAspectRatio = displayAspectRatio

        // Subtitles
        builder.subtitlePassthrough = subtitlePassthrough

        // Container
        builder.containerFormat = containerFormat

        return builder
    }
}

// MARK: - ProfileCategory

/// Categories for grouping encoding profiles in the UI.
public enum ProfileCategory: String, Codable, Sendable, CaseIterable {
    /// Quick-start profiles for common use cases.
    case quickStart = "quick_start"

    /// Profiles optimised for adaptive streaming (HLS/DASH).
    case streaming

    /// Profiles for optical disc authoring (DVD, Blu-ray).
    case disc

    /// Profiles for archival/preservation.
    case archival

    /// User-created custom profiles.
    case custom

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .quickStart: return "Quick Start"
        case .streaming: return "Streaming"
        case .disc: return "Disc Authoring"
        case .archival: return "Archival"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Built-In Profiles

extension EncodingProfile {

    /// All built-in profiles shipped with MeedyaConverter.
    public static let builtInProfiles: [EncodingProfile] = [
        // Quick Start
        .webStandard,
        .webHighQuality,
        .webNextGen,
        .quickConvert,
        .audioExtract,

        // HDR-aware
        .fourKHDRMaster,
        .fourKHDRCompact,
        .hdrToSDR,
        .pqToHLG,
        .pqToDVHLG,

        // Passthrough / Remux
        .remuxToMKV,
        .remuxToMP4,

        // Streaming (CVBR)
        .streaming1080p,
        .streaming4K,

        // Professional
        .proresProxy,
        .proresHQ,
        .dnxhrSQ,

        // Disc Authoring
        .blurayCompatible,
        .dvdCompatible,

        // Archival
        .archiveLossless,
        .archiveProRes4444,

        // Hardware Accelerated
        .hardwareH264,
        .hardwareH265,
    ]

    // MARK: - Quick Start Profiles

    /// Web Standard — H.264/AAC in MP4, maximum compatibility.
    public static let webStandard = EncodingProfile(
        name: "Web Standard",
        description: "H.264 + AAC in MP4 — maximum compatibility for web playback",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 20,
        videoPreset: "medium",
        audioCodec: .aacLC,
        audioBitrate: 160_000,
        containerFormat: .mp4
    )

    /// Web High Quality — H.265/AAC in MP4, better quality at smaller size.
    public static let webHighQuality = EncodingProfile(
        name: "Web High Quality",
        description: "H.265 + AAC in MP4 — better quality, smaller files",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 22,
        videoPreset: "medium",
        audioCodec: .aacLC,
        audioBitrate: 192_000,
        containerFormat: .mp4
    )

    /// Web Next-Gen — AV1/Opus in WebM, best compression efficiency.
    public static let webNextGen = EncodingProfile(
        name: "Web Next-Gen",
        description: "AV1 + Opus in WebM — best efficiency for modern browsers",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .av1,
        videoCRF: 30,
        videoPreset: "6", // SVT-AV1 preset
        audioCodec: .opus,
        audioBitrate: 128_000,
        containerFormat: .webm
    )

    /// Quick Convert — fast H.264 at reasonable quality.
    public static let quickConvert = EncodingProfile(
        name: "Quick Convert",
        description: "Fast H.264 encode — good enough quality, maximum speed",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 23,
        videoPreset: "fast",
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// Audio Extract — extract and convert audio to FLAC.
    public static let audioExtract = EncodingProfile(
        name: "Audio Extract (FLAC)",
        description: "Extract audio to lossless FLAC — no video",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: nil,
        videoPassthrough: false,
        videoCRF: nil,
        videoPreset: nil,
        audioCodec: .flac,
        audioBitrate: nil,
        containerFormat: .mka
    )

    // MARK: - HDR-Aware Profiles

    /// 4K HDR Master — H.265/E-AC-3 in MKV, high-quality archive with HDR.
    public static let fourKHDRMaster = EncodingProfile(
        name: "4K HDR Master",
        description: "H.265 HDR + E-AC-3 7.1 in MKV — high-quality archive",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "slow",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .eac3,
        audioBitrate: 640_000,
        audioChannels: 8,
        containerFormat: .mkv
    )

    /// 4K HDR Compact — H.265 HDR with smaller file size, good for Plex/Jellyfin.
    public static let fourKHDRCompact = EncodingProfile(
        name: "4K HDR Compact",
        description: "H.265 HDR + AAC in MKV — balanced size for media servers",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 24,
        videoPreset: "medium",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .aacLC,
        audioBitrate: 256_000,
        audioChannels: 6,
        containerFormat: .mkv
    )

    /// HDR → SDR — tone-map HDR content to SDR with correct colour conversion.
    public static let hdrToSDR = EncodingProfile(
        name: "HDR → SDR (Tone-Map)",
        description: "Convert HDR to SDR with Hable tone mapping — H.265 + AAC in MP4",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 20,
        videoPreset: "medium",
        pixelFormat: "yuv420p",
        preserveHDR: false,
        toneMapToSDR: true,
        toneMapAlgorithm: "hable",
        audioCodec: .aacLC,
        audioBitrate: 192_000,
        containerFormat: .mp4
    )

    /// PQ → HLG — convert PQ (HDR10) transfer to HLG for broadcast compatibility.
    public static let pqToHLG = EncodingProfile(
        name: "PQ → HLG (Broadcast)",
        description: "Convert PQ/HDR10 to HLG transfer — H.265 10-bit in MKV for broadcast delivery",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "medium",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        convertPQToHLG: true,
        audioCodec: .eac3,
        audioBitrate: 448_000,
        audioChannels: 6,
        containerFormat: .mkv
    )

    /// PQ → DV+HLG — convert PQ to Dolby Vision Profile 8.4 + HLG for maximum compatibility.
    /// Three-tier playback: Dolby Vision → HLG → SDR from a single stream.
    public static let pqToDVHLG = EncodingProfile(
        name: "PQ → DV+HLG (Max Compat)",
        description: "Convert PQ/HDR10 to DV Profile 8.4 + HLG — three-tier playback in MKV",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "medium",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        convertPQToHLG: true,
        convertPQToDVHLG: true,
        audioCodec: .eac3,
        audioBitrate: 640_000,
        audioChannels: 8,
        containerFormat: .mkv
    )

    // MARK: - Passthrough / Remux Profiles

    /// Remux to MKV — copy all streams without re-encoding.
    public static let remuxToMKV = EncodingProfile(
        name: "Remux to MKV",
        description: "Copy all streams to MKV container — no re-encoding",
        category: .quickStart,
        isBuiltIn: true,
        videoPassthrough: true,
        videoCRF: nil,
        videoPreset: nil,
        audioPassthrough: true,
        audioBitrate: nil,
        subtitlePassthrough: true,
        containerFormat: .mkv
    )

    /// Remux to MP4 — copy compatible streams to MP4 container.
    public static let remuxToMP4 = EncodingProfile(
        name: "Remux to MP4",
        description: "Copy streams to MP4 container — no re-encoding",
        category: .quickStart,
        isBuiltIn: true,
        videoPassthrough: true,
        videoCRF: nil,
        videoPreset: nil,
        audioPassthrough: true,
        audioBitrate: nil,
        subtitlePassthrough: false,
        containerFormat: .mp4
    )

    // MARK: - Streaming Profiles (CVBR)

    /// 1080p Streaming — CVBR H.264 for adaptive streaming (HLS/DASH).
    public static let streaming1080p = EncodingProfile(
        name: "1080p Streaming (CVBR)",
        description: "H.264 CVBR + AAC in MP4 — optimised for HLS/DASH delivery",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: nil,
        videoBitrate: 5_000_000,
        videoMaxBitrate: 7_500_000,
        videoPreset: "medium",
        outputWidth: 1920,
        outputHeight: 1080,
        containerFormat: .mp4,
        keyframeIntervalSeconds: 2.0,
        videoBufferSize: 10_000_000
    )

    /// 4K Streaming — CVBR H.265 for high-end adaptive streaming.
    public static let streaming4K = EncodingProfile(
        name: "4K Streaming (CVBR)",
        description: "H.265 CVBR + AAC in MP4 — 4K adaptive streaming delivery",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: nil,
        videoBitrate: 12_000_000,
        videoMaxBitrate: 18_000_000,
        videoPreset: "medium",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .aacLC,
        audioBitrate: 256_000,
        containerFormat: .mp4,
        keyframeIntervalSeconds: 2.0,
        videoBufferSize: 24_000_000
    )

    // MARK: - Professional Profiles

    /// ProRes Proxy — lightweight Apple ProRes for offline editing.
    public static let proresProxy = EncodingProfile(
        name: "ProRes Proxy",
        description: "Apple ProRes Proxy in MOV — lightweight for offline editing",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .prores,
        videoCRF: nil,
        videoPreset: "proxy",
        audioCodec: .pcm,
        audioBitrate: nil,
        containerFormat: .mov
    )

    /// ProRes HQ — high-quality Apple ProRes for mastering.
    public static let proresHQ = EncodingProfile(
        name: "ProRes HQ",
        description: "Apple ProRes HQ in MOV — high-quality mastering codec",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .prores,
        videoCRF: nil,
        videoPreset: "hq",
        audioCodec: .pcm,
        audioBitrate: nil,
        containerFormat: .mov
    )

    /// DNxHR SQ — Avid DNxHR Standard Quality for editing.
    public static let dnxhrSQ = EncodingProfile(
        name: "DNxHR SQ",
        description: "Avid DNxHR Standard Quality in MXF — for Avid/Resolve editing",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .dnxhr,
        videoCRF: nil,
        videoPreset: nil,
        audioCodec: .pcm,
        audioBitrate: nil,
        containerFormat: .mxf
    )

    // MARK: - Disc Authoring Profiles

    /// Blu-ray Compatible — H.264 high profile with AC-3 audio.
    public static let blurayCompatible = EncodingProfile(
        name: "Blu-ray Compatible",
        description: "H.264 High Profile + AC-3 in MPEG-TS — Blu-ray authoring",
        category: .disc,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: nil,
        videoBitrate: 25_000_000,
        videoMaxBitrate: 40_000_000,
        videoPreset: "slow",
        audioCodec: .ac3,
        audioBitrate: 640_000,
        audioChannels: 6,
        containerFormat: .mpegTS,
        videoBufferSize: 30_000_000
    )

    /// DVD Compatible — MPEG-2 with AC-3 audio.
    public static let dvdCompatible = EncodingProfile(
        name: "DVD Compatible",
        description: "MPEG-2 + AC-3 in MPEG-PS — DVD authoring",
        category: .disc,
        isBuiltIn: true,
        videoCodec: .mpeg2,
        videoCRF: nil,
        videoBitrate: 6_000_000,
        videoMaxBitrate: 9_800_000,
        videoPreset: nil,
        outputWidth: 720,
        outputHeight: 480,
        audioCodec: .ac3,
        audioBitrate: 448_000,
        audioChannels: 6,
        containerFormat: .mpegPS
    )

    // MARK: - Archival Profiles

    /// Archive Lossless — FFV1/FLAC in MKV for archival preservation.
    public static let archiveLossless = EncodingProfile(
        name: "Archive (Lossless)",
        description: "FFV1 + FLAC in MKV — lossless archival preservation",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .ffv1,
        videoCRF: nil,
        videoPreset: nil,
        audioCodec: .flac,
        audioBitrate: nil,
        containerFormat: .mkv
    )

    /// Archive ProRes 4444 — lossless-quality Apple ProRes with alpha channel support.
    public static let archiveProRes4444 = EncodingProfile(
        name: "Archive (ProRes 4444)",
        description: "ProRes 4444 + PCM in MOV — near-lossless with alpha channel",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .prores,
        videoCRF: nil,
        videoPreset: "4444",
        pixelFormat: "yuva444p10le",
        audioCodec: .pcm,
        audioBitrate: nil,
        containerFormat: .mov
    )

    // MARK: - Hardware Accelerated Profiles

    /// Hardware H.264 — VideoToolbox-accelerated H.264 for fast encoding.
    public static let hardwareH264 = EncodingProfile(
        name: "Hardware H.264 (Fast)",
        description: "VideoToolbox H.264 + AAC in MP4 — hardware-accelerated fast encode",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: nil,
        videoQP: 28,
        useHardwareEncoding: true,
        audioCodec: .aacLC,
        audioBitrate: 160_000,
        containerFormat: .mp4
    )

    /// Hardware H.265 — VideoToolbox-accelerated H.265 for fast HDR encoding.
    public static let hardwareH265 = EncodingProfile(
        name: "Hardware H.265 (Fast)",
        description: "VideoToolbox H.265 + AAC in MP4 — hardware-accelerated with HDR",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: nil,
        videoQP: 30,
        pixelFormat: "yuv420p10le",
        useHardwareEncoding: true,
        preserveHDR: true,
        audioCodec: .aacLC,
        audioBitrate: 192_000,
        containerFormat: .mp4
    )
}

// MARK: - EncodingProfileStore

/// Manages the collection of encoding profiles (built-in + user-created).
///
/// Profiles are persisted as JSON in the app's support directory.
/// The store provides CRUD operations and JSON import/export.
public final class EncodingProfileStore: @unchecked Sendable {

    // MARK: - Properties

    /// All available profiles (built-in + user-created).
    public private(set) var profiles: [EncodingProfile]

    /// The file URL where user profiles are persisted.
    private let storageURL: URL

    /// Serial lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create a profile store with the given storage location.
    ///
    /// - Parameter storageDirectory: Directory where user profiles JSON is saved.
    ///   Defaults to Application Support/MeedyaConverter/Profiles/.
    public init(storageDirectory: URL? = nil) {
        let defaultDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("Profiles")

        let dir = storageDirectory ?? defaultDir
        self.storageURL = dir.appendingPathComponent("user_profiles.json")

        // Start with built-in profiles
        self.profiles = EncodingProfile.builtInProfiles

        // Load user profiles from disk
        loadUserProfiles()
    }

    // MARK: - CRUD Operations

    /// Add a new user-created profile.
    public func addProfile(_ profile: EncodingProfile) {
        lock.lock()
        defer { lock.unlock() }
        profiles.append(profile)
        saveUserProfiles()
    }

    /// Update an existing profile by ID.
    public func updateProfile(_ profile: EncodingProfile) {
        lock.lock()
        defer { lock.unlock() }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveUserProfiles()
        }
    }

    /// Delete a profile by ID. Built-in profiles cannot be deleted.
    public func deleteProfile(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        profiles.removeAll { $0.id == id && !$0.isBuiltIn }
        saveUserProfiles()
    }

    /// Get a profile by its name.
    public func profile(named name: String) -> EncodingProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Get a profile by its ID.
    public func profile(id: UUID) -> EncodingProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles.first { $0.id == id }
    }

    /// All profiles in a specific category.
    public func profiles(in category: ProfileCategory) -> [EncodingProfile] {
        lock.lock()
        defer { lock.unlock() }
        return profiles.filter { $0.category == category }
    }

    // MARK: - Import/Export

    /// Export a profile to JSON data for sharing.
    public func exportProfile(_ profile: EncodingProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    /// Import a profile from JSON data.
    public func importProfile(from data: Data) throws -> EncodingProfile {
        let decoder = JSONDecoder()
        var profile = try decoder.decode(EncodingProfile.self, from: data)
        // Imported profiles are never built-in
        profile = EncodingProfile(
            id: UUID(), // Generate new ID to avoid conflicts
            name: profile.name,
            description: profile.description,
            category: .custom,
            isBuiltIn: false,
            videoCodec: profile.videoCodec,
            videoPassthrough: profile.videoPassthrough,
            videoCRF: profile.videoCRF,
            videoQP: profile.videoQP,
            videoBitrate: profile.videoBitrate,
            videoMaxBitrate: profile.videoMaxBitrate,
            videoPreset: profile.videoPreset,
            videoTune: profile.videoTune,
            outputWidth: profile.outputWidth,
            outputHeight: profile.outputHeight,
            outputFrameRate: profile.outputFrameRate,
            pixelFormat: profile.pixelFormat,
            useHardwareEncoding: profile.useHardwareEncoding,
            encodingPasses: profile.encodingPasses,
            preserveHDR: profile.preserveHDR,
            toneMapToSDR: profile.toneMapToSDR,
            toneMapAlgorithm: profile.toneMapAlgorithm,
            convertPQToHLG: profile.convertPQToHLG,
            useHlgTools: profile.useHlgTools,
            toneMapPeakNits: profile.toneMapPeakNits,
            toneMapDesaturation: profile.toneMapDesaturation,
            convertPQToDVHLG: profile.convertPQToDVHLG,
            displayAspectRatio: profile.displayAspectRatio,
            audioCodec: profile.audioCodec,
            audioPassthrough: profile.audioPassthrough,
            audioBitrate: profile.audioBitrate,
            audioSampleRate: profile.audioSampleRate,
            audioChannels: profile.audioChannels,
            loudnessNormalization: profile.loudnessNormalization,
            applyPeakLimiter: profile.applyPeakLimiter,
            subtitlePassthrough: profile.subtitlePassthrough,
            containerFormat: profile.containerFormat,
            keyframeIntervalSeconds: profile.keyframeIntervalSeconds,
            videoBufferSize: profile.videoBufferSize
        )
        addProfile(profile)
        return profile
    }

    // MARK: - Persistence

    /// Load user-created profiles from disk.
    private func loadUserProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let userProfiles = try decoder.decode([EncodingProfile].self, from: data)
            profiles.append(contentsOf: userProfiles)
        } catch {
            // Log but don't crash — user can re-create profiles
            print("Warning: Could not load user profiles: \(error.localizedDescription)")
        }
    }

    /// Save user-created profiles to disk.
    private func saveUserProfiles() {
        let userProfiles = profiles.filter { !$0.isBuiltIn }

        do {
            // Ensure directory exists
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(userProfiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Warning: Could not save user profiles: \(error.localizedDescription)")
        }
    }
}
