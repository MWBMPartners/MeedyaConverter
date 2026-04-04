// ============================================================================
// MeedyaConverter — VVCEncoder
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - VVCPreset

/// VVenc encoding presets, from fastest to slowest.
public enum VVCPreset: String, Codable, Sendable, CaseIterable {
    case faster = "faster"
    case fast = "fast"
    case medium = "medium"
    case slow = "slow"
    case slower = "slower"

    /// Display name.
    public var displayName: String {
        switch self {
        case .faster: return "Faster"
        case .fast: return "Fast"
        case .medium: return "Medium (Default)"
        case .slow: return "Slow"
        case .slower: return "Slower"
        }
    }

    /// Approximate speed relative to HEVC medium preset.
    public var relativeSpeed: String {
        switch self {
        case .faster: return "~2× slower than HEVC medium"
        case .fast: return "~3× slower than HEVC medium"
        case .medium: return "~5× slower than HEVC medium"
        case .slow: return "~8× slower than HEVC medium"
        case .slower: return "~15× slower than HEVC medium"
        }
    }
}

// MARK: - VVCTier

/// VVC tier levels, controlling max bitrate.
public enum VVCTier: String, Codable, Sendable {
    case main = "main"
    case high = "high"

    /// Display name.
    public var displayName: String {
        switch self {
        case .main: return "Main Tier"
        case .high: return "High Tier"
        }
    }
}

// MARK: - VVCConfig

/// Configuration for H.266/VVC encoding via vvenc/libvvenc.
public struct VVCConfig: Codable, Sendable {
    /// Quality factor (QP-based, 0–63). Lower = higher quality.
    /// Typical range: 20–35.
    public var qp: Int

    /// Encoding preset.
    public var preset: VVCPreset

    /// Target bitrate in kbps (nil = QP-based encoding).
    public var bitrate: Int?

    /// VVC tier.
    public var tier: VVCTier

    /// Number of encoding threads (0 = auto).
    public var threads: Int

    /// Whether to enable HDR10 metadata passthrough.
    public var hdr10: Bool

    /// Bit depth (8 or 10).
    public var bitDepth: Int

    /// Whether to enable intra refresh (for low-latency streaming).
    public var intraRefresh: Bool

    /// Maximum GOP size.
    public var gopSize: Int?

    /// Whether to output as MP4 (vs raw VVC bitstream).
    public var outputMP4: Bool

    public init(
        qp: Int = 28,
        preset: VVCPreset = .medium,
        bitrate: Int? = nil,
        tier: VVCTier = .main,
        threads: Int = 0,
        hdr10: Bool = false,
        bitDepth: Int = 10,
        intraRefresh: Bool = false,
        gopSize: Int? = nil,
        outputMP4: Bool = true
    ) {
        self.qp = qp
        self.preset = preset
        self.bitrate = bitrate
        self.tier = tier
        self.threads = threads
        self.hdr10 = hdr10
        self.bitDepth = bitDepth
        self.intraRefresh = intraRefresh
        self.gopSize = gopSize
        self.outputMP4 = outputMP4
    }
}

// MARK: - VVCEncoder

/// Builds FFmpeg arguments for H.266/VVC encoding using libvvenc.
///
/// VVC (Versatile Video Coding / H.266 / MPEG-I Part 3) offers approximately
/// 30-50% bitrate savings over HEVC at equivalent quality. Encoder support
/// is still maturing — vvenc is the primary open-source encoder.
///
/// Key considerations:
/// - Encoding is significantly slower than HEVC (5-15× depending on preset)
/// - Container support is limited: MP4 (via `-strict unofficial`), MKV, TS
/// - Hardware decoding is not yet widely available
/// - HDR10/HLG metadata is supported in the spec
/// - No Dolby Vision support yet in vvenc
///
/// Phase 3 / Issue #242
public struct VVCEncoder: Sendable {

    // MARK: - Encoding Arguments

