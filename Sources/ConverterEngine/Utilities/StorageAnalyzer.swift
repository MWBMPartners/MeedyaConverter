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
/// `scanDirectory` produces entries whose codec/resolution/HDR are guessed
/// from the file name (`provenance == .inferredFromFilename`);
/// `probeFiles(_:using:maxConcurrency:progress:)` replaces those guesses
/// with ffprobe data (`.probed`) for every file it can read.
public struct FileAnalysis: Identifiable, Sendable {

    /// How the codec / resolution / HDR / duration fields were obtained.
    public enum Provenance: String, Sendable, Equatable {
        /// Read from the container by ffprobe (`StorageAnalyzer.probeFiles`).
        case probed
        /// Guessed from the file name and extension (`StorageAnalyzer.scanDirectory`);
        /// may be wrong or `nil`. Also what a file keeps when ffprobe cannot read it.
        case inferredFromFilename
    }

    /// Unique identifier for this analysis entry.
    public let id: UUID

    /// The file system URL of the analysed media file.
    public let url: URL

    /// The file size in bytes.
    public let fileSize: Int64

    /// The video codec as ffprobe names it (e.g. "hevc", "h264", "av1"); for
    /// audio-only files the primary audio codec (e.g. "flac"). nil if unknown.
    public let codec: String?

    /// The resolution label (e.g., "1920x1080"), or `nil` if unknown.
    public let resolution: String?

    /// The container format (e.g., "mkv", "mp4"), or `nil` if unknown.
    public let container: String?

    /// Whether the file contains HDR content.
    public let hasHDR: Bool

    /// The media duration in seconds, or `nil` if not determined.
    public let duration: TimeInterval?

    /// How `codec`/`resolution`/`hasHDR`/`duration` were obtained.
    public let provenance: Provenance

    public init(
        id: UUID = UUID(),
        url: URL,
        fileSize: Int64,
        codec: String? = nil,
        resolution: String? = nil,
        container: String? = nil,
        hasHDR: Bool = false,
        duration: TimeInterval? = nil,
        provenance: Provenance
    ) {
        self.id = id
        self.url = url
        self.fileSize = fileSize
        self.codec = codec
        self.resolution = resolution
        self.container = container
        self.hasHDR = hasHDR
        self.duration = duration
        self.provenance = provenance
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

// MARK: - MediaFileProbing

/// Abstraction over "probe one file", so `StorageAnalyzer.probeFiles` can be
/// unit-tested with a mock. `FFmpegProbe` is the production conformer;
/// `StorageAnalysisView.performScan()` passes `FFmpegProbe(ffprobePath:)`
/// resolved via the app's `FFmpegBundleManager`.
public protocol MediaFileProbing: Sendable {
    func analyze(url: URL) async throws -> MediaFile
}

extension FFmpegProbe: MediaFileProbing {}

// MARK: - StorageAnalyzer

/// Scans directories for media files and generates storage utilisation reports.
///
/// Two stages: scanDirectory (file-system facts + file-name guesses, no
/// subprocesses) then probeFiles (real ffprobe through an injected
/// MediaFileProbing, bounded concurrency). StorageAnalysisView.performScan()
/// runs both. estimateSavings estimates re-encode savings from
/// FileSizeEstimator using probed durations when present.
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

    /// Container extensions treated as audio-only. Used both by
    /// `estimateDurationFromSize` (bitrate assumption) and by
    /// `analysis(from:base:)` (to gate the cover-art heuristic).
    private static let audioOnlyContainers: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma",
    ]

    /// Still-image codec names ffprobe reports for embedded cover art —
    /// excluded from `videoStreams` candidates when the container is
    /// audio-only, so an MP3/FLAC/etc. with embedded art isn't reported as
    /// having a "video" stream.
    private static let stillImageCodecs: Set<String> = [
        "mjpeg", "png", "bmp", "gif", "tiff", "webp",
    ]

    /// Default bound on concurrent ffprobe subprocesses for `probeFiles`.
    /// Half the active processor count, clamped to `1...4` — enough to
    /// overlap I/O-bound probes without spawning dozens of subprocesses at
    /// once on many-core machines.
    public static var defaultProbeConcurrency: Int {
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    // MARK: - Directory Scanning

    /// Scan a directory for media files and return analysis entries.
    ///
    /// The actual file-system enumeration is performed synchronously on a
    /// background thread (via `Task.detached`) because `FileManager`'s
    /// `DirectoryEnumerator` is not available from Swift concurrency contexts.
    ///
    /// Every entry is marked `.inferredFromFilename`: only size and container
    /// (extension) are facts; codec/resolution/HDR are file-name guesses and
    /// duration is nil. No ffprobe runs here — pass the result to probeFiles.
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

            // File-name guesses only; replaced by real data in probeFiles(...)
            // when ffprobe can read the file.
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
                duration: nil,
                provenance: .inferredFromFilename
            )

