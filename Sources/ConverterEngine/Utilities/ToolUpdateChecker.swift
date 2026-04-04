// ============================================================================
// MeedyaConverter — ToolUpdateChecker
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ToolUpdateStatus

/// Update status for a bundled tool.
public enum ToolUpdateStatus: String, Codable, Sendable {
    /// The tool is up to date.
    case upToDate = "up_to_date"

    /// An update is available.
    case updateAvailable = "update_available"

    /// The check failed (network error, API issue, etc.).
    case checkFailed = "check_failed"

    /// Status not yet checked.
    case unknown = "unknown"

    /// Display name.
    public var displayName: String {
        switch self {
        case .upToDate: return "Up to Date"
        case .updateAvailable: return "Update Available"
        case .checkFailed: return "Check Failed"
        case .unknown: return "Not Checked"
        }
    }
}

// MARK: - ToolUpdateResult

/// Result of an update check for a single bundled tool.
public struct ToolUpdateResult: Codable, Sendable {
    /// Tool identifier.
    public var toolId: String

    /// Tool display name.
    public var toolName: String

    /// Currently installed version.
    public var installedVersion: String

    /// Latest available version (nil if check failed).
    public var latestVersion: String?

    /// Update status.
    public var status: ToolUpdateStatus

    /// Download URL for the latest release.
    public var downloadURL: String?

    /// Release notes / changelog summary.
    public var releaseNotes: String?

    /// Date of the latest release.
    public var releaseDate: String?

    /// Date when this check was performed.
    public var checkDate: Date

    public init(
        toolId: String,
        toolName: String,
        installedVersion: String,
        latestVersion: String? = nil,
        status: ToolUpdateStatus = .unknown,
        downloadURL: String? = nil,
        releaseNotes: String? = nil,
        releaseDate: String? = nil,
        checkDate: Date = Date()
    ) {
        self.toolId = toolId
        self.toolName = toolName
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.status = status
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.checkDate = checkDate
    }

    /// Whether this result indicates an actionable update.
    public var hasUpdate: Bool {
        status == .updateAvailable
    }
}

// MARK: - ToolUpdateConfig

/// Configuration for tool update checking.
public struct ToolUpdateConfig: Codable, Sendable {
    /// Whether automatic update checks are enabled.
    public var autoCheckEnabled: Bool

    /// Interval between automatic checks in seconds (default: 1 week).
    public var checkIntervalSeconds: TimeInterval

    /// Whether to include pre-release versions.
    public var includePreRelease: Bool

    /// Whether to auto-download updates (direct distribution only).
    public var autoDownload: Bool

    public init(
        autoCheckEnabled: Bool = true,
        checkIntervalSeconds: TimeInterval = 604800, // 7 days
        includePreRelease: Bool = false,
        autoDownload: Bool = false
    ) {
        self.autoCheckEnabled = autoCheckEnabled
        self.checkIntervalSeconds = checkIntervalSeconds
        self.includePreRelease = includePreRelease
        self.autoDownload = autoDownload
    }
}

// MARK: - ToolUpdateChecker

/// Checks for updates to bundled third-party tools by querying GitHub Releases.
///
/// For direct distribution (non-App Store), the checker can notify users
/// and optionally auto-download updates. For App Store builds, this
/// information is used in the CI pipeline to keep bundled versions current.
///
/// Phase 13 / Issue #257
public struct ToolUpdateChecker: Sendable {

    // MARK: - URL Building

    /// Build the GitHub Releases API URL for a tool's latest release.
    ///
    /// - Parameter tool: Bundled tool info.
    /// - Returns: API URL string, or nil if not a GitHub-hosted tool.
    public static func buildLatestReleaseURL(tool: BundledTool) -> String? {
        return ToolBundleManifest.buildLatestReleaseURL(tool: tool)
    }

    /// Build the GitHub Releases API URL for all releases (to find pre-releases).
    ///
    /// - Parameter tool: Bundled tool info.
    /// - Returns: API URL string, or nil.
    public static func buildAllReleasesURL(tool: BundledTool) -> String? {
        guard tool.sourceURL.contains("github.com") else { return nil }
        let cleaned = tool.sourceURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "https://api.github.com/repos/\(cleaned)/releases?per_page=10"
    }

    /// Build HTTP headers for GitHub API requests.
    ///
    /// - Returns: Header dictionary.
    public static func buildHeaders() -> [String: String] {
        return ToolBundleManifest.buildGitHubHeaders()
    }

    // MARK: - Version Comparison

    /// Compare installed vs latest version.
    ///
    /// - Parameters:
    ///   - installed: Installed version string.
    ///   - latest: Latest available version string.
    /// - Returns: Update status.
    public static func compareVersions(
        installed: String,
        latest: String
    ) -> ToolUpdateStatus {
        if ToolBundleManifest.isUpdateAvailable(installed: installed, latest: latest) {
            return .updateAvailable
        }
        return .upToDate
    }

