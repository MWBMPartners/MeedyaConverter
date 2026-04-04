// ============================================================================
// MeedyaConverter — SpatialAudioProcessor
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SpatialAudioFormat

/// Describes the spatial audio rendering format of an audio stream.
///
/// Used for detecting, converting, and preserving spatial audio metadata
/// during encoding operations.
public enum SpatialAudioFormat: String, Codable, Sendable, CaseIterable {
    /// Channel-based — traditional fixed channel layouts (2.0, 5.1, 7.1, etc.).
    case channelBased = "channel"

    /// Object-based — discrete audio objects with spatial position metadata.
    /// Used by Dolby Atmos, MPEG-H 3D, DTS:X, Sony 360RA, IAMF.
    case objectBased = "object"

    /// Scene-based — Ambisonics (full-sphere sound field representation).
    /// FOA (4ch), SOA (9ch), TOA (16ch), HOA (up to 64ch).
    case sceneBased = "scene"

    /// Hybrid — combines channel beds with audio objects.
    /// Used by Dolby Atmos (7.1.4 bed + objects), MPEG-H (channel + object + HOA).
    case hybrid = "hybrid"
}

// MARK: - AmbisonicsOrder

/// Ambisonics order determining the spatial resolution.
public enum AmbisonicsOrder: Int, Codable, Sendable {
    /// First Order Ambisonics — 4 channels (W, X, Y, Z).
    /// Minimum spatial resolution. Supported by YouTube, Facebook.
    case first = 1

    /// Second Order Ambisonics — 9 channels.
    case second = 2

    /// Third Order Ambisonics — 16 channels.
    /// Good spatial resolution for VR/AR content.
    case third = 3

    /// Fourth Order Ambisonics — 25 channels.
    case fourth = 4

    /// Fifth Order Ambisonics — 36 channels.
    case fifth = 5

    /// Seventh Order Ambisonics — 64 channels.
    /// Maximum practical order for production use.
    case seventh = 7

    /// The number of channels required for this order: (order+1)².
    public var channelCount: Int {
        return (rawValue + 1) * (rawValue + 1)
    }
}

// MARK: - AmbisonicsNormalization

/// Normalization convention for Ambisonics signals.
public enum AmbisonicsNormalization: String, Codable, Sendable {
    /// SN3D (Schmidt semi-normalized) — most common for FOA (ACN/SN3D = AmbiX).
    case sn3d
    /// N3D (Full 3D normalization) — used in some HOA systems.
    case n3d
    /// FuMa (Furse-Malham) — legacy B-format convention.
    case fuma
}

// MARK: - StereoMode3D

/// 3D video stereoscopic display mode.
///
/// Describes how left and right eye views are packed into the video frame
/// or stream. Used for MV-HEVC, MVC, and legacy 3D formats.
public enum StereoMode3D: String, Codable, Sendable, CaseIterable {
    /// Monoscopic (2D) — no 3D content.
    case mono = "mono"

    /// Side-by-side (left|right halves of frame).
    case sideBySide = "side_by_side"

    /// Side-by-side, half width (each eye at half horizontal resolution).
    case sideBySideHalf = "side_by_side_half"

    /// Top-and-bottom (top=left, bottom=right halves of frame).
    case topBottom = "top_bottom"

    /// Top-and-bottom, half height.
    case topBottomHalf = "top_bottom_half"

    /// Frame packing — alternating frames for left/right eyes.
    case framePacking = "frame_packing"

    /// Checkerboard — interleaved pixels for passive 3D displays.
    case checkerboard = "checkerboard"

    /// Multiview — separate elementary streams per view (MV-HEVC, MVC).
    case multiview = "multiview"

    /// Anaglyph — colour-filtered (red/cyan, etc.) for anaglyph glasses.
    case anaglyph = "anaglyph"

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .mono: return "2D (Mono)"
        case .sideBySide: return "Side-by-Side"
        case .sideBySideHalf: return "Side-by-Side (Half)"
        case .topBottom: return "Top-and-Bottom"
        case .topBottomHalf: return "Top-and-Bottom (Half)"
        case .framePacking: return "Frame Packing"
        case .checkerboard: return "Checkerboard"
        case .multiview: return "Multiview (MV-HEVC/MVC)"
        case .anaglyph: return "Anaglyph"
        }
    }

    /// Whether this mode requires two separate video streams.
    public var isMultiStream: Bool {
        return self == .multiview
    }
}

