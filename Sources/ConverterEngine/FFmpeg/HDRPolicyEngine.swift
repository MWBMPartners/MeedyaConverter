// ============================================================================
// MeedyaConverter — HDRPolicyEngine
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// NOTE: HDRFormat is defined in Models/MediaStream.swift

// MARK: - HDRCompatibility

/// Describes whether a codec/container combination supports HDR.
public struct HDRCompatibility: Sendable {
    /// Whether the output combination supports HDR10 (PQ + static metadata).
    public var supportsHDR10: Bool

    /// Whether the output combination supports HLG.
    public var supportsHLG: Bool

    /// Whether the output combination supports Dolby Vision.
    public var supportsDolbyVision: Bool

    /// Whether the output combination supports HDR10+.
    public var supportsHDR10Plus: Bool

    /// Whether 10-bit encoding is supported.
    public var supports10Bit: Bool

    public init(
        supportsHDR10: Bool = false,
        supportsHLG: Bool = false,
        supportsDolbyVision: Bool = false,
        supportsHDR10Plus: Bool = false,
        supports10Bit: Bool = false
    ) {
        self.supportsHDR10 = supportsHDR10
        self.supportsHLG = supportsHLG
        self.supportsDolbyVision = supportsDolbyVision
        self.supportsHDR10Plus = supportsHDR10Plus
        self.supports10Bit = supports10Bit
    }

    /// Whether any HDR format is supported.
    public var supportsAnyHDR: Bool {
        supportsHDR10 || supportsHLG || supportsDolbyVision || supportsHDR10Plus
    }
}

// MARK: - HDRPolicyAction

/// The action to take when HDR source meets an output configuration.
public enum HDRPolicyAction: String, Codable, Sendable {
    /// Preserve HDR metadata as-is (output supports it).
    case preserve = "preserve"

    /// Apply tone mapping to SDR (output doesn't support HDR).
    case toneMapToSDR = "tone_map_sdr"

    /// Convert PQ to HLG (output supports HLG but not PQ).
    case convertToHLG = "convert_hlg"

    /// Strip dynamic metadata, keep static HDR10 (output supports HDR10 but not DV/HDR10+).
    case stripDynamicMetadata = "strip_dynamic"

    /// Passthrough (copy stream, no processing).
    case passthrough = "passthrough"

    /// Display name.
    public var displayName: String {
        switch self {
        case .preserve: return "Preserve HDR"
        case .toneMapToSDR: return "Tone Map to SDR"
        case .convertToHLG: return "Convert to HLG"
        case .stripDynamicMetadata: return "Strip Dynamic Metadata"
        case .passthrough: return "Passthrough (Copy)"
        }
    }
}

// MARK: - HDRPolicyEngine

/// Determines the correct HDR handling strategy based on source format,
/// output codec, output container, and user preferences.
///
/// Automatically applies the right conversion when the output format
/// is HDR-incompatible, preserving HDR when possible.
///
/// Phase 3.9c / 3.7
public struct HDRPolicyEngine: Sendable {

    // MARK: - Compatibility Database

    /// Determine HDR compatibility for a codec/container combination.
    ///
    /// - Parameters:
    ///   - videoCodec: Output video codec identifier (e.g., "h265", "h264", "av1", "vp9").
    ///   - container: Output container format (e.g., "mp4", "mkv", "webm").
    /// - Returns: HDR compatibility info.
    public static func compatibility(
        videoCodec: String,
        container: String
    ) -> HDRCompatibility {
        let codec = videoCodec.lowercased()
        let fmt = container.lowercased()

        switch codec {
        case "h265", "hevc", "libx265", "hevc_videotoolbox", "hevc_nvenc", "hevc_qsv", "hevc_amf", "hevc_vaapi":
            return HDRCompatibility(
                supportsHDR10: true,
                supportsHLG: true,
                supportsDolbyVision: fmt == "mp4" || fmt == "mkv" || fmt == "mov" || fmt == "ts",
                supportsHDR10Plus: fmt == "mkv" || fmt == "mp4",
                supports10Bit: true
            )

        case "av1", "libsvtav1", "libaom-av1", "av1_nvenc", "av1_qsv", "av1_amf", "av1_vaapi":
            return HDRCompatibility(
                supportsHDR10: true,
                supportsHLG: true,
                supportsDolbyVision: false,
                supportsHDR10Plus: fmt == "mkv" || fmt == "webm",
                supports10Bit: true
            )

        case "vp9", "libvpx-vp9":
            return HDRCompatibility(
                supportsHDR10: fmt == "mkv" || fmt == "webm",
                supportsHLG: fmt == "mkv" || fmt == "webm",
                supportsDolbyVision: false,
                supportsHDR10Plus: false,
                supports10Bit: true
            )

        case "h264", "libx264", "h264_videotoolbox", "h264_nvenc", "h264_qsv", "h264_amf", "h264_vaapi":
            // H.264 does not support HDR metadata (no HDR SEI/VUI for PQ/HLG)
            return HDRCompatibility(
                supportsHDR10: false,
                supportsHLG: false,
                supportsDolbyVision: false,
                supportsHDR10Plus: false,
                supports10Bit: true // H.264 Hi10P exists but no HDR metadata
            )

        case "prores", "prores_ks", "prores_videotoolbox":
            return HDRCompatibility(
                supportsHDR10: fmt == "mov",
                supportsHLG: fmt == "mov",
                supportsDolbyVision: false,
                supportsHDR10Plus: false,
                supports10Bit: true
            )

        default:
            return HDRCompatibility()
        }
    }