    // MARK: - Result Building

    /// Build an update result for a tool after checking the latest release.
    ///
    /// - Parameters:
    ///   - tool: Bundled tool info.
    ///   - latestVersion: Latest version from GitHub API.
    ///   - downloadURL: Download URL from release assets.
    ///   - releaseNotes: Release notes body.
    ///   - releaseDate: Release publication date.
    /// - Returns: Update result.
    public static func buildResult(
        tool: BundledTool,
        latestVersion: String,
        downloadURL: String? = nil,
        releaseNotes: String? = nil,
        releaseDate: String? = nil
    ) -> ToolUpdateResult {
        let status = compareVersions(
            installed: tool.version,
            latest: latestVersion
        )

        return ToolUpdateResult(
            toolId: tool.id,
            toolName: tool.name,
            installedVersion: tool.version,
            latestVersion: latestVersion,
            status: status,
            downloadURL: downloadURL,
            releaseNotes: releaseNotes,
            releaseDate: releaseDate
        )
    }

    /// Build an error result when the check fails.
    ///
    /// - Parameter tool: Bundled tool info.
    /// - Returns: Update result with failed status.
    public static func buildErrorResult(tool: BundledTool) -> ToolUpdateResult {
        return ToolUpdateResult(
            toolId: tool.id,
            toolName: tool.name,
            installedVersion: tool.version,
            status: .checkFailed
        )
    }

    // MARK: - Release Asset Selection

    /// Select the correct download asset for the current platform.
    ///
    /// - Parameters:
    ///   - assets: Release asset list (name, url pairs).
    ///   - toolBinaryName: Binary name to match.
    /// - Returns: Download URL for the matching asset, or nil.
    public static func selectPlatformAsset(
        assets: [(name: String, url: String)],
        toolBinaryName: String
    ) -> String? {
        #if os(macOS)
        let platformPatterns = ["macos", "darwin", "apple", "osx", "universal"]
        #if arch(arm64)
        let archPatterns = ["arm64", "aarch64", "universal"]
        #else
        let archPatterns = ["x86_64", "amd64", "x64", "universal"]
        #endif
        #elseif os(Linux)
        let platformPatterns = ["linux", "gnu"]
        #if arch(arm64)
        let archPatterns = ["arm64", "aarch64"]
        #else
        let archPatterns = ["x86_64", "amd64", "x64"]
        #endif
        #elseif os(Windows)
        let platformPatterns = ["windows", "win", "win64", "win32"]
        let archPatterns = ["x86_64", "amd64", "x64"]
        #else
        let platformPatterns: [String] = []
        let archPatterns: [String] = []
        #endif

        // First pass: match platform + arch + binary name
        for asset in assets {
            let lower = asset.name.lowercased()
            let matchesPlatform = platformPatterns.contains { lower.contains($0) }
            let matchesArch = archPatterns.contains { lower.contains($0) }
            if matchesPlatform && matchesArch {
                return asset.url
            }
        }

        // Second pass: match platform only
        for asset in assets {
            let lower = asset.name.lowercased()
            let matchesPlatform = platformPatterns.contains { lower.contains($0) }
            if matchesPlatform {
                return asset.url
            }
        }

        return nil
    }

    // MARK: - Check Scheduling

    /// Determine if an update check is due based on last check date and config.
    ///
    /// - Parameters:
    ///   - lastCheckDate: Date of the last update check (nil = never checked).
    ///   - config: Update check configuration.
    /// - Returns: `true` if a check should be performed.
    public static func isCheckDue(
        lastCheckDate: Date?,
        config: ToolUpdateConfig = ToolUpdateConfig()
    ) -> Bool {
        guard config.autoCheckEnabled else { return false }
        guard let lastCheck = lastCheckDate else { return true }

        let elapsed = Date().timeIntervalSince(lastCheck)
        return elapsed >= config.checkIntervalSeconds
    }

    // MARK: - Persistence

    /// Build the file path for storing update check results.
    ///
    /// - Parameter storageDirectory: App support directory.
    /// - Returns: File URL for the results JSON.
    public static func resultsStoragePath(
        storageDirectory: URL
    ) -> URL {
        return storageDirectory
            .appendingPathComponent("MeedyaConverter")
            .appendingPathComponent("ToolUpdates")
            .appendingPathComponent("update_results.json")
    }

    /// Encode update results to JSON data.
    ///
    /// - Parameter results: Array of update results.
    /// - Returns: JSON data.
    public static func encodeResults(_ results: [ToolUpdateResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(results)
    }

    /// Decode update results from JSON data.
    ///
    /// - Parameter data: JSON data.
    /// - Returns: Array of update results.
    public static func decodeResults(_ data: Data) throws -> [ToolUpdateResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ToolUpdateResult].self, from: data)
    }
}
