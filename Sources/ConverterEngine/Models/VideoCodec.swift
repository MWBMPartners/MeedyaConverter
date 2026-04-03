// ============================================================================
// MeedyaConverter — VideoCodec
// Copyright © 2026–2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// MARK: - VideoCodec

/// Represents all supported video codecs for encoding, decoding, and passthrough.
///
/// Each codec has properties describing its capabilities: HDR support,
/// hardware acceleration availability, lossless mode, and the FFmpeg
/// encoder/decoder names used to invoke it.
public enum VideoCodec: String, Codable, Sendable, CaseIterable, Identifiable {

    // MARK: - AVC / HEVC Family

    /// H.264 / AVC — the most widely compatible video codec.
    /// No HDR support. Hardware encoding available on all platforms.
    case h264

    /// H.265 / HEVC — primary codec for 4K and HDR content.
    /// Supports HDR10, HDR10+, HLG, Dolby Vision. Hardware encoding widely available.
    case h265

    /// H.266 / VVC — next-generation codec (~30-50% more efficient than HEVC).
    /// Encoder support is experimental (vvenc). No hardware encoding yet.
    case h266

    // MARK: - Multiview / 3D

    /// MV-HEVC — Apple's multiview HEVC extension for spatial video.
    /// Used by Apple Vision Pro, Meta Quest, Google VR.
    /// Hardware encoding via VideoToolbox on Apple Silicon.
    case mvHevc = "mv_hevc"

    /// MV-H264 — H.264 Stereo High Profile for stereoscopic 3D.
    /// Left/right eye encoding with inter-view prediction.
    case mvH264 = "mv_h264"

    // MARK: - VP / AV Family (Open Source)

    /// VP8 — Google's open video codec. Predecessor to VP9.
    /// Used in WebM containers. No HDR support.
    case vp8

    /// VP9 — Google's open video codec for web video.
    /// Supports HDR10, HLG. Used by YouTube.
    case vp9

    /// AV1 — Alliance for Open Media's next-gen open codec.
    /// Excellent compression efficiency. Supports HDR10, HDR10+, HLG.
    /// Hardware encoding on Apple M3+, NVIDIA RTX 40+, Intel Arc, AMD RX 7000+.
    case av1

    /// AV2 — successor to AV1, still in research phase.
    /// No production encoder exists yet. Placeholder for future support.
    case av2

    // MARK: - Professional / Intermediate

    /// Apple ProRes — professional intermediate codec.
    /// Multiple quality tiers (Proxy, LT, Standard, HQ, 4444, 4444 XQ).
    /// Hardware encoding via VideoToolbox on Apple Silicon.
    case prores

    /// Avid DNxHR — professional post-production codec.
    /// Multiple quality profiles (LB, SQ, HQ, HQX, 444).
    case dnxhr

    /// GoPro CineForm — intermediate codec for editing workflows.
    case cineform

    // MARK: - Legacy / Broadcast

    /// MPEG-2 — DVD and broadcast standard. No HDR support.
    case mpeg2

    /// MPEG-4 Part 2 — legacy codec, predecessor to H.264.
    case mpeg4

    /// Theora — Xiph.org's open video codec.
    /// Software-only encoding. Used in OGG containers.
    case theora

    /// VC-1 / WMV — Microsoft's video codec. Found on Blu-ray and Windows Media.
    case vc1

    // MARK: - Lossless / Archival

    /// FFV1 — FFmpeg's lossless video codec. Used for archival by libraries and archives.
    case ffv1

    /// JPEG 2000 — used in Digital Cinema Packages (DCP).
    /// Supports both lossy and lossless modes.
    case jpeg2000

    // MARK: - Computed Properties

    /// A stable identifier for use with `Identifiable` conformance.
    public var id: String { rawValue }

    /// The FFmpeg encoder name for software encoding.
    /// Returns nil if software encoding is not available.
    public var ffmpegEncoder: String? {
        switch self {
        case .h264: return "libx264"
        case .h265: return "libx265"
        case .h266: return "libvvenc"
        case .mvHevc: return nil // VideoToolbox only
        case .mvH264: return nil // Specialised encoder
        case .vp8: return "libvpx"
        case .vp9: return "libvpx-vp9"
        case .av1: return "libsvtav1"
        case .av2: return nil // No encoder exists yet
        case .prores: return "prores_ks"
        case .dnxhr: return "dnxhd"
        case .cineform: return nil // Decode only in FFmpeg
        case .mpeg2: return "mpeg2video"
        case .mpeg4: return "mpeg4"
        case .theora: return "libtheora"
        case .vc1: return nil // Decode only
        case .ffv1: return "ffv1"
        case .jpeg2000: return "libopenjpeg"
        }
    }

    /// The FFmpeg decoder name.
    public var ffmpegDecoder: String {
        switch self {
        case .h264: return "h264"
        case .h265: return "hevc"
        case .h266: return "vvc"
        case .mvHevc: return "hevc"
        case .mvH264: return "h264"
        case .vp8: return "vp8"
        case .vp9: return "vp9"
        case .av1: return "av1"
        case .av2: return "av2"
        case .prores: return "prores"
        case .dnxhr: return "dnxhd"
        case .cineform: return "cfhd"
        case .mpeg2: return "mpeg2video"
        case .mpeg4: return "mpeg4"
        case .theora: return "theora"
        case .vc1: return "vc1"
        case .ffv1: return "ffv1"
        case .jpeg2000: return "libopenjpeg"
        }
    }

    /// A human-readable display name for this codec.
    public var displayName: String {
        switch self {
        case .h264: return "H.264 / AVC"
        case .h265: return "H.265 / HEVC"
        case .h266: return "H.266 / VVC"
        case .mvHevc: return "MV-HEVC (Multiview/Spatial/3D)"
        case .mvH264: return "MV-H264 (Multiview/Stereo 3D)"
        case .vp8: return "VP8"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        case .av2: return "AV2 (Future)"
        case .prores: return "Apple ProRes"
        case .dnxhr: return "Avid DNxHR"
        case .cineform: return "GoPro CineForm"
        case .mpeg2: return "MPEG-2"
        case .mpeg4: return "MPEG-4"
        case .theora: return "Theora"
        case .vc1: return "VC-1 / WMV"
        case .ffv1: return "FFV1 (Lossless)"
        case .jpeg2000: return "JPEG 2000"
        }
    }

    /// Whether this codec supports HDR metadata (HDR10, HDR10+, HLG, Dolby Vision).
    public var supportsHDR: Bool {
        switch self {
        case .h265, .mvHevc, .vp9, .av1:
            return true
        default:
            return false
        }
    }

    /// Whether this codec can be hardware-encoded on macOS via VideoToolbox.
    public var supportsVideoToolbox: Bool {
        switch self {
        case .h264, .h265, .prores, .mvHevc:
            return true
        case .av1:
            return true // Apple M3+ only
        default:
            return false
        }
    }

    /// Whether this codec supports lossless encoding mode.
    public var supportsLossless: Bool {
        switch self {
        case .ffv1, .jpeg2000, .prores:
            return true
        case .h264, .h265:
            return true // CRF 0 / lossless mode
        default:
            return false
        }
    }

    /// Whether software encoding is available for this codec.
    public var canEncode: Bool {
        return ffmpegEncoder != nil || supportsVideoToolbox
    }

    /// Whether this codec is currently production-ready for encoding.
    /// Returns false for codecs with experimental or unavailable encoders.
    public var isEncoderStable: Bool {
        switch self {
        case .h266, .av2, .cineform, .vc1, .mvH264:
            return false
        default:
            return canEncode
        }
    }
}
