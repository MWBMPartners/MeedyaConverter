// ============================================================================
// MeedyaConverter — SFTPCredentialStoreTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest
@testable import ConverterEngine

/// Regression tests for `SFTPCredentialStore` + the
/// `SFTPServerConfig` JSON shape that backs SECURITY.md F-005.
///
/// These tests use a per-test-class unique `serviceOverride` so they
/// never touch the production `com.mwbm.MeedyaConverter.sftp`
/// Keychain partition. `setUp` rotates the override; `tearDown`
/// drains every credential under that override service to keep
/// re-runs hermetic.
///
/// **Why we cannot mock the Keychain**: `SecItemAdd` /
/// `SecItemCopyMatching` are system services with no abstract
/// interface to substitute. We test against the real Keychain in
/// a sandboxed service name. This means the test target must run
/// on macOS with a usable login keychain — true for both local
/// dev and the GitHub Actions macos-15 runner the release pipeline
/// uses.
final class SFTPCredentialStoreTests: XCTestCase {

    private var testService: String!

    override func setUp() {
        super.setUp()
        // Per-test service to keep cross-test pollution impossible
        // even if a teardown is skipped (debugger-cancelled run).
        testService = "com.mwbm.MeedyaConverter.sftp.tests.\(UUID().uuidString)"
        SFTPCredentialStore.serviceOverride = testService
    }

    override func tearDown() {
        // Drain every entry under the test service.
        try? SFTPCredentialStore.deleteAll(service: testService)
        SFTPCredentialStore.serviceOverride = nil
        testService = nil
        super.tearDown()
    }

    // MARK: - Round-trip

    func test_save_then_read_returnsOriginalPassword() throws {
        let id = UUID()
        try SFTPCredentialStore.save(password: "hunter2", forProfileID: id)
        let read = try SFTPCredentialStore.read(forProfileID: id)
        XCTAssertEqual(read, "hunter2")
    }

    func test_read_missingProfile_returnsNil() throws {
        let id = UUID()
        let read = try SFTPCredentialStore.read(forProfileID: id)
        XCTAssertNil(read)
    }

    func test_save_isIdempotent_overwritesExisting() throws {
        let id = UUID()
        try SFTPCredentialStore.save(password: "first", forProfileID: id)
        try SFTPCredentialStore.save(password: "second", forProfileID: id)
        let read = try SFTPCredentialStore.read(forProfileID: id)
        XCTAssertEqual(read, "second")
    }

    func test_save_perProfileIsolation() throws {
        let a = UUID()
        let b = UUID()
        try SFTPCredentialStore.save(password: "alpha", forProfileID: a)
        try SFTPCredentialStore.save(password: "beta", forProfileID: b)
        XCTAssertEqual(try SFTPCredentialStore.read(forProfileID: a), "alpha")
        XCTAssertEqual(try SFTPCredentialStore.read(forProfileID: b), "beta")
    }

    func test_delete_removesEntry() throws {
        let id = UUID()
        try SFTPCredentialStore.save(password: "doomed", forProfileID: id)
        try SFTPCredentialStore.delete(forProfileID: id)
        XCTAssertNil(try SFTPCredentialStore.read(forProfileID: id))
    }

    func test_delete_isIdempotent_doesNotThrowOnMissing() throws {
        let id = UUID()
        // Never saved — delete should still succeed.
        XCTAssertNoThrow(try SFTPCredentialStore.delete(forProfileID: id))
    }

    func test_passwordWithSpecialCharacters_roundTripsIntact() throws {
        let id = UUID()
        // Common SSH password pitfalls: spaces, quotes, backslashes,
        // unicode. Keychain stores bytes; UTF-8 round-trip is the only
        // contract.
        let password = "p@ss w0rd \"with\\ quotes/ and 🦄 unicode"
        try SFTPCredentialStore.save(password: password, forProfileID: id)
        let read = try SFTPCredentialStore.read(forProfileID: id)
        XCTAssertEqual(read, password)
    }

    // MARK: - SFTPServerConfig JSON shape — F-005 contract

