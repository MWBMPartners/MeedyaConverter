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

    /// License type as an SPDX identifier where possible (e.g. `"MIT"`,
    /// `"MPL-2.0"`, `"LGPL-2.1-or-later"`, `"GPL-2.0-or-later"`).
    public var license: String

    /// Whether `license` is a member of the GPL copyleft family (GPL, but
    /// **not** the weaker LGPL).
    ///
    /// This is the single predicate the App-Store-exclusion guard relies on
    /// (issue #494 / DR-0001): a GPL-family tool may ship only in the Direct
    /// distribution `.dmg`, never in an App Store bundle. The match is on the
    /// SPDX form — `GPL-2.0-only`, `GPL-3.0-or-later`, and the bare legacy
    /// `GPL` all qualify; `LGPL-*` deliberately does not, because it starts
    /// with `L`. Normalise `license` to its SPDX id when adding a tool so this
    /// predicate stays reliable rather than depending on free-text spelling.
    public var isGPLFamily: Bool {
        let upper = license.uppercased()
        return upper == "GPL" || upper.hasPrefix("GPL-") || upper.hasPrefix("GPLV")
    }

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
                license: "LGPL-2.1-or-later"
            ),
            BundledTool(
                id: "hdr10plus_tool",
                name: "hdr10plus_tool",
                version: "1.6.1",
                sourceURL: "https://github.com/quietvoid/hdr10plus_tool",
                lastUpdated: "2026-04-05",
                binaryName: "hdr10plus_tool",
                description: "HDR10+ dynamic metadata extraction, injection, and validation",
                license: "MIT"
            ),
            BundledTool(
                id: "subtitle_tonemap",
                name: "subtitle_tonemap",
                version: "0.2.0",
                sourceURL: "https://github.com/quietvoid/subtitle_tonemap",
                lastUpdated: "2026-04-20",
                binaryName: "subtitle_tonemap",
                description: "Tone-map subtitle colours for HDR→SDR conversions, preserving readability",
                license: "MIT"
            ),
            BundledTool(
                id: "vtracer",
                name: "VTracer",
                version: "1.0.0-alpha.4",
                sourceURL: "https://github.com/visioncortex/vtracer",
                lastUpdated: "2026-09-03",
                binaryName: "vtracer",
                description: "Raster → SVG colour tracing (colour-quantised and photorealistic modes)",
                // Upstream is dual-licensed "MIT OR Apache-2.0"; MIT is the LICENSE
                // file at the repo root. Not GPL-family → ships in every distribution.
                license: "MIT"
            ),
        ],
        schemaVersion: 1,
        generatedDate: "2026-04-01"
    )

    // MARK: - Direct-only manifest (issue #494 / DR-0001)

    /// GPL-family tools that ship ONLY in the Direct `.dmg`. Kept out of
    /// `defaultManifest` so `test_toolBundleManifest_defaultManifestIsAppStoreSafe`
    /// stays the tripwire it was designed to be. First occupant: potrace (#473).
    public static let directOnlyManifest = ToolBundleManifest(
        tools: [
            BundledTool(
                id: "potrace",
                name: "potrace",
                version: "1.16",
                sourceURL: "https://potrace.sourceforge.net/",
                lastUpdated: "2026-09-03",
                binaryName: "potrace",
                description: "Bitmap → SVG outline / monochrome tracing (invoked as a separate process; never linked)",
                license: "GPL-2.0-or-later"
            ),
        ],
        schemaVersion: 1,
        generatedDate: "2026-09-03"
    )

    /// The manifest describing what THIS build actually bundles. App Store
    /// builds (`-DAPP_STORE`, testflight.yml/dev-build.yml) get `defaultManifest`
    /// only; every other build also carries `directOnlyManifest`. `#if APP_STORE`
    /// is the gate because it is the only build-type flag the pipelines set —
    /// release.yml keeps `DIRECT` unset (Sparkle), see release.yml:264.
    public static var activeManifest: ToolBundleManifest {
        #if APP_STORE
        return defaultManifest
        #else
        return ToolBundleManifest(
            tools: defaultManifest.tools + directOnlyManifest.tools,
            schemaVersion: defaultManifest.schemaVersion,
            generatedDate: defaultManifest.generatedDate
        )
        #endif
    }

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

    // MARK: - App Store Exclusion (issue #494 / DR-0001)

    /// The tools in this manifest that carry a GPL-family licence.
    ///
    /// These must never reach an App Store bundle. They are App-Store-excluded
    /// on two independent grounds: the GPL is incompatible with the App Store
    /// terms, and the optical-disc features they exist for cannot function in
    /// the App Sandbox anyway (no raw-device entitlement). See DR-0001.
    public var gplTools: [BundledTool] {
        tools.filter(\.isGPLFamily)
    }

    /// Whether this manifest is safe to ship in an App Store build.
    ///
    /// `defaultManifest` describes tools bundled in **every** distribution, so
    /// it must contain no GPL-family tool. Direct-only GPL tools live in
    /// `directOnlyManifest`; `activeManifest` merges them in except under
    /// `#if APP_STORE`. `verify-no-gpl-in-appstore.sh` is the second line of
    /// defence, run against the assembled bundle.
    public var isAppStoreSafe: Bool {
        gplTools.isEmpty
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
