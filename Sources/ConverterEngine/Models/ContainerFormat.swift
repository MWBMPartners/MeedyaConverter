// ============================================================================
// MeedyaConverter — ContainerFormat
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// MARK: - ContainerFormat

/// Represents all supported media container formats.
///
/// Container formats define how audio, video, subtitle, and metadata streams
/// are multiplexed together into a single file. Each container has different
/// capabilities for which codecs, subtitle formats, and metadata it supports.
public enum ContainerFormat: String, Codable, Sendable, CaseIterable, Identifiable {

    // MARK: - MP4 Family

    /// MPEG-4 Part 14 — the most widely compatible container.
    /// Supports: H.264, H.265, AV1 video; AAC, AC-3, E-AC-3 audio; limited subtitles.
    case mp4

    /// Apple's variant of MP4, typically used for iTunes content.
    /// Identical codec support to MP4 but allows DRM and chapter metadata.
    case m4v

    /// Audio-only MP4 container, commonly used for AAC/ALAC audio files.
    case m4a

    /// Audiobook variant of MP4 with chapter and bookmark support.
    case m4b

    /// Protected MP4 container (DRM-wrapped audio/video).
    case m4p

    // MARK: - Matroska Family

    /// Matroska Video container — supports virtually all codecs and subtitle formats.
    /// The most flexible container for archival and multi-stream content.
    case mkv

    /// Matroska Audio — audio-only variant of MKV.
    case mka

    /// Matroska Subtitles — subtitle-only variant.
    case mks

    /// Matroska 3D — MKV variant optimised for stereoscopic 3D content.
    case mk3d

    // MARK: - Apple / QuickTime

    /// Apple QuickTime container. Supports ProRes, H.264, H.265, AAC, ALAC.
    /// Common in professional video editing workflows.
    case mov

    // MARK: - Web

    /// WebM container — designed for web video delivery.
    /// Supports VP8, VP9, AV1 video; Opus, Vorbis audio; WebVTT subtitles.
    case webm

    // MARK: - Broadcast / Transport

    /// MPEG Transport Stream — used in broadcast television, IPTV, and DVB recordings.
    /// Supports H.264, H.265, MPEG-2 video; AC-3, AAC, MP2 audio; Teletext, DVB-SUB subtitles.
    case mpegTS = "ts"

    /// MPEG Program Stream — used on DVDs.
    /// Supports MPEG-2 video; AC-3, DTS, LPCM audio.
    case mpegPS = "mpg"

    /// Material Exchange Format — professional broadcast and cinema container.
    /// Supports all professional codecs including JPEG 2000, DNxHR, ProRes.
    case mxf

    // MARK: - Legacy

    /// Audio Video Interleave — legacy Microsoft container. Still widely encountered.
    /// Supports most codecs but has limitations with modern features (no native subtitle support).
    case avi

    /// Flash Video — legacy Adobe container. Encountered in older web content.
    case flv

    /// 3GPP container — mobile video format used by older phones.
    case threeGP = "3gp"

    /// 3GPP2 container — variant of 3GP for CDMA networks.
    case threeG2 = "3g2"

    // MARK: - Xiph / Open Source

    /// Ogg container — Xiph.org's open container format.
    /// Supports Theora, VP8 video; Vorbis, Opus, FLAC audio.
    case ogg

    /// OGM (Ogg Media) — extended Ogg container with broader codec support.
    case ogm

    // MARK: - Adaptive Streaming

    /// HTTP Live Streaming — Apple's adaptive streaming format.
    /// Not a traditional container — produces .m3u8 playlists and .ts/.m4s segments.
    case hls

    /// Dynamic Adaptive Streaming over HTTP — ISO standard adaptive streaming.
    /// Not a traditional container — produces .mpd manifests and segment files.
    case dash

    // MARK: - Audio-Only Containers

    /// Audio Interchange File Format — Apple's uncompressed audio container.
    /// Supports PCM audio with various bit depths and sample rates.
    case aiff

    /// Core Audio Format — Apple's flexible audio container with no size limit.
    /// Supports all Apple audio codecs including AAC, ALAC, PCM.
    case caf

    /// Sony Wave64 — extended WAV format for files exceeding 4GB.
    case w64

    /// EBU RF64 — European Broadcasting Union's extended WAV for large files.
    case rf64

    // MARK: - Cinema

    /// Digital Cinema Package — JPEG 2000 video + PCM audio in MXF wrappers.
    /// Used for theatrical film distribution.
    case dcp

    // MARK: - Computed Properties

    /// A stable identifier for use with `Identifiable` conformance.
    public var id: String { rawValue }

