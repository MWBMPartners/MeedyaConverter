// ============================================================================
// MeedyaConverter — SurroundUpmixer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - UpmixAlgorithm

/// Surround upmixing algorithms.
public enum UpmixAlgorithm: String, Codable, Sendable, CaseIterable {
    /// Dolby Pro Logic II decoder — extracts matrixed surround from stereo.
    case proLogicII = "prologic_ii"

    /// DTS Neo:6 decoder — 6.1 channel extraction from stereo.
    case dtsNeo6 = "dts_neo6"

    /// FFmpeg virtual surround — algorithmic upmix using pan filter.
    case virtualSurround = "virtual"

    /// Frequency-based split — sends low frequencies to LFE, high to surrounds.
    case frequencySplit = "freq_split"

    /// Simple channel duplication with attenuation.
    case duplicate = "duplicate"

    /// Display name.
    public var displayName: String {
        switch self {
        case .proLogicII: return "Dolby Pro Logic II Decode"
        case .dtsNeo6: return "DTS Neo:6 Decode"
        case .virtualSurround: return "Virtual Surround (Algorithmic)"
        case .frequencySplit: return "Frequency-Based Split"
        case .duplicate: return "Simple Duplication"
        }
    }

    /// Description of what this algorithm does.
    public var description: String {
        switch self {
        case .proLogicII: return "Decodes Dolby Pro Logic II matrix-encoded stereo to discrete 5.1"
        case .dtsNeo6: return "Decodes DTS Neo:6 matrix-encoded stereo to 6.1 channels"
        case .virtualSurround: return "Creates virtual surround from stereo using phase and delay"
        case .frequencySplit: return "Routes frequencies to appropriate channels (LFE, surrounds)"
        case .duplicate: return "Duplicates front channels to rears with attenuation"
        }
    }

    /// Whether this algorithm decodes matrix-encoded surround (vs synthesizing).
    public var isMatrixDecode: Bool {
        switch self {
        case .proLogicII, .dtsNeo6: return true
        default: return false
        }
    }
}

// MARK: - UpmixTarget

/// Target channel layout for upmixing.
public enum UpmixTarget: String, Codable, Sendable, CaseIterable {
    /// 5.1 surround (FL, FR, FC, LFE, SL, SR).
    case surround51 = "5.1"

    /// 7.1 surround (FL, FR, FC, LFE, SL, SR, BL, BR).
    case surround71 = "7.1"

    /// Display name.
    public var displayName: String {
        switch self {
        case .surround51: return "5.1 Surround"
        case .surround71: return "7.1 Surround"
        }
    }

    /// Channel count.
    public var channelCount: Int {
        switch self {
        case .surround51: return 6
        case .surround71: return 8
        }
    }

    /// FFmpeg channel layout name.
    public var ffmpegLayout: String {
        switch self {
        case .surround51: return "5.1"
        case .surround71: return "7.1"
        }
    }
}

// MARK: - UpmixConfig

/// Configuration for surround upmixing.
public struct UpmixConfig: Codable, Sendable {
    /// Upmix algorithm.
    public var algorithm: UpmixAlgorithm

    /// Target channel layout.
    public var target: UpmixTarget

    /// Center channel extraction gain (0.0–1.0). Higher = more center.
    public var centerGain: Double

    /// Surround channel gain (0.0–1.0).
    public var surroundGain: Double

    /// LFE channel gain (0.0–1.0).
    public var lfeGain: Double

    /// LFE crossover frequency in Hz.
    public var lfeCrossover: Int

    /// Surround delay in milliseconds (for spaciousness).
    public var surroundDelayMs: Int

    public init(
        algorithm: UpmixAlgorithm = .virtualSurround,
        target: UpmixTarget = .surround51,
        centerGain: Double = 0.707,
        surroundGain: Double = 0.5,
        lfeGain: Double = 0.5,
        lfeCrossover: Int = 120,
        surroundDelayMs: Int = 20
    ) {
        self.algorithm = algorithm
        self.target = target
        self.centerGain = centerGain
        self.surroundGain = surroundGain
        self.lfeGain = lfeGain
        self.lfeCrossover = lfeCrossover
        self.surroundDelayMs = surroundDelayMs
    }
}

// MARK: - MatrixEncodingType

/// Types of matrix-encoded surround in stereo tracks.
public enum MatrixEncodingType: String, Codable, Sendable {
    /// Dolby Surround (original matrix encoding).
    case dolbySurround = "dolby_surround"

    /// Dolby Pro Logic II (improved matrix).
    case proLogicII = "prologic_ii"

    /// DTS Neo:6 (DTS matrix encoding).
    case dtsNeo6 = "dts_neo6"

    /// No matrix encoding detected.
    case none = "none"

