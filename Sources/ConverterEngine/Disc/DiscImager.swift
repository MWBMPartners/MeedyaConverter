// ============================================================================
// MeedyaConverter — DiscImager
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ImagingMethod

/// Method used for creating disc images.
public enum ImagingMethod: String, Codable, Sendable, CaseIterable {
    /// Use `dd` for bit-for-bit raw sector copy.
    case dd = "dd"

    /// Use `ddrescue` for error-resilient copying with automatic retry.
    case ddrescue = "ddrescue"

    /// Use `readom` (formerly readcd) for optical disc reading.
    case readom = "readom"

    /// Use macOS `hdiutil` for disc imaging.
    case hdiutil = "hdiutil"

    /// Display name.
    public var displayName: String {
        switch self {
        case .dd: return "dd (Raw Copy)"
        case .ddrescue: return "ddrescue (Error Recovery)"
        case .readom: return "readom (Optical)"
        case .hdiutil: return "hdiutil (macOS)"
        }
    }

    /// Command-line tool name.
    public var toolName: String {
        switch self {
        case .dd: return "dd"
        case .ddrescue: return "ddrescue"
        case .readom: return "readom"
        case .hdiutil: return "hdiutil"
        }
    }
}

// MARK: - ImagingConfig

/// Configuration for a physical disc-to-image copy operation.
public struct ImagingConfig: Codable, Sendable {
    /// Source device path (e.g., /dev/sr0 on Linux, /dev/disk2 on macOS).
    public var sourcePath: String

    /// Output image file path.
    public var outputPath: String

    /// Output image format.
    public var imageFormat: DiscImageFormat

    /// Imaging method to use.
    public var method: ImagingMethod

    /// Read speed (1x, 2x, 4x, etc.). Nil = maximum speed.
    public var readSpeed: Int?

    /// Block size in bytes for raw copying (default 2048 for optical).
    public var blockSize: Int

    /// Number of retries for bad sectors.
    public var retryCount: Int

    /// Whether to verify the image after creation via checksum.
    public var verifyAfterCopy: Bool

    /// Whether to generate a log file for the operation.
    public var generateLog: Bool

    /// Path for ddrescue map file (recovery log).
    public var mapFilePath: String?

    public init(
        sourcePath: String,
        outputPath: String,
        imageFormat: DiscImageFormat = .iso,
        method: ImagingMethod = .dd,
        readSpeed: Int? = nil,
        blockSize: Int = 2048,
        retryCount: Int = 3,
        verifyAfterCopy: Bool = true,
        generateLog: Bool = true,
        mapFilePath: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.imageFormat = imageFormat
        self.method = method
        self.readSpeed = readSpeed
        self.blockSize = blockSize
        self.retryCount = retryCount
        self.verifyAfterCopy = verifyAfterCopy
        self.generateLog = generateLog
        self.mapFilePath = mapFilePath
    }
}

// MARK: - ImagingProgress

/// Progress information for a disc imaging operation.
public struct ImagingProgress: Sendable {
    /// Bytes copied so far.
    public var bytesCopied: Int64

    /// Total bytes to copy (nil if unknown).
    public var totalBytes: Int64?

    /// Copy speed in bytes per second.
    public var bytesPerSecond: Double

    /// Number of read errors encountered.
    public var errorCount: Int

    /// Number of bad sectors found.
    public var badSectors: Int

    /// Current sector being read.
    public var currentSector: Int64

    /// Fraction complete (0.0–1.0), or nil if total is unknown.
    public var fractionComplete: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return Double(bytesCopied) / Double(total)
    }

    /// Estimated time remaining in seconds.
    public var estimatedTimeRemaining: TimeInterval? {
        guard let total = totalBytes, bytesPerSecond > 0 else { return nil }
        let remaining = Double(total - bytesCopied)
        return remaining / bytesPerSecond
    }

    /// Human-readable copy speed (e.g., "12.5 MB/s").
    public var formattedSpeed: String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    public init(
        bytesCopied: Int64 = 0,
        totalBytes: Int64? = nil,
        bytesPerSecond: Double = 0,
        errorCount: Int = 0,
        badSectors: Int = 0,
        currentSector: Int64 = 0
    ) {
        self.bytesCopied = bytesCopied
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.errorCount = errorCount
        self.badSectors = badSectors
        self.currentSector = currentSector
    }
}

// MARK: - DiscImager

/// Builds command-line arguments for bit-for-bit disc-to-image copying.
///
/// Supports multiple imaging methods including `dd`, `ddrescue`, `readom`,
/// and `hdiutil` for cross-platform optical disc cloning.
///
/// Phase 11.26
public struct DiscImager: Sendable {