    /// Build FFmpeg arguments for VVC encoding.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - outputPath: Output file.
    ///   - config: VVC configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildEncodeArguments(
        inputPath: String,
        outputPath: String,
        config: VVCConfig = VVCConfig()
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Encoder
        args += ["-c:v", "libvvenc"]

        // Quality
        if let bitrate = config.bitrate {
            args += ["-b:v", "\(bitrate)k"]
        } else {
            args += ["-qp", "\(config.qp)"]
        }

        // Preset
        args += ["-preset", config.preset.rawValue]

        // Tier
        args += ["-tier", config.tier.rawValue]

        // Threads
        if config.threads > 0 {
            args += ["-threads", "\(config.threads)"]
        }

        // Pixel format
        let pixFmt = config.bitDepth >= 10 ? "yuv420p10le" : "yuv420p"
        args += ["-pix_fmt", pixFmt]

        // GOP
        if let gop = config.gopSize {
            args += ["-g", "\(gop)"]
        }

        // Intra refresh
        if config.intraRefresh {
            args += ["-vvenc-params", "IntraRefreshMode=1"]
        }

        // HDR metadata
        if config.hdr10 {
            args += ["-color_primaries", "bt2020"]
            args += ["-color_trc", "smpte2084"]
            args += ["-colorspace", "bt2020nc"]
            args += ["-color_range", "tv"]
        }

        // Audio passthrough
        args += ["-c:a", "copy"]

        // MP4 requires -strict unofficial for VVC
        if config.outputMP4 || outputPath.hasSuffix(".mp4") || outputPath.hasSuffix(".m4v") {
            args += ["-strict", "unofficial"]
        }

        args += ["-y", outputPath]

