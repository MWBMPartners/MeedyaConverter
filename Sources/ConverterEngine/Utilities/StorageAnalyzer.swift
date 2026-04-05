// ============================================================================
// MeedyaConverter — StorageAnalyzer (Issue #365)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FileAnalysis

/// Analysis result for a single media file discovered during a storage scan.
///
/// Contains the file's metadata (size, codec, resolution, container, HDR status)
/// extracted from the file system and, where available, from media probing.
public struct FileAnalysis: Identifiable, Sendable {

    /// Unique identifier for this analysis entry.
    public let id: UUID

    /// The file system URL of the analysed media file.
    public let url: URL

    /// The file size in bytes.
    public let fileSize: Int64

    /// The detected video codec (e.g., "h265", "av1"), or `nil` if unknown.
    public let codec: String?

    /// The resolution label (e.g., "1920x1080"), or `nil` if unknown.
    public let resolution: String?

    /// The container format (e.g., "mkv", "mp4"), or `nil` if unknown.
    public let container: String?

    /// Whether the file contains HDR content.
    public let hasHDR: Bool

    /// The media duration in seconds, or `nil` if not determined.
    public let duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        url: URL,
        fileSize: Int64,
        codec: String? = nil,
        resolution: String? = nil,
        container: String? = nil,
        hasHDR: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.url = url
        self.fileSize = fileSize
        self.codec = codec
        self.resolution = resolution
        self.container = container
        self.hasHDR = hasHDR
        self.duration = duration
    }

    /// The file name without path components.
    public var fileName: String {
        url.lastPathComponent
    }

    /// Human-readable formatted file size (e.g., "1.5 GB").
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - StorageReport

/// Aggregated storage report for a collection of analysed media files.
///
/// Groups files by codec, resolution, and container format, and provides
/// estimated storage savings for each encoding profile.
public struct StorageReport: Sendable {

    /// Total number of files analysed.
    public let totalFiles: Int

    /// Total size of all analysed files in bytes.
    public let totalSize: Int64

    /// Breakdown by video codec: codec name -> (file count, total bytes).
    public let byCodec: [String: (count: Int, size: Int64)]

    /// Breakdown by resolution: resolution label -> (file count, total bytes).
    public let byResolution: [String: (count: Int, size: Int64)]

    /// Breakdown by container format: container -> (file count, total bytes).
    public let byContainer: [String: (count: Int, size: Int64)]

    /// Estimated storage savings per encoding profile.
    /// Maps profile name to estimated bytes saved (positive = savings).
    public let estimatedSavings: [String: Int64]

    /// Human-readable formatted total size.
    public var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    public init(
        totalFiles: Int,
        totalSize: Int64,
        byCodec: [String: (count: Int, size: Int64)],
        byResolution: [String: (count: Int, size: Int64)],
        byContainer: [String: (count: Int, size: Int64)],
        estimatedSavings: [String: Int64] = [:]
    ) {
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.byCodec = byCodec
        self.byResolution = byResolution
        self.byContainer = byContainer
        self.estimatedSavings = estimatedSavings
    }
}

// MARK: - StorageAnalyzer

/// Scans directories for media files and generates storage utilisation reports.
///
/// The analyser identifies media files by extension, collects file-system
/// metadata (size, container format), and groups results for visual breakdown.
/// It also estimates potential storage savings when re-encoding with a given
/// `EncodingProfile` by leveraging `FileSizeEstimator`.
///
/// All methods are static and `Sendable` — the analyser holds no mutable state.
public struct StorageAnalyzer: Sendable {

    // MARK: - Supported Extensions

