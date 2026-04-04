// ============================================================================
// MeedyaConverter — EncodingStatistics
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodingDataPoint

/// A single data point captured during encoding for graphing.
public struct EncodingDataPoint: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let elapsedSeconds: TimeInterval
    public let encodedSeconds: TimeInterval
    public let fps: Double
    public let bitrate: Double?
    public let quantizer: Double?
    public let frameNumber: Int
    public let outputSizeBytes: Int64?
    public let speedFactor: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        elapsedSeconds: TimeInterval,
        encodedSeconds: TimeInterval,
        fps: Double,
        bitrate: Double? = nil,
        quantizer: Double? = nil,
        frameNumber: Int = 0,
        outputSizeBytes: Int64? = nil,
        speedFactor: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.encodedSeconds = encodedSeconds
        self.fps = fps
        self.bitrate = bitrate
        self.quantizer = quantizer
        self.frameNumber = frameNumber
        self.outputSizeBytes = outputSizeBytes
        self.speedFactor = speedFactor
    }
}

// MARK: - EncodingStatistics

/// Accumulated encoding statistics for a single job, suitable for graphing.
///
/// Collects periodic data points during encoding and provides computed
/// statistics for display in charts and summary views.
///
/// Phase 7.4
public struct EncodingStatistics: Codable, Sendable {
    public var jobID: UUID
    public var jobName: String
    public var startTime: Date
    public var endTime: Date?
    public var dataPoints: [EncodingDataPoint]
    public var inputFileSize: Int64?
    public var outputFileSize: Int64?
    public var inputDuration: TimeInterval?
    public var videoCodec: String?
    public var audioCodec: String?
    public var resolution: String?
    public var encodingPasses: Int

    public init(
        jobID: UUID,
        jobName: String,
        startTime: Date = Date(),
        encodingPasses: Int = 1
    ) {
        self.jobID = jobID
        self.jobName = jobName
        self.startTime = startTime
        self.dataPoints = []
        self.encodingPasses = encodingPasses
    }

    /// Add a data point from FFmpeg progress output.
    public mutating func addDataPoint(_ point: EncodingDataPoint) {
        dataPoints.append(point)
    }

    // MARK: - Computed Statistics

    /// Total wall-clock encoding duration.
    public var totalEncodingDuration: TimeInterval? {
        guard let end = endTime else {
            return dataPoints.last?.elapsedSeconds
        }
        return end.timeIntervalSince(startTime)
    }

    /// Average encoding speed in frames per second.
    public var averageFPS: Double {
        guard !dataPoints.isEmpty else { return 0 }
        let totalFPS = dataPoints.reduce(0.0) { $0 + $1.fps }
        return totalFPS / Double(dataPoints.count)
    }

    /// Peak encoding speed in frames per second.
    public var peakFPS: Double {
        dataPoints.map(\.fps).max() ?? 0
    }

    /// Minimum encoding speed in frames per second.
    public var minimumFPS: Double {
        dataPoints.map(\.fps).min() ?? 0
    }

    /// Average bitrate across all data points (kbps).
    public var averageBitrate: Double? {
        let bitrates = dataPoints.compactMap(\.bitrate)
        guard !bitrates.isEmpty else { return nil }
        return bitrates.reduce(0.0, +) / Double(bitrates.count)
    }

    /// Peak bitrate (kbps).
    public var peakBitrate: Double? {
        dataPoints.compactMap(\.bitrate).max()
    }

    /// Average quantizer value.
    public var averageQuantizer: Double? {
        let quantizers = dataPoints.compactMap(\.quantizer)
        guard !quantizers.isEmpty else { return nil }
        return quantizers.reduce(0.0, +) / Double(quantizers.count)
    }

    /// Compression ratio (input size / output size).
    public var compressionRatio: Double? {
        guard let input = inputFileSize, let output = outputFileSize,
              input > 0, output > 0 else { return nil }
        return Double(input) / Double(output)
    }

    /// Space savings as a percentage (0-100).
    public var spaceSavingsPercent: Double? {
        guard let input = inputFileSize, let output = outputFileSize,
              input > 0 else { return nil }
        return (1.0 - Double(output) / Double(input)) * 100.0
    }

    /// Average speed factor (e.g., 2.5x means encoding is 2.5x faster than realtime).
    public var averageSpeedFactor: Double? {
        let speeds = dataPoints.compactMap(\.speedFactor)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0.0, +) / Double(speeds.count)
    }

    /// Estimated time remaining based on current progress and average speed.
    public var estimatedTimeRemaining: TimeInterval? {
        guard let duration = inputDuration,
              let lastPoint = dataPoints.last,
              lastPoint.encodedSeconds > 0 else { return nil }
        let remaining = duration - lastPoint.encodedSeconds
        guard remaining > 0 else { return 0 }
        let elapsed = lastPoint.elapsedSeconds
        let rate = lastPoint.encodedSeconds / elapsed
        guard rate > 0 else { return nil }
        return remaining / rate
    }

    /// FPS data points suitable for time-series graphing.
    public var fpsTimeSeries: [(elapsed: TimeInterval, value: Double)] {
        dataPoints.map { ($0.elapsedSeconds, $0.fps) }
    }

    /// Bitrate data points suitable for time-series graphing.
    public var bitrateTimeSeries: [(elapsed: TimeInterval, value: Double)] {
        dataPoints.compactMap { point in
            guard let bitrate = point.bitrate else { return nil }
            return (point.elapsedSeconds, bitrate)
        }
    }

    /// Output file size growth over time.
    public var fileSizeTimeSeries: [(elapsed: TimeInterval, value: Int64)] {
        dataPoints.compactMap { point in
            guard let size = point.outputSizeBytes else { return nil }
            return (point.elapsedSeconds, size)
        }
    }

    /// Quantizer data points suitable for time-series graphing.
    public var quantizerTimeSeries: [(elapsed: TimeInterval, value: Double)] {
        dataPoints.compactMap { point in
            guard let q = point.quantizer else { return nil }
            return (point.elapsedSeconds, q)
        }
    }
}