    /// The common file extension(s) associated with this container.
    public var fileExtensions: [String] {
        switch self {
        case .mp4: return ["mp4"]
        case .m4v: return ["m4v"]
        case .m4a: return ["m4a"]
        case .m4b: return ["m4b"]
        case .m4p: return ["m4p"]
        case .mkv: return ["mkv"]
        case .mka: return ["mka"]
        case .mks: return ["mks"]
        case .mk3d: return ["mk3d"]
        case .mov: return ["mov"]
        case .webm: return ["webm"]
        case .mpegTS: return ["ts", "mts", "m2ts"]
        case .mpegPS: return ["mpg", "mpeg", "vob"]
        case .mxf: return ["mxf"]
        case .avi: return ["avi"]
        case .flv: return ["flv"]
        case .threeGP: return ["3gp"]
        case .threeG2: return ["3g2"]
        case .ogg: return ["ogg", "ogv"]
        case .ogm: return ["ogm"]
        case .hls: return ["m3u8"]
        case .dash: return ["mpd"]
        case .aiff: return ["aif", "aiff"]
        case .caf: return ["caf"]
        case .w64: return ["w64"]
        case .rf64: return ["rf64"]
        case .dcp: return ["dcp"]
        }
    }

    /// A human-readable display name for this container format.
    public var displayName: String {
        switch self {
        case .mp4: return "MP4 (MPEG-4 Part 14)"
        case .m4v: return "M4V (Apple Video)"
        case .m4a: return "M4A (MPEG-4 Audio)"
        case .m4b: return "M4B (Audiobook)"
        case .m4p: return "M4P (Protected)"
        case .mkv: return "MKV (Matroska Video)"
        case .mka: return "MKA (Matroska Audio)"
        case .mks: return "MKS (Matroska Subtitles)"
        case .mk3d: return "MK3D (Matroska 3D)"
        case .mov: return "MOV (QuickTime)"
        case .webm: return "WebM"
        case .mpegTS: return "MPEG-TS (Transport Stream)"
        case .mpegPS: return "MPEG-PS (Program Stream)"
        case .mxf: return "MXF (Material Exchange)"
        case .avi: return "AVI"
        case .flv: return "FLV (Flash Video)"
        case .threeGP: return "3GP"
        case .threeG2: return "3G2"
        case .ogg: return "OGG"
        case .ogm: return "OGM"
        case .hls: return "HLS (HTTP Live Streaming)"
        case .dash: return "DASH (MPEG-DASH)"
        case .aiff: return "AIFF"
        case .caf: return "CAF (Core Audio Format)"
        case .w64: return "W64 (Wave64)"
        case .rf64: return "RF64"
        case .dcp: return "DCP (Digital Cinema Package)"
        }
    }

    /// Whether this container supports video streams.
    public var supportsVideo: Bool {
        switch self {
        case .m4a, .m4b, .mka, .mks, .aiff, .caf, .w64, .rf64:
            return false
        default:
            return true
        }
    }

    /// Whether this container supports HDR metadata (HDR10, HDR10+, Dolby Vision, HLG).
    public var supportsHDR: Bool {
        switch self {
        case .mp4, .m4v, .mkv, .mk3d, .mov, .webm, .mpegTS, .mxf:
            return true
        default:
            return false
        }
    }

    /// Whether this container supports subtitle streams.
    public var supportsSubtitles: Bool {
        switch self {
        case .mkv, .mk3d, .mks, .mp4, .m4v, .mov, .mpegTS, .webm, .ogg, .ogm:
            return true
        default:
            return false
        }
    }

    /// Whether this container supports chapter markers.
    public var supportsChapters: Bool {
        switch self {
        case .mkv, .mk3d, .mp4, .m4v, .m4b, .mov, .ogg, .ogm:
            return true
        default:
            return false
        }
    }

    /// Attempt to identify the container format from a file extension.
    /// Returns nil if the extension is not recognized.
    public static func from(fileExtension ext: String) -> ContainerFormat? {
        let lowered = ext.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return allCases.first { $0.fileExtensions.contains(lowered) }
    }

    // MARK: - Codec Compatibility (Phase 3.11)

    /// Video codecs that can be muxed into this container.
    public var supportedVideoCodecs: [VideoCodec] {
        switch self {
        case .mp4, .m4v:
            return [.h264, .h265, .h266, .av1, .mpeg2, .mpeg4, .vp9]
        case .mkv, .mk3d:
            return VideoCodec.allCases // MKV supports everything
        case .mov:
            return [.h264, .h265, .prores, .dnxhr, .av1, .mvHevc, .mpeg2, .mpeg4, .jpeg2000]
        case .webm:
            return [.vp8, .vp9, .av1]
        case .mpegTS:
            return [.h264, .h265, .mpeg2, .av1]
        case .mpegPS:
            return [.mpeg2, .mpeg4]
        case .mxf:
            return [.h264, .h265, .prores, .dnxhr, .mpeg2, .jpeg2000]
        case .avi:
            return [.h264, .h265, .mpeg2, .mpeg4, .ffv1, .dnxhr]
        case .flv:
            return [.h264, .h265, .vp8]
        case .threeGP, .threeG2:
            return [.h264, .mpeg4]
        case .ogg, .ogm:
            return [.theora, .vp8]
        case .hls:
            return [.h264, .h265, .av1]
        case .dash:
            return [.h264, .h265, .av1, .vp9]
        default:
            return [] // Audio-only containers
        }
    }

