// ============================================================================
// MeedyaConverter — FFmpegBundleManager
// Copyright © 2026–2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FFmpegBundleError

/// Errors that can occur when locating or validating FFmpeg binaries.
public enum FFmpegBundleError: LocalizedError, Sendable {
    /// FFmpeg binary was not found in any searched location.
    case ffmpegNotFound

    /// FFprobe binary was not found in any searched location.
    case ffprobeNotFound

    /// The binary was found but is not executable (permissions issue).
    case notExecutable(path: String)

    /// The binary version could not be determined.
    case versionDetectionFailed(path: String)

    /// The binary version is below the minimum required version.
    case versionTooOld(found: String, required: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg binary not found. Install FFmpeg or specify its location in Settings."
        case .ffprobeNotFound:
            return "FFprobe binary not found. It is typically bundled with FFmpeg."
        case .notExecutable(let path):
            return "Binary at '\(path)' is not executable. Check file permissions."
        case .versionDetectionFailed(let path):
            return "Could not determine version of binary at '\(path)'."
        case .versionTooOld(let found, let required):
            return "FFmpeg version \(found) is too old. Minimum required: \(required)."
        }
    }
}

// MARK: - FFmpegBinaryInfo

/// Information about a discovered FFmpeg or FFprobe binary.
public struct FFmpegBinaryInfo: Codable, Sendable {
    /// The full file system path to the binary.
    public let path: String

    /// The version string reported by the binary (e.g., "7.1.2").
    public let version: String

    /// The build configuration string (e.g., "built with Apple clang").
    public let buildInfo: String?

    /// Whether this binary includes libx264 (GPL).
    public let hasLibx264: Bool

    /// Whether this binary includes libx265 (GPL).
    public let hasLibx265: Bool

    /// Whether this binary includes libsvtav1 (AV1 encoder).
    public let hasLibSvtAV1: Bool

    /// Whether this binary was found bundled with the application.
    public let isBundled: Bool

    public init(
        path: String,
        version: String,
        buildInfo: String? = nil,
        hasLibx264: Bool = false,
        hasLibx265: Bool = false,
        hasLibSvtAV1: Bool = false,
        isBundled: Bool = false
    ) {
        self.path = path
        self.version = version
        self.buildInfo = buildInfo
        self.hasLibx264 = hasLibx264
        self.hasLibx265 = hasLibx265
        self.hasLibSvtAV1 = hasLibSvtAV1
        self.isBundled = isBundled
    }
}

// MARK: - FFmpegBundleManager

/// Manages the discovery, validation, and lifecycle of FFmpeg and FFprobe binaries.
///
/// The bundle manager searches for FFmpeg in multiple locations (in priority order):
/// 1. User-specified path (from Settings)
/// 2. Application bundle (Tools/ directory for direct distribution)
/// 3. Homebrew paths (/opt/homebrew/bin, /usr/local/bin)
/// 4. System PATH
///
/// Once located, the manager validates the binary is executable, detects its
/// version and build configuration, and caches the result for the session.
public final class FFmpegBundleManager: @unchecked Sendable {

    // MARK: - Properties

    /// Cached FFmpeg binary info, populated after first successful discovery.
    private var cachedFFmpeg: FFmpegBinaryInfo?

    /// Cached FFprobe binary info.
    private var cachedFFprobe: FFmpegBinaryInfo?

    /// Optional user-specified path override from Settings.
    public var userFFmpegPath: String?

    /// Optional user-specified FFprobe path override.
    public var userFFprobePath: String?

    /// Serial queue for thread-safe access to cached values.
    private let lock = NSLock()

    // MARK: - Search Paths

    /// The ordered list of directories to search for FFmpeg/FFprobe binaries.
    /// User path is checked first, then bundled, then Homebrew, then system.
    private var searchPaths: [String] {
        var paths: [String] = []

        // 1. User-specified directory (highest priority)
        if let userPath = userFFmpegPath {
            let dir = (userPath as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                paths.append(dir)
            }
        }

        // 2. Application bundle (Tools/ directory)
        if let bundlePath = Bundle.main.resourcePath {
            paths.append(bundlePath + "/Tools")
            paths.append(bundlePath)
        }

        // Also check the app's MacOS directory for embedded helpers
        if let execPath = Bundle.main.executablePath {
            let macOSDir = (execPath as NSString).deletingLastPathComponent
            paths.append(macOSDir)
        }

        // 3. Homebrew paths (Apple Silicon first, then Intel legacy)
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")

        // 4. MacPorts
        paths.append("/opt/local/bin")

        // 5. Common Linux/Unix paths
        paths.append("/usr/bin")
        paths.append("/bin")

        return paths
    }

    // MARK: - Initialiser

    /// Create a new FFmpegBundleManager.
    ///
    /// - Parameters:
    ///   - ffmpegPath: Optional user-specified path to the FFmpeg binary.
    ///   - ffprobePath: Optional user-specified path to the FFprobe binary.
    public init(ffmpegPath: String? = nil, ffprobePath: String? = nil) {
        self.userFFmpegPath = ffmpegPath
        self.userFFprobePath = ffprobePath
    }

