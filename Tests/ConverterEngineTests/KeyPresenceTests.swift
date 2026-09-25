// ============================================================================
// MeedyaConverter — KeyPresence tests (Issue #506 commit 2)
// Tests/ConverterEngineTests/KeyPresenceTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Covers the "is a key saved?" checks that never read the key:
//   - `APIKeyManager.hasStoredKey(for:label:storageDirectory:keychainService:)`
//   - `SFTPCredentialStore.exists(forProfileID:)`
//   - `SMTPPasswordKeychain.exists()` (through its internal test seam)
// and the one attributes-only Keychain query all three share
// (`KeychainItemExistence.query`, in `KeyPresence.swift`).
//
// Isolation — every test gets its own:
//   - temporary storage folder for `api_keys.json`, deleted in `tearDown`;
//   - Keychain services named `….Tests.KeyPresence.<kind>.<UUID>`, one each
//     for API keys, SFTP and SMTP, every item under them deleted in
//     `tearDown`. Nothing here ever touches the real services
//     (`Ltd.MWBMpartners.MeedyaConverter.APIKeys`,
//     `com.mwbm.MeedyaConverter.sftp`, `Ltd.MWBMpartners.MeedyaConverter.smtp`).
// No UserDefaults suites are created, so there are no preference files to
// clean up.
//
// Keychain availability: tests that need a WORKING Keychain call
// `try XCTSkipUnless(keychainIsAvailable(), …)` first — the same round-trip
// probe as `APIKeyManagerKeychainTests.probeKeychainPersistence()`, returned
// as a `Bool` the way `APIKeyManagerIndexConsistencyTests` does it. Tests
// that only exercise the saved-keys FILE (missing, unreadable, corrupt,
// pre-Keychain format) or the query's SHAPE run everywhere, including on a
// CI runner with no unlocked Keychain — skipping them there would skip the
// very checks that matter most on such a runner.
//
// SFTP isolation uses the store's existing `serviceOverride` seam (the same
// one `SFTPCredentialStoreTests` uses), restored in `tearDown`. It is a
// process-wide setting; that is safe because XCTest runs the tests inside
// one process one after another, and `swift test --parallel` splits tests
// across separate processes.
//
// `@testable import` is needed for `KeychainItemExistence.query`,
// `SMTPPasswordKeychain.exists(service:account:)` and
// `APIKeyManagerTestSupport.clearKeychain(service:)`.
// ---------------------------------------------------------------------------

import XCTest
import Security
@testable import ConverterEngine

final class KeyPresenceTests: XCTestCase {

    // -----------------------------------------------------------------
    // MARK: - Test fixtures
    // -----------------------------------------------------------------

    /// This test's own folder for `api_keys.json`.
    private var storageDirectory: URL!

    /// This test's own Keychain services — one per kind of secret.
    private var apiKeyService: String!
    private var sftpService: String!
    private var smtpService: String!

    /// Whatever `SFTPCredentialStore.serviceOverride` held before this test
    /// replaced it, put back in `tearDown` (normally nil).
    private var previousSFTPServiceOverride: String?

    /// A string that must never appear in any output of a presence check.
    /// Unique per test so a leftover from another run can't be mistaken for
    /// a leak from this one.
    private var sentinel: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let unique = UUID().uuidString
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypresence-tests-\(unique)")
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        apiKeyService = "Ltd.MWBMpartners.MeedyaConverter.Tests.KeyPresence.APIKeys.\(unique)"
        sftpService = "Ltd.MWBMpartners.MeedyaConverter.Tests.KeyPresence.SFTP.\(unique)"
        smtpService = "Ltd.MWBMpartners.MeedyaConverter.Tests.KeyPresence.SMTP.\(unique)"
        sentinel = "SENTINEL-KEYPRESENCE-\(unique)"