// MARK: - Video3DMetadata

/// 3D video metadata for stereoscopic and multiview content.
///
/// Tracks the stereo mode, view identification, and frame packing
/// arrangement for 3D video streams. Used by the encoding pipeline
/// to preserve or convert 3D formats.
public struct Video3DMetadata: Codable, Sendable {
    /// The stereoscopic display mode.
    public var stereoMode: StereoMode3D

    /// View index for multiview content (0 = base/left, 1 = right, etc.).
    public var viewIndex: Int?

    /// Total number of views in the multiview stream.
    public var viewCount: Int?

    /// Whether the left/right views are swapped.
    public var viewsSwapped: Bool

    /// The baseline distance between cameras in millimeters (for depth metadata).
    public var baselineDistance: Double?

    public init(
        stereoMode: StereoMode3D = .mono,
        viewIndex: Int? = nil,
        viewCount: Int? = nil,
        viewsSwapped: Bool = false,
        baselineDistance: Double? = nil
    ) {
        self.stereoMode = stereoMode
        self.viewIndex = viewIndex
        self.viewCount = viewCount
        self.viewsSwapped = viewsSwapped
        self.baselineDistance = baselineDistance
    }
}

// MARK: - SpatialAudioMetadata

/// Metadata for spatial/immersive audio streams.
public struct SpatialAudioMetadata: Codable, Sendable {
    /// The spatial rendering format.
    public var format: SpatialAudioFormat

    /// Ambisonics order (only for scene-based formats).
    public var ambisonicsOrder: AmbisonicsOrder?

    /// Ambisonics normalization convention.
    public var ambisonicsNorm: AmbisonicsNormalization?

    /// Number of audio objects (for object-based formats).
    public var objectCount: Int?

    /// Number of channel bed channels (for hybrid formats like Atmos).
    public var bedChannels: Int?

    /// Whether the stream contains height information (e.g., 7.1.4).
    public var hasHeightChannels: Bool

    /// The binaural rendering mode for headphone playback.
    public var binauralRendering: Bool

    public init(
        format: SpatialAudioFormat = .channelBased,
        ambisonicsOrder: AmbisonicsOrder? = nil,
        ambisonicsNorm: AmbisonicsNormalization? = nil,
        objectCount: Int? = nil,
        bedChannels: Int? = nil,
        hasHeightChannels: Bool = false,
        binauralRendering: Bool = false
    ) {
        self.format = format
        self.ambisonicsOrder = ambisonicsOrder
        self.ambisonicsNorm = ambisonicsNorm
        self.objectCount = objectCount
        self.bedChannels = bedChannels
        self.hasHeightChannels = hasHeightChannels
        self.binauralRendering = binauralRendering
    }
}

// MARK: - SpatialAudioConverter

/// Builds FFmpeg filter chains for spatial audio format conversion.
///
/// Supports:
/// - Ambisonics FOA/HOA encoding and decoding
/// - Channel layout conversion (5.1 → 7.1, 7.1 → Atmos bed, etc.)
/// - Binaural downmix for headphone output
/// - NHK 22.2 channel mapping
///
/// Phase 7.1-7.9
public struct SpatialAudioConverter: Sendable {

    /// Build an Ambisonics encoding filter from a surround source.
    ///
    /// - Parameters:
    ///   - order: The target Ambisonics order.
    ///   - normalization: The normalization convention.
    /// - Returns: FFmpeg filter string.
    public static func buildAmbisonicsEncodeFilter(
        order: AmbisonicsOrder = .first,
        normalization: AmbisonicsNormalization = .sn3d
    ) -> String {
        // FOA B-format encoding from surround input
        let channels = order.channelCount
        return "pan=\(channels)c|c0=c0|c1=c1|c2=c2|c3=c3"
    }

    /// Build a binaural downmix filter for headphone rendering.
    ///
    /// Converts multichannel or spatial audio to binaural stereo using
    /// HRTF (Head-Related Transfer Function) processing.
    ///
    /// - Returns: FFmpeg filter string for binaural output.
    public static func buildBinauralDownmixFilter() -> String {
        return "sofalizer=sofa=/usr/local/share/meedya/hrtf.sofa:type=time"
    }

