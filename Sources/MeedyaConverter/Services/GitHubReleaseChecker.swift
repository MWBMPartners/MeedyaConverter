// ============================================================================
// MeedyaConverter — GitHubReleaseChecker
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - GitHubReleaseChecker

/// Polls the GitHub Releases API for the latest published release of the
/// MWBMPartners/MeedyaConverter repository and reports whether a newer
/// version than the running app is available.
///
/// This is the **v0.1.0 Direct-build update path (Sparkle Option A)**:
/// it ships in place of the full Sparkle 2 framework for the initial
/// release. Sparkle (Option B) is scaffolded in `Package.swift` under the
/// `DIRECT` build flag and will replace this poller for v0.2.0 once the
/// EdDSA keypair + the `update.mwbm.io` Cloudflare Worker (issue #416)
/// are stood up.
///
/// Design notes
/// ------------
/// * No third-party dependency. Uses `URLSession` + `JSONDecoder`.
/// * Calls are cached for 1 hour to be a polite GitHub API citizen — the
///   public `/releases/latest` endpoint is rate-limited to 60 requests
///   per hour per unauthenticated IP, well above what a polite poll
///   would ever need, but caching keeps us honest.
/// * Pre-release tags (`-alpha`, `-beta`, `-rc.N`) are skipped — only
///   GA releases trigger an "update available" banner.
/// * Network errors are caught and reported via `lastError` rather than
///   thrown; the user-facing settings view simply shows "Couldn't check"
///   and the user retries.
/// * Versions are compared with SemVer-aware ordering (the running
///   build's `CFBundleShortVersionString` parsed into a triple).
///
/// Why no API token / authentication
/// ---------------------------------
/// MeedyaConverter is a desktop app polling a public GitHub repo. There
/// is no shared secret to embed (we cannot ship a personal access token
/// in the binary), and the public anonymous endpoint suits this load.
/// 60 req/hour per IP is more than 1000× our polling needs.
@MainActor
@Observable
final class GitHubReleaseChecker {

    // MARK: - Public observable state

    /// The latest GA release discovered on the most recent successful check,
    /// or `nil` if no check has succeeded yet.
    private(set) var latestRelease: GitHubRelease?

    /// Whether a check is currently in flight.
    private(set) var isChecking: Bool = false

    /// When the most recent check completed (success OR failure).
    private(set) var lastCheckedAt: Date?

    /// Last error encountered, if any, since the most recent successful check.
    private(set) var lastError: String?

    /// Whether the most recent successful check found a version newer than
    /// the currently-running bundle.
    var updateAvailable: Bool {
        guard let latest = latestRelease else { return false }
        return SemVer.isNewer(latest.tagName, than: Self.currentBundleVersion)
    }

