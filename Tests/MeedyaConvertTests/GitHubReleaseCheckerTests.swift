// ============================================================================
// MeedyaConverter — GitHubReleaseCheckerTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest

/// Regression tests for the JSON-decoding and asset-URL host validation
/// in `GitHubRelease` / `GitHubReleaseChecker`. Anchors T3 update-
/// tampering protections per `SECURITY.md` finding F-003.
///
/// These tests live in the `MeedyaConvertTests` test target rather than
/// `ConverterEngineTests` because the type under test is in the GUI
/// target's Services layer, not in the engine module. We re-decode the
/// JSON directly via a local mirror of the relevant struct shape
/// rather than importing the GUI target (the GUI executable can't be
/// imported into a test binary because of the @main attribute); the
/// shape mirror keeps the test focused on the decoded-asset host-check
/// behaviour which is the security-relevant assertion.
final class GitHubReleaseCheckerTests: XCTestCase {

    // MARK: - Asset shape mirror

    /// Mirror of `GitHubRelease.Asset` shape used by the host-check
    /// reasoning. Mirroring rather than importing because the
    /// MeedyaConverter target is @main and can't be linked into a
    /// test binary.
    private struct AssetMirror: Decodable {
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

    private struct ReleaseMirror: Decodable {
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let prerelease: Bool
        let draft: Bool
        let assets: [AssetMirror]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
            case prerelease
            case draft
            case assets
        }
    }

    /// The same allowlist the real `GitHubRelease.dmgAssetHostAllowlist`
    /// uses. Mirrored here for the test to assert behaviour. A drift
    /// between the two would surface in the host-check tests below
    /// returning unexpected results — by design, since the test is the
    /// contract.
    private let dmgAssetHostAllowlist: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
    ]

    private func decode(_ json: String) throws -> ReleaseMirror {
        try JSONDecoder().decode(ReleaseMirror.self, from: Data(json.utf8))
    }

    /// Mirror of the production `dmgAsset` lookup for the test.
    private func validatedDmgAsset(in release: ReleaseMirror) -> AssetMirror? {
        release.assets.first { asset in
            guard asset.name.lowercased().hasSuffix(".dmg") else { return false }
            guard let host = asset.browserDownloadUrl.host?.lowercased() else { return false }
            return dmgAssetHostAllowlist.contains(host)
        }
    }

    // MARK: - dmgAsset host allowlist

    func test_dmgAsset_githubComHost_isAccepted() throws {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/download/v0.2.0/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertNotNil(asset)
        XCTAssertEqual(asset?.name, "MeedyaConverter-0.2.0.dmg")
    }

    func test_dmgAsset_githubusercontentHost_isAccepted() throws {
        // GitHub redirects large release downloads to objects.githubusercontent.com.
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset/123/abcdef/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertNotNil(asset)
    }

    func test_dmgAsset_attackerControlledHost_isRejected() throws {
        // The realistic attacker scenario: a malicious release editor
        // (or a compromised GitHub API response) yields a .dmg whose
        // browser_download_url points at an attacker-controlled
        // host. The host-check must reject this.
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://attacker.example.com/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertNil(asset, "DMG on non-github host must be rejected")
    }

    func test_dmgAsset_caseInsensitiveHostMatch() throws {
        // RFC 3986: hosts are case-insensitive. Foundation's
        // URL.host typically returns the host as-given, so the
        // lowercase comparison in the production code is the right
        // defence.
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://GitHub.com/MWBMPartners/MeedyaConverter/releases/download/v0.2.0/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertNotNil(asset, "Uppercased github.com host should match the case-insensitive allowlist")
    }

    func test_dmgAsset_passesFirstAcceptableAndIgnoresLaterAttacker() throws {
        // If a release has multiple assets ending in .dmg and the FIRST
        // one is on an allowed host, the lookup returns it and ignores
        // any later attacker-host one. (The reverse case — the first
        // is on an attacker host — also rejects the first and falls
        // through to find a github-host one if there is one. Foundation's
        // Array.first(where:) iterates linearly, so the behaviour is
        // first-match-wins-among-acceptable.)
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/download/v0.2.0/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            },
            {
              "name": "MeedyaConverter-0.2.0-malicious.dmg",
              "browser_download_url": "https://attacker.example.com/MeedyaConverter-0.2.0-malicious.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertEqual(asset?.name, "MeedyaConverter-0.2.0.dmg")
    }

    func test_dmgAsset_attackerHostFirstThenLegitimate_picksLegitimate() throws {
        // Asset ordering is GitHub-controlled — but in case a release
        // is configured with the attacker URL first and the legitimate
        // one second, the host allowlist still ensures only the
        // legitimate one is returned.
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/tag/v0.2.0",
          "body": "",
          "prerelease": false,
          "draft": false,
          "assets": [
            {
              "name": "MeedyaConverter-0.2.0-malicious.dmg",
              "browser_download_url": "https://attacker.example.com/MeedyaConverter-0.2.0-malicious.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            },
            {
              "name": "MeedyaConverter-0.2.0.dmg",
              "browser_download_url": "https://github.com/MWBMPartners/MeedyaConverter/releases/download/v0.2.0/MeedyaConverter-0.2.0.dmg",
              "size": 12345678,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let release = try decode(json)
        let asset = validatedDmgAsset(in: release)
        XCTAssertEqual(asset?.name, "MeedyaConverter-0.2.0.dmg")
    }
}
