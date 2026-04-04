// ============================================================================
// MeedyaConverter — ToolBundleManifest
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - BundledTool

/// A third-party tool bundled with MeedyaConverter.
public struct BundledTool: Codable, Sendable, Identifiable {
    /// Unique identifier for the tool.
    public var id: String

    /// Display name.
    public var name: String

    /// Current bundled version.
    public var version: String

    /// Source repository URL.
    public var sourceURL: String

    /// Date of last bundle update.
    public var lastUpdated: String

    /// Binary name (without path).
    public var binaryName: String

    /// Minimum compatible version of MeedyaConverter.
    public var minAppVersion: String?

    /// Description of what the tool does.
    public var description: String

    /// License type (e.g., "MIT", "GPLv2", "Apache-2.0").
    public var license: String

    public init(
        id: String,
        name: String,
        version: String,
        sourceURL: String,
        lastUpdated: String,
        binaryName: String,
        minAppVersion: String? = nil,
        description: String,
        license: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.sourceURL = sourceURL
        self.lastUpdated = lastUpdated
        self.binaryName = binaryName
        self.minAppVersion = minAppVersion
        self.description = description
        self.license = license
    }
}

// MARK: - ToolBundleManifest

/// Manages the manifest of bundled third-party tools and their versions.
///
/// The manifest is stored as `Tools/versions.json` in the app bundle (direct
/// distribution) or embedded at build time (App Store). It tracks version info
/// for each bundled binary to enable update checks.
///
/// Phase 13 / Issue #256
public struct ToolBundleManifest: Codable, Sendable {

    /// All bundled tools.
    public var tools: [BundledTool]

    /// Manifest schema version.
    public var schemaVersion: Int

    /// Date the manifest was last generated.
    public var generatedDate: String

    public init(
        tools: [BundledTool] = [],
        schemaVersion: Int = 1,
        generatedDate: String = ""
    ) {
        self.tools = tools
        self.schemaVersion = schemaVersion
        self.generatedDate = generatedDate
    }

    // MARK: - Built-in Manifest

    /// The default manifest for MeedyaConverter's bundled tools.
    public static let defaultManifest = ToolBundleManifest(
        tools: [
            BundledTool(
                id: "dovi_tool",
                name: "dovi_tool",
                version: "2.1.2",
                sourceURL: "https://github.com/quietvoid/dovi_tool",
                lastUpdated: "2026-04-01",
                binaryName: "dovi_tool",
                description: "Dolby Vision RPU extraction, injection, and profile conversion",
                license: "MIT"
            ),
            BundledTool(
                id: "hlg_tools",
                name: "hlg-tools",
                version: "0.5.0",
                sourceURL: "https://github.com/wswartzendruber/hlg-tools",
                lastUpdated: "2026-04-01",
                binaryName: "pq2hlg",
                description: "PQ (ST 2084) to HLG (ARIB STD-B67) HDR transfer function conversion",
                license: "MPL-2.0"
            ),
            BundledTool(
                id: "mediainfo",
                name: "MediaInfo",
                version: "24.11",
                sourceURL: "https://github.com/MediaArea/MediaInfo",
                lastUpdated: "2026-04-01",
                binaryName: "mediainfo",
                description: "Detailed media file analysis complementing FFprobe",
                license: "BSD-2-Clause"
            ),
            BundledTool(
                id: "fpcalc",
                name: "fpcalc (Chromaprint)",
                version: "1.5.1",
                sourceURL: "https://github.com/acoustid/chromaprint",
                lastUpdated: "2026-04-01",
                binaryName: "fpcalc",
                description: "Audio fingerprint generation for AcoustID lookup",
                license: "LGPL-2.1"
            ),
        ],
        schemaVersion: 1,
        generatedDate: "2026-04-01"
    )

    // MARK: - Lookup

    /// Get a bundled tool by ID.
    ///
    /// - Parameter id: Tool identifier.
    /// - Returns: The bundled tool info, or nil.
    public func tool(id: String) -> BundledTool? {
        tools.first { $0.id == id }
    }

    /// Get a bundled tool by binary name.
    ///
    /// - Parameter binaryName: Binary filename.
    /// - Returns: The bundled tool info, or nil.
    public func tool(binaryName: String) -> BundledTool? {
        tools.first { $0.binaryName == binaryName }
    }

    // MARK: - Update Checking

    /// Build the GitHub Releases API URL for checking updates.
    ///
    /// - Parameter tool: The bundled tool to check.
    /// - Returns: GitHub API URL for latest release.
    public static func buildLatestReleaseURL(tool: BundledTool) -> String? {
        // Extract owner/repo from GitHub URL
        guard tool.sourceURL.contains("github.com") else { return nil }
        let cleaned = tool.sourceURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "https://api.github.com/repos/\(cleaned)/releases/latest"
    }

    /// Build HTTP headers for GitHub API requests.
    ///
    /// - Returns: Header dictionary with User-Agent.
    public static func buildGitHubHeaders() -> [String: String] {
        return [
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "MeedyaConverter/1.0",
        ]
    }

    /// Compare semantic versions.
    ///
    /// - Parameters:
    ///   - installed: Currently installed version string.
    ///   - latest: Latest available version string.
    /// - Returns: `true` if the latest version is newer.
    public static func isUpdateAvailable(
        installed: String,
        latest: String
    ) -> Bool {
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(installedParts.count, latestParts.count) {
            let inst = i < installedParts.count ? installedParts[i] : 0
            let lat = i < latestParts.count ? latestParts[i] : 0
            if lat > inst { return true }
            if lat < inst { return false }
        }
        return false
    }

    // MARK: - Serialization

    /// Encode manifest to JSON data.
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decode manifest from JSON data.
    public static func fromJSON(_ data: Data) throws -> ToolBundleManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(ToolBundleManifest.self, from: data)
    }

    // MARK: - Platform-Specific Binary Paths

    /// Build the expected binary path within the app bundle.
    ///
    /// - Parameters:
    ///   - tool: The bundled tool.
    ///   - bundlePath: App bundle path.
    /// - Returns: Expected binary path.
    public static func bundledBinaryPath(
        tool: BundledTool,
        bundlePath: String
    ) -> String {
        #if os(macOS)
        return "\(bundlePath)/Contents/Helpers/\(tool.binaryName)"
        #elseif os(Linux)
        return "\(bundlePath)/lib/\(tool.binaryName)"
        #elseif os(Windows)
        return "\(bundlePath)\\bin\\\(tool.binaryName).exe"
        #else
        return "\(bundlePath)/\(tool.binaryName)"
        #endif
    }
}
