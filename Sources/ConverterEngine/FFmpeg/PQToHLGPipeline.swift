// ============================================================================
// MeedyaConverter — PQToHLGPipeline
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PQToHLGMethod

/// Methods for converting PQ (SMPTE ST 2084) to HLG (ARIB STD-B67).
public enum PQToHLGMethod: String, Codable, Sendable {
    /// Use hlg-tools (pq2hlg) for high-quality pixel-level conversion.
    /// Requires external hlg-tools binary.
    case hlgTools = "hlg_tools"

    /// Use FFmpeg's built-in zscale filter chain.
    /// Always available, good quality.
    case ffmpegZscale = "ffmpeg_zscale"

    /// Auto-select: use hlg-tools if available, otherwise FFmpeg zscale.
    case auto = "auto"

    /// Display name.
    public var displayName: String {
        switch self {
        case .hlgTools: return "hlg-tools (High Quality)"
        case .ffmpegZscale: return "FFmpeg zscale (Built-in)"
        case .auto: return "Auto (Best Available)"
        }
    }
}

// MARK: - PQToHLGConfig

/// Configuration for PQ to HLG conversion.
public struct PQToHLGConfig: Codable, Sendable {
    /// Conversion method.
    public var method: PQToHLGMethod

    /// Maximum Content Light Level in nits (for tone curve).
    /// Nil means auto-detect from source metadata.
    public var maxCLL: Int?

    /// Maximum Frame Average Light Level in nits.
    public var maxFALL: Int?

    /// Whether to also generate a Dolby Vision RPU (Profile 8.4).
    public var generateDolbyVision: Bool

    /// Video encoder to use.
    public var encoder: String

    /// CRF value for encoding.
    public var crf: Int

    /// Encoder preset (e.g., "medium", "slow").
    public var preset: String

    /// Whether to preserve audio/subtitle streams unchanged.
    public var passthroughOtherStreams: Bool

    public init(
        method: PQToHLGMethod = .auto,
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        generateDolbyVision: Bool = false,
        encoder: String = "libx265",
        crf: Int = 18,
        preset: String = "medium",
        passthroughOtherStreams: Bool = true
    ) {
        self.method = method
        self.maxCLL = maxCLL
        self.maxFALL = maxFALL
        self.generateDolbyVision = generateDolbyVision
        self.encoder = encoder
        self.crf = crf
        self.preset = preset
        self.passthroughOtherStreams = passthroughOtherStreams
    }
}

// MARK: - PQToHLGPipeline

/// Builds multi-step FFmpeg + hlg-tools + dovi_tool pipelines for PQ→HLG conversion.
///
/// Supports two workflows:
///
/// **hlg-tools pipeline** (higher quality):
/// 1. FFmpeg decodes source to raw Y4M pipe
/// 2. pq2hlg converts PQ transfer function to HLG
/// 3. FFmpeg encodes HLG output with correct colour metadata
///
/// **FFmpeg zscale pipeline** (always available):
/// 1. FFmpeg decodes source, applies zscale filter chain for PQ→HLG
/// 2. Encodes with HLG colour metadata
///
/// **Optional DV Profile 8.4 generation** (for PQ→DV+HLG):
/// 1. Extract RPU from source (if DV) or generate new RPU
/// 2. Convert to Profile 8.4 (HLG base)
/// 3. Inject RPU into HLG-encoded stream
///
/// Phase 3 / Issues #254, #255
public struct PQToHLGPipeline: Sendable {

    // MARK: - FFmpeg zscale Method

    /// Build FFmpeg arguments for PQ→HLG using zscale filter.
    ///
    /// - Parameters:
    ///   - inputPath: Source PQ/HDR10 file.
    ///   - outputPath: Output HLG file.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildZscaleArguments(
        inputPath: String,
        outputPath: String,
        config: PQToHLGConfig = PQToHLGConfig()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Video filter: PQ→HLG via zscale
        let filter = buildPQToHLGFilter()
        args += ["-vf", filter]

        // Encoder
        args += ["-c:v", config.encoder]
        args += ["-crf", "\(config.crf)"]
        args += ["-preset", config.preset]

        // 10-bit output required for HLG
        args += ["-pix_fmt", "yuv420p10le"]

        // HLG colour metadata
        args += ["-color_primaries", "bt2020"]
        args += ["-color_trc", "arib-std-b67"]
        args += ["-colorspace", "bt2020nc"]
        args += ["-color_range", "tv"]

        // CLL/FALL if provided
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

    /// Build the zscale filter string for PQ→HLG conversion.
    ///
    /// - Returns: FFmpeg video filter string.
    public static func buildPQToHLGFilter() -> String {
        return [
            "zscale=t=linear:npl=1000",    // PQ → linear light
            "format=gbrpf32le",             // High-precision intermediate
            "zscale=t=arib-std-b67",        // Linear → HLG transfer
            "format=yuv420p10le",           // Output 10-bit 4:2:0
        ].joined(separator: ",")
    }

    // MARK: - hlg-tools Method