        previousSFTPServiceOverride = SFTPCredentialStore.serviceOverride
        SFTPCredentialStore.serviceOverride = sftpService
    }

    override func tearDown() {
        // Every item under this test's OWN services — never any other.
        APIKeyManagerTestSupport.clearKeychain(service: apiKeyService)
        try? SFTPCredentialStore.deleteAll(service: sftpService)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: smtpService!,
        ] as CFDictionary)

        SFTPCredentialStore.serviceOverride = previousSFTPServiceOverride
        try? FileManager.default.removeItem(at: storageDirectory)
        super.tearDown()
    }

    /// Where the manager keeps its saved-keys list for this test.
    private var indexURL: URL { storageDirectory.appendingPathComponent("api_keys.json") }

    /// A manager pointed at this test's folder and Keychain service. Used
    /// only to SET UP state; the checks under test never need one.
    private func makeManager() -> APIKeyManager {
        APIKeyManager(storageDirectory: storageDirectory, keychainService: apiKeyService)
    }

    /// The check under test, pointed at this test's folder and service.
    private func presence(of provider: APIKeyProvider, label: String? = nil) -> KeyPresence {
        APIKeyManager.hasStoredKey(
            for: provider,
            label: label,
            storageDirectory: storageDirectory,
            keychainService: apiKeyService
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Keychain availability probe
    // -----------------------------------------------------------------
    //
    // Mirrors `APIKeyManagerKeychainTests.probeKeychainPersistence()`: write,
    // read back, delete — all under this test's own API-key service. Returns
    // a `Bool` so individual tests can skip, rather than the whole file.
    private func keychainIsAvailable() -> Bool {
        let probeAccount = "keychain-probe-\(UUID().uuidString)"
        let probeData = Data("probe".utf8)
        let itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService!,
            kSecAttrAccount as String: probeAccount,
        ]
        SecItemDelete(itemQuery as CFDictionary)

        var addQuery = itemQuery
        addQuery[kSecValueData as String] = probeData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        var readQuery = itemQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var readResult: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &readResult)

        SecItemDelete(itemQuery as CFDictionary)

        return addStatus == errSecSuccess
            && readStatus == errSecSuccess
            && (readResult as? Data) == probeData
    }

    private let noKeychainReason =
        "Keychain round-trip not supported on this host (e.g. a CI runner with "
        + "no unlocked login Keychain); this test needs a real Keychain item."

    // -----------------------------------------------------------------
    // MARK: - Helpers
    // -----------------------------------------------------------------

    /// Runs `body` with this process's standard output and standard error
    /// redirected into a file, and returns `body`'s value plus everything
    /// written. Used to prove a presence check prints nothing secret.
    ///
    /// Honest limit: this catches `print` and anything else written to
    /// stdout/stderr. It cannot see the system's unified log (`os_log` /
    /// `Logger`); the code under test makes no such calls.
    private func capturingOutput<T>(_ body: () throws -> T) throws -> (value: T, output: String) {
        let captureURL = storageDirectory.appendingPathComponent("captured-output.txt")
        FileManager.default.createFile(atPath: captureURL.path, contents: nil)
        let captureHandle = try FileHandle(forWritingTo: captureURL)

        fflush(nil)
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        dup2(captureHandle.fileDescriptor, STDOUT_FILENO)
        dup2(captureHandle.fileDescriptor, STDERR_FILENO)

        // Restore the real outputs whatever `body` does, including throw.
        defer {
            fflush(nil)
            dup2(savedOut, STDOUT_FILENO)
            dup2(savedErr, STDERR_FILENO)
            close(savedOut)
            close(savedErr)
            try? captureHandle.close()
        }

        let value = try body()
        fflush(nil)
        let output = (try? String(contentsOf: captureURL, encoding: .utf8)) ?? ""
        return (value, output)
    }

    /// Saves an SMTP password under this test's OWN SMTP service, the same
    /// way `EmailSettingsView.savePasswordToKeychain` does (that code lives
    /// in the app module, which engine tests can't reach). Returns the raw
    /// status so the caller can assert set-up succeeded.
    private func addSMTPItem(password: String) -> OSStatus {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: smtpService!,
            kSecAttrAccount as String: SMTPPasswordKeychain.account,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    // -----------------------------------------------------------------
    // MARK: - The shared query never asks for the secret
    // -----------------------------------------------------------------

    /// The single most important property: the Keychain query used by all
    /// three checks asks for NOTHING back — above all not `kSecReturnData`,
    /// the secret itself. The exact key set is checked, so adding any
    /// return key (or anything else) fails this test.
    ///
    /// Honest limit (#506 plan, test 5): this checks the QUERY, not the
    /// absence of a macOS prompt. Proving no prompt appears needs one manual
    /// run of the command-line tool against a key the app saved.
    func test_existenceQuery_asksForNothingBack_aboveAllNotTheSecret() {
        let query = KeychainItemExistence.query(service: "a-service", account: "an-account")

        XCTAssertNil(query[kSecReturnData as String], "The existence query must never request the secret data.")
        XCTAssertNil(query[kSecReturnAttributes as String])
        XCTAssertNil(query[kSecReturnRef as String])
        XCTAssertNil(query[kSecReturnPersistentRef as String])
        XCTAssertNil(
            query[kSecAttrAccessible as String],
            "Matching on accessibility would miss items saved before SECURITY.md F-004."
        )

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "a-service")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "an-account")
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)

        XCTAssertEqual(
            Set(query.keys),
            Set([
                kSecClass as String,
                kSecAttrService as String,
                kSecAttrAccount as String,
                kSecMatchLimit as String,
            ]),
            "The existence query gained or lost a key; if a return key was added, it may now read the secret."
        )
    }

    // -----------------------------------------------------------------
    // MARK: - API keys: the saved-keys file (no Keychain needed)
    // -----------------------------------------------------------------

    /// No `api_keys.json` at all → missing (TRAP 1: no file means no keys).
    /// Checked both for an empty folder and for a folder that doesn't exist.
    func test_missingIndexFile_isMissing() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertEqual(presence(of: .tmdb), .missing)

        let nowhere = storageDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(
            APIKeyManager.hasStoredKey(for: .tmdb, storageDirectory: nowhere, keychainService: apiKeyService),
            .missing
        )
    }

    /// A key that was never saved, while the file DOES exist (holding a
    /// different service's key) → missing, without needing the Keychain.
    func test_neverStoredKey_withAnIndexPresent_isMissing() {
        makeManager().storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "some-other-key"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: indexURL.path),
            "Set-up: the saved-keys file should exist, so this tests 'no entry', not 'no file'."
        )

        XCTAssertEqual(presence(of: .tmdb), .missing)
    }

    /// A file that is there but isn't JSON → couldn't check, NEVER missing
    /// (TRAP 2: unknown is not empty).
    func test_corruptIndexFile_isCouldNotCheck_notMissing() throws {
        try Data("this is not { valid json".utf8).write(to: indexURL)
        XCTAssertEqual(presence(of: .tmdb), .couldNotCheck(.indexNotRecognised))

        // Valid JSON of the wrong shape is just as unrecognised.
        try Data(#"{"version": 2}"#.utf8).write(to: indexURL)
        XCTAssertEqual(presence(of: .tmdb), .couldNotCheck(.indexNotRecognised))
    }

    /// A file written by a NEWER version, naming a service this version
    /// doesn't know, can't be decoded as a whole — so even the perfectly
    /// good TMDB entry beside it is "couldn't check", not "missing". Pins
    /// the downgrade risk in the #506 plan (section 9) to the safe answer.
    func test_indexFromANewerVersion_isCouldNotCheck_evenForAKnownService() throws {
        let json = """
        {
          "version": 2,
          "records": [
            { "provider": "tmdb", "addedDate": "2026-01-01T00:00:00Z",
              "isActive": true, "keychainAccount": "tmdb:default" },
            { "provider": "a_service_from_the_future", "addedDate": "2026-01-01T00:00:00Z",
              "isActive": true, "keychainAccount": "a_service_from_the_future:default" }
          ]
        }
        """
        try Data(json.utf8).write(to: indexURL)

        XCTAssertEqual(presence(of: .tmdb), .couldNotCheck(.indexNotRecognised))

        // Set-up sanity: WITHOUT the unknown service, the same file is
        // recognised — so the refusal above really is caused by the unknown
        // service, not by a typo elsewhere in the fixture. (What the answer
        // then is depends on this host's Keychain, so only "recognised" is
        // asserted.)
        let withoutFuture = """
        {
          "version": 2,
          "records": [
            { "provider": "tmdb", "addedDate": "2026-01-01T00:00:00Z",
              "isActive": true, "keychainAccount": "tmdb:default" }
          ]
        }
        """
        try Data(withoutFuture.utf8).write(to: indexURL)
        XCTAssertNotEqual(presence(of: .tmdb), .couldNotCheck(.indexNotRecognised))
    }

    /// Something that ISN'T a readable file sits where the file should be
    /// (here, a folder with the file's name) → couldn't check, because the
    /// read itself failed.
    func test_unreadableIndexFile_isCouldNotCheck_notMissing() throws {
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
        XCTAssertEqual(presence(of: .tmdb), .couldNotCheck(.indexUnreadable))
    }

    /// A pre-Keychain (v1) file holds secrets in plain text. The manager
    /// migrates such a file when it loads it; the CHECK must not — that
    /// would write to the Keychain (from the command-line tool, too). So:
    /// the answer is "couldn't check", the file is byte-for-byte unchanged,
    /// no Keychain item appeared, and the plain-text secret is nowhere in
    /// the answer.
    func test_preKeychainIndex_isCouldNotCheck_andTheCheckMigratesNothing() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = [StoredAPIKey(provider: .tmdb, apiKey: sentinel, addedDate: Date(timeIntervalSince1970: 1_700_000_000))]
        let legacyBytes = try encoder.encode(legacy)
        try legacyBytes.write(to: indexURL)

        // Set-up sanity: this really is the old format the manager would
        // migrate, not just an unrecognisable file.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try decoder.decode([StoredAPIKey].self, from: legacyBytes))

        let result = presence(of: .tmdb)

        XCTAssertEqual(result, .couldNotCheck(.indexNotRecognised))
        XCTAssertEqual(try Data(contentsOf: indexURL), legacyBytes, "The check must never rewrite the file.")
        XCTAssertFalse(String(reflecting: result).contains(sentinel))

        // Only meaningful where a Keychain exists to be written to; on a
        // host without one, a migration couldn't have written anything
        // either, and the "not found" status itself may differ.
        if keychainIsAvailable() {
            XCTAssertEqual(
                SecItemCopyMatching([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: apiKeyService!,
                    kSecAttrAccount as String: "tmdb:default",
                ] as CFDictionary, nil),
                errSecItemNotFound,
                "The check must never migrate a secret into the Keychain."
            )
        }
    }

    // -----------------------------------------------------------------
    // MARK: - API keys: with a real Keychain
    // -----------------------------------------------------------------

    /// Stored → present.
    func test_storedKey_isPresent() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)

        makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: "tmdb-test-key"))

        XCTAssertEqual(presence(of: .tmdb), .present)
    }

    /// Stored then removed → missing.
    func test_removedKey_isMissing() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        let manager = makeManager()
        manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "tmdb-test-key"))
        XCTAssertEqual(presence(of: .tmdb), .present, "Set-up: the key should be present before removal.")

        manager.removeKey(provider: .tmdb)

        XCTAssertEqual(presence(of: .tmdb), .missing)
    }

    /// The saved-keys file still lists the key, but its Keychain item was
    /// deleted underneath it (by something other than MeedyaConverter) →
    /// MISSING. Decided and pinned here: the Keychain gave a definite "no
    /// such item", which is an answer, not a failure to get one; and the
    /// app itself can't use such an entry (it would load an empty key), so
    /// "still needs a key" is the truth.
    func test_indexEntryWhoseKeychainItemWasDeletedUnderneath_isMissing() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: "tmdb-test-key"))

        // Test-scoped delete, on this test's own service only. Success also
        // pins the account naming ("<provider>:default" for no label).
        let deleteStatus = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService!,
            kSecAttrAccount as String: "tmdb:default",
        ] as CFDictionary)
        XCTAssertEqual(deleteStatus, errSecSuccess, "Set-up: the Keychain item should have existed.")

        // The file must still list the key, or this would only be testing
        // the "no entry" case.
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
        let records = index?["records"] as? [[String: Any]] ?? []
        XCTAssertTrue(
            records.contains { $0["keychainAccount"] as? String == "tmdb:default" },
            "Set-up: the saved-keys file should still list the TMDB key."
        )

        XCTAssertEqual(presence(of: .tmdb), .missing)
    }

    /// A Keychain item that nothing in the saved-keys file points to (what
    /// the lost-update bug used to leave behind) → missing, because the app
    /// can't find it either. Here the file is deleted outright.
    func test_keychainItemWithNoIndexEntry_isMissing() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: "tmdb-test-key"))
        try FileManager.default.removeItem(at: indexURL)

        XCTAssertEqual(presence(of: .tmdb), .missing)
    }

    /// An inactive entry never counts — `key(for:)` skips it, so the app
    /// wouldn't use it.
    func test_inactiveKey_isMissing() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: "tmdb-test-key", isActive: false))

        XCTAssertEqual(presence(of: .tmdb), .missing)
    }

    /// Labels: an exact label matches only itself; no label means "whatever
    /// `key(for:)` would use", which here is the one labelled key.
    func test_labelledKey_matchesItsOwnLabel_andNoLabelMeansAny() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        makeManager().storeKey(StoredAPIKey(provider: .awsS3, apiKey: "AKIA-TEST", secretKey: "s3-secret", label: "work"))

        XCTAssertEqual(presence(of: .awsS3, label: "work"), .present)
        XCTAssertEqual(presence(of: .awsS3, label: "home"), .missing)
        XCTAssertEqual(presence(of: .awsS3), .present)
    }

    /// The media server key saved through commit 1's store is found, with
    /// or without its label.
    func test_mediaServerKey_savedThroughItsStore_isPresent() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        MediaServerCredentialStore.saveKey("plex-token-for-test", store: makeManager())

        XCTAssertEqual(presence(of: .mediaServer), .present)
        XCTAssertEqual(presence(of: .mediaServer, label: MediaServerCredentialStore.keyLabel), .present)
    }

    // -----------------------------------------------------------------
    // MARK: - SFTP
    // -----------------------------------------------------------------

    /// Never saved → missing; saved → present; deleted → missing; another
    /// profile's password doesn't count.
    func test_sftpExists_followsSaveAndDelete() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        let profile = UUID()
        let otherProfile = UUID()

        XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: profile), .missing)

        try SFTPCredentialStore.save(password: "sftp-test-password", forProfileID: profile)
        XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: profile), .present)
        XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: otherProfile), .missing)

        try SFTPCredentialStore.delete(forProfileID: profile)
        XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: profile), .missing)
    }

    // -----------------------------------------------------------------
    // MARK: - SMTP
    // -----------------------------------------------------------------

    /// The two names must never change: every SMTP password already saved
    /// is filed under exactly these, and `EmailSettingsView` now reads them
    /// from here.
    func test_smtpKeychainNames_areTheOnesAlreadyInUse() {
        XCTAssertEqual(SMTPPasswordKeychain.service, "Ltd.MWBMpartners.MeedyaConverter.smtp")
        XCTAssertEqual(SMTPPasswordKeychain.account, "smtpPassword")
    }

    /// Never saved → missing; saved → present; deleted → missing — through
    /// the internal seam, on this test's own service.
    func test_smtpExists_followsTheKeychainItem() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)

        XCTAssertEqual(SMTPPasswordKeychain.exists(service: smtpService, account: SMTPPasswordKeychain.account), .missing)

        XCTAssertEqual(addSMTPItem(password: "smtp-test-password"), errSecSuccess, "Set-up: could not add the test SMTP item.")
        XCTAssertEqual(SMTPPasswordKeychain.exists(service: smtpService, account: SMTPPasswordKeychain.account), .present)

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: smtpService!,
            kSecAttrAccount as String: SMTPPasswordKeychain.account,
        ] as CFDictionary)
        XCTAssertEqual(SMTPPasswordKeychain.exists(service: smtpService, account: SMTPPasswordKeychain.account), .missing)
    }

    // -----------------------------------------------------------------
    // MARK: - No check ever returns or prints the secret
    // -----------------------------------------------------------------

    /// Saves the SAME sentinel as an API key, an SFTP password and an SMTP
    /// password, runs all three checks with stdout and stderr captured, and
    /// requires: every answer is `.present`, and the sentinel appears
    /// neither in anything printed nor in any rendering of the answers.
    func test_presenceChecks_neverReturnOrPrintTheSecret() throws {
        try XCTSkipUnless(keychainIsAvailable(), noKeychainReason)
        let profile = UUID()
        makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: sentinel))
        try SFTPCredentialStore.save(password: sentinel, forProfileID: profile)
        XCTAssertEqual(addSMTPItem(password: sentinel), errSecSuccess, "Set-up: could not add the test SMTP item.")

        let captured = try capturingOutput { () -> [KeyPresence] in
            [
                presence(of: .tmdb),
                SFTPCredentialStore.exists(forProfileID: profile),
                SMTPPasswordKeychain.exists(service: smtpService, account: SMTPPasswordKeychain.account),
            ]
        }

        XCTAssertEqual(captured.value, [.present, .present, .present])
        XCTAssertFalse(captured.output.contains(sentinel), "A presence check printed the secret.")
        for answer in captured.value {
            XCTAssertFalse(String(describing: answer).contains(sentinel))
            XCTAssertFalse(String(reflecting: answer).contains(sentinel))
            var dumped = ""
            dump(answer, to: &dumped)
            XCTAssertFalse(dumped.contains(sentinel))
        }
    }
}
