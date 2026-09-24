// ============================================================================
// MeedyaConverter — APIKeyManager index-consistency tests (Codex catch-up
// review, finding 2 / finding 10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `APIKeyManagerKeychainTests.swift` covers the Keychain migration and the
// "secrets never touch disk" invariants from issue #380. This file covers a
// DIFFERENT bug, found in the 24 Sept 2026 Codex catch-up review (finding 2,
// plus the related notification gap in finding 10):
//
//   `APIKeyManager` keeps its index of saved keys in a JSON file
//   (`api_keys.json`) and rewrites the WHOLE file, from its own in-memory
//   `keys` array, on every `storeKey`/`removeKey`/`markUsed` call. Several
//   long-lived instances of this class exist at once in the real app —
//   `MetadataSettingsTab`, `MeedyaDBSettingsTab` and `CloudStorageView` each
//   keep their own for as long as their screen stays open. Before the fix,
//   whichever instance saved LAST would silently overwrite every other
//   instance's saved record, because each one only ever read the file once,
//   in `init`. The secret itself survived in the Keychain — nothing deleted
//   it — but nothing on disk pointed back to it any more, so a FRESH
//   `APIKeyManager()` (exactly what the disc pipeline view models,
//   `TMDBLookupSheet` and the uploaders construct on demand) reported the
//   key as missing.
//
// The fix, in `APIKeyManager.swift`, is a private `reloadLocked()` that
// every mutator and every lookup method calls, under the same lock hold, so
// each one acts on the file as it stands right now rather than on a
// snapshot taken whenever this particular instance was last read. The tests
// below exercise that directly: two "writer" instances (A, B) simulating two
// long-lived screens, and a fresh "reader" instance (C) simulating what the
// view models create on demand.
//
// A DELIBERATE DIFFERENCE from `APIKeyManagerKeychainTests.swift`: that
// file's `probeKeychainPersistence()` skips EVERY test if the host's
// Keychain cannot persist (e.g. a fresh GitHub Actions runner with no
// unlocked default Keychain). That skip is correct for tests asserting on
// SECRETS, which genuinely live only in the Keychain. It would be WRONG
// here for most of these tests, because the bug being tested lives in the
// on-disk METADATA RECORD (provider, label, timestamps, Keychain-account
// string) — that record is written and read by plain `Data`/`JSONEncoder`
// calls and exists (with an empty `apiKey`, if the Keychain write silently
// failed) regardless of Keychain availability. Skipping those assertions on
// a headless CI runner would skip the very tests that catch a regression of
// this bug there. Only the one test that specifically checks a RECOVERED
// SECRET (`test_freshManagerRecoversOtherWritersSecret`) uses the
// Keychain-availability probe, following the same pattern as
// `APIKeyManagerKeychainTests.probeKeychainPersistence()`.
//
// `@testable import` is used so `tearDown` can call
// `APIKeyManagerTestSupport.clearKeychain(service:)`, matching the existing
// policy documented in `APIKeyManagerKeychainTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import Security
@testable import ConverterEngine

final class APIKeyManagerIndexConsistencyTests: XCTestCase {

    // -----------------------------------------------------------------
    // MARK: - Test fixtures
    // -----------------------------------------------------------------

    /// Unique storage directory backing the JSON envelope for THIS test
    /// method. XCTest creates a fresh instance of the test class per test
    /// method and calls `setUpWithError()` on each, so a UUID minted here
    /// is unique per test — required because CI runs `swift test
    /// --parallel`, and a directory shared between two tests running at
    /// once would make one test's writes visible to another's reader.
    private var storageDirectory: URL!

    /// Unique Keychain service for this test method, for the same reason.
    private var keychainService: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let unique = UUID().uuidString
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apikeymanager-index-tests-\(unique)")
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        keychainService = "Ltd.MWBMpartners.MeedyaConverter.Tests.IndexConsistency.\(unique)"

