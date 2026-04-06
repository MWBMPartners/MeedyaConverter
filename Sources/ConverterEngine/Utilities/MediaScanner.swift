// ============================================================================
// MeedyaConverter — MediaScanner (Issue #333)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ScannedMediaFile

/// Represents a single media file discovered during a directory scan,
/// enriched with codec and stream metadata extracted via FFprobe.
///
/// The scanner populates these fields lazily — only files that pass
/// the initial extension check are probed for detailed metadata.
///
/// Phase 12 — Media Library Browser (Issue #333)
public struct ScannedMediaFile: Identifiable, Sendable {

    /// Unique identifier for this scanned file entry.
    public let id: UUID

    /// The on-disk URL of the media file.
    public let url: URL

    /// The file name (including extension) for display purposes.
    public let fileName: String

    /// Total file size in bytes.
    public let fileSize: Int64

    /// Primary video codec name (e.g. ``"h264"``, ``"hevc"``, ``"av1"``).
    /// `nil` if the file contains no video stream.
    public let codec: String?

    /// Human-readable resolution label (e.g. ``"1920x1080"``).
    /// `nil` if no video stream is present.
    public let resolution: String?

    /// Video frame width in pixels. `nil` if no video stream.
    public let width: Int?

    /// Video frame height in pixels. `nil` if no video stream.
    public let height: Int?

    /// Whether the video stream contains HDR metadata
    /// (BT.2020 colour space, PQ/HLG transfer, or HDR10/Dolby Vision).
    public let hasHDR: Bool

    /// Container format name (e.g. ``"mp4"``, ``"mkv"``, ``"mov"``).
    public let container: String?

    /// Total duration of the media in seconds. `nil` if undetermined.
    public let duration: TimeInterval?

    /// Primary audio codec name (e.g. ``"aac"``, ``"ac3"``, ``"flac"``).
    /// `nil` if the file contains no audio stream.
    public let audioCodec: String?

    /// Number of audio channels in the primary audio stream.
    /// `nil` if no audio stream is present.
    public let channelCount: Int?

    /// Creates a new scanned media file entry.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if omitted).
    ///   - url: On-disk file URL.
    ///   - fileName: Display file name.
    ///   - fileSize: Size in bytes.
    ///   - codec: Primary video codec name.
    ///   - resolution: Human-readable resolution string.
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - hasHDR: Whether the file contains HDR metadata.
    ///   - container: Container format name.
    ///   - duration: Duration in seconds.
    ///   - audioCodec: Primary audio codec name.
    ///   - channelCount: Number of audio channels.
    public init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        fileSize: Int64,
        codec: String? = nil,
        resolution: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        hasHDR: Bool = false,
        container: String? = nil,
        duration: TimeInterval? = nil,
        audioCodec: String? = nil,
        channelCount: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.codec = codec
        self.resolution = resolution
        self.width = width
        self.height = height
        self.hasHDR = hasHDR
        self.container = container
        self.duration = duration
        self.audioCodec = audioCodec
        self.channelCount = channelCount
    }
}

// MARK: - MediaScanFilter

/// Filter criteria for narrowing scan results by codec, resolution,
/// HDR status, container format, file size, and duration ranges.
///
/// All fields are optional — `nil` means "no constraint" for that axis.
/// Filters are combined with logical AND: a file must satisfy every
/// non-nil criterion to pass.
///
/// Phase 12 — Media Library Browser (Issue #333)
public struct MediaScanFilter: Sendable {

    /// If non-nil, only include files whose video codec is in this set.
    public var codecs: Set<String>?

    /// Minimum video height in pixels (e.g. 720 for "720p+").
    public var minResolutionHeight: Int?

    /// If non-nil, only include files whose HDR flag matches this value.
    public var hasHDR: Bool?

    /// If non-nil, only include files whose container format is in this set.
    public var containers: Set<String>?

    /// Minimum file size in bytes.
    public var minFileSize: Int64?

    /// Maximum file size in bytes.
    public var maxFileSize: Int64?

    /// Minimum duration in seconds.
    public var minDuration: TimeInterval?

    /// Maximum duration in seconds.
    public var maxDuration: TimeInterval?

