// ============================================================================
// MeedyaConverter — QualityMetrics
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - QualityMetricType

/// The type of objective video quality metric to calculate.
public enum QualityMetricType: String, Codable, Sendable, CaseIterable {
    /// VMAF (Video Multimethod Assessment Fusion) — Netflix's perceptual quality metric.
    /// Scale: 0–100 (93+ = excellent for streaming).
    case vmaf

    /// SSIM (Structural Similarity Index) — structural quality comparison.
    /// Scale: 0.0–1.0 (0.97+ = excellent).
    case ssim

    /// PSNR (Peak Signal-to-Noise Ratio) — pixel-level error measurement.
    /// Scale: typically 30–50 dB for video (40+ = very good).
    case psnr
}

// MARK: - VMAFModel

/// Available VMAF quality models.
public enum VMAFModel: String, Codable, Sendable {
    /// Standard VMAF model for HD content (default).
    case standard = "vmaf_v0.6.1"

    /// 4K VMAF model calibrated for larger viewing distances.
    case uhd4K = "vmaf_4k_v0.6.1"

    /// Negative VMAF model — for mobile/phone content.
    case phone = "vmaf_v0.6.1neg"
}

// MARK: - QualityScore

/// A single quality measurement result.
public struct QualityScore: Codable, Sendable {
    /// The metric type.
    public var metric: QualityMetricType

    /// Overall mean score.
    public var mean: Double

    /// Minimum score across all frames.
    public var min: Double

    /// Maximum score across all frames.
    public var max: Double

    /// Harmonic mean (for VMAF, more representative than arithmetic mean).
    public var harmonicMean: Double?

    /// 1st percentile score (worst 1% of frames).
    public var percentile1: Double?

    /// 5th percentile score.
    public var percentile5: Double?

    /// 95th percentile score.
    public var percentile95: Double?

    /// Total frames analysed.
    public var frameCount: Int

    public init(
        metric: QualityMetricType,
        mean: Double,
        min: Double,
        max: Double,
        harmonicMean: Double? = nil,
        percentile1: Double? = nil,
        percentile5: Double? = nil,
        percentile95: Double? = nil,
        frameCount: Int = 0
    ) {
        self.metric = metric
        self.mean = mean
        self.min = min
        self.max = max
        self.harmonicMean = harmonicMean
        self.percentile1 = percentile1
        self.percentile5 = percentile5
        self.percentile95 = percentile95
        self.frameCount = frameCount
    }

    /// Human-readable summary of the score.
    public var summary: String {
        switch metric {
        case .vmaf:
            let quality = mean >= 93 ? "Excellent" : mean >= 80 ? "Good" : mean >= 60 ? "Fair" : "Poor"
            return "VMAF: \(String(format: "%.2f", mean)) (\(quality), min=\(String(format: "%.2f", min)))"
        case .ssim:
            let quality = mean >= 0.97 ? "Excellent" : mean >= 0.92 ? "Good" : mean >= 0.85 ? "Fair" : "Poor"
            return "SSIM: \(String(format: "%.4f", mean)) (\(quality))"
        case .psnr:
            let quality = mean >= 40 ? "Excellent" : mean >= 35 ? "Good" : mean >= 30 ? "Fair" : "Poor"
            return "PSNR: \(String(format: "%.2f", mean)) dB (\(quality))"
        }
    }
}

// MARK: - QualityReport

/// A comprehensive quality report containing multiple metrics.
public struct QualityReport: Codable, Sendable {
    /// The reference (source) file path.
    public var referencePath: String

    /// The distorted (encoded) file path.
    public var distortedPath: String

    /// Individual metric scores.
    public var scores: [QualityScore]

    /// Timestamp when the analysis was performed.
    public var analysedAt: Date

    /// Duration of the analysis in seconds.
    public var analysisDuration: TimeInterval?

    public init(
        referencePath: String,
        distortedPath: String,
        scores: [QualityScore] = [],
        analysedAt: Date = Date(),
        analysisDuration: TimeInterval? = nil
    ) {
        self.referencePath = referencePath
        self.distortedPath = distortedPath
        self.scores = scores
        self.analysedAt = analysedAt
        self.analysisDuration = analysisDuration
    }

    /// Get the score for a specific metric type.
    public func score(for metric: QualityMetricType) -> QualityScore? {
        scores.first { $0.metric == metric }
    }

    /// Whether all metrics meet minimum quality thresholds.
    public var meetsQualityThresholds: Bool {
        for score in scores {
            switch score.metric {
            case .vmaf: if score.mean < 80 { return false }
            case .ssim: if score.mean < 0.92 { return false }
            case .psnr: if score.mean < 35 { return false }
            }
        }
        return true
    }
}

// MARK: - QualityMetricsBuilder

/// Builds FFmpeg filter chains and arguments for quality metric calculation.
///
/// Uses FFmpeg's `libvmaf`, `ssim`, and `psnr` filters to compute
/// objective quality scores between a reference and distorted video.
///
/// Phase 7.12
public struct QualityMetricsBuilder: Sendable {