    /// Audio codecs that can be muxed into this container.
    public var supportedAudioCodecs: [AudioCodec] {
        switch self {
        case .mp4, .m4v, .m4a, .m4b, .m4p:
            // TrueHD is not officially part of the MP4 spec but is supported by
            // most major players (Plex, Jellyfin, VLC, MPC-HC, Infuse). When muxing
            // TrueHD into MP4 it MUST NOT be the default audio stream — a fully
            // compatible codec (AAC, AC-3, E-AC-3) must also be present and set as default.
            return [.aacLC, .heAAC, .heAACv2, .xheAAC, .ac3, .eac3, .trueHD, .alac, .opus, .flac, .mp3]
        case .mkv, .mk3d, .mka:
            return AudioCodec.allCases // MKV supports everything
        case .mov:
            return [.aacLC, .heAAC, .heAACv2, .ac3, .eac3, .alac, .pcm, .flac, .opus, .mp3]
        case .webm:
            return [.opus, .vorbis]
        case .mpegTS:
            return [.aacLC, .heAAC, .ac3, .eac3, .dts, .mp2, .mp3, .opus]
        case .mpegPS:
            return [.ac3, .dts, .pcm, .mp2]
        case .mxf:
            return [.pcm, .aacLC, .ac3, .eac3]
        case .avi:
            return [.mp3, .ac3, .aacLC, .pcm, .dts]
        case .flv:
            return [.aacLC, .mp3]
        case .threeGP, .threeG2:
            return [.aacLC, .heAAC]
        case .ogg, .ogm:
            return [.vorbis, .opus, .flac]
        case .hls:
            return [.aacLC, .heAAC, .ac3, .eac3, .flac]
        case .dash:
            return [.aacLC, .heAAC, .ac3, .eac3, .opus]
        case .aiff:
            return [.pcm]
        case .caf:
            return [.aacLC, .alac, .pcm, .opus, .flac]
        case .w64, .rf64:
            return [.pcm]
        default:
            return []
        }
    }

    /// Check whether a specific video codec is compatible with this container.
    public func supportsVideoCodec(_ codec: VideoCodec) -> Bool {
        supportedVideoCodecs.contains(codec)
    }

    /// Check whether a specific audio codec is compatible with this container.
    public func supportsAudioCodec(_ codec: AudioCodec) -> Bool {
        supportedAudioCodecs.contains(codec)
    }

    /// Audio codecs that are supported in this container but MUST NOT be the default
    /// audio stream. A fully compatible codec must also be present and marked as default.
    ///
    /// Example: TrueHD in MP4 — widely supported by players but not part of the
    /// official ISOBMFF/MP4 specification. Requires a compatible fallback stream.
    public var nonDefaultAudioCodecs: [AudioCodec] {
        switch self {
        case .mp4, .m4v, .m4a, .m4b, .m4p:
            return [.trueHD]
        default:
            return []
        }
    }

    /// Whether the given audio codec must NOT be marked as the default stream
    /// when muxed into this container (requires a compatible fallback).
    public func requiresNonDefault(_ codec: AudioCodec) -> Bool {
        nonDefaultAudioCodecs.contains(codec)
    }

    /// The FFmpeg format name for this container (used with -f flag).
    public var ffmpegFormatName: String {
        switch self {
        case .mp4, .m4v, .m4a, .m4b, .m4p: return "mp4"
        case .mkv, .mk3d: return "matroska"
        case .mka: return "matroska"
        case .mks: return "matroska"
        case .mov: return "mov"
        case .webm: return "webm"
        case .mpegTS: return "mpegts"
        case .mpegPS: return "mpeg"
        case .mxf: return "mxf"
        case .avi: return "avi"
        case .flv: return "flv"
        case .threeGP: return "3gp"
        case .threeG2: return "3g2"
        case .ogg, .ogm: return "ogg"
        case .hls: return "hls"
        case .dash: return "dash"
        case .aiff: return "aiff"
        case .caf: return "caf"
        case .w64: return "w64"
        case .rf64: return "rf64"
        case .dcp: return "mxf" // DCP uses MXF wrapper
        }
    }

    /// Whether this container supports Dolby Vision metadata.
    public var supportsDolbyVision: Bool {
        switch self {
        case .mp4, .m4v, .mkv, .mk3d, .mov, .mpegTS:
            return true
        default:
            return false
        }
    }
}
