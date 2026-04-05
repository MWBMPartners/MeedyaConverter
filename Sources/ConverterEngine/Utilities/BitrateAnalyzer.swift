// ============================================================================
// MeedyaConverter — BitrateAnalyzer (Issue #287)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - BitrateDataPoint

/// A single bitrate measurement at a specific point in the media timeline.
///
/// Each data point corresponds to one frame (or aggregated second window)
/// extracted from FFprobe output. The ``frameType`` indicates the picture
/// coding type: "I" (intra), "P" (predicted), or "B" (bi-directional).
public struct BitrateDataPoint: Sendable {

    /// Presentation timestamp in seconds from the start of the stream.
    public let timestamp: TimeInterval

    /// Instantaneous bitrate in bits per second (bps).
    public let bitrate: Double

    /// Frame picture type: "I", "P", "B", or `nil` if unavailable.
    public let frameType: String?

    /// Memberwise initializer.
    public init(timestamp: TimeInterval, bitrate: Double, frameType: String?) {
        self.timestamp = timestamp
        self.bitrate = bitrate
        self.frameType = frameType
    }
}

// MARK: - BitrateAnalysis

/// Aggregated result of a bitrate analysis pass over a media file.
///
/// Contains the per-second data points used for heatmap rendering, plus
/// summary statistics (average, peak, minimum bitrate and total duration).
public struct BitrateAnalysis: Sendable {

    /// Per-second bitrate data points for visualization.
    public let dataPoints: [BitrateDataPoint]

    /// Arithmetic mean bitrate across all data points, in bps.
    public let averageBitrate: Double

    /// Maximum observed bitrate in bps.
    public let peakBitrate: Double

    /// Minimum observed bitrate in bps.
    public let minBitrate: Double

    /// Total media duration in seconds.
    public let duration: TimeInterval

    /// Memberwise initializer.
    public init(
        dataPoints: [BitrateDataPoint],
        averageBitrate: Double,
        peakBitrate: Double,
        minBitrate: Double,
        duration: TimeInterval
    ) {
        self.dataPoints = dataPoints
        self.averageBitrate = averageBitrate
        self.peakBitrate = peakBitrate
        self.minBitrate = minBitrate
        self.duration = duration
    }
}

// MARK: - BitrateAnalyzer

/// Builds FFprobe arguments and parses output to produce a bitrate analysis.
///
/// The analyzer uses a two-step workflow:
/// 1. Build command-line arguments for FFprobe via ``buildAnalysisArguments(inputPath:)``.
/// 2. Parse the resulting CSV output via ``parseProbeOutput(_:)`` to produce
///    a ``BitrateAnalysis`` suitable for heatmap visualization.
///
/// Frame-level packet sizes are aggregated into per-second windows to smooth
/// the bitrate curve and reduce data point count for rendering.
///
/// Phase 11 — Bitrate Heatmap Visualization (Issue #287)
public struct BitrateAnalyzer: Sendable {

    // MARK: - Argument Building

    /// Build FFprobe arguments for extracting per-frame packet sizes.
    ///
    /// The generated command outputs CSV rows with three columns:
    /// `frame,<pkt_pts_time>,<pkt_size>,<pict_type>`. Packet size is in
    /// bytes; the caller converts to bits per second during parsing.
    ///
    /// - Parameter inputPath: Absolute path to the source media file.
    /// - Returns: An array of command-line arguments for FFprobe.
    public static func buildAnalysisArguments(inputPath: String) -> [String] {
        return [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_frames",
            "-show_entries", "frame=pkt_pts_time,pkt_size,pict_type",
            "-of", "csv=p=0",
            inputPath
        ]
    }

    // MARK: - Output Parsing

    /// Parse FFprobe CSV output into a ``BitrateAnalysis``.
    ///
    /// Each CSV line is expected to contain three fields:
    /// `<pkt_pts_time>,<pkt_size_bytes>,<pict_type>`. Lines that cannot
    /// be parsed are silently skipped. Frame-level data is aggregated
    /// into per-second windows: total bytes in each one-second bucket
    /// are multiplied by 8 to yield bits per second.
    ///
    /// - Parameter output: Raw CSV output from FFprobe.
    /// - Returns: A ``BitrateAnalysis`` with per-second data points and summary stats.
    public static func parseProbeOutput(_ output: String) -> BitrateAnalysis {
        // Parse individual frames
        var frames: [(timestamp: Double, bytes: Int, type: String?)] = []

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed.components(separatedBy: ",")
            guard fields.count >= 2 else { continue }

            guard let timestamp = Double(fields[0].trimmingCharacters(in: .whitespaces)),
                  let packetSize = Int(fields[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let pictType: String?
            if fields.count >= 3 {
                let rawType = fields[2].trimmingCharacters(in: .whitespaces)
                pictType = rawType.isEmpty ? nil : rawType
            } else {
                pictType = nil
            }

            frames.append((timestamp: timestamp, bytes: packetSize, type: pictType))
        }

        // Guard against empty input
        guard !frames.isEmpty else {
            return BitrateAnalysis(
                dataPoints: [],
                averageBitrate: 0,
                peakBitrate: 0,
                minBitrate: 0,
                duration: 0
            )
        }

        // Sort by timestamp
        frames.sort { $0.timestamp < $1.timestamp }

        let totalDuration = (frames.last?.timestamp ?? 0) + 0.001

        // Aggregate into per-second buckets
        var buckets: [Int: (totalBytes: Int, dominantType: String?)] = [:]
        for frame in frames {
            let bucketIndex = Int(frame.timestamp)
            var existing = buckets[bucketIndex] ?? (totalBytes: 0, dominantType: nil)
            existing.totalBytes += frame.bytes
            // Use the first frame type encountered in the bucket (typically the I-frame)
            if existing.dominantType == nil {
                existing.dominantType = frame.type
            }
            buckets[bucketIndex] = existing
        }

        // Convert buckets to data points (bits per second)
        let maxBucket = buckets.keys.max() ?? 0
        var dataPoints: [BitrateDataPoint] = []
        for second in 0...maxBucket {
            let bucket = buckets[second]
            let bitrate = Double((bucket?.totalBytes ?? 0) * 8)
            dataPoints.append(BitrateDataPoint(
                timestamp: Double(second),
                bitrate: bitrate,
                frameType: bucket?.dominantType
            ))
        }

        // Compute summary statistics
        let bitrates = dataPoints.map(\.bitrate)
        let totalBitrate = bitrates.reduce(0, +)
        let count = Double(bitrates.count)
        let averageBitrate = count > 0 ? totalBitrate / count : 0
        let peakBitrate = bitrates.max() ?? 0
        let minBitrate = bitrates.min() ?? 0

        return BitrateAnalysis(
            dataPoints: dataPoints,
            averageBitrate: averageBitrate,
            peakBitrate: peakBitrate,
            minBitrate: minBitrate,
            duration: totalDuration
        )
    }
}