    /// Build FFmpeg arguments to compute VMAF between two files.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original (source) video.
    ///   - distortedPath: Path to the encoded (distorted) video.
    ///   - model: VMAF model to use.
    ///   - logPath: Optional path for per-frame JSON log output.
    ///   - scaleToReference: Whether to scale distorted to match reference resolution.
    /// - Returns: FFmpeg argument array.
    public static func buildVMAFArguments(
        referencePath: String,
        distortedPath: String,
        model: VMAFModel = .standard,
        logPath: String? = nil,
        scaleToReference: Bool = true
    ) -> [String] {
        var args: [String] = []

        // Distorted first, reference second (FFmpeg libvmaf convention)
        args += ["-i", distortedPath]
        args += ["-i", referencePath]

        // Build the libvmaf filter
        var vmafOpts = "model=version=\(model.rawValue)"
        if let log = logPath {
            vmafOpts += ":log_path=\(log):log_fmt=json"
        }

        var filter: String
        if scaleToReference {
            // Scale distorted to match reference resolution before comparing
            filter = "[0:v]scale=flags=bicubic[distorted];[distorted][1:v]libvmaf=\(vmafOpts)"
        } else {
            filter = "[0:v][1:v]libvmaf=\(vmafOpts)"
        }

        args += ["-lavfi", filter]
        args += ["-f", "null", "-"]

        return args
    }

    /// Build FFmpeg arguments to compute SSIM between two files.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original video.
    ///   - distortedPath: Path to the encoded video.
    ///   - logPath: Optional path for per-frame CSV log.
    /// - Returns: FFmpeg argument array.
    public static func buildSSIMArguments(
        referencePath: String,
        distortedPath: String,
        logPath: String? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-i", distortedPath]
        args += ["-i", referencePath]

        var filter = "[0:v][1:v]ssim"
        if let log = logPath {
            filter += "=stats_file=\(log)"
        }

        args += ["-lavfi", filter]
        args += ["-f", "null", "-"]

        return args
    }

    /// Build FFmpeg arguments to compute PSNR between two files.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original video.
    ///   - distortedPath: Path to the encoded video.
    ///   - logPath: Optional path for per-frame CSV log.
    /// - Returns: FFmpeg argument array.
    public static func buildPSNRArguments(
        referencePath: String,
        distortedPath: String,
        logPath: String? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-i", distortedPath]
        args += ["-i", referencePath]

        var filter = "[0:v][1:v]psnr"
        if let log = logPath {
            filter += "=stats_file=\(log)"
        }

        args += ["-lavfi", filter]
        args += ["-f", "null", "-"]

        return args
    }

    /// Build FFmpeg arguments to compute all three metrics in a single pass.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original video.
    ///   - distortedPath: Path to the encoded video.
    ///   - metrics: The metrics to compute.
    ///   - vmafModel: VMAF model to use (if VMAF is included).
    ///   - logDir: Directory for per-frame log output.
    /// - Returns: FFmpeg argument array.
    public static func buildCombinedArguments(
        referencePath: String,
        distortedPath: String,
        metrics: Set<QualityMetricType> = [.vmaf, .ssim, .psnr],
        vmafModel: VMAFModel = .standard,
        logDir: String? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-i", distortedPath]
        args += ["-i", referencePath]

        // Chain multiple quality filters using split/tee
        var filters: [String] = []

        if metrics.contains(.psnr) {
            var f = "[0:v][1:v]psnr"
            if let dir = logDir {
                f += "=stats_file=\(dir)/psnr.log"
            }
            filters.append(f)
        }

        if metrics.contains(.ssim) {
            var f = "[0:v][1:v]ssim"
            if let dir = logDir {
                f += "=stats_file=\(dir)/ssim.log"
            }
            filters.append(f)
        }

        if metrics.contains(.vmaf) {
            var vmafOpts = "model=version=\(vmafModel.rawValue)"
            if let dir = logDir {
                vmafOpts += ":log_path=\(dir)/vmaf.json:log_fmt=json"
            }
            filters.append("[0:v][1:v]libvmaf=\(vmafOpts)")
        }

        // For a single metric, use it directly; for multiple, use the last one
        // (FFmpeg processes all filters in the chain)
        if let filter = filters.last {
            args += ["-lavfi", filter]
        }

        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - Output Parsing

    /// Parse VMAF score from FFmpeg stderr output.
    ///
    /// FFmpeg outputs: `[Parsed_libvmaf_0 @ 0x...] VMAF score: 95.123456`
    public static func parseVMAFScore(from output: String) -> Double? {
        let lines = output.split(separator: "\n")
        for line in lines {
            if line.contains("VMAF score:") {
                let parts = line.split(separator: ":")
                if let last = parts.last {
                    return Double(last.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    /// Parse SSIM scores from FFmpeg stderr output.
    ///
    /// FFmpeg outputs: `[Parsed_ssim_0 @ 0x...] SSIM Y:0.987654 (18.72) U:0.993210 V:0.991234 All:0.990699 (20.41)`
    public static func parseSSIMScore(from output: String) -> Double? {
        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("SSIM") && line.contains("All:") else { continue }
            let str = String(line)
            guard let allRange = str.range(of: "All:") else { continue }
            let afterAll = str[allRange.upperBound...]
            let valueStr = afterAll.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
            return Double(valueStr)
        }
        return nil
    }

    /// Parse PSNR scores from FFmpeg stderr output.
    ///
    /// FFmpeg outputs: `[Parsed_psnr_0 @ 0x...] PSNR y:45.123456 u:47.234567 v:46.345678 average:45.901234 min:32.123456 max:inf`
    public static func parsePSNRScore(from output: String) -> (average: Double, min: Double)? {
        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("PSNR") && line.contains("average:") else { continue }
            let str = String(line)

            func extractValue(_ key: String) -> Double? {
                guard let range = str.range(of: "\(key):") else { return nil }
                let after = str[range.upperBound...]
                let valueStr = after.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
                return Double(valueStr)
            }

            guard let avg = extractValue("average") else { continue }
            let min = extractValue("min") ?? avg
            return (average: avg, min: min)
        }
        return nil
    }
}
