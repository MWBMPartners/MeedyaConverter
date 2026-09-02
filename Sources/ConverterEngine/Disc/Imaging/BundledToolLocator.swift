// ============================================================================
// MeedyaConverter — BundledToolLocator
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ToolLocatorError

/// Errors raised while locating a bundled or system command-line tool.
public enum ToolLocatorError: LocalizedError, Sendable {
    /// The named tool was not found in any searched location.
    case toolNotFound(name: String)

    /// A candidate at the given path exists but is not executable.
    case notExecutable(path: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "The '\(name)' tool was not found. Install it or specify its "
                + "location in Settings."
        case .notExecutable(let path):
            return "The tool at '\(path)' is not executable. Check file permissions."
        }
    }
}

// MARK: - BundledToolLocator

/// A generic locator for a command-line tool, factored from
/// `FFmpegBundleManager`'s documented lookup order so `cdrdao` (and later
/// `ddrescue`/`wodim`) can be found without touching `FFmpegBundleManager`
/// itself — the FFmpeg migration onto this locator is explicitly out of scope
/// (minimal diff), and the duplicated ordering is documented in both places.
///
/// Per decision DR-0001 the tool is *located, never linked*: this class finds
/// a binary on disk and hands back its path for the executor to launch as a
/// subprocess. It never loads a library.
///
/// The priority order (highest first) mirrors `FFmpegBundleManager.searchPaths`:
/// 1. the user override's directory,
/// 2. the app bundle's `Contents/Helpers` (where the release pipeline stages
///    helpers),
/// 3. the bundle's legacy `Resources/Tools` and `Resources` root,
/// 4. the executable's own directory,
/// 5. Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`),
/// 6. MacPorts (`/opt/local/bin`),
/// 7. the common Unix locations `/usr/bin` and `/bin`,
/// and finally `which(1)` as a last resort.
///
/// The ordering is a *pure* static function (`searchDirectories`) so CI can
/// assert it with injected paths and no app bundle; `locate()` does the thin
/// filesystem walk and caches under an `NSLock`, exactly like
/// `FFmpegBundleManager`.
public final class BundledToolLocator: @unchecked Sendable {

    /// The binary name to find (e.g. `cdrdao`).
    private let toolName: String

    /// Optional full path to the binary, supplied by the user (Settings). Like
    /// `FFmpegBundleManager.userFFmpegPath`, this is a full path to the
    /// executable, not a directory.
    public var userOverridePath: String?

    /// Cached resolved path, populated after the first successful `locate()`.
    private var cachedPath: String?

    /// Guards `cachedPath`, mirroring `FFmpegBundleManager`'s `NSLock`.
    private let lock = NSLock()

    /// Create a locator for `toolName`.
    ///
    /// - Parameters:
    ///   - toolName: The binary name to find.
    ///   - userOverridePath: Optional full path override.
    public init(toolName: String, userOverridePath: String? = nil) {
        self.toolName = toolName
        self.userOverridePath = userOverridePath
    }

    /// The ordered directory list to search, in priority order.
    ///
    /// PURE and unit-testable: the caller injects what would otherwise come
    /// from `Bundle.main`, so tests need no application bundle. A `nil`
    /// injection simply omits that source's entries without disturbing the
    /// order of the rest.
    ///
    /// - Parameters:
    ///   - userOverridePath: The user override's *full binary path*; its parent
    ///     directory is searched first.
    ///   - bundleURL: The app bundle URL (`Bundle.main.bundleURL`), or `nil`.
    ///   - resourcePath: The bundle resource path (`Bundle.main.resourcePath`),
    ///     or `nil`.
    ///   - executablePath: The running executable path
    ///     (`Bundle.main.executablePath`), or `nil`.
    /// - Returns: The directories to search, highest priority first.
    public static func searchDirectories(
        userOverridePath: String?,
        bundleURL: URL?,
        resourcePath: String?,
        executablePath: String?
    ) -> [String] {
        var paths: [String] = []

        // 1. User override's directory (highest priority).
        if let userPath = userOverridePath {
            let dir = (userPath as NSString).deletingLastPathComponent
            if !dir.isEmpty { paths.append(dir) }
        }

        // 2. App bundle Contents/Helpers (preferred bundled location).
        if let bundleURL {
            paths.append(bundleURL.appendingPathComponent("Contents/Helpers").path)
        }

        // 3. Legacy Resources/Tools and Resources root.
        if let resourcePath {
            paths.append(resourcePath + "/Tools")
            paths.append(resourcePath)
        }

        // 4. The executable's own directory.
        if let executablePath {
            let dir = (executablePath as NSString).deletingLastPathComponent
            if !dir.isEmpty { paths.append(dir) }
        }

        // 5. Homebrew (Apple Silicon first, then Intel legacy).
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")

        // 6. MacPorts.
        paths.append("/opt/local/bin")

        // 7. Common Unix locations.
        paths.append("/usr/bin")
        paths.append("/bin")

        return paths
    }

    /// Locate the tool on disk, caching the result for the session.
    ///
    /// Tries the user override's full path first, then walks
    /// `searchDirectories` (populated from `Bundle.main`), then falls back to
    /// `which(1)`. The resolved path is cached until `clearCache()`.
    ///
    /// - Returns: The full path to the executable.
    /// - Throws: `ToolLocatorError.toolNotFound` when nothing is found.
    public func locate() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cachedPath { return cachedPath }

        let fm = FileManager.default

        // User override full path — highest priority. A non-executable or
        // absent override falls through to the search rather than failing hard.
        if let userPath = userOverridePath, fm.isExecutableFile(atPath: userPath) {
            cachedPath = userPath
            return userPath
        }

        let directories = Self.searchDirectories(
            userOverridePath: userOverridePath,
            bundleURL: Bundle.main.bundleURL,
            resourcePath: Bundle.main.resourcePath,
            executablePath: Bundle.main.executablePath
        )
        for dir in directories {
            let candidate = (dir as NSString).appendingPathComponent(toolName)
            if fm.isExecutableFile(atPath: candidate) {
                cachedPath = candidate
                return candidate
            }
        }

        // Last resort: which(1).
        if let whichResult = try? Self.runWhich(toolName),
           !whichResult.isEmpty,
           fm.isExecutableFile(atPath: whichResult) {
            cachedPath = whichResult
            return whichResult
        }

        throw ToolLocatorError.toolNotFound(name: toolName)
    }

    /// Clear the cached path, forcing a fresh search on the next `locate()`.
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedPath = nil
    }

    // MARK: - Private helpers

    /// Run `which(1)` and return its trimmed first line, or `nil` on failure.
    private static func runWhich(_ name: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.split(separator: "\n").first.map(String.init)
    }
}