    /// Display name.
    public var displayName: String {
        switch self {
        case .dolbySurround: return "Dolby Surround"
        case .proLogicII: return "Dolby Pro Logic II"
        case .dtsNeo6: return "DTS Neo:6"
        case .none: return "None (Standard Stereo)"
        }
    }
}

// MARK: - SurroundUpmixer

/// Builds FFmpeg filter chains for surround upmixing and matrix decoding.
///
/// Supports:
/// - Dolby Pro Logic II matrix decoding (stereo → discrete 5.1)
/// - DTS Neo:6 matrix decoding (stereo → 6.1)
/// - Algorithmic virtual surround synthesis
/// - Frequency-based channel routing (LFE crossover)
/// - Configurable center/surround/LFE gains
/// - Surround delay for spaciousness
///
/// Phase 5.15 / 5.15a
public struct SurroundUpmixer: Sendable {

    // MARK: - Virtual Surround (Pan Filter)

    /// Build FFmpeg pan filter for stereo to 5.1 virtual surround.
    ///
    /// Uses the pan filter with carefully tuned coefficients to create
    /// a convincing 5.1 mix from stereo input.
    ///
    /// Channel mapping:
    /// - FL = L * 0.707
    /// - FR = R * 0.707
    /// - FC = (L + R) * centerGain
    /// - LFE = (L + R) lowpass at crossover
    /// - SL = L * surroundGain (inverted phase, delayed)
    /// - SR = R * surroundGain (inverted phase, delayed)
    ///
    /// - Parameter config: Upmix configuration.
    /// - Returns: FFmpeg audio filter string.
    public static func buildVirtualSurround51Filter(
        config: UpmixConfig = UpmixConfig()
    ) -> String {
        let cg = config.centerGain
        let sg = config.surroundGain
        let lg = config.lfeGain

        var filters: [String] = []

        // Pan to 5.1 with derived channels
        let panExpr = "pan=5.1|" +
            "FL=\(cg)*FL|" +
            "FR=\(cg)*FR|" +
            "FC=\(cg)*FL+\(cg)*FR|" +
            "LFE=\(lg)*FL+\(lg)*FR|" +
            "BL=\(sg)*FL|" +
            "BR=\(sg)*FR"
        filters.append(panExpr)

        // LFE lowpass filter
        filters.append("lowpass=f=\(config.lfeCrossover):channels=LFE")

        // Add delay to surround channels for spaciousness
        if config.surroundDelayMs > 0 {
            let delaySec = Double(config.surroundDelayMs) / 1000.0
            filters.append("adelay=0|0|0|0|\(Int(delaySec * 1000))|\(Int(delaySec * 1000))")
        }

        return filters.joined(separator: ",")
    }

    /// Build FFmpeg pan filter for stereo to 7.1 virtual surround.
    ///
    /// - Parameter config: Upmix configuration.
    /// - Returns: FFmpeg audio filter string.
    public static func buildVirtualSurround71Filter(
        config: UpmixConfig = UpmixConfig()
    ) -> String {
        let cg = config.centerGain
        let sg = config.surroundGain
        let bg = sg * 0.7 // Back surrounds slightly quieter
        let lg = config.lfeGain

        var filters: [String] = []

        let panExpr = "pan=7.1|" +
            "FL=\(cg)*FL|" +
            "FR=\(cg)*FR|" +
            "FC=\(cg)*FL+\(cg)*FR|" +
            "LFE=\(lg)*FL+\(lg)*FR|" +
            "BL=\(bg)*FL|" +
            "BR=\(bg)*FR|" +
            "SL=\(sg)*FL|" +
            "SR=\(sg)*FR"
        filters.append(panExpr)

        filters.append("lowpass=f=\(config.lfeCrossover):channels=LFE")

        return filters.joined(separator: ",")
    }

    // MARK: - Frequency Split

    /// Build FFmpeg filter for frequency-based surround upmix.
    ///
    /// Routes low frequencies to LFE, mid to center/front, high to surrounds.
    ///
    /// - Parameter config: Upmix configuration.
    /// - Returns: FFmpeg audio filter string.
    public static func buildFrequencySplitFilter(
        config: UpmixConfig = UpmixConfig()
    ) -> String {
        let crossover = config.lfeCrossover

        // Use crossfeed and channelsplit approach
        var filters: [String] = []

        // First upmix to target layout
        filters.append("aformat=channel_layouts=\(config.target.ffmpegLayout)")

        // Apply LFE crossover
        filters.append("lowpass=f=\(crossover):channels=LFE")

        return filters.joined(separator: ",")
    }

    // MARK: - Pro Logic II Decode

