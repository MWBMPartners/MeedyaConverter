// ============================================================================
// MeedyaConverter — WatchFolderManager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - PostProcessingAction

/// Action to take with the source file after successful encoding.
public enum PostProcessingAction: String, Codable, Sendable {
    /// Leave the source file in place (no action).
    case leaveInPlace = "leave"

    /// Move the source to a "completed" subfolder.
    case moveToCompleted = "move"

    /// Delete the source file after successful encoding.
    case deleteSource = "delete"
}

// MARK: - WatchFolderConfig

/// Configuration for a single watch folder.
public struct WatchFolderConfig: Codable, Sendable, Identifiable {
    /// Unique identifier for this watch folder.
    public var id: String

    /// Display name for the watch folder.
    public var name: String

    /// The directory path to monitor.
    public var watchPath: String

    /// The output directory for encoded files.
    /// If nil, output goes to a sibling "output" folder.
    public var outputPath: String?

    /// The encoding profile name to apply.
    public var profileName: String

    /// File extensions to watch for (e.g., ["mkv", "mp4", "avi"]).
    /// Empty means watch all recognised media extensions.
    public var fileExtensions: [String]

    /// Whether to monitor subdirectories recursively.
    public var recursive: Bool

    /// Action to take with source file after encoding.
    public var postAction: PostProcessingAction

    /// Maximum number of concurrent encoding jobs from this folder.
    public var concurrencyLimit: Int

    /// Whether this watch folder is currently active.
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        watchPath: String,
        outputPath: String? = nil,
        profileName: String = "webStandard",
        fileExtensions: [String] = [],
        recursive: Bool = false,
        postAction: PostProcessingAction = .leaveInPlace,
        concurrencyLimit: Int = 1,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.watchPath = watchPath
        self.outputPath = outputPath
        self.profileName = profileName
        self.fileExtensions = fileExtensions
        self.recursive = recursive
        self.postAction = postAction
        self.concurrencyLimit = concurrencyLimit
        self.isActive = isActive
    }

    /// The effective output directory.
    public var effectiveOutputPath: String {
        if let output = outputPath { return output }
        return (watchPath as NSString).appendingPathComponent("output")
    }

    /// Default media file extensions recognised by watch folders.
    public static let defaultMediaExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "wmv", "flv",
        "webm", "ts", "mts", "m2ts", "vob", "mpg", "mpeg",
        "3gp", "ogv", "mxf", "wav", "flac", "aac", "mp3",
        "m4a", "ogg", "opus", "wma", "aiff", "dsd", "dsf",
    ]

    /// Check whether a file should be processed by this watch folder.
    ///
    /// - Parameter filename: The file name (not path) to check.
    /// - Returns: `true` if the file matches the watch criteria.
    public func shouldProcess(filename: String) -> Bool {
        // Skip hidden files and system files
        if filename.hasPrefix(".") { return false }
        let lowered = filename.lowercased()
        if lowered == "thumbs.db" || lowered == "desktop.ini" { return false }

        let ext = (filename as NSString).pathExtension.lowercased()
        if fileExtensions.isEmpty {
            return Self.defaultMediaExtensions.contains(ext)
        }
        return fileExtensions.contains(ext)
    }
}

// MARK: - WatchFolderStatus

/// Runtime status of a watch folder.
public struct WatchFolderStatus: Sendable {
    /// The watch folder configuration ID.
    public var configId: String

    /// Whether the folder is currently being monitored.
    public var isMonitoring: Bool

    /// Number of files successfully processed.
    public var filesProcessed: Int

    /// Number of files currently queued for processing.
    public var filesQueued: Int

    /// Number of files that failed to encode.
    public var filesFailed: Int

    /// Most recent error message (if any).
    public var lastError: String?

    /// Timestamp of the last processed file.
    public var lastProcessedAt: Date?

    public init(
        configId: String,
        isMonitoring: Bool = false,
        filesProcessed: Int = 0,
        filesQueued: Int = 0,
        filesFailed: Int = 0,
        lastError: String? = nil,
        lastProcessedAt: Date? = nil
    ) {
        self.configId = configId
        self.isMonitoring = isMonitoring
        self.filesProcessed = filesProcessed
        self.filesQueued = filesQueued
        self.filesFailed = filesFailed
        self.lastError = lastError
        self.lastProcessedAt = lastProcessedAt
    }
}

// MARK: - FileStabilityChecker

/// Checks whether a file has finished being written to disk.
///
/// Compares file size at two time intervals to determine if the file
/// is still being written. This prevents processing incomplete files
/// from downloads, copy operations, or other transfers.
public struct FileStabilityChecker: Sendable {

    /// Minimum time between stability checks in seconds.
    public static let defaultCheckInterval: TimeInterval = 2.0

    /// Number of consecutive checks that must show the same size.
    public static let requiredStableChecks: Int = 2

    /// Check if a file appears stable (not being written to).
    ///
    /// - Parameter path: The file path to check.
    /// - Returns: The file size in bytes, or nil if the file doesn't exist.
    public static func fileSize(at path: String) -> Int64? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Determine the output path for a processed file.
    ///
    /// - Parameters:
    ///   - inputPath: The source file path.
    ///   - config: The watch folder configuration.
    ///   - outputExtension: The output file extension (e.g., "mp4").
    /// - Returns: The output file path.
    public static func outputPath(
        for inputPath: String,
        config: WatchFolderConfig,
        outputExtension: String = "mp4"
    ) -> String {
        let inputFilename = (inputPath as NSString).lastPathComponent
        let baseName = (inputFilename as NSString).deletingPathExtension
        let outputFilename = "\(baseName).\(outputExtension)"

        let outputDir: String
        if config.recursive {
            // Preserve subdirectory structure
            let watchDir = config.watchPath
            let inputDir = (inputPath as NSString).deletingLastPathComponent
            let relativePath = inputDir.replacingOccurrences(of: watchDir, with: "")
            outputDir = (config.effectiveOutputPath as NSString)
                .appendingPathComponent(relativePath)
        } else {
            outputDir = config.effectiveOutputPath
        }

        return (outputDir as NSString).appendingPathComponent(outputFilename)
    }
}

// MARK: - WatchFolderStore

/// Persists watch folder configurations to JSON.
public struct WatchFolderStore: Sendable {

    /// Encode watch folder configurations to JSON data.
    public static func encode(configs: [WatchFolderConfig]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configs)
    }

    /// Decode watch folder configurations from JSON data.
    public static func decode(from data: Data) throws -> [WatchFolderConfig] {
        let decoder = JSONDecoder()
        return try decoder.decode([WatchFolderConfig].self, from: data)
    }
}