    // MARK: - Discovery

    /// Locate and validate the FFmpeg binary.
    ///
    /// Searches all known paths in priority order, validates the binary is
    /// executable, and detects its version and capabilities.
    ///
    /// - Returns: An `FFmpegBinaryInfo` describing the found binary.
    /// - Throws: `FFmpegBundleError` if no valid FFmpeg is found.
    public func locateFFmpeg() throws -> FFmpegBinaryInfo {
        lock.lock()
        defer { lock.unlock() }

        // Return cached result if available
        if let cached = cachedFFmpeg {
            return cached
        }

        // If user specified a full path, try that first
        if let userPath = userFFmpegPath {
            if FileManager.default.isExecutableFile(atPath: userPath) {
                let info = try detectBinaryInfo(at: userPath, isBundled: false)
                cachedFFmpeg = info
                return info
            }
        }

        // Search all known paths for "ffmpeg"
        let info = try findBinary(named: "ffmpeg")
        cachedFFmpeg = info
        return info
    }

    /// Locate and validate the FFprobe binary.
    ///
    /// - Returns: An `FFmpegBinaryInfo` describing the found FFprobe binary.
    /// - Throws: `FFmpegBundleError` if no valid FFprobe is found.
    public func locateFFprobe() throws -> FFmpegBinaryInfo {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedFFprobe {
            return cached
        }

        if let userPath = userFFprobePath {
            if FileManager.default.isExecutableFile(atPath: userPath) {
                let info = try detectBinaryInfo(at: userPath, isBundled: false)
                cachedFFprobe = info
                return info
            }
        }

        let info = try findBinary(named: "ffprobe")
        cachedFFprobe = info
        return info
    }

    /// Clear the cached binary information, forcing a fresh search on next access.
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedFFmpeg = nil
        cachedFFprobe = nil
    }

    // MARK: - Private Helpers

    /// Search all known paths for a binary with the given name.
    private func findBinary(named binaryName: String) throws -> FFmpegBinaryInfo {
        let fm = FileManager.default

        for searchDir in searchPaths {
            let candidatePath = (searchDir as NSString).appendingPathComponent(binaryName)

            if fm.isExecutableFile(atPath: candidatePath) {
                let isBundled = candidatePath.contains(Bundle.main.bundlePath)
                return try detectBinaryInfo(at: candidatePath, isBundled: isBundled)
            }
        }

        // Not found in any search path — try which(1) as a last resort
        if let whichResult = try? runSimpleCommand("/usr/bin/which", arguments: [binaryName]),
           !whichResult.isEmpty,
           fm.isExecutableFile(atPath: whichResult) {
            return try detectBinaryInfo(at: whichResult, isBundled: false)
        }

        // Binary not found anywhere
        if binaryName == "ffmpeg" {
            throw FFmpegBundleError.ffmpegNotFound
        } else {
            throw FFmpegBundleError.ffprobeNotFound
        }
    }

    /// Detect the version and capabilities of a binary at the given path.
    private func detectBinaryInfo(at path: String, isBundled: Bool) throws -> FFmpegBinaryInfo {
        // Run the binary with -version flag to get version info
        guard let output = try? runSimpleCommand(path, arguments: ["-version"]) else {
            throw FFmpegBundleError.versionDetectionFailed(path: path)
        }

        // Parse version from first line (e.g., "ffmpeg version 7.1.2 Copyright (c) ...")
        let version = parseVersion(from: output) ?? "unknown"
        let buildInfo = parseBuildInfo(from: output)

        // Check for key libraries in the configuration
        let hasLibx264 = output.contains("--enable-libx264") || output.contains("libx264")
        let hasLibx265 = output.contains("--enable-libx265") || output.contains("libx265")
        let hasLibSvtAV1 = output.contains("--enable-libsvtav1") || output.contains("libsvtav1")

        return FFmpegBinaryInfo(
            path: path,
            version: version,
            buildInfo: buildInfo,
            hasLibx264: hasLibx264,
            hasLibx265: hasLibx265,
            hasLibSvtAV1: hasLibSvtAV1,
            isBundled: isBundled
        )
    }

    /// Parse the version number from FFmpeg's -version output.
    private func parseVersion(from output: String) -> String? {
        // Match patterns like "ffmpeg version 7.1.2" or "ffprobe version N-12345-..."
        let lines = output.split(separator: "\n")
        guard let firstLine = lines.first else { return nil }

        // Try to extract version after "version" keyword
        let components = firstLine.split(separator: " ")
        if let versionIndex = components.firstIndex(where: { $0.lowercased() == "version" }),
           versionIndex + 1 < components.count {
            return String(components[versionIndex + 1])
        }

        return nil
    }

    /// Parse the build configuration from FFmpeg's -version output.
    private func parseBuildInfo(from output: String) -> String? {
        let lines = output.split(separator: "\n")
        return lines.first(where: { $0.contains("built with") }).map(String.init)
    }

    /// Run a simple command and capture its stdout output.
    /// Returns the trimmed output string, or throws on failure.
    private func runSimpleCommand(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe() // Suppress stderr

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