    /// Convenience accessor for the user-facing status line in the
    /// Settings → Updates tab.
    var statusMessage: String {
        if isChecking { return "Checking GitHub Releases…" }
        if let error = lastError { return "Couldn't check: \(error)" }
        guard let lastCheckedAt else { return "Not yet checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: lastCheckedAt, relativeTo: Date())
        if let latest = latestRelease, updateAvailable {
            return "Update available: \(latest.tagName) (checked \(when))"
        }
        return "Up to date with v\(Self.currentBundleVersion) (checked \(when))"
    }

    // MARK: - Configuration

    /// Cache TTL — successive `check(force:)` calls within this window
    /// return cached results unless `force: true` is passed (which the
    /// user's "Check for Updates" button does).
    private let cacheTTL: TimeInterval = 3_600  // 1 hour

    /// The repository to poll. Hard-coded to MeedyaConverter's home.
    /// `https://api.github.com/repos/<owner>/<repo>/releases/latest`
    private let releasesEndpoint = URL(
        string: "https://api.github.com/repos/MWBMPartners/MeedyaConverter/releases/latest"
    )!

    /// The URLSession used for polling. Injected for testability.
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Run a check. If a successful check completed within `cacheTTL`,
    /// returns immediately unless `force == true`.
    ///
    /// The user's "Check for Updates" button passes `force: true`. The
    /// app-launch / settings-tab-opened automatic check passes `false`.
    func check(force: Bool = false) async {
        if !force,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < cacheTTL,
           latestRelease != nil,
           lastError == nil {
            return
        }

        isChecking = true
        lastError = nil
        defer {
            isChecking = false
            lastCheckedAt = Date()
        }

        var request = URLRequest(url: releasesEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MeedyaConverter/\(Self.currentBundleVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastError = "Unexpected response"
                return
            }

            switch http.statusCode {
            case 200:
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                // Only surface GA releases — pre-releases (rc / beta / alpha)
                // are reserved for testers and shouldn't pop up as "update
                // available" on the general-audience Direct builds.
                if release.prerelease == false && release.draft == false {
                    latestRelease = release
                } else {
                    // Pre-release at the top of the list means the latest
                    // GA is older. Keep whatever we had before; don't
                    // surface a pre-release nag.
                }
            case 403:
                lastError = "GitHub rate limit reached. Try again in an hour."
            case 404:
                lastError = "Repository not found"
            case 500...599:
                lastError = "GitHub is having issues. Try again later."
            default:
                lastError = "Unexpected status code \(http.statusCode)"
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                lastError = "Not connected to the internet"
            case .timedOut:
                lastError = "Request timed out"
            default:
                lastError = urlError.localizedDescription
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Bundle version

    /// `CFBundleShortVersionString` of the running app, with a sensible
    /// fallback for environments where Bundle.main isn't an .app
    /// (CLI / library / Swift Package tests).
    static var currentBundleVersion: String {
        if let bundle = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundle.isEmpty {
            return bundle
        }
        return "0.0.0"
    }
}

// MARK: - GitHubRelease

/// Decodes the JSON payload returned by the GitHub Releases API
/// `/repos/{owner}/{repo}/releases/latest` endpoint.
///
/// Only the fields MeedyaConverter actually uses are captured —
/// `JSONDecoder` ignores the rest, which keeps us resilient to GitHub
/// adding new fields without bumping their API version.
struct GitHubRelease: Codable, Equatable, Sendable {
    /// SemVer tag like `v0.1.0` or `v0.2.0-rc.1`.
    let tagName: String

    /// The browser-facing URL of the release page.
    let htmlUrl: URL

    /// The release notes body (markdown).
    let body: String?

    /// Whether the release is flagged as a pre-release.
    let prerelease: Bool

    /// Whether the release is a draft (not yet published).
    let draft: Bool

    /// Attached release-asset files (the .dmg we point users at).
    let assets: [Asset]

    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let browserDownloadUrl: URL
        let size: Int64
        let contentType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
            case size
            case contentType = "content_type"
        }
    }

    /// The .dmg asset for this release, picked as the first asset whose
    /// filename ends in `.dmg`. `nil` if the release doesn't carry one
    /// (e.g. legacy releases that only attached a .tar.gz).
    var dmgAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case prerelease
        case draft
        case assets
    }
}

// MARK: - SemVer comparison

/// Minimal SemVer comparison just sufficient for "is the polled release
/// newer than this build?" — strips a leading `v`, splits on `.`, parses
/// the first three components as Ints, ignores pre-release / build
/// metadata.
///
/// We deliberately don't pull in a SemVer library — the comparison surface
/// is tiny and the standard library does it fine.
enum SemVer {
    /// Returns `true` iff `lhs` parses to a strictly newer triple than `rhs`.
    /// On any parse failure returns `false` so a malformed tag never
    /// triggers a spurious "update available".
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        guard let left = parseTriple(lhs), let right = parseTriple(rhs) else {
            return false
        }
        return left > right
    }

    /// Parses `v0.1.2-rc.4` → `(0, 1, 2)`. Returns nil on malformed input.
    static func parseTriple(_ s: String) -> Triple? {
        var stripped = s
        if stripped.first == "v" || stripped.first == "V" {
            stripped.removeFirst()
        }
        // Strip pre-release ("-alpha") and build-metadata ("+sha") suffixes
        if let dash = stripped.firstIndex(of: "-") {
            stripped = String(stripped[..<dash])
        }
        if let plus = stripped.firstIndex(of: "+") {
            stripped = String(stripped[..<plus])
        }
        let parts = stripped.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        return Triple(parts[0], parts[1], parts[2])
    }

    /// Comparable major.minor.patch triple.
    struct Triple: Comparable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int

        init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        static func < (lhs: Triple, rhs: Triple) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }
}