    // MARK: - Policy Decision

    /// Determine the correct HDR action for a given source/output combination.
    ///
    /// - Parameters:
    ///   - sourceFormat: Detected HDR format of the source.
    ///   - videoCodec: Output video codec.
    ///   - container: Output container format.
    ///   - userPreference: User's explicit preference (nil = auto).
    /// - Returns: The recommended action.
    public static func recommendAction(
        sourceFormat: HDRFormat,
        videoCodec: String,
        container: String,
        userPreference: HDRPolicyAction? = nil
    ) -> HDRPolicyAction {
        // If user explicitly set a preference, honour it
        if let pref = userPreference {
            return pref
        }

        // SDR source — no HDR processing needed
        guard sourceFormat.isHDR else {
            return .passthrough
        }

        let compat = compatibility(videoCodec: videoCodec, container: container)

        // Output doesn't support any HDR — must tone map to SDR
        guard compat.supportsAnyHDR else {
            return .toneMapToSDR
        }

        // Check specific format support
        switch sourceFormat {
        case .dolbyVision, .dolbyVisionHDR10:
            if compat.supportsDolbyVision {
                return .preserve
            } else if compat.supportsHDR10 {
                return .stripDynamicMetadata
            } else {
                return .toneMapToSDR
            }

        case .hdr10Plus:
            if compat.supportsHDR10Plus {
                return .preserve
            } else if compat.supportsHDR10 {
                return .stripDynamicMetadata
            } else {
                return .toneMapToSDR
            }

        case .hdr10, .pq:
            if compat.supportsHDR10 {
                return .preserve
            } else {
                return .toneMapToSDR
            }

        case .hlg:
            if compat.supportsHLG {
                return .preserve
            } else if compat.supportsHDR10 {
                // Convert HLG → PQ/HDR10 (rare scenario)
                return .preserve
            } else {
                return .toneMapToSDR
            }

        case .sdr:
            return .passthrough
        }
    }

    // MARK: - FFmpeg Arguments

    /// Build FFmpeg arguments to implement the recommended HDR action.
    ///
    /// - Parameters:
    ///   - action: The HDR policy action.
    ///   - sourceFormat: Source HDR format.
    ///   - toneMapConfig: Optional tone mapping configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildArguments(
        action: HDRPolicyAction,
        sourceFormat: HDRFormat,
        toneMapConfig: ToneMapConfig = ToneMapConfig()
    ) -> [String] {
        switch action {
        case .preserve:
            return buildPreserveArguments(sourceFormat: sourceFormat)

        case .toneMapToSDR:
            if sourceFormat.isHLG {
                let filter = ColorSpaceConverter.buildHLGtoSDRFilter(config: toneMapConfig)
                return ["-vf", filter] + ColorSpaceConverter.buildStripHDRMetadataArguments()
            } else {
                let filter = ColorSpaceConverter.buildToneMapFilter(config: toneMapConfig)
                return ["-vf", filter] + ColorSpaceConverter.buildStripHDRMetadataArguments()
            }

        case .convertToHLG:
            var args: [String] = []
            args += ["-vf", "zscale=t=arib-std-b67:p=bt2020:m=bt2020nc"]
            args += ["-color_primaries", "bt2020"]
            args += ["-color_trc", "arib-std-b67"]
            args += ["-colorspace", "bt2020nc"]
            return args

        case .stripDynamicMetadata:
            // Keep HDR10 static metadata, strip dynamic (DV RPU, HDR10+ SEI)
            return [
                "-color_primaries", "bt2020",
                "-color_trc", "smpte2084",
                "-colorspace", "bt2020nc",
            ]

        case .passthrough:
            return []
        }
    }

    /// Build FFmpeg arguments to preserve HDR metadata during encoding.
    ///
    /// - Parameter sourceFormat: Source HDR format.
    /// - Returns: FFmpeg argument array.
    public static func buildPreserveArguments(
        sourceFormat: HDRFormat
    ) -> [String] {
        switch sourceFormat {
        case .hlg:
            return [
                "-color_primaries", "bt2020",
                "-color_trc", "arib-std-b67",
                "-colorspace", "bt2020nc",
            ]
        case .hdr10, .hdr10Plus, .pq:
            return [
                "-color_primaries", "bt2020",
                "-color_trc", "smpte2084",
                "-colorspace", "bt2020nc",
            ]
        case .dolbyVision, .dolbyVisionHDR10:
            return [
                "-color_primaries", "bt2020",
                "-color_trc", "smpte2084",
                "-colorspace", "bt2020nc",
                "-strict", "unofficial",
            ]
        case .sdr:
            return []
        }
    }

    // MARK: - HDR Detection

    /// Detect the HDR format from FFprobe stream metadata.
    ///
    /// - Parameters:
    ///   - colorTransfer: Color transfer characteristic string from FFprobe.
    ///   - colorPrimaries: Color primaries string from FFprobe.
    ///   - sideDataList: Side data types present (e.g., "Dolby Vision configuration").
    /// - Returns: Detected HDR format.
    public static func detectFormat(
        colorTransfer: String?,
        colorPrimaries: String?,
        sideDataList: [String] = []
    ) -> HDRFormat {
        let transfer = (colorTransfer ?? "").lowercased()
        let primaries = (colorPrimaries ?? "").lowercased()

        // Check for Dolby Vision
        let hasDV = sideDataList.contains { $0.lowercased().contains("dolby vision") }
        if hasDV {
            // DV + HDR10 fallback layer
            if transfer.contains("smpte2084") || transfer.contains("pq") {
                return .dolbyVisionHDR10
            }
            return .dolbyVision
        }

        // Check for HDR10+ (indicated by side data)
        let hasHDR10Plus = sideDataList.contains { $0.lowercased().contains("hdr10+") || $0.lowercased().contains("dynamic") }
        if hasHDR10Plus && (transfer.contains("smpte2084") || transfer.contains("pq")) {
            return .hdr10Plus
        }

        // Check for PQ (HDR10)
        if transfer.contains("smpte2084") || transfer.contains("pq") {
            return .hdr10
        }

        // Check for HLG
        if transfer.contains("arib-std-b67") || transfer.contains("hlg") {
            return .hlg
        }

        return .sdr
    }

    /// Determine if an output format requires pixel format upgrade to 10-bit.
    ///
    /// - Parameters:
    ///   - action: HDR policy action.
    ///   - currentPixelFormat: Current pixel format string.
    /// - Returns: Recommended pixel format (nil = no change needed).
    public static func recommendedPixelFormat(
        action: HDRPolicyAction,
        currentPixelFormat: String?
    ) -> String? {
        switch action {
        case .preserve, .convertToHLG, .stripDynamicMetadata:
            // HDR requires 10-bit
            let fmt = (currentPixelFormat ?? "").lowercased()
            if fmt.contains("10") || fmt.contains("12") {
                return nil // Already sufficient
            }
            return "yuv420p10le"

        case .toneMapToSDR:
            return "yuv420p" // 8-bit SDR

        case .passthrough:
            return nil
        }
    }
}

