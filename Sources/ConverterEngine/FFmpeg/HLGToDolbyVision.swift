// ============================================================================
// MeedyaConverter — HLGToDolbyVision
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DVProfileTarget

/// Target Dolby Vision profile for HLG conversion.
public enum DVProfileTarget: String, Codable, Sendable, CaseIterable {
    /// Profile 8.4 — HLG base layer with DV RPU enhancement.
    /// Three-tier fallback: DV → HLG → SDR.
    case profile84 = "8.4"

    /// Profile 5 — IPT-PQ base layer (single layer, no backward compatibility).
    /// Requires DV-capable playback device.
    case profile5 = "5"

    /// Display name.
    public var displayName: String {
        switch self {
        case .profile84: return "Profile 8.4 (HLG + DV, recommended)"
        case .profile5: return "Profile 5 (DV only)"
        }
    }

    /// dovi_tool mode parameter value.
    public var doviToolMode: String {
        switch self {
        case .profile84: return "4"
        case .profile5: return "0"
        }
    }

    /// Whether this profile preserves HLG backward compatibility.
    public var hlgCompatible: Bool {
        self == .profile84
    }

    /// Base layer transfer function.
    public var baseLayerTransfer: String {
        switch self {
        case .profile84: return "arib-std-b67"
        case .profile5: return "smpte2084"
        }
    }
}

// MARK: - HLGToDVConfig

/// Configuration for HLG to Dolby Vision conversion.
public struct HLGToDVConfig: Codable, Sendable {
    /// Target Dolby Vision profile.
    public var profile: DVProfileTarget

    /// Maximum Content Light Level in nits.
    public var maxCLL: Int?

    /// Maximum Frame Average Light Level in nits.
    public var maxFALL: Int?

    /// Mastering display max luminance in nits.
    public var maxLuminance: Int

    /// Mastering display min luminance in nits × 10000.
    public var minLuminance: Int

    /// Video encoder.
    public var encoder: String

    /// CRF value for encoding.
    public var crf: Int

    /// Encoder preset.
    public var preset: String

    /// Whether to copy audio/subtitle streams.
    public var passthroughOtherStreams: Bool

    public init(
        profile: DVProfileTarget = .profile84,
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        maxLuminance: Int = 1000,
        minLuminance: Int = 50,
        encoder: String = "libx265",
        crf: Int = 18,
        preset: String = "medium",
        passthroughOtherStreams: Bool = true
    ) {
        self.profile = profile
        self.maxCLL = maxCLL
        self.maxFALL = maxFALL
        self.maxLuminance = maxLuminance
        self.minLuminance = minLuminance
        self.encoder = encoder
        self.crf = crf
        self.preset = preset
        self.passthroughOtherStreams = passthroughOtherStreams
    }
}

// MARK: - HLGToDolbyVision

/// Builds multi-step pipelines for HLG → Dolby Vision conversion.
///
/// Supports two main workflows:
///
/// **Profile 8.4 (HLG base + DV RPU)** — recommended:
/// 1. Encode HLG source with correct metadata
/// 2. Generate Profile 8.4 RPU via dovi_tool
/// 3. Extract HEVC elementary stream
/// 4. Inject RPU into HEVC stream
/// 5. Mux back into container with audio/subs
///
/// **Profile 5 (DV only)** — requires DV-capable devices:
/// 1. Convert HLG → PQ via zscale
/// 2. Encode with PQ metadata
/// 3. Generate Profile 5 RPU
/// 4. Extract/inject/mux
///
/// Phase 3 / Issue #246
public struct HLGToDolbyVision: Sendable {

    // MARK: - Profile 8.4 Pipeline (HLG base)

    /// Build FFmpeg arguments to encode HLG source for Profile 8.4.
    ///
    /// Profile 8.4 keeps HLG as the base layer, so encoding preserves
    /// the HLG transfer function. The DV RPU is injected afterwards.
    ///
    /// - Parameters:
    ///   - inputPath: Source HLG video.
    ///   - outputPath: Encoded HLG output.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildProfile84EncodeArguments(
        inputPath: String,
        outputPath: String,
        config: HLGToDVConfig = HLGToDVConfig()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Encoder
        args += ["-c:v", config.encoder]
        args += ["-crf", "\(config.crf)"]
        args += ["-preset", config.preset]

