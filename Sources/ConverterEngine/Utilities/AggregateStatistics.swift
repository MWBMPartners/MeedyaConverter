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
//   - `StatisticsTracker`: A thread-safe, JSON-persisted singleton that
//     records each completed encode and exposes the running totals.
//
// Storage: ~/Library/Application Support/MeedyaConverter/statistics.json
//
// Phase 11 — Dashboard Statistics (Issue #284)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - EncodingStats

/// Aggregate encoding statistics accumulated across all encoding jobs.
///
/// Persisted as JSON by `StatisticsTracker` and displayed in the
/// `DashboardView`. All properties are `Codable` and `Sendable` for
/// safe cross-isolation transfer.
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

// MARK: - StatisticsTracker

/// Thread-safe tracker that persists aggregate encoding statistics to disk.
///
/// Uses `NSLock` for synchronisation and writes to
/// `~/Library/Application Support/MeedyaConverter/statistics.json`.
///
/// Usage:
/// ```swift
/// let tracker = StatisticsTracker.shared
/// tracker.recordEncode(
///     codec: "H.265 / HEVC",
///     container: "mkv",
///     profile: "Web Standard",
///     inputSize: 4_000_000_000,
///     outputSize: 1_200_000_000,
///     duration: 342.5,
///     success: true
/// )
/// let stats = tracker.currentStats()
/// ```
///
/// Phase 11 — Dashboard Statistics (Issue #284)
public final class StatisticsTracker: @unchecked Sendable {

    // MARK: - Shared Instance

    /// The shared singleton tracker.
    public static let shared = StatisticsTracker()

    // MARK: - Properties

    /// The running aggregate statistics.
    private var stats: EncodingStats

    /// Serial lock for thread-safe read/write access.
    private let lock = NSLock()

    /// File URL where the JSON statistics file is persisted.
    private let storageURL: URL

    // MARK: - Initialiser

    /// Creates a tracker backed by the given storage directory.
    ///
    /// - Parameter storageDirectory: The directory for the statistics JSON
    ///   file. Defaults to `~/Library/Application Support/MeedyaConverter/`.
    public init(storageDirectory: URL? = nil) {
        let baseDir = storageDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("MeedyaConverter")
        self.storageURL = baseDir.appendingPathComponent("statistics.json")
        self.stats = EncodingStats()
        loadStats()
    }

    // MARK: - Public API

    /// Record the result of a completed encoding job.
    ///
    /// - Parameters:
    ///   - codec: The display name of the video codec used (e.g. "H.265 / HEVC").
    ///   - container: The output container format (e.g. "mkv", "mp4").
    ///   - profile: The encoding profile name used.
    ///   - inputSize: Size of the source file in bytes.
    ///   - outputSize: Size of the encoded output file in bytes.
    ///   - duration: Wall-clock encoding duration in seconds.
    ///   - success: Whether the encode completed successfully.
    public func recordEncode(
        codec: String,
        container: String,
        profile: String,
        inputSize: Int64,
        outputSize: Int64,
        duration: TimeInterval,
        success: Bool
    ) {
        lock.lock()
        stats.totalEncodes += 1
        if success {
            stats.successfulEncodes += 1
        } else {
            stats.failedEncodes += 1
        }
        stats.totalEncodingTime += duration
        stats.totalInputBytes += inputSize
        stats.totalOutputBytes += outputSize
        stats.codecUsage[codec, default: 0] += 1
        stats.profileUsage[profile, default: 0] += 1
        stats.containerUsage[container, default: 0] += 1
        lock.unlock()

        saveStats()
    }

    /// Returns a snapshot of the current aggregate statistics.
    public func currentStats() -> EncodingStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    /// Resets all statistics to zero and deletes the persisted file.
    public func resetStats() {
        lock.lock()
        stats = EncodingStats()
        lock.unlock()

        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Persistence

    /// Loads statistics from disk. Called once during initialisation.
    private func loadStats() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let loaded = try decoder.decode(EncodingStats.self, from: data)
            lock.lock()
            stats = loaded
            lock.unlock()
        } catch {
            // Corrupt file — start fresh
        }
    }

    /// Writes the current statistics to disk atomically.
    private func saveStats() {
        lock.lock()
        let snapshot = stats
        lock.unlock()

        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Persistence failure is non-fatal
        }
    }
}