    // MARK: - dd Arguments

    /// Build `dd` arguments for raw disc copying.
    ///
    /// - Parameter config: Imaging configuration.
    /// - Returns: Argument array for `dd`.
    public static func buildDdArguments(config: ImagingConfig) -> [String] {
        var args = [
            "if=\(config.sourcePath)",
            "of=\(config.outputPath)",
            "bs=\(config.blockSize)",
            "status=progress",
            "conv=noerror,sync",
        ]

        if config.retryCount > 0 {
            args.append("iflag=direct")
        }

        return args
    }

    // MARK: - ddrescue Arguments

    /// Build `ddrescue` arguments for error-resilient disc copying.
    ///
    /// ddrescue is preferred for damaged discs as it handles bad sectors
    /// gracefully and can resume interrupted operations.
    ///
    /// - Parameter config: Imaging configuration.
    /// - Returns: Argument array for `ddrescue`.
    public static func buildDdrescueArguments(config: ImagingConfig) -> [String] {
        var args: [String] = []

        // Block size
        args += ["-b", "\(config.blockSize)"]

        // Retry count for bad sectors
        args += ["-r", "\(config.retryCount)"]

        // Direct disc access (skip OS cache)
        args.append("-d")

        // Show progress
        args.append("-v")

        // Source and output
        args.append(config.sourcePath)
        args.append(config.outputPath)

        // Map file (recovery log) — required for resume support
        if let mapFile = config.mapFilePath {
            args.append(mapFile)
        } else {
            args.append("\(config.outputPath).map")
        }

        return args
    }

    // MARK: - readom Arguments

    /// Build `readom` (readcd) arguments for optical disc reading.
    ///
    /// - Parameter config: Imaging configuration.
    /// - Returns: Argument array for `readom`.
    public static func buildReadomArguments(config: ImagingConfig) -> [String] {
        var args: [String] = []

        // Device path
        args += ["dev=\(config.sourcePath)"]

        // Output file
        args += ["f=\(config.outputPath)"]

        // Read speed
        if let speed = config.readSpeed {
            args += ["speed=\(speed)"]
        }

        // Retry count
        args += ["retries=\(config.retryCount)"]

        return args
    }

    // MARK: - hdiutil Arguments

    /// Build `hdiutil` arguments for macOS disc imaging.
    ///
    /// - Parameter config: Imaging configuration.
    /// - Returns: Argument array for `hdiutil`.
    public static func buildHdiutilArguments(config: ImagingConfig) -> [String] {
        var args = [
            "create",
            "-srcdevice", config.sourcePath,
            "-format", "UDTO", // Read-only DVD/CD master
        ]

        args.append(config.outputPath)
        return args
    }

    // MARK: - Unified Builder

    /// Build arguments for the configured imaging method.
    ///
    /// - Parameter config: Imaging configuration.
    /// - Returns: Tuple of (tool name, argument array).
    public static func buildArguments(
        config: ImagingConfig
    ) -> (tool: String, arguments: [String]) {
        switch config.method {
        case .dd:
            return ("dd", buildDdArguments(config: config))
        case .ddrescue:
            return ("ddrescue", buildDdrescueArguments(config: config))
        case .readom:
            return ("readom", buildReadomArguments(config: config))
        case .hdiutil:
            return ("hdiutil", buildHdiutilArguments(config: config))
        }
    }

    // MARK: - Verification

    /// Build arguments to compute a checksum for verification.
    ///
    /// - Parameters:
    ///   - filePath: Path to the image file.
    ///   - algorithm: Checksum algorithm ("sha256", "md5").
    /// - Returns: Tuple of (tool name, argument array).
    public static func buildChecksumArguments(
        filePath: String,
        algorithm: String = "sha256"
    ) -> (tool: String, arguments: [String]) {
        switch algorithm.lowercased() {
        case "md5":
            return ("md5sum", [filePath])
        case "sha1":
            return ("sha1sum", [filePath])
        default:
            return ("sha256sum", [filePath])
        }
    }

    /// Build arguments to compute a checksum of the source device for comparison.
    ///
    /// - Parameters:
    ///   - devicePath: Source device path.
    ///   - sizeBytes: Number of bytes to checksum.
    ///   - blockSize: Block size for reading.
    ///   - algorithm: Checksum algorithm.
    /// - Returns: Shell command string for piped checksum.
    public static func buildDeviceChecksumCommand(
        devicePath: String,
        sizeBytes: Int64,
        blockSize: Int = 2048,
        algorithm: String = "sha256"
    ) -> String {
        let blocks = sizeBytes / Int64(blockSize)
        let tool = algorithm.lowercased() == "md5" ? "md5sum" : "sha256sum"
        return "dd if=\(devicePath) bs=\(blockSize) count=\(blocks) status=none | \(tool)"
    }