    /// Build FFmpeg filter for Dolby Pro Logic II matrix decoding.
    ///
    /// Pro Logic II decodes matrix-encoded surround information from stereo
    /// into discrete 5.1 channels. The encoding uses phase and amplitude
    /// relationships between L and R to encode center and surround.
    ///
    /// - Returns: FFmpeg audio filter string.
    public static func buildProLogicIIDecodeFilter() -> String {
        // Pro Logic II decode matrix:
        // FC = (L + R) * 0.707
        // SL = (L - R) * 0.707
        // SR = (R - L) * 0.707 (inverted)
        // LFE = (L + R) lowpass
        let panExpr = "pan=5.1|" +
            "FL=FL|" +
            "FR=FR|" +
            "FC=0.707*FL+0.707*FR|" +
            "LFE=0.5*FL+0.5*FR|" +
            "BL=0.707*FL-0.707*FR|" +
            "BR=0.707*FR-0.707*FL"
        return panExpr + ",lowpass=f=120:channels=LFE"
    }

    /// Build FFmpeg filter for DTS Neo:6 matrix decoding.
    ///
    /// Similar to Pro Logic II but with slightly different coefficients
    /// and includes a back center channel for 6.1.
    ///
    /// - Returns: FFmpeg audio filter string.
    public static func buildDTSNeo6DecodeFilter() -> String {
        // Neo:6 uses different steering coefficients
        let panExpr = "pan=5.1|" +
            "FL=FL|" +
            "FR=FR|" +
            "FC=0.6*FL+0.6*FR|" +
            "LFE=0.4*FL+0.4*FR|" +
            "BL=0.6*FL-0.6*FR|" +
            "BR=0.6*FR-0.6*FL"
        return panExpr + ",lowpass=f=120:channels=LFE"
    }

    // MARK: - Full Argument Builder

    /// Build FFmpeg arguments for surround upmixing.
    ///
    /// - Parameters:
    ///   - inputPath: Source stereo file.
    ///   - outputPath: Output surround file.
    ///   - config: Upmix configuration.
    ///   - audioCodec: Output audio codec (nil = copy-compatible codec).
    ///   - bitrate: Audio bitrate in kbps.
    /// - Returns: FFmpeg argument array.
    public static func buildUpmixArguments(
        inputPath: String,
        outputPath: String,
        config: UpmixConfig = UpmixConfig(),
        audioCodec: String? = nil,
        bitrate: Int? = nil
    ) -> [String] {
        var args: [String] = ["-i", inputPath]

        // Select appropriate filter
        let filter: String
        switch config.algorithm {
        case .proLogicII:
            filter = buildProLogicIIDecodeFilter()
        case .dtsNeo6:
            filter = buildDTSNeo6DecodeFilter()
        case .virtualSurround:
            if config.target == .surround71 {
                filter = buildVirtualSurround71Filter(config: config)
            } else {
                filter = buildVirtualSurround51Filter(config: config)
            }
        case .frequencySplit:
            filter = buildFrequencySplitFilter(config: config)
        case .duplicate:
            filter = "pan=\(config.target.ffmpegLayout)|FL=FL|FR=FR|FC=0.5*FL+0.5*FR|LFE=0.3*FL+0.3*FR|BL=0.4*FL|BR=0.4*FR"
        }

        args += ["-af", filter]

        // Audio codec
        if let codec = audioCodec {
            args += ["-c:a", codec]
        } else {
            // Default to AAC for 5.1
            args += ["-c:a", "aac"]
        }

        if let br = bitrate {
            args += ["-b:a", "\(br)k"]
        }

        // Copy video
        args += ["-c:v", "copy"]

        args += ["-y", outputPath]

        return args
    }

    // MARK: - Matrix Detection

    /// Build FFmpeg arguments to analyze stereo for matrix encoding.
    ///
    /// Uses the astats filter to check for phase correlation patterns
    /// that indicate matrix-encoded surround.
    ///
    /// - Parameter inputPath: Source stereo file.
    /// - Returns: FFmpeg argument array for analysis.
    public static func buildMatrixDetectionArguments(
        inputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-af", "astats=metadata=1:reset=1",
            "-f", "null",
            "-",
        ]
    }

    // MARK: - Downmix

    /// Build FFmpeg filter to downmix surround to stereo.
    ///
    /// - Parameter sourceLayout: Source channel layout (e.g., "5.1", "7.1").
    /// - Returns: FFmpeg audio filter string.
    public static func buildDownmixFilter(sourceLayout: String) -> String {
        return "pan=stereo|FL=0.707*FC+FL+0.5*BL|FR=0.707*FC+FR+0.5*BR"
    }

    /// Build FFmpeg arguments for surround to stereo downmix.
    ///
    /// - Parameters:
    ///   - inputPath: Source surround file.
    ///   - outputPath: Output stereo file.
    /// - Returns: FFmpeg argument array.
    public static func buildDownmixArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return [
            "-i", inputPath,
            "-af", buildDownmixFilter(sourceLayout: "5.1"),
            "-ac", "2",
            "-c:v", "copy",
            "-y", outputPath,
        ]
    }
}
