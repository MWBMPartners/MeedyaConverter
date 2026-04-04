// ============================================================================
// MeedyaConverter — ColourSpaceConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ColourSpace

/// Represents ITU-R colour space standards used in media encoding.
///
/// Each colour space defines a combination of colour primaries, transfer
/// characteristics, and matrix coefficients that together describe how
/// pixel values map to visible colours.
public enum ColourSpace: String, Codable, Sendable, CaseIterable {
    /// BT.601 — Standard Definition (NTSC/PAL).
    /// Used for DVD, SD broadcast, and legacy content.
    case bt601 = "bt601"

    /// BT.709 — High Definition SDR.
    /// The standard for HD broadcast, Blu-ray SDR, and web content.
    case bt709 = "bt709"

    /// BT.2020 — Ultra High Definition / Wide Colour Gamut.
    /// Required for HDR10, HLG, and Dolby Vision content.
    case bt2020 = "bt2020"

    /// DCI-P3 — Digital Cinema Initiative.
    /// Used in cinema mastering and Apple displays (Display P3).
    case dciP3 = "dci_p3"

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .bt601: return "BT.601 (SD)"
        case .bt709: return "BT.709 (HD SDR)"
        case .bt2020: return "BT.2020 (UHD/HDR)"
        case .dciP3: return "DCI-P3 (Cinema)"
        }
    }

    /// FFmpeg colour primaries value.
    public var ffmpegPrimaries: String {
        switch self {
        case .bt601: return "smpte170m"
        case .bt709: return "bt709"
        case .bt2020: return "bt2020"
        case .dciP3: return "smpte431"
        }
    }

    /// FFmpeg transfer characteristics value.
    public var ffmpegTransfer: String {
        switch self {
        case .bt601: return "smpte170m"
        case .bt709: return "bt709"
        case .bt2020: return "bt709" // BT.2020 SDR uses BT.709 transfer
        case .dciP3: return "smpte428"
        }
    }

    /// FFmpeg matrix coefficients value.
    public var ffmpegMatrix: String {
        switch self {
        case .bt601: return "smpte170m"
        case .bt709: return "bt709"
        case .bt2020: return "bt2020nc"
        case .dciP3: return "bt709"
        }
    }

    /// Whether this colour space is wide gamut (wider than BT.709).
    public var isWideGamut: Bool {
        switch self {
        case .bt2020, .dciP3: return true
        case .bt601, .bt709: return false
        }
    }
}

// MARK: - ColourSpaceConverter

/// Builds FFmpeg filter chains for colour space conversion between standards.
///
/// Colour space conversion is needed when:
/// - Upconverting SD (BT.601) to HD (BT.709) for modern playback
/// - Downconverting UHD (BT.2020) to HD (BT.709) without tone mapping
/// - Converting cinema masters (DCI-P3) to broadcast (BT.709/BT.2020)
///
/// Uses the zscale filter for high-quality colour space conversion with
/// proper chromatic adaptation and gamut mapping.
public struct ColourSpaceConverter: Sendable {

    /// Build a zscale filter string to convert between colour spaces.
    ///
    /// - Parameters:
    ///   - source: The source colour space.
    ///   - target: The target colour space.
    ///   - range: The output colour range ("tv" for limited, "pc" for full). Defaults to "tv".
    /// - Returns: A zscale filter string, or nil if no conversion is needed.
    public static func buildFilter(
        from source: ColourSpace,
        to target: ColourSpace,
        range: String = "tv"
    ) -> String? {
        guard source != target else { return nil }
        return "zscale=p=\(target.ffmpegPrimaries):t=\(target.ffmpegTransfer):m=\(target.ffmpegMatrix):r=\(range)"
    }

    /// Build FFmpeg output arguments for colour signalling (no pixel conversion).
    ///
    /// These arguments tag the output stream with the correct colour metadata
    /// without applying any pixel-level conversion. Use when the pixel data
    /// already matches the target colour space.
    ///
    /// - Parameter colourSpace: The colour space to signal.
    /// - Returns: FFmpeg argument pairs for colour metadata.
    public static func buildSignallingArguments(for colourSpace: ColourSpace) -> [String] {
        return [
            "-color_primaries", colourSpace.ffmpegPrimaries,
            "-color_trc", colourSpace.ffmpegTransfer,
            "-colorspace", colourSpace.ffmpegMatrix,
        ]
    }

    /// Determine the appropriate output colour space for a given codec and HDR mode.
    ///
    /// - Parameters:
    ///   - codec: The output video codec.
    ///   - isHDR: Whether the output will be HDR.
    /// - Returns: The recommended colour space.
    public static func recommendedColourSpace(
        for codec: VideoCodec,
        isHDR: Bool
    ) -> ColourSpace {
        if isHDR && codec.supportsHDR {
            return .bt2020
        }
        return .bt709
    }
}