            results.append(analysis)
        }

        return results
    }

    // MARK: - Probing

    /// Replace each entry's file-name guesses with real ffprobe data.
    ///
    /// `files` is typically the output of `scanDirectory`. Results are
    /// written back by index, so the returned array has the same order and
    /// count as `files` regardless of which probes finish first. A file
    /// `prober.analyze(url:)` cannot read (missing, corrupt, permission
    /// denied, etc.) is left unchanged in the output — it keeps whatever
    /// `provenance` it already had (typically `.inferredFromFilename`).
    /// This function never throws.
    ///
    /// At most `maxConcurrency` probes run at once (clamped to `>= 1`);
    /// `progress`, if provided, is called once per completed probe (not
    /// once per file scheduled) with the fraction `completed/total`, and
    /// may be called on any thread — hop to `@MainActor` yourself if the
    /// sink needs to touch UI state. Empty `files` returns `[]` without
    /// calling `progress`.
    ///
    /// Cancellation (`Task.isCancelled`) is checked before every new probe
    /// is scheduled, so a cancelled caller stops starting new work quickly;
    /// probes already in flight still run to completion (`FFmpegProbe
    /// .analyze` does not itself observe cancellation) and their results
    /// are still written back.
    public static func probeFiles(
        _ files: [FileAnalysis],
        using prober: any MediaFileProbing,
        maxConcurrency: Int = StorageAnalyzer.defaultProbeConcurrency,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> [FileAnalysis] {
        guard !files.isEmpty else { return [] }
        let limit = max(1, maxConcurrency)
        let total = files.count

        return await withTaskGroup(of: (index: Int, analysis: FileAnalysis).self) { group in
            var results = files
            var completed = 0
            var nextIndex = 0

            while nextIndex < min(limit, total), !Task.isCancelled {
                let index = nextIndex
                group.addTask { (index: index, analysis: await probeOne(files[index], using: prober)) }
                nextIndex += 1
            }

            for await item in group {
                results[item.index] = item.analysis
                completed += 1
                progress?(Double(completed) / Double(total))

                if nextIndex < total, !Task.isCancelled {
                    let index = nextIndex
                    group.addTask { (index: index, analysis: await probeOne(files[index], using: prober)) }
                    nextIndex += 1
                }
            }
            return results
        }
    }

    /// Probe a single file, falling back to `base` unchanged on any error.
    private static func probeOne(_ base: FileAnalysis, using prober: any MediaFileProbing) async -> FileAnalysis {
        do {
            return analysis(from: try await prober.analyze(url: base.url), base: base)
        } catch {
            return base
        }
    }

    /// Build a `.probed` `FileAnalysis` from a real `MediaFile`, keeping
    /// `base`'s id/url/fileSize/container and replacing codec/resolution/
    /// hasHDR/duration with values read from the container.
    ///
    /// The video stream considered is `mediaFile.videoStreams`, preferring
    /// the default-disposition stream, else the first — except when `base
    /// .container` is an audio-only extension, in which case still-image
    /// codecs (`stillImageCodecs`, e.g. embedded cover art) are excluded
    /// first so an MP3/FLAC with embedded art isn't reported as having a
    /// video stream.
    public static func analysis(from mediaFile: MediaFile, base: FileAnalysis) -> FileAnalysis {
        let container = base.container ?? base.url.pathExtension.lowercased()
        let isAudioContainer = audioOnlyContainers.contains(container)
        let candidates = mediaFile.videoStreams.filter { stream in
            guard isAudioContainer else { return true }
            return !stillImageCodecs.contains(stream.codecName?.lowercased() ?? "")
        }
        let videoStream = candidates.first { $0.isDefault } ?? candidates.first
        let audioStream = mediaFile.primaryAudioStream

        let codec = videoStream?.codecName ?? audioStream?.codecName
        let resolution: String? = {
            guard let v = videoStream, let w = v.width, let h = v.height, w > 0, h > 0 else { return nil }
            return "\(w)x\(h)"
        }()
        let hasHDR = videoStream.map { !$0.hdrFormats.isEmpty } ?? false
        let rawDuration = mediaFile.duration
            ?? videoStream?.duration
            ?? mediaFile.streams.compactMap(\.duration).max()
        let duration = rawDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        return FileAnalysis(
            id: base.id, url: base.url, fileSize: base.fileSize,
            codec: codec, resolution: resolution, container: base.container,
            hasHDR: hasHDR, duration: duration, provenance: .probed
        )
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
    /// re-encoded output would be larger. Uses file.duration when a probe
    /// supplied it, otherwise estimateDurationFromSize.
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

        // Check for codec hints in the filename. Returns ffprobe's
        // codec_name ("hevc"), so probed and inferred files share a report key.
        if name.contains("h265") || name.contains("hevc") || name.contains("x265") {
            return "hevc"
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
        let averageBitrate: Double

        if let container, Self.audioOnlyContainers.contains(container) {
            averageBitrate = 1_000_000 // 1 Mbps for audio
        } else {
            averageBitrate = 5_000_000 // 5 Mbps for video
        }

        // duration = file_size_bits / bitrate
        let fileSizeBits = Double(fileSize) * 8.0
        return fileSizeBits / averageBitrate
    }
}
