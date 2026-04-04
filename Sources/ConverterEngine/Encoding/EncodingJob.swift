// ============================================================================
// MeedyaConverter — EncodingJob (Full Implementation)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import Combine

// MARK: - EncodingJobStatus

/// The current status of an encoding job in the queue.
public enum EncodingJobStatus: String, Codable, Sendable {
    /// Job is waiting in the queue to be processed.
    case queued

    /// Job is currently being encoded.
    case encoding

    /// Job encoding is paused.
    case paused

    /// Job completed successfully.
    case completed

    /// Job failed with an error.
    case failed

    /// Job was cancelled by the user.
    case cancelled
}

// MARK: - EncodingJobConfig

/// Complete configuration for an encoding job — what to encode and how.
///
/// This replaces the placeholder `EncodingJob` from the initial scaffolding
/// and provides the full specification needed by the encoding backend.
public struct EncodingJobConfig: Identifiable, Codable, Sendable {
    /// Unique identifier for this job.
    public let id: UUID

    /// The source media file URL.
    public var inputURL: URL

    /// The output file URL.
    public var outputURL: URL

    /// The encoding profile to use.
    public var profile: EncodingProfile

    /// Optional: specific video stream index to encode (nil = default).
    public var videoStreamIndex: Int?

    /// Optional: specific audio stream index to encode (nil = default).
    public var audioStreamIndex: Int?

    /// Optional: specific subtitle stream index (nil = default).
    public var subtitleStreamIndex: Int?

    /// Whether to map all streams from source.
    public var mapAllStreams: Bool

    /// Additional metadata to embed in the output.
    public var outputMetadata: [String: String]

    /// Per-stream metadata overrides.
    public var streamMetadata: [String: [String: String]]

    /// Custom video filter chain (overrides profile if set).
    public var videoFilterChain: String?

    /// Custom audio filter chain (overrides profile if set).
    public var audioFilterChain: String?

    /// Extra FFmpeg arguments for advanced use.
    public var extraArguments: [String]

    /// Timestamp when this job was created.
    public var createdAt: Date

    /// Priority for queue ordering (higher = processed first).
    public var priority: Int

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        outputURL: URL,
        profile: EncodingProfile,
        videoStreamIndex: Int? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        mapAllStreams: Bool = false,
        outputMetadata: [String: String] = [:],
        streamMetadata: [String: [String: String]] = [:],
        videoFilterChain: String? = nil,
        audioFilterChain: String? = nil,
        extraArguments: [String] = [],
        priority: Int = 0
    ) {
        self.id = id
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.profile = profile
        self.videoStreamIndex = videoStreamIndex
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.mapAllStreams = mapAllStreams
        self.outputMetadata = outputMetadata
        self.streamMetadata = streamMetadata
        self.videoFilterChain = videoFilterChain
        self.audioFilterChain = audioFilterChain
        self.extraArguments = extraArguments
        self.createdAt = Date()
        self.priority = priority
    }

    /// Convert this job config into FFmpeg arguments using the profile.
    public func buildArguments() -> [String] {
        var builder = profile.toArgumentBuilder(inputURL: inputURL, outputURL: outputURL)

        // Apply stream selection overrides
        builder.videoStreamIndex = videoStreamIndex
        builder.audioStreamIndex = audioStreamIndex
        builder.subtitleStreamIndex = subtitleStreamIndex
        builder.mapAllStreams = mapAllStreams

        // Apply metadata
        builder.metadata = outputMetadata
        builder.streamMetadata = streamMetadata

        // Apply filter overrides
        if let vf = videoFilterChain {
            builder.videoFilterChain = vf
        }
        if let af = audioFilterChain {
            builder.audioFilterChain = af
        }

        // Apply extra arguments
        builder.extraArguments = extraArguments

        return builder.build()
    }
}

// MARK: - EncodingJobState

/// Runtime state of a job being processed — tracks progress and timing.
public final class EncodingJobState: ObservableObject, @unchecked Sendable {
    /// The job configuration.
    public let config: EncodingJobConfig

    /// Current status of the job.
    @Published public var status: EncodingJobStatus

    /// Progress fraction (0.0 to 1.0).
    @Published public var progress: Double

    /// Current encoding speed (e.g., 2.5x realtime).
    @Published public var speed: Double?

    /// Estimated time remaining in seconds.
    @Published public var eta: TimeInterval?

    /// Current output bitrate in kbps.
    @Published public var currentBitrate: Double?

    /// Current frame being processed.
    @Published public var currentFrame: Int?

    /// Error message if the job failed.
    @Published public var errorMessage: String?

