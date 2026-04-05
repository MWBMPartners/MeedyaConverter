// ============================================================================
// MeedyaConverter — QualityMetricsUtility (Issue #291)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - QualityScoreResult
// ---------------------------------------------------------------------------
/// Aggregated quality score result containing VMAF, SSIM, and PSNR values.
///
/// Designed as a lightweight, serialisable summary that can be stored
/// alongside encoding job metadata or displayed in the quality metrics UI.
///
/// Phase 7 — VMAF/SSIM Quality Scoring (Issue #291)
public struct QualityScoreResult: Codable, Sendable, Equatable {

    /// VMAF score (0–100), or `nil` if VMAF was not computed.
    public var vmaf: Double?

    /// SSIM score (0.0–1.0), or `nil` if SSIM was not computed.
    public var ssim: Double?

    /// PSNR score in dB, or `nil` if PSNR was not computed.
    public var psnr: Double?

    /// Per-frame VMAF scores for temporal quality analysis, or `nil`
    /// if per-frame logging was not enabled.
    public var perFrameScores: [Double]?

    // MARK: - Initialisation

    /// Creates a new quality score result.
    ///
    /// - Parameters:
    ///   - vmaf: VMAF score (0–100).
    ///   - ssim: SSIM score (0.0–1.0).
    ///   - psnr: PSNR score in dB.
    ///   - perFrameScores: Optional per-frame VMAF scores.
    public init(
        vmaf: Double? = nil,
        ssim: Double? = nil,
        psnr: Double? = nil,
        perFrameScores: [Double]? = nil
    ) {
        self.vmaf = vmaf
        self.ssim = ssim
        self.psnr = psnr
        self.perFrameScores = perFrameScores
    }

    // MARK: - Quality Assessment

    /// Human-readable quality grade based on all available metrics.
    ///
    /// Returns "Excellent", "Good", "Fair", or "Poor" based on the
    /// highest-priority available metric (VMAF > SSIM > PSNR).
    public var qualityGrade: String {
        if let vmaf {
            if vmaf >= 93 { return "Excellent" }
            if vmaf >= 80 { return "Good" }
            if vmaf >= 60 { return "Fair" }
            return "Poor"
        }
        if let ssim {
            if ssim >= 0.97 { return "Excellent" }
            if ssim >= 0.92 { return "Good" }
            if ssim >= 0.85 { return "Fair" }
            return "Poor"
        }
        if let psnr {
            if psnr >= 40 { return "Excellent" }
            if psnr >= 35 { return "Good" }
            if psnr >= 30 { return "Fair" }
            return "Poor"
        }
        return "Unknown"
    }

    /// Whether all available metrics meet recommended quality thresholds.
    public var meetsRecommendedThresholds: Bool {
        if let vmaf, vmaf < 80 { return false }
        if let ssim, ssim < 0.92 { return false }
        if let psnr, psnr < 35 { return false }
        return true
    }
}

// ---------------------------------------------------------------------------
// MARK: - QualityMetrics
// ---------------------------------------------------------------------------
/// Static utilities for building FFmpeg quality-metric arguments and
/// parsing their output.
///
/// Wraps the FFmpeg `libvmaf`, `ssim`, and `psnr` filter invocations
/// into convenient argument builders, and parses the resulting stderr
/// or log-file output into structured `QualityScoreResult` values.
///
/// ## Usage
///
/// ```swift
/// let args = QualityMetrics.buildVMAFArguments(
///     referencePath: "/path/to/source.mov",
///     distortedPath: "/path/to/encoded.mp4",
///     logPath: "/tmp/vmaf_log.json"
/// )
/// // Execute FFmpeg with `args`, then parse:
/// let score = QualityMetrics.parseVMAFLog("/tmp/vmaf_log.json")
/// ```
///
/// Phase 7 — VMAF/SSIM Quality Scoring (Issue #291)
public struct QualityMetrics: Sendable {

    // MARK: - VMAF Argument Builder