    /// File extensions recognised as media files during directory scanning.
    private static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm",
        "ts", "mts", "m2ts", "mpg", "mpeg", "vob", "ogv", "3gp",
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma",
    ]

    // MARK: - Directory Scanning

    /// Scan a directory for media files and return analysis entries.
    ///
    /// The actual file-system enumeration is performed synchronously on a
    /// background thread (via `Task.detached`) because `FileManager`'s
    /// `DirectoryEnumerator` is not available from Swift concurrency contexts.
    ///
    /// - Parameters:
    ///   - url: The root directory URL to scan.
    ///   - recursive: Whether to scan subdirectories. Defaults to `true`.
    /// - Returns: An array of `FileAnalysis` entries for each discovered
    ///   media file.
    public static func scanDirectory(
        at url: URL,
        recursive: Bool = true
    ) async -> [FileAnalysis] {
        // Move the synchronous file-system work off the cooperative pool.
        let scannedURL = url
        let isRecursive = recursive
        let extensions = mediaExtensions

        // Use withCheckedContinuation to bridge synchronous file enumeration
        // into the async world. The file-system work runs on a detached task's
        // thread but the synchronous performScan helper avoids the
        // "unavailable from asynchronous contexts" restriction on
        // NSDirectoryEnumerator by executing inside a nonisolated closure.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = performScan(at: scannedURL, recursive: isRecursive, extensions: extensions)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous helper that enumerates the directory and collects file analyses.
    private static func performScan(
        at url: URL,
        recursive: Bool,
        extensions: Set<String>
    ) -> [FileAnalysis] {
        let fileManager = FileManager.default

        // Determine enumeration options.
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: options
        ) else {
            return []
        }

        var results: [FileAnalysis] = []

        while let fileURL = enumerator.nextObject() as? URL {
            // Filter to media extensions.
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }

            // Verify it is a regular file.
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let container = ext

            // Derive codec and resolution heuristics from file name and extension.
            let codec = inferCodec(from: fileURL)
            let resolution = inferResolution(from: fileURL)
            let hasHDR = inferHDR(from: fileURL)

            let analysis = FileAnalysis(
                url: fileURL,
                fileSize: fileSize,
                codec: codec,
                resolution: resolution,
                container: container,
                hasHDR: hasHDR,
                duration: nil
            )

            results.append(analysis)
        }

        return results
    }

    // MARK: - Report Generation

    /// Generate an aggregated `StorageReport` from a collection of file analyses.
    ///
    /// - Parameter files: The analysed file entries.
    /// - Returns: A `StorageReport` with breakdown by codec, resolution,
    ///   and container format.
    public static func generateReport(files: [FileAnalysis]) -> StorageReport {
        let totalFiles = files.count
        let totalSize = files.reduce(Int64(0)) { $0 + $1.fileSize }

        // Group by codec.
        var byCodec: [String: (count: Int, size: Int64)] = [:]
        for file in files {
            let key = file.codec ?? "Unknown"
            let existing = byCodec[key] ?? (count: 0, size: 0)
            byCodec[key] = (count: existing.count + 1, size: existing.size + file.fileSize)
        }

        // Group by resolution.
        var byResolution: [String: (count: Int, size: Int64)] = [:]
        for file in files {
            let key = file.resolution ?? "Unknown"
            let existing = byResolution[key] ?? (count: 0, size: 0)
            byResolution[key] = (count: existing.count + 1, size: existing.size + file.fileSize)
        }

        // Group by container.
        var byContainer: [String: (count: Int, size: Int64)] = [:]
        for file in files {
            let key = file.container ?? "Unknown"
            let existing = byContainer[key] ?? (count: 0, size: 0)
            byContainer[key] = (count: existing.count + 1, size: existing.size + file.fileSize)
        }

        return StorageReport(
            totalFiles: totalFiles,
            totalSize: totalSize,
            byCodec: byCodec,
            byResolution: byResolution,
            byContainer: byContainer
        )
    }

    // MARK: - Savings Estimation

    /// Estimate total storage savings when re-encoding the given files
    /// with a target encoding profile.
    ///
    /// Uses `FileSizeEstimator` to predict the output size for each file,
    /// then sums the difference between current size and estimated output.
    /// A positive return value indicates bytes saved; negative means the
    /// re-encoded output would be larger.
    ///
    /// - Parameters:
    ///   - files: The analysed media files.
    ///   - targetProfile: The encoding profile to estimate against.
    /// - Returns: Estimated total bytes saved (positive = smaller output).
    public static func estimateSavings(
        files: [FileAnalysis],
        targetProfile: EncodingProfile
    ) -> Int64 {
        var totalSavings: Int64 = 0

        for file in files {
            let duration = file.duration ?? estimateDurationFromSize(
                fileSize: file.fileSize,
                container: file.container
            )

            let estimate = FileSizeEstimator.estimateOutputSize(
                profile: targetProfile,
                duration: duration,
                sourceFileSize: UInt64(file.fileSize)
            )

            let savings = file.fileSize - estimate.estimatedBytes
            totalSavings += savings
        }

        return totalSavings
    }

    // MARK: - Private Helpers

    /// Infer the video codec from the file URL (extension and name heuristics).
    private static func inferCodec(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        // Check for codec hints in the filename.
        if name.contains("h265") || name.contains("hevc") || name.contains("x265") {
            return "h265"
        } else if name.contains("h264") || name.contains("avc") || name.contains("x264") {
            return "h264"
        } else if name.contains("av1") || name.contains("svtav1") {
            return "av1"
        } else if name.contains("vp9") {
            return "vp9"
        }

        // Infer from container extension.
        switch ext {
        case "webm": return "vp9"
        case "ogv":  return "theora"
        case "mp3":  return "mp3"
        case "flac": return "flac"
        case "opus": return "opus"
        default:     return nil
        }
    }

    /// Infer the resolution from filename conventions (e.g., "1080p", "4K").
    private static func inferResolution(from url: URL) -> String? {
        let name = url.lastPathComponent.lowercased()

        if name.contains("2160p") || name.contains("4k") || name.contains("uhd") {
            return "3840x2160"
        } else if name.contains("1440p") || name.contains("2k") {
            return "2560x1440"
        } else if name.contains("1080p") || name.contains("fhd") {
            return "1920x1080"
        } else if name.contains("720p") || name.contains("hd") {
            return "1280x720"
        } else if name.contains("480p") || name.contains("sd") {
            return "854x480"
        }

        return nil
    }

    /// Infer HDR presence from filename conventions.
    private static func inferHDR(from url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.contains("hdr") || name.contains("hdr10") || name.contains("dolby")
            || name.contains("hlg") || name.contains("dv")
    }

    /// Rough duration estimate from file size when no probe data is available.
    /// Assumes an average video bitrate based on container type.
    private static func estimateDurationFromSize(
        fileSize: Int64,
        container: String?
    ) -> TimeInterval {
        // Assume average bitrate of ~5 Mbps for video, ~1 Mbps for audio-only.
        let audioOnlyContainers: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma"]
        let averageBitrate: Double

        if let container, audioOnlyContainers.contains(container) {
            averageBitrate = 1_000_000 // 1 Mbps for audio
        } else {
            averageBitrate = 5_000_000 // 5 Mbps for video
        }

        // duration = file_size_bits / bitrate
        let fileSizeBits = Double(fileSize) * 8.0
        return fileSizeBits / averageBitrate
    }
}