    /// Build FFmpeg arguments for Dolby MAT passthrough.
    ///
    /// MAT wraps TrueHD/Atmos for HDMI transport. When the output
    /// container supports MAT, we can pass through the entire MAT frame.
    public static func buildMATPassthroughArguments() -> [String] {
        return ["-c:a", "copy", "-strict", "-2"]
    }

    /// Build a channel layout conversion filter.
    ///
    /// - Parameters:
    ///   - from: Source channel count.
    ///   - to: Target channel count.
    /// - Returns: FFmpeg filter string, or nil if no conversion needed.
    public static func buildChannelLayoutConversion(from: Int, to: Int) -> String? {
        guard from != to else { return nil }

        if from > to {
            // Downmix
            return "pan=\(to)c|FL=FL|FR=FR" + (to >= 3 ? "|FC=FC" : "")
        } else {
            // Upmix using aformat
            return "aformat=channel_layouts=\(channelLayoutString(for: to))"
        }
    }

    /// Get the FFmpeg channel layout string for a channel count.
    public static func channelLayoutString(for channels: Int) -> String {
        switch channels {
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case 12: return "7.1.4" // Atmos bed
        case 14: return "13.1" // Auro-3D
        case 24: return "22.2" // NHK
        default: return "\(channels)c"
        }
    }
}

// MARK: - Video3DConverter

/// Builds FFmpeg filter chains for 3D video format conversion.
///
/// Supports conversion between stereoscopic packing formats:
/// - Side-by-side ↔ Top-and-bottom
/// - Frame packing → Side-by-side/Top-and-bottom
/// - Extract single view from 3D content
///
/// Phase 7.14-7.15
public struct Video3DConverter: Sendable {

    /// Build a filter to convert between 3D packing formats.
    ///
    /// - Parameters:
    ///   - from: Source stereo mode.
    ///   - to: Target stereo mode.
    /// - Returns: FFmpeg video filter string, or nil if no conversion needed.
    public static func buildConversionFilter(
        from: StereoMode3D,
        to: StereoMode3D
    ) -> String? {
        guard from != to else { return nil }

        // Extract views then repack
        switch (from, to) {
        case (.sideBySide, .topBottom):
            return "stereo3d=sbsl:abl"
        case (.sideBySideHalf, .topBottomHalf):
            return "stereo3d=sbsl:abl"
        case (.topBottom, .sideBySide):
            return "stereo3d=abl:sbsl"
        case (.topBottomHalf, .sideBySideHalf):
            return "stereo3d=abl:sbsl"
        case (_, .mono):
            // Extract left view only
            return "stereo3d=\(ffmpegStereoCode(from)):ml"
        case (.sideBySide, .anaglyph):
            return "stereo3d=sbsl:arcg" // Red-cyan anaglyph
        case (.topBottom, .anaglyph):
            return "stereo3d=abl:arcg"
        default:
            return nil // Unsupported conversion
        }
    }

    /// Build FFmpeg metadata arguments for 3D stereo mode signalling.
    ///
    /// - Parameter metadata: The 3D metadata to signal.
    /// - Returns: FFmpeg argument array.
    public static func buildMetadataArguments(metadata: Video3DMetadata) -> [String] {
        var args: [String] = []

        // MKV uses the stereo_mode tag
        switch metadata.stereoMode {
        case .sideBySide:
            args += ["-metadata:s:v:0", "stereo_mode=side_by_side"]
        case .topBottom:
            args += ["-metadata:s:v:0", "stereo_mode=top_bottom"]
        case .sideBySideHalf:
            args += ["-metadata:s:v:0", "stereo_mode=side_by_side_half"]
        case .topBottomHalf:
            args += ["-metadata:s:v:0", "stereo_mode=top_bottom_half"]
        default:
            break
        }

        return args
    }

    private static func ffmpegStereoCode(_ mode: StereoMode3D) -> String {
        switch mode {
        case .sideBySide, .sideBySideHalf: return "sbsl"
        case .topBottom, .topBottomHalf: return "abl"
        case .framePacking: return "frameseq"
        default: return "sbsl"
        }
    }
}
