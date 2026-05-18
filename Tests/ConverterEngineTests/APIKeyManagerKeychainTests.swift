// ============================================================================
// MeedyaConverter — APIKeyManager Keychain migration tests (Issue #380)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Verifies the security-relevant invariants of the post-#380 APIKeyManager:
//
//   * Secrets round-trip through the Keychain — a new manager instance with
//     the same storage directory and service hydrates the same secrets the
//     previous instance wrote.
//   * The on-disk `api_keys.json` envelope contains ONLY metadata. The four
//     secret fields (`apiKey`, `secretKey`, `accessToken`, `refreshToken`)
//     must never appear in plaintext form on disk after a store call.
//   * Legacy migration: a hand-written `api_keys.json` in the pre-#380
//     `[StoredAPIKey]` shape (with secrets in plaintext) is migrated into
//     the Keychain on first load, and the file is rewritten in the new
//     metadata-only envelope shape.
//
// `@testable import` is used so the tests can call
// `APIKeyManagerTestSupport.clearKeychain(service:)` between runs. This
// matches the policy described at the top of ConverterEngineTests.swift —
// use `@testable` only when private-state access is genuinely required.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class APIKeyManagerKeychainTests: XCTestCase {

    // -----------------------------------------------------------------
    // MARK: - Test fixtures
    // -----------------------------------------------------------------

    /// Unique Keychain service for this test instance so we never collide
    /// with the user's real API key store, nor with parallel test runs.
    private var keychainService: String!

    /// Unique storage directory backing the JSON envelope, deleted in
    /// `tearDown` to keep the test sandbox clean.
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        keychainService = "Ltd.MWBMpartners.MeedyaConverter.Tests.APIKeys.\(UUID().uuidString)"
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apikeymanager-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        APIKeyManagerTestSupport.clearKeychain(service: keychainService)
        try? FileManager.default.removeItem(at: storageDirectory)
        super.tearDown()
    }

    /// Absolute path the manager uses for its envelope file.
    private var jsonURL: URL { storageDirectory.appendingPathComponent("api_keys.json") }

    // -----------------------------------------------------------------
    // MARK: - Invariant 1: round-trip through the Keychain
    // -----------------------------------------------------------------

    /// Verifies that secrets stored by one manager instance are visible
    /// to a fresh manager instance pointed at the same storage and
    /// Keychain service.
    func test_apiKeyManager_roundTripsAllSecretsThroughKeychain() {
        // -- First instance: store a key with every secret field set. --
        let original = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        let stored = StoredAPIKey(
            provider: .awsS3,
            apiKey: "AKIA-TEST-ACCESS-KEY",
            secretKey: "test-secret-key-payload",
            accessToken: "oauth-access-token",
            refreshToken: "oauth-refresh-token",
            tokenExpiry: Date(timeIntervalSince1970: 1_800_000_000),
            label: "primary"
        )
        original.storeKey(stored)

        // -- Second instance: hydrate from disk + Keychain. --
        let reopened = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        guard let recovered = reopened.key(for: .awsS3) else {
            return XCTFail("Expected to hydrate the stored key on reopen.")
        }
        XCTAssertEqual(recovered.apiKey, "AKIA-TEST-ACCESS-KEY")
        XCTAssertEqual(recovered.secretKey, "test-secret-key-payload")
        XCTAssertEqual(recovered.accessToken, "oauth-access-token")
        XCTAssertEqual(recovered.refreshToken, "oauth-refresh-token")
        XCTAssertEqual(recovered.label, "primary")
        XCTAssertEqual(
            recovered.tokenExpiry,
            Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 2: secrets do not leak to disk
    // -----------------------------------------------------------------

    /// Verifies that after `storeKey`, the JSON envelope on disk contains
    /// none of the secret material. This is the core invariant the audit
    /// (issue #380) demanded.
    func test_apiKeyManager_doesNotWriteSecretsToDisk() throws {
        let manager = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        // Each secret field uses a distinctive marker so a substring scan
        // of the JSON file unambiguously fails if any of them leaked.
        let key = StoredAPIKey(
            provider: .tmdb,
            apiKey: "API-KEY-LEAK-CANARY",
            secretKey: "SECRET-KEY-LEAK-CANARY",
            accessToken: "ACCESS-TOKEN-LEAK-CANARY",
            refreshToken: "REFRESH-TOKEN-LEAK-CANARY",
            label: "rotation-test"
        )
        manager.storeKey(key)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: jsonURL.path),
            "Manager should have written the metadata envelope."
        )
        let onDisk = try String(contentsOf: jsonURL, encoding: .utf8)
        for canary in [
            "API-KEY-LEAK-CANARY",
            "SECRET-KEY-LEAK-CANARY",
            "ACCESS-TOKEN-LEAK-CANARY",
            "REFRESH-TOKEN-LEAK-CANARY",
        ] {
            XCTAssertFalse(
                onDisk.contains(canary),
                "Secret `\(canary)` leaked into the on-disk envelope. "
                + "Issue #380 requires that only metadata be persisted."
            )
        }

        // The envelope should however carry the metadata we expect, so a
        // future manager instance can find its Keychain entry.
        XCTAssertTrue(onDisk.contains("\"version\""))
        XCTAssertTrue(onDisk.contains("tmdb"))
        XCTAssertTrue(onDisk.contains("rotation-test"))
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 3: legacy migration
    // -----------------------------------------------------------------

    /// Verifies that a pre-#380 `[StoredAPIKey]` JSON file (with secrets
    /// in plaintext) is migrated into the Keychain on first load and the
    /// file is rewritten in the metadata-only envelope shape.
    func test_apiKeyManager_migratesLegacyPlaintextStore() throws {
        // -- Hand-write a v1-shape file containing one record with all
        //    four secret fields populated. --
        let legacyJSON = """
        [
          {
            "provider": "tmdb",
            "apiKey": "LEGACY-API-KEY",
            "secretKey": "LEGACY-SECRET-KEY",
            "accessToken": "LEGACY-ACCESS-TOKEN",
            "refreshToken": "LEGACY-REFRESH-TOKEN",
            "label": "migrated",
            "addedDate": "2026-01-01T00:00:00Z",
            "isActive": true
          }
        ]
        """
        try legacyJSON.write(to: jsonURL, atomically: true, encoding: .utf8)

        // -- Instantiating the manager should trigger the migration. --
        let manager = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )

        // -- Secrets are recoverable via the public API. --
        guard let migrated = manager.key(for: .tmdb) else {
            return XCTFail("Expected the migrated key to be loaded.")
        }
        XCTAssertEqual(migrated.apiKey, "LEGACY-API-KEY")
        XCTAssertEqual(migrated.secretKey, "LEGACY-SECRET-KEY")
        XCTAssertEqual(migrated.accessToken, "LEGACY-ACCESS-TOKEN")
        XCTAssertEqual(migrated.refreshToken, "LEGACY-REFRESH-TOKEN")
        XCTAssertEqual(migrated.label, "migrated")

        // -- The file on disk has been rewritten in v2 shape without any
        //    of the plaintext secrets. --
        let rewritten = try String(contentsOf: jsonURL, encoding: .utf8)
        XCTAssertTrue(rewritten.contains("\"version\""),
                      "Post-migration file must be the v2 envelope.")
        for canary in [
            "LEGACY-API-KEY",
            "LEGACY-SECRET-KEY",
            "LEGACY-ACCESS-TOKEN",
            "LEGACY-REFRESH-TOKEN",
        ] {
            XCTAssertFalse(
                rewritten.contains(canary),
                "After migration, secret `\(canary)` must not remain on "
                + "disk; it should live exclusively in the Keychain."
            )
        }

        // -- A second manager instance also sees the migrated secrets,
        //    via the new envelope this time. --
        let reopened = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        XCTAssertEqual(reopened.key(for: .tmdb)?.apiKey, "LEGACY-API-KEY")
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 4: deletion removes the Keychain item
    // -----------------------------------------------------------------

    /// Verifies that `removeKey` actually deletes the matching Keychain
    /// item — otherwise a re-added key would silently inherit the old
    /// secret.
    func test_apiKeyManager_removeKey_deletesKeychainItem() {
        let manager = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        let first = StoredAPIKey(
            provider: .tmdb,
            apiKey: "FIRST-KEY",
            label: "rotation"
        )
        manager.storeKey(first)
        manager.removeKey(provider: .tmdb, label: "rotation")

        // Re-create the manager — the in-memory cache is gone now, so the
        // only way the secret could come back is if the Keychain still
        // held it. It must not.
        let reopened = APIKeyManager(
            storageDirectory: storageDirectory,
            keychainService: keychainService
        )
        XCTAssertNil(
            reopened.key(for: .tmdb),
            "Removing a key must clear the matching Keychain item; "
            + "otherwise re-adding the same (provider,label) would "
            + "silently inherit the previous secret."
        )
    }
}
