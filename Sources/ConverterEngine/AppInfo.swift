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

    public enum Version {
        /// Semantic version number (X.Y.Z).
        public static let number = "0.1.0"

        /// Optional version codename.
        public static let codename: String? = nil

        /// Development status: "Alpha", "Beta", "RC", or nil for release.
        public static let developmentStatus: String? = "Alpha"

        /// Full display version string (e.g., "0.1.0-alpha").
        public static var displayString: String {
            if let status = developmentStatus {
                return "\(number)-\(status.lowercased())"
            }
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