// MARK: - HLGMetadataPreserver

/// Builds FFmpeg arguments to preserve HLG-specific metadata during transcoding.
///
/// HLG content requires specific color metadata (BT.2020 primaries, ARIB STD-B67
/// transfer) and optional static metadata to maintain correct playback.
///
/// Phase 3.7
public struct HLGMetadataPreserver: Sendable {

    /// Build FFmpeg arguments for HLG metadata preservation during re-encode.
    ///
    /// - Parameters:
    ///   - maxCLL: Maximum Content Light Level (optional, HLG rarely uses this).
    ///   - maxFALL: Maximum Frame Average Light Level (optional).
    /// - Returns: FFmpeg argument array.
    public static func buildPreservationArguments(
        maxCLL: Int? = nil,
        maxFALL: Int? = nil
    ) -> [String] {
        var args: [String] = [
            // Colour description for HLG
            "-color_primaries", "bt2020",
            "-color_trc", "arib-std-b67",
            "-colorspace", "bt2020nc",
            "-color_range", "tv",
        ]

        // HLG rarely uses CLL/FALL but some content has it
        if let cll = maxCLL, let fall = maxFALL {
            args += ["-max_cll", "\(cll),\(fall)"]
        }

        return args
    }

    /// Build FFmpeg arguments for HLG pixel format preservation.
    ///
    /// HLG must be encoded in 10-bit to preserve the full dynamic range.
    ///
    /// - Parameter sourcePixelFormat: Source pixel format.
    /// - Returns: Recommended pixel format argument or empty.
    public static func buildPixelFormatArguments(
        sourcePixelFormat: String?
    ) -> [String] {
        let fmt = (sourcePixelFormat ?? "").lowercased()
        // If already 10-bit or higher, preserve
        if fmt.contains("10") || fmt.contains("12") || fmt.contains("16") {
            return ["-pix_fmt", fmt]
        }
        // Upgrade to 10-bit for HLG
        return ["-pix_fmt", "yuv420p10le"]
    }

    /// Validate that an encoder supports HLG output.
    ///
    /// - Parameter encoder: FFmpeg encoder name.
    /// - Returns: `true` if the encoder can produce HLG content.
    public static func isEncoderHLGCapable(encoder: String) -> Bool {
        let hlgEncoders = [
            "libx265", "hevc_videotoolbox", "hevc_nvenc", "hevc_qsv",
            "hevc_amf", "hevc_vaapi",
            "libsvtav1", "libaom-av1", "av1_nvenc", "av1_qsv",
            "libvpx-vp9",
            "prores_ks", "prores_videotoolbox",
        ]
        return hlgEncoders.contains(encoder.lowercased())
    }
}