        // Deliberately NO Keychain-availability skip here — see the file
        // overview above for why most of these tests must run even on a
        // host where the Keychain cannot persist.
    }

    override func tearDown() {
        APIKeyManagerTestSupport.clearKeychain(service: keychainService)
        try? FileManager.default.removeItem(at: storageDirectory)
        super.tearDown()
    }

    /// Absolute path the manager uses for its envelope file.
    private var jsonURL: URL { storageDirectory.appendingPathComponent("api_keys.json") }

    /// Constructs a manager pointed at this test's isolated storage
    /// directory and Keychain service. Named to read like what it stands
    /// in for at the call site: `makeManager()` for "another writer" or
    /// "a fresh reader", matching the real app's `APIKeyManager()` /
    /// `@State private var keyManager = APIKeyManager()` call sites.
    private func makeManager() -> APIKeyManager {
        APIKeyManager(storageDirectory: storageDirectory, keychainService: keychainService)
    }

    // -----------------------------------------------------------------
    // MARK: - Keychain availability probe (secret-level test only)
    // -----------------------------------------------------------------
    //
    // Mirrors `APIKeyManagerKeychainTests.probeKeychainPersistence()`, but
    // returns a `Bool` for use with `XCTSkipUnless` in a single test,
    // rather than skipping the whole file from `setUpWithError()`. See the
    // file overview above for why the two files gate differently.
    private func keychainIsAvailable() -> Bool {
        let probeAccount = "keychain-probe-\(UUID().uuidString)"
        let probeData = Data("probe".utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService!,
            kSecAttrAccount as String: probeAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService!,
            kSecAttrAccount as String: probeAccount,
            kSecValueData as String: probeData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        var readResult: AnyObject?
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService!,
            kSecAttrAccount as String: probeAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &readResult)
        let recovered = readResult as? Data

        SecItemDelete(deleteQuery as CFDictionary)

        return addStatus == errSecSuccess && readStatus == errSecSuccess && recovered == probeData
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 1: the delivery proof
    // -----------------------------------------------------------------

    /// The scenario from the bug report, almost verbatim: instance A saves
    /// a TMDB key, then instance B (an older, still-open screen) saves an
    /// unrelated MeedyaDB key. A fresh instance C — exactly what
    /// `TMDBLookupSheet`, the disc pipeline view models and the uploaders
    /// construct on demand — must find BOTH records. Before the fix, B's
    /// `saveKeys()` call would rewrite the whole file from B's stale
    /// in-memory copy (which never saw A's write) and A's record would be
    /// gone.
    func test_freshManager_seesBothWritersRecords() {
        let a = makeManager()
        let b = makeManager()

        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY-A", label: "TMDB"))
        b.storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "MEEDYADB-KEY-B", label: "MeedyaDB"))

        let c = makeManager()

        // Asserted at the RECORD level (label/provider), which the on-disk
        // metadata index carries regardless of whether this host's
        // Keychain could persist the secret — see the file overview.
        guard let tmdbRecord = c.key(for: .tmdb) else {
            return XCTFail(
                "C (a fresh manager) must find A's TMDB record even though "
                + "B saved AFTER A and storeKey() rewrites the whole index "
                + "file from its own in-memory copy."
            )
        }
        XCTAssertEqual(tmdbRecord.label, "TMDB")

        guard let meedyaDBRecord = c.key(for: .meedyaDB) else {
            return XCTFail("C must also find B's MeedyaDB record.")
        }
        XCTAssertEqual(meedyaDBRecord.label, "MeedyaDB")
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 2: an unrelated removal doesn't erase another
    //         writer's record
    // -----------------------------------------------------------------

    /// B removes a key for a DIFFERENT provider than the one A just
    /// stored — a key B never had, on a provider A didn't touch. Without
    /// the reload-before-write fix, `removeKey` would still rewrite the
    /// whole file from B's stale (empty) in-memory array, erasing A's
    /// record as a side effect of removing something that was never
    /// there in the first place.
    func test_unrelatedRemoval_byAnotherInstance_doesNotEraseFirstWritersRecord() {
        let a = makeManager()
        let b = makeManager()

        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
        b.removeKey(provider: .meedyaDB, label: "MeedyaDB")

        let c = makeManager()
        guard let tmdbRecord = c.key(for: .tmdb) else {
            return XCTFail(
                "C must still find A's TMDB record after B's unrelated "
                + "removeKey call for a provider A never touched."
            )
        }
        XCTAssertEqual(tmdbRecord.label, "TMDB")
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 3: an existing instance sees another's write
    //         through its OWN lookup, not just via a fresh instance
    // -----------------------------------------------------------------

    /// B is constructed BEFORE A stores anything, and is never recreated.
    /// This specifically exercises the reload inside the LOOKUP path
    /// (`key(for:)`) rather than inside `init` — the two are different
    /// code paths, and a fix that only reloaded in mutators (or only in
    /// `init`) would pass invariant 1 while still leaving a long-lived
    /// reader like `MetadataSettingsTab` showing stale information.
    func test_existingInstance_seesAnotherWritersRecordThroughItsOwnLookup() {
        let a = makeManager()
        let b = makeManager()

        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

        guard let record = b.key(for: .tmdb) else {
            return XCTFail(
                "B must see A's record through its own key(for:) call — "
                + "B was never recreated, so this proves the lookup itself "
                + "reloads, not just a fresh instance's init."
            )
        }
        XCTAssertEqual(record.label, "TMDB")
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 4: a missing file, found on reload, means no keys
    // -----------------------------------------------------------------

    /// Trap 1 in `reloadLocked()`: a file that has gone missing since the
    /// last reload is authoritative — it means no keys, not "keep
    /// trusting whatever this instance last saw". Exercised by deleting
    /// the index file out from under a manager that already has a key
    /// loaded, then reading through the SAME instance.
    func test_missingFileAfterReload_meansNoKeys() {
        let a = makeManager()
        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
        XCTAssertNotNil(a.key(for: .tmdb), "Sanity check: the key must exist before we delete the file.")

        try? FileManager.default.removeItem(at: jsonURL)

        XCTAssertNil(
            a.key(for: .tmdb),
            "After the index file is deleted, a reload must report NO "
            + "keys — not go on trusting a's stale in-memory copy of a "
            + "file that no longer exists."
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 5: didChangeNotification, and its lock ordering
    // -----------------------------------------------------------------

    /// `storeKey` must post `didChangeNotification` — and, since the
    /// point of the notification is that a settings screen can react by
    /// reading straight back from the SAME manager, the handler below
    /// does exactly that. If the manager posted while still holding its
    /// internal lock, this test would hang (NSLock is not re-entrant)
    /// instead of failing cleanly, which is why a timeout is given to
    /// `wait(for:timeout:)` rather than leaving it to hang indefinitely.
    func test_storeKey_postsDidChangeNotification_andObserverCanReadBackSafely() {
        let a = makeManager()
        let didFire = expectation(description: "didChangeNotification posted by storeKey")

        let observer = NotificationCenter.default.addObserver(
            forName: APIKeyManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            // Confirm this notification really is A's, not some other
            // manager's from a different test running concurrently.
            guard (notification.object as? APIKeyManager) === a else { return }
            // Reading the SAME manager from inside the handler must not
            // deadlock — this is exactly the reentrancy that posting
            // AFTER `lock.unlock()` is meant to make safe.
            _ = a.key(for: .tmdb)
            didFire.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

        wait(for: [didFire], timeout: 5.0)
    }

    /// Same as above, for `removeKey`.
    func test_removeKey_postsDidChangeNotification_andObserverCanReadBackSafely() {
        let a = makeManager()
        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

        let didFire = expectation(description: "didChangeNotification posted by removeKey")
        let observer = NotificationCenter.default.addObserver(
            forName: APIKeyManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.object as? APIKeyManager) === a else { return }
            _ = a.key(for: .tmdb)
            didFire.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        a.removeKey(provider: .tmdb, label: "TMDB")

        wait(for: [didFire], timeout: 5.0)
    }

    /// `markUsed` deliberately does NOT post `didChangeNotification` (a
    /// last-used timestamp is bookkeeping, not something any "is a key
    /// saved" UI needs to redraw for). Proven with an inverted
    /// expectation rather than by absence of a crash, so a future change
    /// that starts posting here gets caught by a failing test rather than
    /// a silently-more-chatty notification.
    func test_markUsed_doesNotPostDidChangeNotification() {
        let a = makeManager()
        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

        let didFire = expectation(description: "didChangeNotification must NOT be posted by markUsed")
        didFire.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: APIKeyManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.object as? APIKeyManager) === a else { return }
            didFire.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        a.markUsed(provider: .tmdb)

        wait(for: [didFire], timeout: 1.0)
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 6: the recovered SECRET (Keychain-gated)
    // -----------------------------------------------------------------

    /// The secret-level counterpart to invariant 1. Gated on Keychain
    /// availability — unlike the record-level tests above, an actual
    /// `apiKey` value can only round-trip through a Keychain that this
    /// host can actually persist to. See `APIKeyManagerKeychainTests`
    /// for the same rationale in more detail.
    func test_freshManager_recoversOtherWritersSecret() throws {
        try XCTSkipUnless(
            keychainIsAvailable(),
            "Keychain round-trip not supported on this host (no unlocked "
            + "default user Keychain, e.g. a fresh GitHub Actions runner). "
            + "The record-level invariants above already cover this "
            + "manager's behaviour without a working Keychain; this test "
            + "has nothing meaningful left to check without one."
        )

        let a = makeManager()
        let b = makeManager()

        a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "SECRET-TMDB-KEY", label: "TMDB"))
        b.storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "SECRET-MEEDYADB-KEY", label: "MeedyaDB"))

        let c = makeManager()
        XCTAssertEqual(
            c.key(for: .tmdb)?.apiKey,
            "SECRET-TMDB-KEY",
            "With a working Keychain, C must recover not just A's record "
            + "but A's actual secret too."
        )
    }
}
