// ============================================================================
// MeedyaConverter — ETAPredictor (Issue #328)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodeHistoryEntry

/// A single historical encode record used by `ETAPredictor` to build
/// predictive models for future encoding time estimates.
///
/// Each entry captures the key parameters that influence encode speed
/// (codec, preset, resolution, hardware acceleration) alongside the
/// measured input and output durations.
public struct EncodeHistoryEntry: Codable, Sendable, Identifiable {

    /// Unique identifier for this history entry.
    public let id: UUID

    /// The video codec used (e.g., "h265", "av1").
    public let codec: String

    /// The encoder preset used (e.g., "medium", "slow").
    public let preset: String

    /// The output resolution label (e.g., "1920x1080", "3840x2160").
    public let resolution: String

    /// The source media duration in seconds.
    public let inputDuration: TimeInterval

    /// The wall-clock encoding duration in seconds.
    public let encodeDuration: TimeInterval

    /// Whether hardware acceleration was used for this encode.
    public let hardwareAccelerated: Bool

    /// Timestamp when this encode was completed.
    public let date: Date

    public init(
        id: UUID = UUID(),
        codec: String,
        preset: String,
        resolution: String,
        inputDuration: TimeInterval,
        encodeDuration: TimeInterval,
        hardwareAccelerated: Bool,
        date: Date = Date()
    ) {
        self.id = id
        self.codec = codec
        self.preset = preset
        self.resolution = resolution
        self.inputDuration = inputDuration
        self.encodeDuration = encodeDuration
        self.hardwareAccelerated = hardwareAccelerated
        self.date = date
    }

    /// The speed factor for this encode (input duration / encode duration).
    /// A value of 2.0 means encoding ran at 2x real-time speed.
    public var speedFactor: Double {
        guard encodeDuration > 0 else { return 0 }
        return inputDuration / encodeDuration
    }
}

// MARK: - ETAPrediction

/// The result of an ETA prediction, including the estimated wall-clock
/// seconds and a confidence score indicating prediction reliability.
public struct ETAPrediction: Sendable {

    /// Estimated wall-clock encoding time in seconds.
    public let estimate: TimeInterval

    /// Confidence level from 0.0 (no confidence) to 1.0 (high confidence).
    /// Based on the number of matching historical data points.
    public let confidence: Double

    public init(estimate: TimeInterval, confidence: Double) {
        self.estimate = estimate
        self.confidence = confidence
    }
}

// MARK: - ETAPredictor

/// Predicts encoding ETA based on historical encode performance data.
///
/// `ETAPredictor` persists a rolling history of completed encodes to a
/// JSON file in the app's Application Support directory. When asked to
/// predict the ETA for a new encode, it finds similar past encodes
/// (matching codec, preset, resolution, and hardware-acceleration flag)
/// and computes a weighted average of their speed factors.
///
/// Thread safety is provided by an internal `NSLock` — the class is
/// marked `@unchecked Sendable` because it manages its own locking.
///
/// ## Capacity
/// The history store retains a maximum of 1,000 entries. When the limit
/// is reached, the oldest entries are evicted in FIFO order.
public final class ETAPredictor: @unchecked Sendable {

    // MARK: - Constants

    /// Maximum number of history entries retained before FIFO eviction.
    private static let maxEntries = 1_000

    /// The file name used for persisted history data.
    private static let historyFileName = "encode_history.json"

    // MARK: - State

    /// The in-memory history buffer, loaded from disk on init.
    private var entries: [EncodeHistoryEntry]

    /// Lock for thread-safe access to `entries`.
    private let lock = NSLock()

    /// The URL of the persisted history JSON file.
    private let storageURL: URL

    // MARK: - Initialisation