// MARK: - EncodingStatisticsCollector

/// Collects encoding statistics from FFmpeg progress output during encoding.
///
/// Thread-safe collector that builds `EncodingStatistics` incrementally
/// from progress callbacks.
public final class EncodingStatisticsCollector: @unchecked Sendable {
    private var statistics: EncodingStatistics
    private let lock = NSLock()
    private let startTime: Date
    private var sampleInterval: TimeInterval
    private var lastSampleTime: Date

    public init(
        jobID: UUID,
        jobName: String,
        sampleInterval: TimeInterval = 1.0
    ) {
        self.startTime = Date()
        self.statistics = EncodingStatistics(
            jobID: jobID,
            jobName: jobName,
            startTime: startTime
        )
        self.sampleInterval = sampleInterval
        self.lastSampleTime = .distantPast
    }

    /// Record a progress update from FFmpeg.
    ///
    /// - Parameters:
    ///   - fps: Current frames per second.
    ///   - bitrate: Current bitrate in kbps (if available).
    ///   - encodedSeconds: Seconds of video encoded so far.
    ///   - quantizer: Current quantizer value (if available).
    ///   - frameNumber: Current frame number.
    ///   - outputSizeBytes: Current output file size.
    ///   - speed: Speed factor (e.g., "2.5x").
    public func recordProgress(
        fps: Double,
        bitrate: Double? = nil,
        encodedSeconds: TimeInterval,
        quantizer: Double? = nil,
        frameNumber: Int = 0,
        outputSizeBytes: Int64? = nil,
        speed: Double? = nil
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastSampleTime) >= sampleInterval else { return }

        let point = EncodingDataPoint(
            elapsedSeconds: now.timeIntervalSince(startTime),
            encodedSeconds: encodedSeconds,
            fps: fps,
            bitrate: bitrate,
            quantizer: quantizer,
            frameNumber: frameNumber,
            outputSizeBytes: outputSizeBytes,
            speedFactor: speed
        )

        lock.lock()
        statistics.addDataPoint(point)
        lastSampleTime = now
        lock.unlock()
    }

    /// Set input file metadata.
    public func setInputMetadata(
        fileSize: Int64?,
        duration: TimeInterval?,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        resolution: String? = nil
    ) {
        lock.lock()
        statistics.inputFileSize = fileSize
        statistics.inputDuration = duration
        statistics.videoCodec = videoCodec
        statistics.audioCodec = audioCodec
        statistics.resolution = resolution
        lock.unlock()
    }

    /// Set the output file size after encoding completes.
    public func setOutputFileSize(_ size: Int64) {
        lock.lock()
        statistics.outputFileSize = size
        lock.unlock()
    }

    /// Mark encoding as complete.
    public func markComplete() {
        lock.lock()
        statistics.endTime = Date()
        lock.unlock()
    }

    /// Get a snapshot of the current statistics.
    public var currentStatistics: EncodingStatistics {
        lock.lock()
        defer { lock.unlock() }
        return statistics
    }
}

// MARK: - EncodingStatisticsStore

/// Persists encoding statistics history for review and comparison.
public final class EncodingStatisticsStore: @unchecked Sendable {
    private var history: [EncodingStatistics] = []
    private let lock = NSLock()
    private let storageURL: URL
    private let maxHistoryCount: Int

    public init(
        directory: URL? = nil,
        maxHistoryCount: Int = 100
    ) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/MeedyaConverter/Statistics")
        self.storageURL = dir.appendingPathComponent("encoding_history.json")
        self.maxHistoryCount = maxHistoryCount
        loadHistory()
    }

    /// Add completed encoding statistics to history.
    public func addStatistics(_ stats: EncodingStatistics) {
        lock.lock()
        history.append(stats)
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }
        lock.unlock()
        saveHistory()
    }

    /// All stored statistics, newest first.
    public var allStatistics: [EncodingStatistics] {
        lock.lock()
        defer { lock.unlock() }
        return history.reversed()
    }

    /// Get statistics for a specific job.
    public func statistics(forJob jobID: UUID) -> EncodingStatistics? {
        lock.lock()
        defer { lock.unlock() }
        return history.first { $0.jobID == jobID }
    }

    /// Export all statistics as JSON.
    public func exportAsJSON() throws -> Data {
        lock.lock()
        let current = history
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(current)
    }

    /// Clear all stored statistics.
    public func clearHistory() {
        lock.lock()
        history.removeAll()
        lock.unlock()
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            lock.lock()
            history = try decoder.decode([EncodingStatistics].self, from: data)
            lock.unlock()
        } catch {
            // Silently ignore corrupt history files
        }
    }

    private func saveHistory() {
        lock.lock()
        let current = history
        lock.unlock()

        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(current)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Persistence failure is non-fatal
        }
    }
}