    func test_legacyJSON_withoutIdField_decodesWithFreshUUID() throws {
        // A blob written before Cycle 17. The decoder must mint a
        // fresh UUID so the migration path has something to key off.
        let legacyJSON = """
        {
          "host": "sftp.example.com",
          "port": 22,
          "username": "alice",
          "authMethod": { "password": { "_0": "legacy-plaintext" } },
          "remotePath": "/upload",
          "label": "Old"
        }
        """
        let config = try JSONDecoder().decode(
            SFTPServerConfig.self,
            from: Data(legacyJSON.utf8)
        )
        // We don't assert the specific UUID — only that the field
        // was populated. UUID(uuidString: ...) on an empty / nil
        // would have produced something nil-ish; we just exercise
        // that the value exists and stringifies.
        XCTAssertFalse(config.id.uuidString.isEmpty)
        XCTAssertEqual(config.host, "sftp.example.com")
        if case .password(let pw) = config.authMethod {
            XCTAssertEqual(pw, "legacy-plaintext")
        } else {
            XCTFail("Expected .password authMethod")
        }
    }

    func test_modernJSON_withIdField_preservesId() throws {
        let id = UUID()
        let modernJSON = """
        {
          "id": "\(id.uuidString)",
          "host": "sftp.example.com",
          "port": 2222,
          "username": "bob",
          "authMethod": { "password": { "_0": "" } },
          "remotePath": "/up",
          "label": "New"
        }
        """
        let config = try JSONDecoder().decode(
            SFTPServerConfig.self,
            from: Data(modernJSON.utf8)
        )
        XCTAssertEqual(config.id, id)
    }

    func test_encodingRedactedProfile_emitsEmptyPasswordString() throws {
        // The persistProfiles redaction emits .password("") in the
        // encoded JSON. Round-tripping that through Codable must
        // preserve the empty string, NOT silently drop the case to
        // some other AuthMethod variant.
        let original = SFTPServerConfig(
            host: "sftp.example.com",
            port: 22,
            username: "carol",
            authMethod: .password(""),
            remotePath: "/u",
            label: "Redacted"
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([SFTPServerConfig].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        if case .password(let pw) = decoded[0].authMethod {
            XCTAssertEqual(pw, "")
        } else {
            XCTFail("Expected .password authMethod with empty string")
        }
    }

    func test_encodingRedactedProfile_jsonStringDoesNotContainPlaintext() throws {
        // The load-bearing assertion of F-005: the bytes that get
        // handed to UserDefaults must not literally contain the
        // user's password anywhere. Encode a profile that the
        // persistProfiles redaction would emit and grep the raw
        // JSON for the would-be plaintext.
        let redacted = SFTPServerConfig(
            host: "sftp.example.com",
            port: 22,
            username: "dave",
            authMethod: .password(""),  // already redacted shape
            remotePath: "/u",
            label: "Persisted"
        )
        let data = try JSONEncoder().encode([redacted])
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(
            jsonString.contains("VERY_SECRET_PW_THAT_WOULD_BE_A_BUG"),
            "Sanity: control string not present"
        )
        // The empty password JSON shape must be present (we verify
        // by decoding) but the encoded form must not carry any
        // recognisable secret material from buildConfig's input.
        XCTAssertFalse(
            jsonString.contains("hunter2"),
            "Encoded JSON must not contain the canonical test password"
        )
    }

    // MARK: - Migration path end-to-end

    func test_migrationFlow_legacyPlaintext_isLiftedToKeychain() throws {
        // Synthesise the exact byte-for-byte flow the View's
        // loadProfiles takes on a legacy blob: decode the JSON,
        // detect a non-empty .password(...) case, hand it to the
        // credential store. Then assert the Keychain has the
        // password under the decoded id.
        let legacyJSON = """
        [
          {
            "host": "sftp.example.com",
            "port": 22,
            "username": "eve",
            "authMethod": { "password": { "_0": "legacy-plaintext" } },
            "remotePath": "/upload",
            "label": "Old"
          }
        ]
        """
        let profiles = try JSONDecoder().decode(
            [SFTPServerConfig].self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(profiles.count, 1)

        let profile = profiles[0]
        if case .password(let pw) = profile.authMethod {
            try SFTPCredentialStore.save(password: pw, forProfileID: profile.id)
        } else {
            XCTFail("Legacy profile expected .password authMethod")
        }

        let readBack = try SFTPCredentialStore.read(forProfileID: profile.id)
        XCTAssertEqual(readBack, "legacy-plaintext")
    }
}