    /// Creates an `ETAPredictor` that loads and persists history at the
    /// given directory URL. Defaults to the app's Application Support folder.
    ///
    /// - Parameter directory: The directory in which to store `encode_history.json`.
    ///   When `nil`, the standard Application Support directory is used.
    public init(directory: URL? = nil) {
        let baseDir: URL
        if let directory {
            baseDir = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseDir = appSupport.appendingPathComponent("MeedyaConverter", isDirectory: true)
        }

        self.storageURL = baseDir.appendingPathComponent(Self.historyFileName)

        // Load existing history from disk.
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([EncodeHistoryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    // MARK: - Recording

    /// Record a completed encode so future predictions can reference it.
    ///
    /// If the history exceeds `maxEntries`, the oldest entries are evicted
    /// in FIFO order. The updated history is persisted to disk.
    ///
    /// - Parameter entry: The completed encode's performance data.
    public func recordEncode(_ entry: EncodeHistoryEntry) {
        lock.lock()
        defer { lock.unlock() }

        entries.append(entry)

        // FIFO eviction: drop oldest entries when over capacity.
        if entries.count > Self.maxEntries {
            let overflow = entries.count - Self.maxEntries
            entries.removeFirst(overflow)
        }

        persistToDisk()
    }

    // MARK: - Prediction

    /// Predict the encoding ETA for a job with the given parameters.
    ///
    /// The predictor searches for historical encodes that match the codec,
    /// preset, resolution, and hardware-acceleration flag. Matching entries
    /// are weighted by recency (newer entries have more influence). The
    /// result is a predicted wall-clock duration and a confidence score.
    ///
    /// - Parameters:
    ///   - codec: Video codec identifier (e.g., "h265").
    ///   - preset: Encoder preset (e.g., "medium").
    ///   - resolution: Output resolution label (e.g., "1920x1080").
    ///   - inputDuration: Source media duration in seconds.
    ///   - hwAccel: Whether hardware encoding will be used.
    /// - Returns: A tuple of `(estimate, confidence)`, or `nil` if no
    ///   matching history exists.
    public func predictETA(
        codec: String,
        preset: String,
        resolution: String,
        inputDuration: TimeInterval,
        hwAccel: Bool
    ) -> ETAPrediction? {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        guard inputDuration > 0 else { return nil }

        // Find entries matching all criteria.
        let exactMatches = snapshot.filter { entry in
            entry.codec == codec
                && entry.preset == preset
                && entry.resolution == resolution
                && entry.hardwareAccelerated == hwAccel
                && entry.speedFactor > 0
        }

        // Broaden to codec + hw if exact matches are insufficient.
        let matches: [EncodeHistoryEntry]
        if exactMatches.count >= 2 {
            matches = exactMatches
        } else {
            let broadMatches = snapshot.filter { entry in
                entry.codec == codec
                    && entry.hardwareAccelerated == hwAccel
                    && entry.speedFactor > 0
            }
            matches = broadMatches.isEmpty ? exactMatches : broadMatches
        }

        guard !matches.isEmpty else { return nil }

        // Compute recency-weighted average speed factor.
        // More recent encodes get higher weight (linear decay).
        let sortedByDate = matches.sorted { $0.date < $1.date }
        var weightedSum: Double = 0
        var totalWeight: Double = 0

        for (index, entry) in sortedByDate.enumerated() {
            let weight = Double(index + 1) // Newer entries have higher index → higher weight.
            weightedSum += entry.speedFactor * weight
            totalWeight += weight
        }

        let averageSpeed = weightedSum / totalWeight
        let estimatedDuration = inputDuration / averageSpeed

        // Confidence: scales with number of matching data points (cap at 1.0).
        // 1 match = 0.2, 5+ matches = 1.0.
        let confidence = min(1.0, Double(matches.count) / 5.0)

        return ETAPrediction(estimate: estimatedDuration, confidence: confidence)
    }

    // MARK: - History Management

    /// The current number of history entries.
    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Returns a copy of all history entries (thread-safe snapshot).
    public var allEntries: [EncodeHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Remove all history entries and delete the persisted file.
    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }

        entries.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Persistence

    /// Write the current entries array to disk as JSON.
    private func persistToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(entries) else { return }

        // Ensure the parent directory exists.
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try? data.write(to: storageURL, options: .atomic)
    }
}
