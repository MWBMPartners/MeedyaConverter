// ============================================================================
// MeedyaConverter — ColorSpaceConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ColorPrimaries

/// Color primaries (gamut) as defined by ITU standards.
public enum ColorPrimaries: String, Codable, Sendable, CaseIterable {
    /// BT.601 NTSC (SMPTE 170M).
    case bt601NTSC = "smpte170m"

    /// BT.601 PAL (BT.470BG).
    case bt601PAL = "bt470bg"

    /// BT.709 — standard HD color primaries.
    case bt709 = "bt709"

    /// BT.2020 — UHD wide color gamut.
    case bt2020 = "bt2020"

    /// DCI-P3 — digital cinema color space.
    case dciP3 = "smpte431"

    /// Display P3 (DCI-P3 with D65 white point, used by Apple displays).
    case displayP3 = "smpte432"

    /// Display name.
    public var displayName: String {
        switch self {
        case .bt601NTSC: return "BT.601 (NTSC)"
        case .bt601PAL: return "BT.601 (PAL)"
        case .bt709: return "BT.709 (HD)"
        case .bt2020: return "BT.2020 (UHD)"
        case .dciP3: return "DCI-P3"
        case .displayP3: return "Display P3"
        }
    }

    /// FFmpeg zscale primaries parameter value.
    public var zscaleValue: String {
        switch self {
        case .bt601NTSC: return "170m"
        case .bt601PAL: return "470bg"
        case .bt709: return "709"
        case .bt2020: return "2020"
        case .dciP3: return "431"
        case .displayP3: return "432"
        }
    }

    /// Whether this is a wide color gamut (HDR-capable).
    public var isWideGamut: Bool {
        switch self {
        case .bt2020, .dciP3, .displayP3: return true
        default: return false
        }
    }
}

// MARK: - TransferFunction

/// Transfer function (gamma curve / EOTF).
public enum TransferFunction: String, Codable, Sendable, CaseIterable {
    /// BT.709 gamma (~2.2).
    case bt709 = "bt709"

    /// sRGB (~2.2 with linear segment).
    case srgb = "iec61966-2-1"

    /// PQ (Perceptual Quantizer, ST 2084) — HDR10.
    case pq = "smpte2084"

    /// HLG (Hybrid Log-Gamma, ARIB STD-B67) — BBC/NHK HDR.
    case hlg = "arib-std-b67"

    /// Linear light.
    case linear = "linear"

    /// BT.601 gamma (~2.2).
    case bt601 = "bt601"

    /// Display name.
    public var displayName: String {
        switch self {
        case .bt709: return "BT.709 (SDR)"
        case .srgb: return "sRGB"
        case .pq: return "PQ / ST 2084 (HDR10)"
        case .hlg: return "HLG (Hybrid Log-Gamma)"
        case .linear: return "Linear"
        case .bt601: return "BT.601 (SD)"
        }
    }

    /// FFmpeg zscale transfer parameter value.
    public var zscaleValue: String {
        switch self {
        case .bt709: return "709"
        case .srgb: return "iec61966-2-1"
        case .pq: return "smpte2084"
        case .hlg: return "arib-std-b67"
        case .linear: return "linear"
        case .bt601: return "601"
        }
    }

    /// Whether this transfer function is HDR.
    public var isHDR: Bool {
        switch self {
        case .pq, .hlg: return true
        default: return false
        }
    }
}

// MARK: - ColorMatrix

/// Color matrix coefficients for Y'CbCr conversion.
public enum ColorMatrix: String, Codable, Sendable, CaseIterable {
    /// BT.601 (SD video).
    case bt601 = "bt601"

    /// BT.709 (HD video).
    case bt709 = "bt709"

    /// BT.2020 NCL (non-constant luminance, standard for UHD).
    case bt2020NCL = "bt2020nc"

    /// BT.2020 CL (constant luminance).
    case bt2020CL = "bt2020c"

