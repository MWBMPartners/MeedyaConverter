// ============================================================================
// MeedyaConverter — TempFileManager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - TempFileManager

/// Manages temporary files created during encoding operations.
///
/// Each encoding job gets a unique subdirectory within the temp base directory.
/// All intermediary files (demuxed streams, multipass logs, filter outputs, etc.)
/// are written within that subdirectory. When a job completes (success or failure),
/// its entire temp directory is deleted automatically.
///
/// The base directory defaults to the OS temp directory but can be overridden
/// by the user to use a fast scratch drive (NVMe, SSD RAID, etc.).
public final class TempFileManager: @unchecked Sendable {

    // MARK: - Properties

    /// The base directory for all temp files.
    /// Defaults to the OS temp directory (managed by the OS, auto-purged).
    public private(set) var baseDirectory: URL

    /// Lock for thread-safe access.
    private let lock = NSLock()

    /// Tracks active job directories for orphan detection.
    private var activeJobs: Set<UUID> = []

    // MARK: - Constants

    /// The subdirectory prefix used to identify MeedyaConverter temp directories.
    private static let jobDirectoryPrefix = "meedya-job-"

    // MARK: - Initialiser

    /// Create a new TempFileManager.
    ///
    /// - Parameter baseDirectory: The root directory for temp files.
    ///   Defaults to the OS temp directory (auto-managed by the OS).
    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.temporaryDirectory
    }

    // MARK: - Job Directory Management

    /// Create a unique temp directory for an encoding job.
    ///
    /// Creates subdirectories for different temp file categories:
    /// - `demux/` — demuxed streams
    /// - `multipass/` — pass analysis logs
    /// - `segments/` — HLS/DASH segments during generation
    /// - `filters/` — intermediate filter outputs (PCM, upmixed audio, etc.)
    ///
    /// - Parameter jobID: The unique identifier for the encoding job.
    /// - Returns: The URL of the created job temp directory.
    /// - Throws: If the directory cannot be created.
    public func createJobDirectory(for jobID: UUID) throws -> URL {
        let jobDir = baseDirectory
            .appendingPathComponent("\(Self.jobDirectoryPrefix)\(jobID.uuidString)")

        let fm = FileManager.default

        // Create the job directory and standard subdirectories
        let subdirs = ["demux", "multipass", "segments", "filters"]
        for subdir in subdirs {
            try fm.createDirectory(
                at: jobDir.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        // Track this job as active
        lock.lock()
        activeJobs.insert(jobID)
        lock.unlock()

        return jobDir
    }

    /// Get the temp directory path for a specific job without creating it.
    ///
    /// - Parameter jobID: The job's unique identifier.
    /// - Returns: The URL where this job's temp files would be stored.
    public func jobDirectory(for jobID: UUID) -> URL {
        return baseDirectory
            .appendingPathComponent("\(Self.jobDirectoryPrefix)\(jobID.uuidString)")
    }

    /// Clean up all temp files for a completed encoding job.
    ///
    /// Deletes the entire job subdirectory and all its contents.
    /// Called automatically when a job finishes (success or failure).
    ///
    /// - Parameter jobID: The job's unique identifier.
    public func cleanupJob(_ jobID: UUID) {
        let jobDir = jobDirectory(for: jobID)
        let fm = FileManager.default

        // Remove the entire job directory tree
        try? fm.removeItem(at: jobDir)

        // Remove from active tracking
        lock.lock()
        activeJobs.remove(jobID)
        lock.unlock()
    }

    /// Detect and clean up orphaned job directories.
    ///
    /// Orphaned directories can occur if the app crashes or is force-quit
    /// during an encoding job. This method finds job directories that are
    /// not tracked as active and removes them.
    ///
    /// - Returns: The number of orphaned directories cleaned up.
    @discardableResult
    public func cleanupOrphanedJobs() -> Int {
        let fm = FileManager.default
        var cleanedCount = 0

        // List all items in the base directory
        guard let contents = try? fm.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return 0
        }

        lock.lock()
        let currentActive = activeJobs
        lock.unlock()

        for item in contents {
            let name = item.lastPathComponent

            // Check if this is a MeedyaConverter job directory
            guard name.hasPrefix(Self.jobDirectoryPrefix) else { continue }

            // Extract the UUID from the directory name
            let uuidStr = String(name.dropFirst(Self.jobDirectoryPrefix.count))
            guard let jobID = UUID(uuidString: uuidStr) else { continue }

            // If this job is not in the active set, it's orphaned
            if !currentActive.contains(jobID) {
                try? fm.removeItem(at: item)
                cleanedCount += 1
            }
        }

        return cleanedCount
    }

    // MARK: - Disk Space Monitoring

    /// Get the available disk space on the temp directory's volume, in bytes.
    ///
    /// - Returns: Available disk space in bytes.
    /// - Throws: If the volume info cannot be read.
    public func availableSpace() throws -> UInt64 {
        let values = try baseDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return UInt64(capacity)
        }

        // Fallback to basic available capacity
        let fallbackValues = try baseDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let capacity = fallbackValues.volumeAvailableCapacity {
            return UInt64(capacity)
        }

        return 0
    }

    /// Get available disk space as a formatted string (e.g., "45.2 GB").
    public var availableSpaceString: String {
        guard let space = try? availableSpace() else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(space))
    }

    /// Check if the temp volume has at least the specified amount of free space.
    ///
    /// - Parameter minimumBytes: The minimum required space in bytes (default: 1 GB).
    /// - Returns: True if sufficient space is available.
    public func hasMinimumSpace(_ minimumBytes: UInt64 = 1_073_741_824) -> Bool {
        guard let available = try? availableSpace() else { return false }
        return available >= minimumBytes
    }

    // MARK: - Configuration

    /// Update the base directory to a new location.
    ///
    /// This does NOT move existing job directories. Only new jobs will use
    /// the new location. Existing jobs continue using their original directory.
    ///
    /// - Parameter directory: The new base directory URL.
    /// - Throws: If the directory does not exist or is not writable.
    public func setBaseDirectory(_ directory: URL) throws {
        let fm = FileManager.default

        // Verify the directory exists and is writable
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(
                domain: "TempFileManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Directory does not exist: \(directory.path)"]
            )
        }

        guard fm.isWritableFile(atPath: directory.path) else {
            throw NSError(
                domain: "TempFileManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Directory is not writable: \(directory.path)"]
            )
        }

        lock.lock()
        baseDirectory = directory
        lock.unlock()
    }

    /// Get the total size of all active job temp directories, in bytes.
    public func totalActiveTempSize() -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0

        lock.lock()
        let jobs = activeJobs
        lock.unlock()

        for jobID in jobs {
            let dir = jobDirectory(for: jobID)
            if let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            ) {
                for case let fileURL as URL in enumerator {
                    if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let size = values.fileSize {
                        total += UInt64(size)
                    }
                }
            }
        }

        return total
    }
}