        // 10-bit output
        args += ["-pix_fmt", "yuv420p10le"]

        // Preserve HLG colour metadata
        args += ["-color_primaries", "bt2020"]
        args += ["-color_trc", "arib-std-b67"]
        args += ["-colorspace", "bt2020nc"]
        args += ["-color_range", "tv"]

        // CLL metadata
        if let cll = config.maxCLL, let fall = config.maxFALL {
            args += ["-max_cll", "\(cll),\(fall)"]
        }

        // Audio/subtitle passthrough
        if config.passthroughOtherStreams {
            args += ["-c:a", "copy"]
            args += ["-c:s", "copy"]
        }

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Profile 5 Pipeline (PQ base)

    /// Build FFmpeg arguments to convert HLG → PQ for Profile 5.
    ///
    /// Profile 5 requires PQ (SMPTE ST 2084) as the base layer transfer.
    /// Uses zscale to convert HLG → PQ.
    ///
    /// - Parameters:
    ///   - inputPath: Source HLG video.
    ///   - outputPath: Encoded PQ output.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildProfile5EncodeArguments(
        inputPath: String,
        outputPath: String,
        config: HLGToDVConfig = HLGToDVConfig()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // HLG → PQ conversion filter
        let filter = buildHLGToPQFilter()
        args += ["-vf", filter]

        // Encoder
        args += ["-c:v", config.encoder]
        args += ["-crf", "\(config.crf)"]
        args += ["-preset", config.preset]

        // 10-bit output
        args += ["-pix_fmt", "yuv420p10le"]

        // PQ colour metadata
        args += ["-color_primaries", "bt2020"]
        args += ["-color_trc", "smpte2084"]
        args += ["-colorspace", "bt2020nc"]
        args += ["-color_range", "tv"]

        // CLL metadata
        if let cll = config.maxCLL, let fall = config.maxFALL {
            args += ["-max_cll", "\(cll),\(fall)"]
        }

        // Audio/subtitle passthrough
        if config.passthroughOtherStreams {
            args += ["-c:a", "copy"]
            args += ["-c:s", "copy"]
        }

        args += ["-y", outputPath]