    // MARK: - Drive Detection

    /// Build arguments to list available optical drives (Linux).
    ///
    /// - Returns: Arguments for listing block devices.
    public static func buildLinuxDriveDetectionArguments() -> (tool: String, arguments: [String]) {
        return ("lsblk", ["-d", "-o", "NAME,TYPE,SIZE,MODEL", "-n", "-J"])
    }

    /// Build arguments to list available optical drives (macOS).
    ///
    /// - Returns: Arguments for listing drives via diskutil.
    public static func buildMacOSDriveDetectionArguments() -> (tool: String, arguments: [String]) {
        return ("diskutil", ["list", "-plist", "external"])
    }

    // MARK: - Progress Parsing

    /// Parse `dd` progress output.
    ///
    /// dd outputs lines like:
    /// `1234567+0 records in` / `1234567 bytes (1.2 MB, 1.2 MiB) copied, 2.5 s, 500 kB/s`
    ///
    /// - Parameter output: dd stderr output line.
    /// - Returns: Parsed progress, or nil if line doesn't contain progress info.
    public static func parseDdProgress(from output: String) -> ImagingProgress? {
        // Match "N bytes ... copied, Ns, speed"
        guard output.contains("bytes") && output.contains("copied") else { return nil }

        var progress = ImagingProgress()

        // Extract bytes copied
        let parts = output.split(separator: " ")
        if let first = parts.first, let bytes = Int64(first) {
            progress.bytesCopied = bytes
        }

        // Extract speed (last element, e.g., "500 kB/s" or "12.5 MB/s")
        if let speedStr = output.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) {
            let speed = speedStr.lowercased()
            if speed.contains("gb/s") {
                if let val = Double(speed.replacingOccurrences(of: "gb/s", with: "").trimmingCharacters(in: .whitespaces)) {
                    progress.bytesPerSecond = val * 1_000_000_000
                }
            } else if speed.contains("mb/s") {
                if let val = Double(speed.replacingOccurrences(of: "mb/s", with: "").trimmingCharacters(in: .whitespaces)) {
                    progress.bytesPerSecond = val * 1_000_000
                }
            } else if speed.contains("kb/s") {
                if let val = Double(speed.replacingOccurrences(of: "kb/s", with: "").trimmingCharacters(in: .whitespaces)) {
                    progress.bytesPerSecond = val * 1_000
                }
            }
        }

        return progress
    }

    /// Parse `ddrescue` progress output.
    ///
    /// ddrescue outputs lines like:
    /// `rescued:  1234 kB,  errsize:   0 B,  current rate:  1234 kB/s`
    ///
    /// - Parameter output: ddrescue output line.
    /// - Returns: Parsed progress, or nil if line doesn't contain progress info.
    public static func parseDdrescueProgress(from output: String) -> ImagingProgress? {
        guard output.contains("rescued:") else { return nil }

        var progress = ImagingProgress()

        // Extract rescued bytes
        if let rescuedRange = output.range(of: "rescued:") {
            let afterRescued = output[rescuedRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let parts = afterRescued.split(separator: ",")
            if let first = parts.first {
                let sizeStr = first.trimmingCharacters(in: .whitespaces)
                progress.bytesCopied = parseSize(sizeStr)
            }
        }

        // Extract error size
        if let errRange = output.range(of: "errsize:") {
            let afterErr = output[errRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let parts = afterErr.split(separator: ",")
            if let first = parts.first {
                let sizeStr = first.trimmingCharacters(in: .whitespaces)
                let errBytes = parseSize(String(sizeStr))
                if errBytes > 0 {
                    progress.badSectors = Int(errBytes / 2048)
                }
            }
        }

        return progress
    }

    /// Parse a human-readable size string (e.g., "1234 kB", "5.6 MB") to bytes.
    private static func parseSize(_ sizeStr: String) -> Int64 {
        let lower = sizeStr.lowercased().trimmingCharacters(in: .whitespaces)
        let components = lower.split(separator: " ")
        guard components.count >= 1,
              let value = Double(components[0]) else { return 0 }

        if components.count >= 2 {
            let unit = String(components[1])
            if unit.hasPrefix("gb") { return Int64(value * 1_000_000_000) }
            if unit.hasPrefix("mb") { return Int64(value * 1_000_000) }
            if unit.hasPrefix("kb") { return Int64(value * 1_000) }
        }

        return Int64(value)
    }
}
