// ============================================================================
// MeedyaConverter — GitHubReleaseChecker
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - UpdateChannel

/// The user's opted-in update channel — which release "track" the app
/// checks for updates on. Persisted at `@AppStorage("updateChannel")`
/// (see `UpdateSettingsTab` in `SettingsView.swift`), read back via
/// `UserDefaults.standard` from non-View code such as
/// `AppUpdateChecker.selectedChannel`, mirroring the pattern already
/// documented at `MetadataSettingsTab` for `metadataBackend`.
///
/// Roadmap #4:
/// * `.stable` — GA releases only. The default, and behaviourally
///   IDENTICAL to how `GitHubReleaseChecker` worked before this channel
///   concept existed — see `check(force:channel:)`'s doc comment.
/// * `.beta` / `.alpha` — opt-in pre-release channels for testers. When
///   intAppsAPI is configured, `AppUpdateChecker` checks the matching
///   remote channel slug via `IntAppsAPIClient.checkForUpdate`. When it
///   is not configured, `GitHubReleaseChecker` falls back to listing
///   GitHub releases and stops filtering out pre-release tags.
enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta
    case alpha

    /// Human-readable label for the Settings UI.
    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .beta:   return "Beta"
        case .alpha:  return "Alpha"
        }
    }
}

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
/// * Pre-release tags (`-alpha`, `-beta`, `-rc.N`) are skipped for the
///   `.stable` channel (the default, and the only channel most users
///   ever see) — only GA releases trigger an "update available" banner
///   there. Roadmap #4: a user who opts into the `.beta`/`.alpha`
///   channel (Settings → Updates) gets pre-release tags surfaced too —
///   see `check(force:channel:)`. This is purely additive: nothing about
///   the `.stable` path below changed to add it.
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
    ///
    /// **Known limitation on the `.beta`/`.alpha` channels** (#4):
    /// `SemVer.isNewer`/`parseTriple` deliberately strip the pre-release
    /// suffix before comparing (documented on `SemVer` below) — left
    /// untouched here so the `.stable` channel's comparison stays
    /// byte-for-byte identical. Two pre-release tags sharing the same
    /// `major.minor.patch` (e.g. `v0.2.0-alpha.2` → `v0.2.0-alpha.3`)
    /// therefore compare equal, not newer, on the GitHub-fallback path.
    /// This only affects testers WITHOUT intAppsAPI configured — the
    /// intAppsAPI path (`AppUpdateChecker`) gets its `update_available`
    /// verdict computed server-side, unaffected by this.
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

    /// The repository to poll for `.stable` (the default and — pre-#4 —
    /// only — channel). GitHub's `/releases/latest` is DEFINED by GitHub
    /// as "the most recent non-prerelease, non-draft release", so this
    /// endpoint alone was always sufficient to implement the pre-#4
    /// "skip pre-releases" behaviour.
    /// `https://api.github.com/repos/<owner>/<repo>/releases/latest`
    private static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/MWBMPartners/MeedyaConverter/releases/latest"
    )!

    /// The repository's full release list, used for the `.beta`/`.alpha`
    /// channels (#4) — `/releases/latest` can never return a pre-release
    /// by GitHub's own definition of that endpoint, so surfacing
    /// pre-release tags requires listing releases instead and picking
    /// the newest one that matches the selected channel client-side.
    /// `per_page=20` is comfortably more than the gap between any two
    /// alpha/beta drops in practice; if nothing in the page matches,
    /// `latestRelease` is simply left unchanged, exactly like the
    /// `.stable` "no GA release found" case below.
    private static let releasesListEndpoint = URL(
        string: "https://api.github.com/repos/MWBMPartners/MeedyaConverter/releases?per_page=20"
    )!

    /// The URLSession used for polling. Injected for testability.
    private let session: URLSession

    /// The channel of the most recently COMPLETED check (successful or
    /// not) — used only to invalidate the `cacheTTL` short-circuit when
    /// the user switches channels between calls, so switching from
    /// Stable to Alpha doesn't serve up to an hour of stale Stable data.
    /// `nil` before the first check ever runs.
    private var lastCheckedChannel: UpdateChannel?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Run a check. If a successful check completed within `cacheTTL`
    /// **for the same channel**, returns immediately unless `force ==
    /// true`.
    ///
    /// The user's "Check for Updates" button passes `force: true`. The
    /// app-launch / settings-tab-opened automatic check passes `false`.
    ///
    /// - Parameter channel: Which release channel to check. Defaults to
    ///   `.stable`, and every call site that doesn't explicitly opt a
    ///   user into a pre-release channel gets byte-for-byte the same
    ///   request (`latestReleaseEndpoint`) and filtering
    ///   (`prerelease == false && draft == false`) this method always
    ///   used, pre-#4.
    func check(force: Bool = false, channel: UpdateChannel = .stable) async {
        if !force,
           lastCheckedChannel == channel,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < cacheTTL,
           latestRelease != nil,
           lastError == nil {
            return
        }

        isChecking = true
        lastError = nil
        lastCheckedChannel = channel
        defer {
            isChecking = false
            lastCheckedAt = Date()
        }

        var request = URLRequest(url: channel == .stable ? Self.latestReleaseEndpoint : Self.releasesListEndpoint)
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
                if channel == .stable {
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
                } else {
                    // #4: Beta/Alpha — the newest non-draft release in the
                    // list, pre-release tag or not. This is the one actual
                    // behaviour change for issue #4: stop filtering out
                    // `-alpha`/`-beta`/`-rc` tags once the tester has opted
                    // in via Settings → Updates.
                    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                    if let newest = releases.first(where: { $0.draft == false }) {
                        latestRelease = newest
                    }
                    // else: nothing in this page qualifies — keep whatever
                    // we had before, same "don't surface a nag" policy as
                    // the .stable branch above.
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
    /// filename ends in `.dmg` AND whose `browser_download_url` host is
    /// in the GitHub-served allowlist. `nil` if the release doesn't
    /// carry one (e.g. legacy releases that only attached a .tar.gz)
    /// or if every candidate's host fails the allowlist.
    ///
    /// **Why the host check** (SECURITY.md threat T3 / finding F-003):
    /// the GitHub Releases API is the trusted source of truth for asset
    /// URLs, but `browser_download_url` is a JSON-encoded URL string —
    /// a future API change (or a maliciously edited release asset that
    /// gets past GitHub's own validation, or a community fork pointing
    /// at a mirror) could produce a URL on an unexpected host. Since
    /// the SettingsView "Download DMG" button opens this URL via
    /// `NSWorkspace.shared.open(_:)` — handing it to the user's
    /// browser without further validation — a non-github host would
    /// be a redirect-to-attacker vector. The allowlist is the
    /// **minimum** trustworthy set for GitHub-served release assets;
    /// the lowercase comparison is deliberate (URL hosts are
    /// case-insensitive per RFC 3986).
    var dmgAsset: Asset? {
        assets.first { asset in
            guard asset.name.lowercased().hasSuffix(".dmg") else { return false }
            guard let host = asset.browserDownloadUrl.host?.lowercased() else { return false }
            return Self.dmgAssetHostAllowlist.contains(host)
        }
    }

    /// Hosts permitted to serve release `.dmg` assets. GitHub Releases
    /// returns one of these two hosts as of 2026 — `github.com` for
    /// direct release downloads and `objects.githubusercontent.com`
    /// for redirected CDN downloads. Any other host fails the
    /// `dmgAsset` validation and the SettingsView falls back to
    /// pointing the user at the release page instead.
    fileprivate static let dmgAssetHostAllowlist: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
    ]

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