    /// Display name.
    public var displayName: String {
        switch self {
        case .bt601: return "BT.601"
        case .bt709: return "BT.709"
        case .bt2020NCL: return "BT.2020 NCL"
        case .bt2020CL: return "BT.2020 CL"
        }
    }

    /// FFmpeg zscale matrix parameter value.
    public var zscaleValue: String { rawValue }
}

// MARK: - ToneMapAlgorithm

/// HDR to SDR tone mapping algorithms.
public enum ToneMapAlgorithm: String, Codable, Sendable, CaseIterable {
    /// Hable (John Hable's filmic curve). Best general-purpose algorithm.
    case hable

    /// Reinhard global operator. Natural, soft look.
    case reinhard

    /// Mobius smooth transition. Minimizes artifacts.
    case mobius

    /// BT.2390 (ITU reference). Broadcast compliance.
    case bt2390

    /// Linear clipping. Fast but low quality.
    case linear

    /// No tone mapping (hard clip).
    case clip = "none"

    /// Display name.
    public var displayName: String {
        switch self {
        case .hable: return "Hable (Filmic)"
        case .reinhard: return "Reinhard"
        case .mobius: return "Mobius"
        case .bt2390: return "BT.2390 (ITU)"
        case .linear: return "Linear"
        case .clip: return "None (Clip)"
        }
    }

    /// Description of the algorithm's characteristics.
    public var description: String {
        switch self {
        case .hable: return "Film-like roll-off, preserves highlight detail"
        case .reinhard: return "Soft, natural brightness distribution"
        case .mobius: return "Smooth transition, minimal artifacts"
        case .bt2390: return "ITU standard, broadcast compliant"
        case .linear: return "Simple scaling, fast"
        case .clip: return "Hard clip HDR values (not recommended)"
        }
    }
}

// MARK: - HDRMetadata

/// HDR metadata from a video stream.
public struct HDRMetadata: Codable, Sendable {
    /// Maximum Content Light Level (nits).
    public var maxCLL: Int?

    /// Maximum Frame Average Light Level (nits).
    public var maxFALL: Int?

    /// Mastering display color volume — red primary (x, y).
    public var masteringDisplayRed: (x: Double, y: Double)?

    /// Green primary.
    public var masteringDisplayGreen: (x: Double, y: Double)?

    /// Blue primary.
    public var masteringDisplayBlue: (x: Double, y: Double)?

    /// White point.
    public var masteringDisplayWhitePoint: (x: Double, y: Double)?

    /// Minimum luminance (nits).
    public var masteringDisplayMinLuminance: Double?

    /// Maximum luminance (nits).
    public var masteringDisplayMaxLuminance: Double?

    /// Whether HDR10+ dynamic metadata is present.
    public var hasHDR10Plus: Bool

    /// Whether Dolby Vision metadata is present.
    public var hasDolbyVision: Bool

    /// Dolby Vision profile (if present).
    public var dolbyVisionProfile: Int?

    public init(
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        hasHDR10Plus: Bool = false,
        hasDolbyVision: Bool = false,
        dolbyVisionProfile: Int? = nil
    ) {
        self.maxCLL = maxCLL
        self.maxFALL = maxFALL
        self.hasHDR10Plus = hasHDR10Plus
        self.hasDolbyVision = hasDolbyVision
        self.dolbyVisionProfile = dolbyVisionProfile
    }

    // Custom Codable for tuples
    enum CodingKeys: String, CodingKey {
        case maxCLL, maxFALL, hasHDR10Plus, hasDolbyVision, dolbyVisionProfile
    }

    /// Peak brightness in nits (from metadata or default).
    public var peakBrightness: Double {
        if let maxLum = masteringDisplayMaxLuminance {
            return maxLum
        }
        if let cll = maxCLL {
            return Double(cll)
        }
        return 1000 // Default assumption
    }
}

// MARK: - ToneMapConfig

/// Configuration for HDR to SDR tone mapping.
public struct ToneMapConfig: Codable, Sendable {
    /// Tone mapping algorithm.
    public var algorithm: ToneMapAlgorithm

