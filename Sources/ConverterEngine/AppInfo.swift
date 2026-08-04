// ============================================================================
// MeedyaConverter — AppInfo (Central Application Identity)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

/// Central source of truth for application identity, version, vendor,
/// copyright, and license information.
///
/// Follows the pattern established by `infoAppVer.php` in the phpWhoIs project.
/// All targets (ConverterEngine, meedya-convert, MeedyaConverter) reference
/// this single file for version and identity data.
public enum AppInfo {

    // MARK: - Application Identity

    public enum Application {

        // MARK: Bundle Identifiers

        /// Bundle ID for Apple App Store distribution (sandboxed, FFmpegKit, no Sparkle).
        public static let appStoreBundleId = "Ltd.MWBMpartners.MeedyaConverter.Lite"

        /// Bundle ID for direct distribution (macOS, Windows, Linux).
        /// Hardened runtime, system FFmpeg via Process, Sparkle updates.
        public static let directBundleId = "Ltd.MWBMpartners.MeedyaConverter"

        /// The active bundle ID for the current build configuration.
        /// App Store builds use the `.Lite` suffix; all other platforms share the direct ID.
        public static var id: String {
            #if APP_STORE
            return appStoreBundleId
            #else
            return directBundleId
            #endif
        }

        /// Shared App Group identifier for data sharing between App Store and direct builds.
        /// Allows users to switch distribution channels without losing profiles/settings.
        public static let appGroupId = "group.Ltd.MWBMpartners.MeedyaConverter"

        // MARK: Application Metadata

        /// Human-readable application name.
        public static let name = "MeedyaConverter"

        /// Application website URL.
        public static let websiteURL = ""

        /// Short description.
        public static let synopsis = "Professional cross-platform media conversion with passthrough, HDR, spatial audio, disc ripping, and cloud uploads."

        /// SEO/discovery keywords.
        public static let keywords = "media converter, video transcoder, FFmpeg, HDR, HLS, DASH, disc ripping, audio conversion, image conversion"
    }

    // MARK: - Version

    /// Version information for the application.
    ///
    /// **Single source of truth:** the `VERSION` file at the repo root.
    /// `VERSION` is synchronised into:
    ///   - `Sources/MeedyaConverter/Resources/Info.plist`
    ///     (`CFBundleShortVersionString`), which is read here at runtime via
    ///     `Bundle.main.infoDictionary`.
    ///   - The `fallbackNumber` constant below, which is used only when no
    ///     `Info.plist` is available (e.g. when the `ConverterEngine` library
    ///     is loaded by `swift test` or the `meedya-convert` CLI without a
    ///     packaged `.app` bundle).
    ///
    /// Both sinks are kept in sync by `Scripts/build/sync-app-info-version.sh`,
    /// which CI invokes before every build. Run it manually after editing
    /// `VERSION`:
    /// ```
    /// ./Scripts/build/sync-app-info-version.sh
    /// ```
    ///
    /// The historical hard-coded `"Alpha"` development-status suffix has been
    /// removed; pre-release status (e.g. `0.1.0-alpha`, `0.1.0-beta.3`) should
    /// now be encoded directly in the `VERSION` file as a SemVer pre-release
    /// identifier, so the same string flows through Info.plist, the in-app
    /// "About" panel, and the AppleScript scripting bridge without divergence.
    public enum Version {

        /// Fallback semantic version (X.Y.Z[-pre]) used when
        /// `CFBundleShortVersionString` is unavailable from `Bundle.main`.
        ///
        /// **Keep this in sync with `VERSION`** — `sync-app-info-version.sh`
        /// rewrites this line automatically; the marker comment below is the
        /// anchor the script greps for.
        // sync-app-info-version: fallbackNumber
        public static let fallbackNumber = "0.1.0"

        /// Semantic version number (X.Y.Z[-pre]).
        ///
        /// Read from `CFBundleShortVersionString` in `Bundle.main.infoDictionary`
        /// at runtime. Falls back to `fallbackNumber` when no bundle Info.plist
        /// is loaded **or** when the loaded value does not look like a SemVer
        /// triple (CLI / library / test contexts).
        ///
        /// **Why the SemVer shape check** (Cycle 24): under `swift test`,
        /// `Bundle.main.infoDictionary["CFBundleShortVersionString"]` is
        /// non-empty — it returns a default like `"16.0"` (the macOS / Xcode
        /// SDK marker), not the app's own version. An `isEmpty`-only fallback
        /// therefore lets that leak into `ConverterEngine.version` and breaks
        /// the SemVer-shape regression test. The triple-dot heuristic
        /// rejects two-segment SDK markers without rejecting legitimate
        /// pre-release / build-metadata suffixes (those follow the
        /// `MAJOR.MINOR.PATCH[-pre][+build]` core).
        public static var number: String {
            if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               !bundleVersion.isEmpty,
               looksLikeSemVerTriple(bundleVersion) {
                return bundleVersion
            }
            return fallbackNumber
        }

        /// Returns `true` when `version` starts with a `MAJOR.MINOR.PATCH`
        /// triple of integers. Anything after the patch component
        /// (`-alpha`, `+build.123`, etc.) is ignored — what matters is
        /// that the *core* is well-formed.
        private static func looksLikeSemVerTriple(_ version: String) -> Bool {
            let withoutBuild = version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""
            let core         = withoutBuild.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            let components   = core.split(separator: ".")
            guard components.count >= 3 else { return false }
            for component in components.prefix(3) {
                if Int(component) == nil { return false }
            }
            return true
        }

        /// Optional version codename.
        public static let codename: String? = nil

        /// Full display version string. Equal to `number` — any pre-release
        /// suffix (e.g. `-alpha`, `-beta.2`, `-rc.1`) is encoded in the
        /// `VERSION` file / `CFBundleShortVersionString` itself.
        public static var displayString: String {
            return number
        }

        /// Repo build metadata (populated by CI at build time).
        public enum Build {
            /// Git commit SHA (full). Set by CI via environment or code generation.
            nonisolated(unsafe) public static var commitSHA: String? = nil

            /// Git commit SHA (short, 7 chars).
            public static var commitSHAShort: String? {
                commitSHA.map { String($0.prefix(7)) }
            }

            /// Git commit date (ISO 8601).
            nonisolated(unsafe) public static var commitDate: String? = nil

            /// GitHub commit URL.
            public static var commitURL: String? {
                guard let sha = commitSHA else { return nil }
                return "https://github.com/MWBMPartners/MeedyaConverter/commit/\(sha)"
            }
        }
    }

    // MARK: - Vendor

    public enum Vendor {
        public static let name = "MWBM Partners Ltd"
        public static let websiteURL = "https://www.MWBMpartners.Ltd"

        public enum Parent {
            public static let name = "MWBM Partners Ltd"
            public static let websiteURL = "https://www.MWBMpartners.Ltd"
        }
    }

    // MARK: - Copyright

    public enum Copyright {
        public static let startYear = "2026"

        /// Dynamically generates copyright string with current year.
        public static var statement: String {
            let currentYear = Calendar.current.component(.year, from: Date())
            let yearString = currentYear > Int(startYear)! ? "\(startYear)-\(currentYear)" : startYear
            return "Copyright \u{00A9} \(yearString) \(Vendor.name). All rights reserved."
        }

        public static let rightsStatement = "All Rights Reserved"
    }

    // MARK: - License

    public enum License {
        public static let type = "Proprietary"
        public static let userLicenseType = "Freemium"
        public static let userLicenseCost = "Free (with paid tiers)"
    }
}