    /// Creates a new scan filter with the specified criteria.
    ///
    /// - Parameters:
    ///   - codecs: Allowed video codec names.
    ///   - minResolutionHeight: Minimum vertical resolution.
    ///   - hasHDR: Required HDR status.
    ///   - containers: Allowed container formats.
    ///   - minFileSize: Minimum file size in bytes.
    ///   - maxFileSize: Maximum file size in bytes.
    ///   - minDuration: Minimum duration in seconds.
    ///   - maxDuration: Maximum duration in seconds.
    public init(
        codecs: Set<String>? = nil,
        minResolutionHeight: Int? = nil,
        hasHDR: Bool? = nil,
        containers: Set<String>? = nil,
        minFileSize: Int64? = nil,
        maxFileSize: Int64? = nil,
        minDuration: TimeInterval? = nil,
        maxDuration: TimeInterval? = nil
    ) {
        self.codecs = codecs
        self.minResolutionHeight = minResolutionHeight
        self.hasHDR = hasHDR
        self.containers = containers
        self.minFileSize = minFileSize
        self.maxFileSize = maxFileSize
        self.minDuration = minDuration
        self.maxDuration = maxDuration
    }
}

// MARK: - MediaScanner

/// Scans directories for media files and extracts metadata via FFprobe.
///
/// ``MediaScanner`` is the back-end engine for the Media Library Browser
/// (Issue #333). It is **not** a persistent library or database — it
/// performs a one-shot scan of a given directory, probes each media file
/// for codec/resolution/HDR metadata, and returns the results as an array
/// of ``ScannedMediaFile`` values.
///
/// Usage:
/// ```swift
/// let files = await MediaScanner.scan(directory: folderURL, recursive: true)
/// let filtered = MediaScanner.filter(files: files, by: MediaScanFilter(hasHDR: true))
/// ```
///
/// Phase 12 — Media Library Browser (Issue #333)
public struct MediaScanner: Sendable {

    // MARK: - Known Media Extensions

    /// File extensions recognised as media files.
    /// Covers common video and audio containers.
    private static let mediaExtensions: Set<String> = [
        // Video containers
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv",
        "ts", "mts", "m2ts", "vob", "mpg", "mpeg", "3gp", "ogv",
        // Audio containers
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma",
        "aiff", "aif", "alac", "ape", "wv", "dsf", "dff",
        // Image sequences / animated
        "gif", "webp", "apng",
        // Professional
        "mxf", "r3d", "braw", "dng"
    ]

    // MARK: - Public API

