// ============================================================================
// MeedyaConverter — AggregateStatistics (Dashboard Stats)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides aggregate encoding statistics for the Dashboard view.
//
//   - `EncodingStats`: A value type that accumulates totals across all
//     encoding jobs (counts, bytes, durations, codec/profile/container usage).
//   - `EncodingStats.init(aggregating:)`: Derives those totals from the
//     per-job history persisted by `EncodingStatisticsStore` — the single
//     source of truth for encoding statistics (Issue #284, re #363). There
//     is no separate tracker or storage file for aggregate stats; they are
//     always computed on demand from `EncodingStatisticsStore.allStatistics`.
//
// Phase 11 — Dashboard Statistics (Issue #284)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - EncodingStats

/// Aggregate encoding statistics accumulated across all encoding jobs.
///
/// Derived on demand via `init(aggregating:)` from the per-job history
/// persisted by `EncodingStatisticsStore` — the single source of truth —
/// and displayed in the `DashboardView`. All properties are `Codable` and
/// `Sendable` for safe cross-isolation transfer.
public struct EncodingStats: Codable, Sendable {

    // MARK: - Counters

    /// Total number of encoding jobs attempted (success + failure).
    public var totalEncodes: Int

    /// Number of encoding jobs that completed successfully.
    public var successfulEncodes: Int

    /// Number of encoding jobs that failed.
    public var failedEncodes: Int

    // MARK: - Cumulative Metrics

    /// Total wall-clock time spent encoding, in seconds.
    public var totalEncodingTime: TimeInterval

    /// Total bytes of all source files processed.
    public var totalInputBytes: Int64

    /// Total bytes of all output files produced.
    public var totalOutputBytes: Int64

    // MARK: - Usage Distributions

    /// Count of encodes per video codec name (e.g. "H.265 / HEVC": 42).
    public var codecUsage: [String: Int]

    /// Count of encodes per encoding profile name.
    public var profileUsage: [String: Int]

    /// Count of encodes per output container format (e.g. "mkv": 15).
    public var containerUsage: [String: Int]

    // MARK: - Computed Properties

    /// Net storage saved across all encodes (input minus output bytes).
    ///
    /// A negative value indicates the output was larger than the input
    /// (can happen with lossless or up-conversion workflows).
    public var storageSaved: Int64 {
        totalInputBytes - totalOutputBytes
    }

    /// Average wall-clock encoding time per job, in seconds.
    ///
    /// Returns `0` when no encodes have been recorded.
    public var averageEncodingTime: TimeInterval {
        guard totalEncodes > 0 else { return 0 }
        return totalEncodingTime / Double(totalEncodes)
    }

    /// Fraction of encodes that succeeded (0.0 ... 1.0).
    ///
    /// Returns `0` when no encodes have been recorded.
    public var successRate: Double {
        guard totalEncodes > 0 else { return 0 }
        return Double(successfulEncodes) / Double(totalEncodes)
    }

    // MARK: - Initialiser

    /// Creates a zeroed-out stats instance.
    public init() {
        self.totalEncodes = 0
        self.successfulEncodes = 0
        self.failedEncodes = 0
        self.totalEncodingTime = 0
        self.totalInputBytes = 0
        self.totalOutputBytes = 0
        self.codecUsage = [:]
        self.profileUsage = [:]
        self.containerUsage = [:]
    }
}

// MARK: - EncodingStats + Aggregation (Issue #284)

extension EncodingStats {
    /// Derives dashboard aggregates from the per-job history persisted by
    /// EncodingStatisticsStore — the single source of truth (Issue #284).
    public init(aggregating history: [EncodingStatistics]) {
        self.init()
        for job in history {
            totalEncodes += 1
            let ok = job.succeeded ?? true   // legacy records were success-only
            if ok {
                successfulEncodes += 1
                totalInputBytes += job.inputFileSize ?? 0
                totalOutputBytes += job.outputFileSize ?? 0
            } else {
                failedEncodes += 1
            }
            totalEncodingTime += job.totalEncodingDuration ?? 0
            if let codec = job.videoCodec { codecUsage[codec, default: 0] += 1 }
            if let profile = job.profileName { profileUsage[profile, default: 0] += 1 }
            if let container = job.containerFormat { containerUsage[container, default: 0] += 1 }
        }
    }
}
