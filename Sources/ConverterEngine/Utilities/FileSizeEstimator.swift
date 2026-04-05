// ============================================================================
// MeedyaConverter — FileSizeEstimator (Issue #274)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FileSizeEstimate

/// The result of an output file size estimation, including the estimated
/// byte count, confidence level, and formatted display strings.
public struct FileSizeEstimate: Sendable {

    /// Estimated output file size in bytes.
    public let estimatedBytes: Int64

    /// Confidence level of the estimate: "high" for CBR, "medium" for CRF, "low" for passthrough.
    public let confidenceLevel: String

    /// Human-readable formatted file size (e.g., "1.5 GB", "350 MB").
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: estimatedBytes)
    }

    /// Whether the estimated output fits on a single-layer DVD (4.7 GB).
    public var fitsOnDVD: Bool {
        return estimatedBytes <= 4_700_000_000
    }

    /// Whether the estimated output fits on a single-layer Blu-ray disc (25 GB).
    public var fitsOnBluRay: Bool {
        return estimatedBytes <= 25_000_000_000
    }

    public init(estimatedBytes: Int64, confidenceLevel: String) {
        self.estimatedBytes = estimatedBytes
        self.confidenceLevel = confidenceLevel
    }
}

// MARK: - FileSizeEstimator

/// Estimates the output file size for a given encoding profile and source.
///
/// Uses bitrate-based calculation for CBR/CVBR modes, compression-ratio
/// heuristics for CRF mode, and source file size for passthrough.
public struct FileSizeEstimator: Sendable {

    // MARK: - DVD / Blu-ray Constants

    /// Single-layer DVD capacity in bytes (4.7 GB).
    private static let dvdCapacity: Int64 = 4_700_000_000

    /// Single-layer Blu-ray capacity in bytes (25 GB).
    private static let bluRayCapacity: Int64 = 25_000_000_000

    // MARK: - Estimation

    /// Estimate the output file size for a given profile, duration, and source size.
    ///
    /// - Parameters:
    ///   - profile: The encoding profile to estimate for.
    ///   - duration: The media duration in seconds.
    ///   - sourceFileSize: The source file size in bytes (used for passthrough and CRF heuristics).
    /// - Returns: A `FileSizeEstimate` with the predicted size and confidence.
    public static func estimateOutputSize(
        profile: EncodingProfile,
        duration: TimeInterval,
        sourceFileSize: UInt64?
    ) -> FileSizeEstimate {
        guard duration > 0 else {
            return FileSizeEstimate(estimatedBytes: 0, confidenceLevel: "low")
        }

        // Passthrough: estimate equals source file size
        if profile.videoPassthrough && profile.audioPassthrough {
            let estimate = Int64(sourceFileSize ?? 0)
            return FileSizeEstimate(estimatedBytes: estimate, confidenceLevel: "low")
        }

        // CBR / CVBR: calculate from bitrates
        if let videoBitrate = profile.videoBitrate {
            let videoBitsPerSecond = Int64(videoBitrate)
            let audioBitsPerSecond = Int64(profile.audioBitrate ?? 128_000)

            let totalBitsPerSecond = videoBitsPerSecond + audioBitsPerSecond
            let totalBytes = (totalBitsPerSecond * Int64(duration)) / 8

            // Add ~2% overhead for container metadata and headers
            let withOverhead = Int64(Double(totalBytes) * 1.02)
            return FileSizeEstimate(estimatedBytes: withOverhead, confidenceLevel: "high")
        }

        // CRF: estimate based on source size and compression ratio heuristic
        if let crf = profile.videoCRF, let sourceSize = sourceFileSize {
            let ratio = compressionRatioForCRF(crf, codec: profile.videoCodec)
            let videoEstimate = Int64(Double(sourceSize) * ratio)

            // Add audio estimate if not passthrough
            let audioBytesEstimate: Int64
            if profile.audioPassthrough {
                // Rough estimate: audio is typically 5-10% of source
                audioBytesEstimate = Int64(Double(sourceSize) * 0.05)
            } else {
                let audioBps = Int64(profile.audioBitrate ?? 128_000)
                audioBytesEstimate = (audioBps * Int64(duration)) / 8
            }

            let total = videoEstimate + audioBytesEstimate
            return FileSizeEstimate(estimatedBytes: total, confidenceLevel: "medium")
        }

        // Fallback: rough estimate from source size
        if let sourceSize = sourceFileSize {
            return FileSizeEstimate(estimatedBytes: Int64(Double(sourceSize) * 0.6), confidenceLevel: "low")
        }

        return FileSizeEstimate(estimatedBytes: 0, confidenceLevel: "low")
    }

    // MARK: - CRF Compression Heuristic

    /// Estimate a compression ratio based on CRF value and codec.
    ///
    /// Lower CRF values produce larger files (less compression).
    /// These are rough heuristics — actual results vary by content complexity.
    ///
    /// - Parameters:
    ///   - crf: The CRF value (typically 0–51).
    ///   - codec: The video codec being used.
    /// - Returns: An estimated ratio of output size to source size (0.0–1.0+).
    private static func compressionRatioForCRF(_ crf: Int, codec: VideoCodec?) -> Double {
        // Base ratio curve: CRF 18 ≈ 80%, CRF 23 ≈ 50%, CRF 28 ≈ 30%, CRF 35 ≈ 15%
        let baseRatio: Double
        switch crf {
        case ..<15:
            baseRatio = 1.0
        case 15..<18:
            baseRatio = 0.85
        case 18..<21:
            baseRatio = 0.65
        case 21..<24:
            baseRatio = 0.50
        case 24..<28:
            baseRatio = 0.35
        case 28..<32:
            baseRatio = 0.25
        case 32..<36:
            baseRatio = 0.15
        default:
            baseRatio = 0.10
        }

        // Codec efficiency multiplier (H.265/AV1 compress more than H.264)
        let codecMultiplier: Double
        switch codec {
        case .h264:
            codecMultiplier = 1.4
        case .h265:
            codecMultiplier = 1.0
        case .av1:
            codecMultiplier = 0.85
        case .vp9:
            codecMultiplier = 1.05
        default:
            codecMultiplier = 1.0
        }

        return baseRatio * codecMultiplier
    }
}