        return args
    }

    /// Build the zscale filter string for HLG → PQ conversion.
    ///
    /// - Returns: FFmpeg video filter string.
    public static func buildHLGToPQFilter() -> String {
        return [
            "zscale=t=linear:npl=100",     // HLG → linear light (100 nits system gamma)
            "format=gbrpf32le",             // High-precision intermediate
            "zscale=t=smpte2084",           // Linear → PQ transfer
            "format=yuv420p10le",           // Output 10-bit 4:2:0
        ].joined(separator: ",")
    }

    // MARK: - RPU Generation

    /// Build dovi_tool arguments to generate RPU for the target profile.
    ///
    /// - Parameters:
    ///   - outputRPUPath: Path for the generated RPU binary.
    ///   - config: Conversion configuration.
    /// - Returns: dovi_tool argument array.
    public static func buildGenerateRPUArguments(
        outputRPUPath: String,
        config: HLGToDVConfig = HLGToDVConfig()
    ) -> [String] {
        var args = ["generate", "-m", config.profile.doviToolMode, "-o", outputRPUPath]
        if let cll = config.maxCLL { args += ["--max-cll", "\(cll)"] }
        if let fall = config.maxFALL { args += ["--max-fall", "\(fall)"] }
        args += ["--max-lum", "\(config.maxLuminance)"]
        args += ["--min-lum", "\(config.minLuminance)"]
        return args
    }

    // MARK: - HEVC Stream Operations

    /// Build FFmpeg arguments to extract HEVC elementary stream.
    ///
    /// - Parameters:
    ///   - inputPath: Container file.
    ///   - outputPath: Raw HEVC output.
    /// - Returns: FFmpeg argument array.
    public static func buildExtractHEVCArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-map", "0:v:0",
            "-c:v", "copy",
            "-bsf:v", "hevc_mp4toannexb",
            "-f", "hevc",
            "-y", outputPath,
        ]
    }

    /// Build dovi_tool arguments to inject RPU into HEVC stream.
    ///
    /// - Parameters:
    ///   - hevcInputPath: HEVC elementary stream.
    ///   - rpuPath: RPU binary.
    ///   - outputPath: Output HEVC with DV RPU.
    /// - Returns: dovi_tool argument array.
    public static func buildInjectRPUArguments(
        hevcInputPath: String,
        rpuPath: String,
        outputPath: String
    ) -> [String] {
        return ["inject-rpu", "-i", hevcInputPath, "--rpu-in", rpuPath, "-o", outputPath]
    }

    /// Build FFmpeg arguments to mux HEVC+RPU back into container.
    ///
    /// - Parameters:
    ///   - hevcPath: HEVC stream with DV RPU injected.
    ///   - originalPath: Original source for audio/subs.
    ///   - outputPath: Final output container.
    /// - Returns: FFmpeg argument array.
    public static func buildMuxArguments(
        hevcPath: String,
        originalPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", hevcPath,
            "-i", originalPath,
            "-map", "0:v",
            "-map", "1:a?",
            "-map", "1:s?",
            "-c", "copy",
            "-strict", "unofficial",
            "-y", outputPath,
        ]
    }

    // MARK: - Pipeline Description

    /// Describe the full pipeline steps for an HLG→DV conversion.
    ///
    /// - Parameter config: Conversion configuration.
    /// - Returns: Ordered list of step descriptions.
    public static func describePipeline(config: HLGToDVConfig) -> [String] {
        var steps: [String] = []

        switch config.profile {
        case .profile84:
            steps.append("1. Encode HLG source with HLG metadata preserved")
            steps.append("2. Generate Dolby Vision Profile 8.4 RPU")
            steps.append("3. Extract HEVC elementary stream")
            steps.append("4. Inject RPU into HEVC stream")
            steps.append("5. Mux back into container with audio/subs")
        case .profile5:
            steps.append("1. Convert HLG → PQ via zscale filter")
            steps.append("2. Encode with PQ/BT.2020 metadata")
            steps.append("3. Generate Dolby Vision Profile 5 RPU")
            steps.append("4. Extract HEVC elementary stream")
            steps.append("5. Inject RPU into HEVC stream")
            steps.append("6. Mux back into container with audio/subs")
        }

        return steps
    }

    // MARK: - Validation

    /// Validate that the encoder supports Dolby Vision output.
    ///
    /// Only HEVC (H.265) encoders can produce Dolby Vision compatible streams.
    ///
    /// - Parameter encoder: FFmpeg encoder name.
    /// - Returns: Array of validation warnings. Empty means valid.
    public static func validateEncoder(_ encoder: String) -> [String] {
        var warnings: [String] = []
        let lower = encoder.lowercased()

        // DV requires HEVC
        let hevcEncoders = ["libx265", "hevc_videotoolbox", "hevc_nvenc", "hevc_qsv", "hevc_amf", "hevc_vaapi"]
        if !hevcEncoders.contains(lower) {
            warnings.append("Dolby Vision requires HEVC encoding — '\(encoder)' is not a supported HEVC encoder")
        }

        return warnings
    }

    /// Validate the complete configuration.
    ///
    /// - Parameter config: Conversion configuration.
    /// - Returns: Array of validation warnings.
    public static func validateConfig(_ config: HLGToDVConfig) -> [String] {
        var warnings = validateEncoder(config.encoder)

        if config.maxLuminance <= 0 {
            warnings.append("Max luminance must be positive")
        }

        if config.minLuminance < 0 {
            warnings.append("Min luminance must be non-negative")
        }

        if config.minLuminance >= config.maxLuminance * 10000 {
            warnings.append("Min luminance should be less than max luminance")
        }

        return warnings
    }
}