    /// Builds FFmpeg arguments for VMAF quality analysis.
    ///
    /// Constructs a command that reads both the distorted (encoded) and
    /// reference (original) files, applies the `libvmaf` filter, and
    /// optionally writes per-frame scores to a JSON log file.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original (source) video.
    ///   - distortedPath: Path to the encoded (distorted) video.
    ///   - logPath: Path for per-frame JSON log output.
    /// - Returns: An array of FFmpeg arguments (without the `ffmpeg` binary itself).
    public static func buildVMAFArguments(
        referencePath: String,
        distortedPath: String,
        logPath: String
    ) -> [String] {
        var args: [String] = []

        // FFmpeg libvmaf convention: distorted first, reference second
        args += ["-i", distortedPath]
        args += ["-i", referencePath]

        // Build the libvmaf filter string with JSON logging
        let vmafFilter = "[0:v][1:v]libvmaf=log_path=\(logPath):log_fmt=json"
        args += ["-lavfi", vmafFilter]

        // Output to null (we only care about the VMAF score, not re-encoded data)
        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - SSIM Argument Builder

    /// Builds FFmpeg arguments for SSIM quality analysis.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original video.
    ///   - distortedPath: Path to the encoded video.
    /// - Returns: FFmpeg argument array for SSIM computation.
    public static func buildSSIMArguments(
        referencePath: String,
        distortedPath: String
    ) -> [String] {
        var args: [String] = []

        args += ["-i", distortedPath]
        args += ["-i", referencePath]
        args += ["-lavfi", "[0:v][1:v]ssim"]
        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - PSNR Argument Builder

    /// Builds FFmpeg arguments for PSNR quality analysis.
    ///
    /// - Parameters:
    ///   - referencePath: Path to the original video.
    ///   - distortedPath: Path to the encoded video.
    /// - Returns: FFmpeg argument array for PSNR computation.
    public static func buildPSNRArguments(
        referencePath: String,
        distortedPath: String
    ) -> [String] {
        var args: [String] = []

        args += ["-i", distortedPath]
        args += ["-i", referencePath]
        args += ["-lavfi", "[0:v][1:v]psnr"]
        args += ["-f", "null", "-"]

        return args
    }

    // MARK: - VMAF Log Parsing

    /// Parses a VMAF JSON log file into a `QualityScoreResult`.
    ///
    /// The JSON log produced by FFmpeg's `libvmaf` filter contains a
    /// top-level `pooled_metrics` object with the aggregate VMAF score,
    /// and a `frames` array with per-frame scores.
    ///
    /// - Parameter logPath: Path to the JSON log file written by FFmpeg.
    /// - Returns: A `QualityScoreResult` with VMAF and per-frame data,
    ///   or `nil` if the file cannot be read or parsed.
    public static func parseVMAFLog(_ logPath: String) -> QualityScoreResult? {
        guard let data = FileManager.default.contents(atPath: logPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract the aggregate VMAF score from pooled_metrics
        var vmafScore: Double?
        if let pooled = json["pooled_metrics"] as? [String: Any],
           let vmafDict = pooled["vmaf"] as? [String: Any],
           let mean = vmafDict["mean"] as? Double {
            vmafScore = mean
        }

        // Extract per-frame scores from the frames array
        var perFrame: [Double]?
        if let frames = json["frames"] as? [[String: Any]] {
            perFrame = frames.compactMap { frame -> Double? in
                guard let metrics = frame["metrics"] as? [String: Any],
                      let vmaf = metrics["vmaf"] as? Double else {
                    return nil
                }
                return vmaf
            }
        }

        guard vmafScore != nil || perFrame != nil else {
            return nil
        }

        return QualityScoreResult(
            vmaf: vmafScore,
            perFrameScores: perFrame
        )
    }

    // MARK: - SSIM Output Parsing

    /// Parses the aggregate SSIM score from FFmpeg's stderr output.
    ///
    /// FFmpeg prints a line like:
    /// ```
    /// [Parsed_ssim_0 @ 0x...] SSIM Y:0.987 U:0.993 V:0.991 All:0.990 (20.41)
    /// ```
    ///
    /// This method extracts the `All:` value.
    ///
    /// - Parameter output: FFmpeg stderr output containing SSIM results.
    /// - Returns: The aggregate SSIM score, or `nil` if not found.
    public static func parseSSIMOutput(_ output: String) -> Double? {
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

    // MARK: - PSNR Output Parsing

    /// Parses the aggregate PSNR score from FFmpeg's stderr output.
    ///
    /// FFmpeg prints a line like:
    /// ```
    /// [Parsed_psnr_0 @ 0x...] PSNR y:45.12 u:47.23 v:46.34 average:45.90 min:32.12 max:inf
    /// ```
    ///
    /// This method extracts the `average:` value.
    ///
    /// - Parameter output: FFmpeg stderr output containing PSNR results.
    /// - Returns: The average PSNR score in dB, or `nil` if not found.
    public static func parsePSNROutput(_ output: String) -> Double? {
        let lines = output.split(separator: "\n")
        for line in lines {
            guard line.contains("PSNR") && line.contains("average:") else { continue }
            let str = String(line)
            guard let avgRange = str.range(of: "average:") else { continue }
            let afterAvg = str[avgRange.upperBound...]
            let valueStr = afterAvg.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
            return Double(valueStr)
        }
        return nil
    }
}