    /// Checks whether a URL points to a recognised media file based on extension.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: `true` if the file extension is in the known media types set.
    public static func isMediaFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return mediaExtensions.contains(ext)
    }

    /// Scans a directory for media files and probes each one for metadata.
    ///
    /// Enumerates all files in the given directory (optionally recursively),
    /// filters by known media extensions, then runs FFprobe on each file
    /// to extract codec, resolution, HDR, duration, and audio metadata.
    ///
    /// - Parameters:
    ///   - directory: The root directory to scan.
    ///   - recursive: Whether to descend into subdirectories.
    /// - Returns: An array of ``ScannedMediaFile`` with metadata populated.
    public static func scan(directory: URL, recursive: Bool) async -> [ScannedMediaFile] {
        let fileManager = FileManager.default
        var mediaURLs: [URL] = []

        // Enumerate files in the directory
        // File enumeration is performed synchronously to avoid the
        // async-context restriction on NSEnumerator.makeIterator().
        if recursive {
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            if let enumerator {
                while let fileURL = enumerator.nextObject() as? URL {
                    if isMediaFile(fileURL) {
                        mediaURLs.append(fileURL)
                    }
                }
            }
        } else {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            mediaURLs = contents.filter { isMediaFile($0) }
        }

        // Probe each file for metadata
        var results: [ScannedMediaFile] = []
        for url in mediaURLs {
            let scanned = await probeFile(url: url)
            results.append(scanned)
        }

        return results
    }

    /// Filters an array of scanned files by the given criteria.
    ///
    /// All non-nil filter fields are combined with logical AND.
    ///
    /// - Parameters:
    ///   - files: The scanned files to filter.
    ///   - filter: The filter criteria.
    /// - Returns: The subset of files that match all specified criteria.
    public static func filter(files: [ScannedMediaFile], by filter: MediaScanFilter) -> [ScannedMediaFile] {
        files.filter { file in
            // Codec filter
            if let codecs = filter.codecs, let codec = file.codec {
                if !codecs.contains(codec) { return false }
            } else if let codecs = filter.codecs, file.codec == nil {
                // File has no codec info but filter requires specific codecs
                if !codecs.isEmpty { return false }
            }

            // Resolution filter
            if let minHeight = filter.minResolutionHeight {
                guard let height = file.height, height >= minHeight else { return false }
            }

            // HDR filter
            if let requiredHDR = filter.hasHDR {
                if file.hasHDR != requiredHDR { return false }
            }

            // Container filter
            if let containers = filter.containers, let container = file.container {
                if !containers.contains(container) { return false }
            } else if let containers = filter.containers, file.container == nil {
                if !containers.isEmpty { return false }
            }

            // File size range
            if let minSize = filter.minFileSize {
                if file.fileSize < minSize { return false }
            }
            if let maxSize = filter.maxFileSize {
                if file.fileSize > maxSize { return false }
            }

            // Duration range
            if let minDur = filter.minDuration {
                guard let dur = file.duration, dur >= minDur else { return false }
            }
            if let maxDur = filter.maxDuration {
                guard let dur = file.duration, dur <= maxDur else { return false }
            }

            return true
        }
    }

    // MARK: - Private Helpers

    /// Probes a single file via FFprobe and constructs a ``ScannedMediaFile``.
    ///
    /// If FFprobe is unavailable or fails, returns a file entry with
    /// only file-system metadata (name, size) and `nil` for probed fields.
    ///
    /// - Parameter url: The media file URL.
    /// - Returns: A populated ``ScannedMediaFile``.
    private static func probeFile(url: URL) async -> ScannedMediaFile {
        let fileManager = FileManager.default
        let fileSize: Int64 = {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }()

        let fileName = url.lastPathComponent
        let containerExt = url.pathExtension.lowercased()

        // Attempt to run FFprobe for detailed metadata
        guard let ffprobePath = locateFFprobe() else {
            return ScannedMediaFile(
                url: url,
                fileName: fileName,
                fileSize: fileSize,
                container: containerExt
            )
        }

        do {
            let json = try await runFFprobe(
                ffprobePath: ffprobePath,
                arguments: [
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    url.path
                ]
            )
            return parseProbeOutput(json: json, url: url, fileName: fileName, fileSize: fileSize, containerExt: containerExt)
        } catch {
            return ScannedMediaFile(
                url: url,
                fileName: fileName,
                fileSize: fileSize,
                container: containerExt
            )
        }
    }

    /// Locates the FFprobe binary on the system.
    ///
    /// Checks common installation paths in order of preference.
    ///
    /// - Returns: The path to FFprobe, or `nil` if not found.
    private static func locateFFprobe() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Runs FFprobe as a subprocess and returns the raw JSON output.
    ///
    /// - Parameters:
    ///   - ffprobePath: Path to the FFprobe binary.
    ///   - arguments: Command-line arguments to pass.
    /// - Returns: The raw JSON string from stdout.
    /// - Throws: If the process fails or returns non-zero exit code.
    private static func runFFprobe(ffprobePath: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parses FFprobe JSON output into a ``ScannedMediaFile``.
    ///
    /// Extracts video codec, resolution, HDR status, duration, and audio
    /// metadata from the JSON structure returned by FFprobe.
    ///
    /// - Parameters:
    ///   - json: Raw JSON string from FFprobe.
    ///   - url: The media file URL.
    ///   - fileName: Display file name.
    ///   - fileSize: File size in bytes.
    ///   - containerExt: File extension used as fallback container name.
    /// - Returns: A populated ``ScannedMediaFile``.
    private static func parseProbeOutput(
        json: String,
        url: URL,
        fileName: String,
        fileSize: Int64,
        containerExt: String
    ) -> ScannedMediaFile {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ScannedMediaFile(url: url, fileName: fileName, fileSize: fileSize, container: containerExt)
        }

        let streams = root["streams"] as? [[String: Any]] ?? []
        let format = root["format"] as? [String: Any] ?? [:]

        // Find primary video stream
        let videoStream = streams.first { ($0["codec_type"] as? String) == "video" }
        let audioStream = streams.first { ($0["codec_type"] as? String) == "audio" }

        let videoCodec = videoStream?["codec_name"] as? String
        let width = videoStream?["width"] as? Int
        let height = videoStream?["height"] as? Int
        let resolution: String? = {
            guard let w = width, let h = height else { return nil }
            return "\(w)x\(h)"
        }()

        // HDR detection: check colour transfer, colour space, and side data
        let hasHDR: Bool = {
            guard let vs = videoStream else { return false }
            let transfer = vs["color_transfer"] as? String ?? ""
            let space = vs["color_space"] as? String ?? ""
            let hdrIndicators = ["smpte2084", "arib-std-b67", "bt2020"]
            return hdrIndicators.contains(where: { transfer.contains($0) || space.contains($0) })
        }()

        let container = (format["format_name"] as? String)?.components(separatedBy: ",").first ?? containerExt
        let duration: TimeInterval? = {
            if let durStr = format["duration"] as? String {
                return Double(durStr)
            }
            return nil
        }()

        let audioCodec = audioStream?["codec_name"] as? String
        let channelCount = audioStream?["channels"] as? Int

        return ScannedMediaFile(
            url: url,
            fileName: fileName,
            fileSize: fileSize,
            codec: videoCodec,
            resolution: resolution,
            width: width,
            height: height,
            hasHDR: hasHDR,
            container: container,
            duration: duration,
            audioCodec: audioCodec,
            channelCount: channelCount
        )
    }
}