    /// Source peak brightness in nits (nil = auto-detect from metadata).
    public var peakBrightness: Double?

    /// Desaturation strength (0.0 = none, 1.0 = full).
    public var desaturation: Double

    /// Output bit depth (8 or 10).
    public var outputBitDepth: Int

    /// Whether to output 10-bit SDR (wider gradient, less banding).
    public var use10BitSDR: Bool

    public init(
        algorithm: ToneMapAlgorithm = .hable,
        peakBrightness: Double? = nil,
        desaturation: Double = 0.0,
        outputBitDepth: Int = 8,
        use10BitSDR: Bool = false
    ) {
        self.algorithm = algorithm
        self.peakBrightness = peakBrightness
        self.desaturation = desaturation
        self.outputBitDepth = outputBitDepth
        self.use10BitSDR = use10BitSDR
    }
}

// MARK: - ColorSpaceConfig

/// Configuration for color space conversion.
public struct ColorSpaceConfig: Codable, Sendable {
    /// Target color primaries.
    public var targetPrimaries: ColorPrimaries

    /// Target transfer function.
    public var targetTransfer: TransferFunction

    /// Target color matrix.
    public var targetMatrix: ColorMatrix

    /// Tone mapping config (for HDR → SDR).
    public var toneMap: ToneMapConfig?

    /// Whether to apply chroma upsampling (4:2:0 → 4:4:4 for processing).
    public var chromaUpsampling: Bool

    /// Output pixel format (nil = auto).
    public var outputPixelFormat: String?

    public init(
        targetPrimaries: ColorPrimaries = .bt709,
        targetTransfer: TransferFunction = .bt709,
        targetMatrix: ColorMatrix = .bt709,
        toneMap: ToneMapConfig? = nil,
        chromaUpsampling: Bool = false,
        outputPixelFormat: String? = nil
    ) {
        self.targetPrimaries = targetPrimaries
        self.targetTransfer = targetTransfer
        self.targetMatrix = targetMatrix
        self.toneMap = toneMap
        self.chromaUpsampling = chromaUpsampling
        self.outputPixelFormat = outputPixelFormat
    }
}

// MARK: - ColorSpaceConverter

/// Builds FFmpeg filter chains for color space conversion and HDR tone mapping.
///
/// Supports:
/// - Color primaries conversion (BT.601/709/2020, DCI-P3)
/// - Transfer function conversion (gamma, PQ, HLG, sRGB)
/// - Color matrix conversion
/// - HDR to SDR tone mapping (Hable, Reinhard, Mobius, BT.2390)
/// - HDR metadata preservation and stripping
/// - 10-bit and 12-bit processing pipelines
///
/// Phase 3.26 / 3.9b
public struct ColorSpaceConverter: Sendable {

    // MARK: - HDR to SDR Tone Mapping

    /// Build FFmpeg filter chain for HDR to SDR tone mapping.
    ///
    /// Uses zscale (zimg) for high-quality color space conversion
    /// and the tonemap filter for perceptual tone mapping.
    ///
    /// - Parameters:
    ///   - config: Tone mapping configuration.
    ///   - sourcePrimaries: Source color primaries.
    ///   - sourceTransfer: Source transfer function.
    /// - Returns: FFmpeg video filter string.
    public static func buildToneMapFilter(
        config: ToneMapConfig,
        sourcePrimaries: ColorPrimaries = .bt2020,
        sourceTransfer: TransferFunction = .pq
    ) -> String {
        var filters: [String] = []

        // Step 1: Convert to linear light for tone mapping
        let peak = config.peakBrightness ?? 1000.0
        filters.append("zscale=t=linear:npl=\(Int(peak))")

        // Step 2: Convert to high-precision format
        filters.append("format=gbrpf32le")

        // Step 3: Gamut mapping (BT.2020 → BT.709)
        filters.append("zscale=p=bt709")

        // Step 4: Tone mapping
        var tonemapStr = "tonemap=\(config.algorithm.rawValue)"
        tonemapStr += ":desat=\(config.desaturation)"
        if config.algorithm != .clip {
            tonemapStr += ":peak=\(peak / 10000.0)" // Normalize to 0-1 range
        }
        filters.append(tonemapStr)

        // Step 5: Convert to target color space
        filters.append("zscale=t=bt709:m=bt709:r=tv")

        // Step 6: Output pixel format
        if config.use10BitSDR || config.outputBitDepth == 10 {
            filters.append("format=yuv420p10le")
        } else {
            filters.append("format=yuv420p")
        }

        return filters.joined(separator: ",")
    }