    /// Timestamp when encoding started.
    public var startedAt: Date?

    /// Timestamp when encoding completed/failed/cancelled.
    public var completedAt: Date?

    /// Path to the job's temp directory.
    public var tempDirectoryURL: URL?

    /// The lock for thread-safe property updates.
    private let lock = NSLock()

    public init(config: EncodingJobConfig) {
        self.config = config
        self.status = .queued
        self.progress = 0.0
    }

    /// Elapsed encoding time in seconds (from start to now or completion).
    public var elapsedTime: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    /// A summary string for display (e.g., "Encoding 45% • 2.5x • ETA 3:25").
    public var summaryString: String {
        switch status {
        case .queued: return "Queued"
        case .encoding:
            let pct = Int(progress * 100)
            var parts = ["\(pct)%"]
            if let spd = speed { parts.append(String(format: "%.1fx", spd)) }
            if let remaining = eta {
                let mins = Int(remaining) / 60
                let secs = Int(remaining) % 60
                parts.append("ETA \(mins):\(String(format: "%02d", secs))")
            }
            return parts.joined(separator: " • ")
        case .paused: return "Paused at \(Int(progress * 100))%"
        case .completed: return "Complete"
        case .failed: return "Failed: \(errorMessage ?? "unknown error")"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - EncodingQueue

/// Manages a queue of encoding jobs for sequential processing.
///
/// Jobs are processed one at a time in priority order (highest first),
/// then by creation time (oldest first). The queue provides add, remove,
/// reorder, and cancel operations.
public final class EncodingQueue: ObservableObject, @unchecked Sendable {

    // MARK: - Properties

    /// All jobs in the queue (in display order).
    @Published public private(set) var jobs: [EncodingJobState] = []

    /// The currently encoding job, if any.
    @Published public var currentJob: EncodingJobState?

    /// Whether the queue is currently processing jobs.
    @Published public private(set) var isProcessing: Bool = false

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    public init() {}

    // MARK: - Queue Management

    /// Add a job to the queue.
    ///
    /// - Parameter config: The encoding job configuration.
    /// - Returns: The created job state for UI binding.
    @discardableResult
    public func addJob(_ config: EncodingJobConfig) -> EncodingJobState {
        let jobState = EncodingJobState(config: config)

        lock.lock()
        jobs.append(jobState)
        // Sort by priority (descending) then creation time (ascending)
        jobs.sort { a, b in
            if a.config.priority != b.config.priority {
                return a.config.priority > b.config.priority
            }
            return a.config.createdAt < b.config.createdAt
        }
        lock.unlock()

        return jobState
    }

    /// Remove a job from the queue by ID.
    /// Running jobs cannot be removed — cancel them first.
    public func removeJob(id: UUID) {
        lock.lock()
        jobs.removeAll { $0.config.id == id && $0.status != .encoding }
        lock.unlock()
    }

    /// Move a job to a different position in the queue.
    public func moveJob(fromIndex: Int, toIndex: Int) {
        lock.lock()
        guard fromIndex >= 0, fromIndex < jobs.count,
              toIndex >= 0, toIndex <= jobs.count else {
            lock.unlock()
            return
        }
        let job = jobs.remove(at: fromIndex)
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        jobs.insert(job, at: min(adjustedIndex, jobs.count))
        lock.unlock()
    }

    /// Cancel a specific job. If it's currently encoding, stops the encode.
    public func cancelJob(id: UUID) {
        lock.lock()
        if let job = jobs.first(where: { $0.config.id == id }) {
            job.status = .cancelled
            job.completedAt = Date()
        }
        lock.unlock()
    }

    /// Cancel all pending (queued) jobs.
    public func cancelAllPending() {
        lock.lock()
        for job in jobs where job.status == .queued {
            job.status = .cancelled
            job.completedAt = Date()
        }
        lock.unlock()
    }

    /// Get the next queued job to process.
    public func nextPendingJob() -> EncodingJobState? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.first { $0.status == .queued }
    }

    /// Clear completed, failed, and cancelled jobs from the queue.
    public func clearFinished() {
        lock.lock()
        jobs.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        lock.unlock()
    }

    // MARK: - Statistics

    /// Number of jobs currently queued (waiting to be processed).
    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return jobs.filter { $0.status == .queued }.count
    }

    /// Number of completed jobs.
    public var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return jobs.filter { $0.status == .completed }.count
    }

    /// Number of failed jobs.
    public var failedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return jobs.filter { $0.status == .failed }.count
    }

    /// Total number of jobs in the queue.
    public var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return jobs.count
    }
}
