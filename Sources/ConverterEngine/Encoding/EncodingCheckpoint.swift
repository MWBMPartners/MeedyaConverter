// ============================================================================
// MeedyaConverter — EncodingCheckpoint
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - EncodingCheckpoint

/// A snapshot of an in-progress encoding job that can be used to resume
/// after an interruption (crash, power failure, user quit).
///
/// Each checkpoint records the job identity, file paths, profile settings,
/// and the last known good timestamp so that FFmpeg can resume encoding
/// from that point using `-ss` to seek past already-encoded content.
public struct EncodingCheckpoint: Codable, Sendable, Identifiable {

    // MARK: - Properties

    /// The unique identifier of the encoding job this checkpoint belongs to.
    public let jobId: UUID

    /// The source media file URL.
    public let inputURL: URL

    /// The output file URL (partial output may exist on disk).
    public let outputURL: URL

    /// A snapshot of the encoding profile at the time the checkpoint was saved.
    /// Ensures resume uses identical settings even if the profile was later modified.
    public let profileSnapshot: EncodingProfile

    /// The last successfully encoded timestamp (in seconds from start).
    /// FFmpeg can seek to this position to resume encoding.
    public let lastGoodTimestamp: TimeInterval

    /// The fraction of the total encode that was completed (0.0–1.0).
    public let progressFraction: Double

    /// When this checkpoint was created.
    public let createdAt: Date

    /// Conformance to Identifiable via the job ID.
    public var id: UUID { jobId }

    // MARK: - Initialiser

    /// Create a new encoding checkpoint.
    ///
    /// - Parameters:
    ///   - jobId: The unique identifier of the encoding job.
    ///   - inputURL: The source media file URL.
    ///   - outputURL: The output file URL.
    ///   - profileSnapshot: The encoding profile settings at checkpoint time.
    ///   - lastGoodTimestamp: The last successfully encoded timestamp in seconds.
    ///   - progressFraction: The fraction of encoding completed (0.0–1.0).
    ///   - createdAt: When this checkpoint was created. Defaults to now.
    public init(
        jobId: UUID,
        inputURL: URL,
        outputURL: URL,
        profileSnapshot: EncodingProfile,
        lastGoodTimestamp: TimeInterval,
        progressFraction: Double,
        createdAt: Date = Date()
    ) {
        self.jobId = jobId
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.profileSnapshot = profileSnapshot
        self.lastGoodTimestamp = lastGoodTimestamp
        self.progressFraction = progressFraction
        self.createdAt = createdAt
    }
}

// MARK: - CheckpointManager

/// Manages persistence of encoding checkpoints to disk.
///
/// Checkpoints are stored as individual JSON files in the application's
/// support directory under `MeedyaConverter/Checkpoints/`. Each file is
/// named by the job UUID for fast lookup and deletion.
///
/// Thread-safe via an internal lock — safe to call from any thread or actor.
public final class CheckpointManager: @unchecked Sendable {

    // MARK: - Properties

    /// The directory where checkpoint JSON files are stored.
    private let checkpointDirectory: URL

    /// Serial lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Initialiser

    /// Create a checkpoint manager with the given storage directory.
    ///
    /// - Parameter storageDirectory: Directory for checkpoint files.
    ///   Defaults to `Application Support/MeedyaConverter/Checkpoints/`.
    public init(storageDirectory: URL? = nil) {
        let defaultDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("Checkpoints")

        self.checkpointDirectory = storageDirectory ?? defaultDir
    }

    // MARK: - Save

    /// Save a checkpoint to disk as a JSON file.
    ///
    /// Overwrites any existing checkpoint for the same job ID.
    ///
    /// - Parameter checkpoint: The checkpoint to persist.
    /// - Throws: File system or encoding errors.
    public func saveCheckpoint(_ checkpoint: EncodingCheckpoint) throws {
        lock.lock()
        defer { lock.unlock() }

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: checkpointDirectory,
            withIntermediateDirectories: true
        )

        let fileURL = checkpointFileURL(for: checkpoint.jobId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Load

    /// Load a checkpoint for the given job ID, if one exists.
    ///
    /// - Parameter jobId: The job identifier to look up.
    /// - Returns: The checkpoint if found and decodable, or nil.
    public func loadCheckpoint(for jobId: UUID) -> EncodingCheckpoint? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = checkpointFileURL(for: jobId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(EncodingCheckpoint.self, from: data)
        } catch {
            // Corrupted checkpoint — log but don't crash
            print("Warning: Could not load checkpoint \(jobId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - List

    /// List all resumable checkpoints on disk, sorted by creation date (newest first).
    ///
    /// Filters out checkpoints whose source files no longer exist.
    ///
    /// - Returns: An array of valid, resumable checkpoints.
    public func listResumableCheckpoints() -> [EncodingCheckpoint] {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: checkpointDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var checkpoints: [EncodingCheckpoint] = []
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let checkpoint = try? decoder.decode(EncodingCheckpoint.self, from: data) else {
                continue
            }

            // Only include checkpoints whose source file still exists
            if fm.fileExists(atPath: checkpoint.inputURL.path) {
                checkpoints.append(checkpoint)
            }
        }

        // Sort by creation date, newest first
        return checkpoints.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Delete

    /// Delete the checkpoint for a specific job ID.
    ///
    /// - Parameter jobId: The job identifier whose checkpoint should be removed.
    public func deleteCheckpoint(for jobId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = checkpointFileURL(for: jobId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Delete all checkpoint files from disk.
    public func deleteAllCheckpoints() {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: checkpointDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return
        }

        for fileURL in files where fileURL.pathExtension == "json" {
            try? fm.removeItem(at: fileURL)
        }
    }

    // MARK: - Helpers

    /// Construct the file URL for a checkpoint JSON file.
    ///
    /// - Parameter jobId: The job UUID used as the filename.
    /// - Returns: The full file URL including the `.json` extension.
    private func checkpointFileURL(for jobId: UUID) -> URL {
        checkpointDirectory.appendingPathComponent("\(jobId.uuidString).json")
    }
}