    /// Build the decode step: FFmpeg → Y4M pipe for hlg-tools.
    ///
    /// - Parameters:
    ///   - inputPath: Source video.
    ///   - y4mOutputPath: Temporary Y4M file path.
    /// - Returns: FFmpeg argument array.
    public static func buildDecodeToY4MArguments(
        inputPath: String,
        y4mOutputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-pix_fmt", "yuv420p10le",
            "-strict", "-1",
            "-f", "yuv4mpegpipe",
            "-y", y4mOutputPath,
        ]
    }

    /// Build the pq2hlg step arguments.
    ///
    /// - Parameters:
    ///   - y4mInputPath: Input Y4M from decode step.
    ///   - y4mOutputPath: Output Y4M with HLG transfer.
    ///   - maxCLL: Maximum Content Light Level.
    /// - Returns: pq2hlg argument array.
    public static func buildPQ2HLGArguments(
        y4mInputPath: String,
        y4mOutputPath: String,
        maxCLL: Int? = nil
    ) -> [String] {
        var args = ["-i", y4mInputPath, "-o", y4mOutputPath]
        if let cll = maxCLL {
            args += ["--max-cll", "\(cll)"]
        }
        return args
    }

    /// Build the encode step: Y4M → final output with HLG metadata.
    ///
    /// - Parameters:
    ///   - y4mInputPath: HLG Y4M from pq2hlg.
    ///   - originalInputPath: Original source (for audio/subs).
    ///   - outputPath: Final output path.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildEncodeFromY4MArguments(
        y4mInputPath: String,
        originalInputPath: String,
        outputPath: String,
        config: PQToHLGConfig = PQToHLGConfig()
    ) -> [String] {
        var args: [String] = [
            "-i", y4mInputPath,    // HLG video
            "-i", originalInputPath, // Original for audio/subs
        ]

        // Map video from Y4M, audio/subs from original
        args += ["-map", "0:v"]
        args += ["-map", "1:a?"]
        args += ["-map", "1:s?"]

        // Encode video
        args += ["-c:v", config.encoder]
        args += ["-crf", "\(config.crf)"]
        args += ["-preset", config.preset]
        args += ["-pix_fmt", "yuv420p10le"]

        // HLG metadata
        args += ["-color_primaries", "bt2020"]
        args += ["-color_trc", "arib-std-b67"]
        args += ["-colorspace", "bt2020nc"]

        // Passthrough audio/subs
        args += ["-c:a", "copy"]
        args += ["-c:s", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - DV Profile 8.4 Generation

    /// Build dovi_tool arguments to generate a Profile 8.4 RPU.
    ///
    /// Profile 8.4 uses HLG as the base layer with DV enhancement RPU,
    /// providing three-tier fallback: DV → HLG → SDR.
    ///
    /// - Parameters:
    ///   - outputRPUPath: Path for the generated RPU binary.
    ///   - maxCLL: Maximum Content Light Level.
    ///   - maxFALL: Maximum Frame Average Light Level.
    ///   - maxLuminance: Mastering display max luminance.
    ///   - minLuminance: Mastering display min luminance (nits × 10000).
    /// - Returns: dovi_tool argument array.
    public static func buildGenerateProfile84RPUArguments(
        outputRPUPath: String,
        maxCLL: Int? = nil,
        maxFALL: Int? = nil,
        maxLuminance: Int? = nil,
        minLuminance: Int? = nil
    ) -> [String] {
        var args = ["generate", "-m", "4", "-o", outputRPUPath]
        if let maxL = maxLuminance { args += ["--max-lum", "\(maxL)"] }
        if let minL = minLuminance { args += ["--min-lum", "\(minL)"] }
        if let cll = maxCLL { args += ["--max-cll", "\(cll)"] }
        if let fall = maxFALL { args += ["--max-fall", "\(fall)"] }
        return args
    }

    /// Build dovi_tool arguments to inject RPU into HEVC stream.
    ///
    /// - Parameters:
    ///   - hevcInputPath: HEVC elementary stream.
    ///   - rpuPath: RPU binary from generation step.
    ///   - outputPath: Output HEVC with DV RPU.
    /// - Returns: dovi_tool argument array.
    public static func buildInjectRPUArguments(
        hevcInputPath: String,
        rpuPath: String,
        outputPath: String
    ) -> [String] {
        return ["inject-rpu", "-i", hevcInputPath, "--rpu-in", rpuPath, "-o", outputPath]
    }

    /// Build FFmpeg arguments to extract HEVC elementary stream.
    ///
    /// Needed before dovi_tool inject-rpu (which operates on raw HEVC).
    ///
    /// - Parameters:
    ///   - inputPath: Container file (MKV, MP4).
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

    /// Build FFmpeg arguments to mux HEVC+RPU back into container.
    ///
    /// - Parameters:
    ///   - hevcPath: HEVC stream with DV RPU injected.
    ///   - originalPath: Original source for audio/subs.
    ///   - outputPath: Final output container.
    /// - Returns: FFmpeg argument array.
    public static func buildMuxDVHLGArguments(
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

    /// Describe the full pipeline steps for a PQ→HLG conversion.
    ///
    /// - Parameter config: Conversion configuration.
    /// - Returns: Ordered list of step descriptions.
    public static func describePipeline(config: PQToHLGConfig) -> [String] {
        var steps: [String] = []

        switch config.method {
        case .hlgTools:
            steps.append("1. Decode source to Y4M (10-bit 4:2:0)")
            steps.append("2. Convert PQ→HLG transfer with pq2hlg")
            steps.append("3. Encode HLG output with \(config.encoder)")
        case .ffmpegZscale:
            steps.append("1. Decode source with PQ→HLG zscale filter chain")
            steps.append("2. Encode HLG output with \(config.encoder)")
        case .auto:
            steps.append("1. Detect hlg-tools availability")
            steps.append("2. Use pq2hlg if available, otherwise zscale filter")
            steps.append("3. Encode HLG output with \(config.encoder)")
        }

        if config.generateDolbyVision {
            steps.append("\(steps.count + 1). Generate Dolby Vision Profile 8.4 RPU")
            steps.append("\(steps.count + 1). Extract HEVC elementary stream")
            steps.append("\(steps.count + 1). Inject RPU into HEVC stream")
            steps.append("\(steps.count + 1). Mux back into container with audio/subs")
        }

        return steps
    }
}
