// ============================================================================
// MeedyaConverter — AdditionalEncodingProfiles
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - Additional Built-in Profiles

/// Extended set of encoding profiles covering all resolution/codec/HDR
/// combinations for common workflows.
///
/// Phase 3 / Issue #241
public extension EncodingProfile {

    // MARK: - AV1 Profiles

    /// AV1 1080p — efficient open codec for web delivery.
    static let av1_1080p = EncodingProfile(
        name: "AV1 1080p",
        description: "AV1 CRF + Opus in WebM — efficient open codec for web delivery",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .av1,
        videoCRF: 30,
        videoPreset: "6",
        outputWidth: 1920,
        outputHeight: 1080,
        audioCodec: .opus,
        audioBitrate: 128_000,
        containerFormat: .webm
    )

    /// AV1 4K — high-efficiency 4K encoding.
    static let av1_4K = EncodingProfile(
        name: "AV1 4K",
        description: "AV1 CRF + Opus in MKV — 4K high-efficiency encoding",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .av1,
        videoCRF: 28,
        videoPreset: "6",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .opus,
        audioBitrate: 192_000,
        containerFormat: .mkv
    )

    /// AV1 4K HDR — AV1 with HDR10 metadata for streaming.
    static let av1_4KHDR = EncodingProfile(
        name: "AV1 4K HDR",
        description: "AV1 CRF + Opus in MKV — 4K HDR streaming with open codec",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .av1,
        videoCRF: 26,
        videoPreset: "5",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .opus,
        audioBitrate: 192_000,
        containerFormat: .mkv
    )

    // MARK: - H.265 Extended Profiles