        return args
    }

    /// Build vvencapp standalone encoder arguments (non-FFmpeg pipeline).
    ///
    /// Used when piping raw YUV from FFmpeg to vvencapp for maximum control.
    ///
    /// - Parameters:
    ///   - inputPath: Raw YUV input or "-" for stdin pipe.
    ///   - outputPath: Output VVC bitstream.
    ///   - width: Frame width.
    ///   - height: Frame height.
    ///   - frameRate: Frame rate.
    ///   - config: VVC configuration.
    /// - Returns: vvencapp argument array.
    public static func buildVvencAppArguments(
        inputPath: String,
        outputPath: String,
        width: Int,
        height: Int,
        frameRate: Double,
        config: VVCConfig = VVCConfig()
    ) -> [String] {
        var args: [String] = []

        args += ["-i", inputPath]
        args += ["-o", outputPath]
        args += ["-s", "\(width)x\(height)"]
        args += ["-r", "\(Int(frameRate))"]
        args += ["--preset", config.preset.rawValue]
        args += ["--qp", "\(config.qp)"]
        args += ["--tier", config.tier.rawValue]
        args += ["--threads", "\(config.threads)"]

        if config.bitDepth >= 10 {
            args += ["--internal-bitdepth", "10"]
        }

        if let bitrate = config.bitrate {
            args += ["--bitrate", "\(bitrate)"]
        }

        if let gop = config.gopSize {
            args += ["--intraperiod", "\(gop)"]
        }

        if config.hdr10 {
            args += ["--hdr", "hdr10"]
        }

        return args
    }

    /// Build FFmpeg arguments to decode source into raw YUV for vvencapp pipe.
    ///
    /// - Parameters:
    ///   - inputPath: Source video file.
    ///   - config: VVC configuration (for bit depth).
    /// - Returns: FFmpeg argument array for piped output.
    public static func buildDecodeForPipeArguments(
        inputPath: String,
        config: VVCConfig = VVCConfig()
    ) -> [String] {
        let pixFmt = config.bitDepth >= 10 ? "yuv420p10le" : "yuv420p"
        return [
            "-i", inputPath,
            "-f", "rawvideo",
            "-pix_fmt", pixFmt,
            "-"
        ]
    }

    // MARK: - Container Support

    /// VVC container compatibility information.
    public struct ContainerSupport: Sendable {
        /// Container format.
        public var container: String
        /// Whether VVC is supported.
        public var supported: Bool
        /// Whether `-strict unofficial` is needed.
        public var requiresStrict: Bool
        /// Notes.
        public var notes: String

        public init(container: String, supported: Bool, requiresStrict: Bool, notes: String) {
            self.container = container
            self.supported = supported
            self.requiresStrict = requiresStrict
            self.notes = notes
        }
    }

    /// Get VVC container support information.
    ///
    /// - Parameter container: Container format identifier.
    /// - Returns: Support information.
    public static func containerSupport(container: String) -> ContainerSupport {
        switch container.lowercased() {
        case "mp4", "m4v":
            return ContainerSupport(
                container: container,
                supported: true,
                requiresStrict: true,
                notes: "Supported with -strict unofficial in FFmpeg 7.0+"
            )
        case "mkv", "mka":
            return ContainerSupport(
                container: container,
                supported: true,
                requiresStrict: false,
                notes: "Native support in Matroska"
            )
        case "ts", "m2ts":
            return ContainerSupport(
                container: container,
                supported: true,
                requiresStrict: true,
                notes: "Supported in MPEG-TS with experimental muxer"
            )
        case "mov":
            return ContainerSupport(
                container: container,
                supported: false,
                requiresStrict: false,
                notes: "QuickTime MOV does not yet support VVC"
            )
        case "webm":
            return ContainerSupport(
                container: container,
                supported: false,
                requiresStrict: false,
                notes: "WebM does not support VVC"
            )
        default:
            return ContainerSupport(
                container: container,
                supported: false,
                requiresStrict: false,
                notes: "Unknown container — VVC support unlikely"
            )
        }
    }

    /// List all containers with VVC support.
    ///
    /// - Returns: Array of supported container formats.
    public static func supportedContainers() -> [String] {
        return ["mp4", "mkv", "ts"]
    }

    // MARK: - Quality Estimation

    /// Estimate the CRF-equivalent quality for a given VVC QP value.
    ///
    /// VVC QP values roughly map to HEVC CRF with an offset due to
    /// the codec's improved compression efficiency.
    ///
    /// - Parameter qp: VVC QP value.
    /// - Returns: Approximate equivalent HEVC CRF for similar visual quality.
    public static func approximateHEVCEquivalentCRF(qp: Int) -> Int {
        // VVC at QP X gives roughly similar quality to HEVC at CRF (X+4)
        // due to ~30% bitrate savings at the same quality
        return min(51, qp + 4)
    }

    /// Estimate bitrate savings vs HEVC at similar quality.
    ///
    /// - Parameter hevcBitrateKbps: HEVC bitrate in kbps.
    /// - Returns: Estimated VVC bitrate range (min, max) in kbps.
    public static func estimatedBitrateSavings(
        hevcBitrateKbps: Int
    ) -> (min: Int, max: Int) {
        // VVC typically achieves 30-50% savings over HEVC
        let minSaving = Int(Double(hevcBitrateKbps) * 0.50) // 50% of HEVC = 50% saving
        let maxSaving = Int(Double(hevcBitrateKbps) * 0.70) // 70% of HEVC = 30% saving
        return (min: minSaving, max: maxSaving)
    }

    // MARK: - Pipeline Description

    /// Describe the VVC encoding pipeline for the UI.
    ///
    /// - Parameter config: VVC configuration.
    /// - Returns: Ordered list of step descriptions.
    public static func describePipeline(config: VVCConfig) -> [String] {
        var steps: [String] = []

        steps.append("1. Decode source video")

        if config.hdr10 {
            steps.append("2. Preserve HDR10 metadata (BT.2020/PQ)")
        }

        let qualityDesc = config.bitrate != nil
            ? "\(config.bitrate!)kbps target bitrate"
            : "QP \(config.qp)"

        steps.append("\(steps.count + 1). Encode with libvvenc (\(config.preset.displayName), \(qualityDesc))")

        if config.outputMP4 {
            steps.append("\(steps.count + 1). Mux into MP4 container (-strict unofficial)")
        }

        steps.append("\(steps.count + 1). Copy audio streams")

        return steps
    }
}