    /// Build FFmpeg arguments for HDR to SDR conversion.
    ///
    /// - Parameters:
    ///   - inputPath: Source HDR file.
    ///   - outputPath: Output SDR file.
    ///   - config: Tone mapping configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildHDRtoSDRArguments(
        inputPath: String,
        outputPath: String,
        config: ToneMapConfig = ToneMapConfig()
    ) -> [String] {
        let filter = buildToneMapFilter(config: config)

        var args: [String] = ["-i", inputPath]
        args += ["-vf", filter]

        // Ensure SDR color metadata in output
        args += ["-color_primaries", "bt709"]
        args += ["-color_trc", "bt709"]
        args += ["-colorspace", "bt709"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Color Space Conversion (non-HDR)

    /// Build FFmpeg filter chain for general color space conversion.
    ///
    /// - Parameter config: Color space conversion configuration.
    /// - Returns: FFmpeg video filter string.
    public static func buildColorSpaceFilter(
        config: ColorSpaceConfig
    ) -> String {
        var filters: [String] = []

        var zscaleParams: [String] = []
        zscaleParams.append("p=\(config.targetPrimaries.zscaleValue)")
        zscaleParams.append("t=\(config.targetTransfer.zscaleValue)")
        zscaleParams.append("m=\(config.targetMatrix.zscaleValue)")
        zscaleParams.append("r=tv")

        if config.chromaUpsampling {
            zscaleParams.append("c=left")
        }

        filters.append("zscale=\(zscaleParams.joined(separator: ":"))")

        if let pixFmt = config.outputPixelFormat {
            filters.append("format=\(pixFmt)")
        }

        return filters.joined(separator: ",")
    }

    /// Build FFmpeg arguments for color space conversion.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildColorSpaceArguments(
        inputPath: String,
        outputPath: String,
        config: ColorSpaceConfig
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Apply tone mapping if converting from HDR to SDR
        if let toneMap = config.toneMap {
            let filter = buildToneMapFilter(config: toneMap)
            args += ["-vf", filter]
        } else {
            let filter = buildColorSpaceFilter(config: config)
            args += ["-vf", filter]
        }

        // Set output color metadata
        args += ["-color_primaries", config.targetPrimaries.rawValue]
        args += ["-color_trc", config.targetTransfer.rawValue]
        args += ["-colorspace", config.targetMatrix.rawValue]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - HLG Conversion

    /// Build FFmpeg filter for HLG to SDR conversion.
    ///
    /// HLG requires a different approach than PQ since it uses
    /// a scene-referred signal.
    ///
    /// - Parameter config: Tone mapping configuration.
    /// - Returns: FFmpeg video filter string.
    public static func buildHLGtoSDRFilter(
        config: ToneMapConfig = ToneMapConfig()
    ) -> String {
        var filters: [String] = []

        // HLG to linear (scene-referred)
        filters.append("zscale=t=linear:npl=100")
        filters.append("format=gbrpf32le")

        // BT.2020 → BT.709 gamut
        filters.append("zscale=p=bt709")

        // Tone map
        filters.append("tonemap=\(config.algorithm.rawValue):desat=\(config.desaturation)")

        // Output
        filters.append("zscale=t=bt709:m=bt709:r=tv")

        if config.use10BitSDR {
            filters.append("format=yuv420p10le")
        } else {
            filters.append("format=yuv420p")
        }

        return filters.joined(separator: ",")
    }

    // MARK: - HDR Metadata Arguments

    /// Build FFmpeg arguments to preserve HDR metadata in output.
    ///
    /// - Parameter metadata: HDR metadata to embed.
    /// - Returns: FFmpeg argument array.
    public static func buildHDRMetadataArguments(
        metadata: HDRMetadata
    ) -> [String] {
        var args: [String] = []

        // Content light level
        if let maxCLL = metadata.maxCLL, let maxFALL = metadata.maxFALL {
            args += ["-max_cll", "\(maxCLL),\(maxFALL)"]
        }

        // Mastering display color volume
        if let maxLum = metadata.masteringDisplayMaxLuminance,
           let minLum = metadata.masteringDisplayMinLuminance {
            // G(x,y)B(x,y)R(x,y)WP(x,y)L(max,min)
            let mdcv = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(\(Int(maxLum * 10000)),\(Int(minLum * 10000)))"
            args += ["-master_display", mdcv]
        }

        return args
    }

    /// Build FFmpeg arguments to strip HDR metadata from output (for SDR output).
    ///
    /// - Returns: FFmpeg argument array.
    public static func buildStripHDRMetadataArguments() -> [String] {
        return [
            "-color_primaries", "bt709",
            "-color_trc", "bt709",
            "-colorspace", "bt709",
        ]
    }

    // MARK: - Dolby Vision Handling

    /// Build dovi_tool arguments to strip Dolby Vision RPU (flatten to HDR10).
    ///
    /// - Parameters:
    ///   - inputPath: Source file with Dolby Vision.
    ///   - outputPath: Output HDR10 file.
    /// - Returns: Argument array for dovi_tool.
    public static func buildDoViToHDR10Arguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return ["remove", "-i", inputPath, "-o", outputPath]
    }

    /// Build dovi_tool arguments to convert between Dolby Vision profiles.
    ///
    /// - Parameters:
    ///   - inputPath: Source file.
    ///   - outputPath: Output file.
    ///   - targetProfile: Target DV profile (e.g., 8).
    /// - Returns: Argument array for dovi_tool.
    public static func buildDoViProfileConvertArguments(
        inputPath: String,
        outputPath: String,
        targetProfile: Int
    ) -> [String] {
        return ["convert", "--discard", "-i", inputPath, "-o", outputPath, "-p", "\(targetProfile)"]
    }

    // MARK: - Detection Helpers

    /// Determine if a color space conversion is needed.
    ///
    /// - Parameters:
    ///   - sourcePrimaries: Source color primaries.
    ///   - targetPrimaries: Target color primaries.
    ///   - sourceTransfer: Source transfer function.
    ///   - targetTransfer: Target transfer function.
    /// - Returns: `true` if conversion is needed.
    public static func needsConversion(
        sourcePrimaries: ColorPrimaries,
        targetPrimaries: ColorPrimaries,
        sourceTransfer: TransferFunction,
        targetTransfer: TransferFunction
    ) -> Bool {
        return sourcePrimaries != targetPrimaries || sourceTransfer != targetTransfer
    }

    /// Determine if HDR to SDR tone mapping is needed.
    ///
    /// - Parameters:
    ///   - sourceTransfer: Source transfer function.
    ///   - targetTransfer: Target transfer function.
    /// - Returns: `true` if tone mapping is needed.
    public static func needsToneMapping(
        sourceTransfer: TransferFunction,
        targetTransfer: TransferFunction
    ) -> Bool {
        return sourceTransfer.isHDR && !targetTransfer.isHDR
    }

    /// Recommend target color space for a given output resolution.
    ///
    /// - Parameter height: Output video height.
    /// - Returns: Recommended color primaries.
    public static func recommendedPrimaries(forHeight height: Int) -> ColorPrimaries {
        if height >= 2160 {
            return .bt2020
        } else if height >= 720 {
            return .bt709
        } else {
            return .bt601NTSC
        }
    }
}