    /// H.265 720p — balanced quality for smaller screens.
    static let h265_720p = EncodingProfile(
        name: "H.265 720p",
        description: "H.265 CRF + AAC in MP4 — balanced 720p for mobile/tablet",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 23,
        videoPreset: "medium",
        outputWidth: 1280,
        outputHeight: 720,
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// H.265 1080p High Quality — slower encode for better compression.
    static let h265_1080pHQ = EncodingProfile(
        name: "H.265 1080p HQ",
        description: "H.265 slow preset + AAC in MKV — high-quality 1080p",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "slow",
        outputWidth: 1920,
        outputHeight: 1080,
        audioCodec: .aacLC,
        audioBitrate: 192_000,
        containerFormat: .mkv
    )

    /// H.265 4K HDR HLG — for HLG broadcast workflows.
    static let h265_4K_HLG = EncodingProfile(
        name: "H.265 4K HLG",
        description: "H.265 + AAC in MKV — 4K HLG broadcast-compatible",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 20,
        videoPreset: "medium",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .aacLC,
        audioBitrate: 256_000,
        containerFormat: .mkv
    )

    /// H.265 8K — ultra-high resolution encoding.
    static let h265_8K = EncodingProfile(
        name: "H.265 8K",
        description: "H.265 + AAC in MKV — 8K ultra-high resolution",
        category: .archival,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 22,
        videoPreset: "medium",
        outputWidth: 7680,
        outputHeight: 4320,
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .aacLC,
        audioBitrate: 320_000,
        containerFormat: .mkv
    )

    // MARK: - H.264 Extended Profiles

    /// H.264 480p — SD quality for legacy/compatibility.
    static let h264_480p = EncodingProfile(
        name: "H.264 480p",
        description: "H.264 + AAC in MP4 — SD 480p for maximum compatibility",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 23,
        videoPreset: "medium",
        outputWidth: 854,
        outputHeight: 480,
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// H.264 720p — HD for web and mobile.
    static let h264_720p = EncodingProfile(
        name: "H.264 720p",
        description: "H.264 + AAC in MP4 — HD 720p for web and mobile",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 22,
        videoPreset: "medium",
        outputWidth: 1280,
        outputHeight: 720,
        audioCodec: .aacLC,
        audioBitrate: 160_000,
        containerFormat: .mp4
    )

    // MARK: - VP9 Profiles

    /// VP9 1080p — open codec for web streaming.
    static let vp9_1080p = EncodingProfile(
        name: "VP9 1080p",
        description: "VP9 CRF + Opus in WebM — open codec for web streaming",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .vp9,
        videoCRF: 31,
        videoPreset: "good",
        outputWidth: 1920,
        outputHeight: 1080,
        audioCodec: .opus,
        audioBitrate: 128_000,
        containerFormat: .webm
    )

    /// VP9 4K — high-resolution open codec.
    static let vp9_4K = EncodingProfile(
        name: "VP9 4K",
        description: "VP9 CRF + Opus in WebM — 4K open codec encoding",
        category: .streaming,
        isBuiltIn: true,
        videoCodec: .vp9,
        videoCRF: 28,
        videoPreset: "good",
        pixelFormat: "yuv420p10le",
        audioCodec: .opus,
        audioBitrate: 192_000,
        containerFormat: .webm
    )

    // MARK: - Surround Audio Profiles

    /// 1080p Surround — H.265 with EAC-3 5.1 surround.
    static let h265_1080p_surround = EncodingProfile(
        name: "H.265 1080p Surround",
        description: "H.265 + EAC-3 5.1 in MKV — 1080p with surround audio",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 20,
        videoPreset: "medium",
        outputWidth: 1920,
        outputHeight: 1080,
        audioCodec: .eac3,
        audioBitrate: 640_000,
        audioChannels: 6,
        containerFormat: .mkv
    )

    /// 4K Dolby — H.265 with EAC-3 Atmos-compatible audio.
    static let h265_4K_dolby = EncodingProfile(
        name: "4K Dolby (H.265 + EAC-3)",
        description: "H.265 HDR + EAC-3 Atmos in MKV — premium home theatre",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h265,
        videoCRF: 18,
        videoPreset: "slow",
        pixelFormat: "yuv420p10le",
        preserveHDR: true,
        audioCodec: .eac3,
        audioBitrate: 768_000,
        audioChannels: 8,
        containerFormat: .mkv
    )

    // MARK: - Audio-Only Profiles

    /// High Quality MP3 — 320kbps CBR.
    static let audioMP3_HQ = EncodingProfile(
        name: "MP3 320kbps",
        description: "High quality MP3 at 320kbps CBR",
        category: .quickStart,
        isBuiltIn: true,
        videoPassthrough: true,
        audioCodec: .mp3,
        audioBitrate: 320_000,
        containerFormat: .mp4
    )

    /// Opus Voice — optimised for speech/podcasts.
    static let audioOpus_voice = EncodingProfile(
        name: "Opus Voice (64kbps)",
        description: "Opus at 64kbps — optimised for speech and podcasts",
        category: .quickStart,
        isBuiltIn: true,
        videoPassthrough: true,
        audioCodec: .opus,
        audioBitrate: 64_000,
        containerFormat: .webm
    )

    /// FLAC Lossless — lossless audio archival.
    static let audioFLAC = EncodingProfile(
        name: "FLAC Lossless",
        description: "FLAC lossless audio — bit-perfect archival",
        category: .archival,
        isBuiltIn: true,
        videoPassthrough: true,
        audioCodec: .flac,
        audioBitrate: nil,
        containerFormat: .mkv
    )

    // MARK: - Social Media Profiles

    /// Twitter/X — H.264 720p for social media.
    static let socialTwitter = EncodingProfile(
        name: "Twitter/X (720p)",
        description: "H.264 720p + AAC in MP4 — optimised for Twitter/X upload",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 23,
        videoPreset: "fast",
        outputWidth: 1280,
        outputHeight: 720,
        outputFrameRate: 30.0,
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// Instagram/TikTok — H.264 1080p vertical.
    static let socialInstagram = EncodingProfile(
        name: "Instagram/TikTok (1080p)",
        description: "H.264 1080p + AAC in MP4 — optimised for Instagram/TikTok",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 22,
        videoPreset: "fast",
        outputWidth: 1080,
        outputHeight: 1920,
        outputFrameRate: 30.0,
        audioCodec: .aacLC,
        audioBitrate: 128_000,
        containerFormat: .mp4
    )

    /// YouTube — H.264 1080p optimised for YouTube processing.
    static let socialYouTube = EncodingProfile(
        name: "YouTube (1080p)",
        description: "H.264 1080p + AAC in MP4 — optimised for YouTube upload",
        category: .quickStart,
        isBuiltIn: true,
        videoCodec: .h264,
        videoCRF: 18,
        videoPreset: "slow",
        outputWidth: 1920,
        outputHeight: 1080,
        audioCodec: .aacLC,
        audioBitrate: 256_000,
        containerFormat: .mp4,
        keyframeIntervalSeconds: 2.0
    )

    // MARK: - All Extended Profiles

    /// All additional encoding profiles.
    static var allAdditionalProfiles: [EncodingProfile] {
        return [
            .av1_1080p, .av1_4K, .av1_4KHDR,
            .h265_720p, .h265_1080pHQ, .h265_4K_HLG, .h265_8K,
            .h264_480p, .h264_720p,
            .vp9_1080p, .vp9_4K,
            .h265_1080p_surround, .h265_4K_dolby,
            .audioMP3_HQ, .audioOpus_voice, .audioFLAC,
            .socialTwitter, .socialInstagram, .socialYouTube,
        ]
    }
}
