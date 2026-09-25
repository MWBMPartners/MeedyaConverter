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
// Codex's round-2 review of that fix (25 Sept 2026, chunk 1b) found three
// more problems, covered by invariants 5, 7 and 8 below:
//   - the lock was per INSTANCE, so two instances writing at the same
//     moment could still lose each other's records (invariant 7 — the lock
//     is now shared by every instance);
//   - a list that EXISTS but could not be read or was written by a newer
//     version was still rewritten whole from a stale copy (invariant 8 —
//     writes now refuse with `APIKeyStoreError` and change nothing);
//   - the notification tests could hang instead of failing (invariant 5 —
//     the write now runs on a background queue under a timeout).
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
    func test_freshManager_seesBothWritersRecords() throws {
        let a = makeManager()
        let b = makeManager()

        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY-A", label: "TMDB"))
        try b.storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "MEEDYADB-KEY-B", label: "MeedyaDB"))

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
    func test_unrelatedRemoval_byAnotherInstance_doesNotEraseFirstWritersRecord() throws {
        let a = makeManager()
        let b = makeManager()

        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
        try b.removeKey(provider: .meedyaDB, label: "MeedyaDB")

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
    func test_existingInstance_seesAnotherWritersRecordThroughItsOwnLookup() throws {
        let a = makeManager()
        let b = makeManager()

        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

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
    func test_missingFileAfterReload_meansNoKeys() throws {
        let a = makeManager()
        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
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
    /// reading straight back from a manager, the handler below does
    /// exactly that, on the SAME manager.
    ///
    /// **Why the write runs on a background queue (Codex round-2 review,
    /// chunk 1b, finding 3).** The observer is registered with `queue:
    /// nil`, so it runs synchronously on whichever thread posts. This test
    /// used to call `storeKey` on the test's own thread, so if a regression
    /// ever posted while still holding the lock, the observer's `key(for:)`
    /// would deadlock the TEST thread itself — before `wait(for:timeout:)`
    /// was even reached — and the whole test process would hang instead of
    /// failing. Now the write runs on a background queue, and the test
    /// thread only waits, with a timeout. A deadlock then becomes a clear
    /// "timed out" failure naming this test.
    ///
    /// **What it cannot prevent:** the deadlocked background thread keeps
    /// holding the lock for good, and that lock is shared by every
    /// `APIKeyManager` in the process. So after such a failure, the NEXT
    /// test that creates or uses a manager will hang. The point is that
    /// the FIRST failure is a readable one, pointing at the cause.
    func test_storeKey_postsDidChangeNotification_andObserverCanReadBackSafely() {
        let a = makeManager()
        let didFire = expectation(description: "didChangeNotification posted by storeKey")
        let writeReturned = expectation(description: "storeKey returned")
        let failures = FailureLog()

        let observer = NotificationCenter.default.addObserver(
            forName: APIKeyManager.didChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            // Confirm this notification really is A's, not some other
            // manager's from a different test running concurrently.
            guard (notification.object as? APIKeyManager) === a else { return }
            // Reading the SAME manager from inside the handler must not
            // deadlock — this is exactly the reentrancy that posting only
            // AFTER the lock is released is meant to make safe.
            _ = a.key(for: .tmdb)
            didFire.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
            } catch {
                failures.record("storeKey threw: \(error)")
            }
            writeReturned.fulfill()
        }

        wait(for: [didFire, writeReturned], timeout: 5.0)
        XCTAssertEqual(failures.all, [])
    }

    /// Same as above, for `removeKey` — including running the write on a
    /// background queue so a deadlock fails instead of hanging.
    func test_removeKey_postsDidChangeNotification_andObserverCanReadBackSafely() throws {
        let a = makeManager()
        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

        let didFire = expectation(description: "didChangeNotification posted by removeKey")
        let writeReturned = expectation(description: "removeKey returned")
        let failures = FailureLog()
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

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try a.removeKey(provider: .tmdb, label: "TMDB")
            } catch {
                failures.record("removeKey threw: \(error)")
            }
            writeReturned.fulfill()
        }

        wait(for: [didFire, writeReturned], timeout: 5.0)
        XCTAssertEqual(failures.all, [])
    }

    /// `markUsed` deliberately does NOT post `didChangeNotification` (a
    /// last-used timestamp is bookkeeping, not something any "is a key
    /// saved" UI needs to redraw for). Proven with an inverted
    /// expectation rather than by absence of a crash, so a future change
    /// that starts posting here gets caught by a failing test rather than
    /// a silently-more-chatty notification.
    func test_markUsed_doesNotPostDidChangeNotification() throws {
        let a = makeManager()
        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))

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

        try a.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "SECRET-TMDB-KEY", label: "TMDB"))
        try b.storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "SECRET-MEEDYADB-KEY", label: "MeedyaDB"))

        let c = makeManager()
        XCTAssertEqual(
            c.key(for: .tmdb)?.apiKey,
            "SECRET-TMDB-KEY",
            "With a working Keychain, C must recover not just A's record "
            + "but A's actual secret too."
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 7: ONE lock for every instance (Codex round-2
    //         review, chunk 1b, finding 1)
    // -----------------------------------------------------------------

    /// How many times the concurrent-write scenario below is repeated,
    /// each time over a fresh, empty list, and how many keys each round
    /// writes: 10 rounds of 12, so 120 concurrent writes per run. Written
    /// as constants so a failure message can say exactly how much was
    /// tried.
    ///
    /// Why these sizes (measured on 25 Sept 2026, on the maintainer's Mac,
    /// in the local test harness — `.claude/local-test-harness.md`): with
    /// the lock planted back to one per instance, 10 runs out of 10 failed,
    /// and so did all 100 of their rounds (each round lost 3 to 7 of its
    /// 12 records). Even 3 rounds of 8 failed 10 runs out of 10, so these
    /// sizes leave a margin rather than being the least that works. Every
    /// write re-reads the whole list and asks the Keychain about every
    /// record, so a round's cost grows with the SQUARE of its key count.
    /// This size took 0.85 seconds in the first measurements. (24 keys per
    /// round, tried first, took about 2 seconds then, but 7 to 19 seconds
    /// later the same day while the Mac's load average was above 400 from
    /// other work — which is why it was halved.)
    private static let concurrentRounds = 10
    private static let concurrentKeysPerRound = 12

    /// Two instances over ONE storage directory, many `storeKey` calls at
    /// once from several threads, each call on one of the two instances
    /// (even-numbered keys through A, odd through B), every key a
    /// different (provider, label) pair. Afterwards a FRESH instance must
    /// see every single record.
    ///
    /// This is the lost-update race the per-instance lock allowed: A and B
    /// each re-read the list, each added a different key, and each saved
    /// the whole list; whichever saved last dropped the other's record.
    /// With the lock shared by every instance, "re-read, change, save" is
    /// one step, so no record can be lost. If the lock ever goes back to
    /// being per instance, this test fails (checked on 25 Sept 2026 by
    /// planting exactly that change — see the sizes above for how
    /// reliably).
    ///
    /// **The keys carry NO secret**, only a provider and a label, so no
    /// Keychain item is ever created (`storeKey` writes a secret only when
    /// there is one). Deliberately so, for two reasons:
    /// - the race is in the LIST, which holds only provider, label and
    ///   dates, so a record-level check is the whole of the proof — and it
    ///   works whether or not this host's Keychain can persist anything
    ///   (see the file overview for why that matters on CI);
    /// - with a real secret per key, one run took 32 seconds on this Mac
    ///   (every write re-reads every record's secret) and put 240 items in
    ///   the login Keychain. Tried first, and rejected for both reasons.
    func test_concurrentStores_acrossTwoInstances_loseNoRecord() {
        let providers = APIKeyProvider.allCases
        for round in 0..<Self.concurrentRounds {
            // A fresh, empty folder per round, so each round's writes start
            // from nothing and its cost stays small (see the sizes above).
            let roundDirectory = storageDirectory.appendingPathComponent("round-\(round)")
            let a = APIKeyManager(storageDirectory: roundDirectory, keychainService: keychainService)
            let b = APIKeyManager(storageDirectory: roundDirectory, keychainService: keychainService)
            let failures = FailureLog()

            DispatchQueue.concurrentPerform(iterations: Self.concurrentKeysPerRound) { index in
                let writer = index.isMultiple(of: 2) ? a : b
                // `apiKey: ""` and no other secret: a record only — see
                // "The keys carry NO secret" above.
                let key = StoredAPIKey(
                    provider: providers[index % providers.count],
                    apiKey: "",
                    label: "concurrent-\(round)-\(index)"
                )
                do {
                    try writer.storeKey(key)
                } catch {
                    failures.record("storeKey #\(index) threw: \(error)")
                }
            }
            XCTAssertEqual(failures.all, [], "Round \(round): no write may be refused over a readable list.")

            let expected = Set((0..<Self.concurrentKeysPerRound).map { index in
                "\(providers[index % providers.count].rawValue)|concurrent-\(round)-\(index)"
            })
            let reader = APIKeyManager(storageDirectory: roundDirectory, keychainService: keychainService)
            let found = Set(providers.flatMap { reader.keys(for: $0) }.map { key in
                "\(key.provider.rawValue)|\(key.label ?? "")"
            })
            let missing = expected.subtracting(found)
            XCTAssertTrue(
                missing.isEmpty,
                "Round \(round) of \(Self.concurrentRounds): a fresh manager is missing "
                + "\(missing.count) of \(expected.count) records written concurrently "
                + "through two instances — a lost update. Missing: \(missing.sorted())"
            )
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Invariant 8: a write never overwrites a list it couldn't
    //         read (Codex round-2 review, chunk 1b, finding 2)
    // -----------------------------------------------------------------

    /// Bytes that are not JSON at all — a damaged list.
    private let garbage = Data("this is not { valid json, it is a damaged list".utf8)

    /// Asks the Keychain whether an item exists under this test's service,
    /// ATTRIBUTES ONLY (never the secret). `errSecItemNotFound` means no.
    private func keychainStatus(account: String) -> OSStatus {
        SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService!,
            kSecAttrAccount as String: account,
        ] as CFDictionary, nil)
    }

    /// A damaged list on disk: `storeKey` must refuse with
    /// `.savedKeysListUnreadable`, leave the file byte-for-byte as it was,
    /// and write no Keychain item. Before the fix it rewrote the whole
    /// list from this instance's (empty) memory — i.e. replaced a list it
    /// could not read with one holding only the new key.
    func test_unreadableIndex_storeKeyRefuses_andChangesNothing() throws {
        try garbage.write(to: jsonURL)
        let manager = makeManager()

        XCTAssertThrowsError(
            try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "MUST-NOT-LAND", label: "TMDB"))
        ) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListUnreadable)
        }
        XCTAssertEqual(try Data(contentsOf: jsonURL), garbage, "A refused write must leave the list byte-for-byte as it was.")

        // Only meaningful where a Keychain exists to be written to: on a
        // host without one, a write could not have landed anyway.
        if keychainIsAvailable() {
            XCTAssertEqual(
                keychainStatus(account: "tmdb:TMDB"), errSecItemNotFound,
                "A refused write must not put the secret in the Keychain either."
            )
        }
    }

    /// The same for `removeKey`: a key is saved, then the list is damaged.
    /// The removal must refuse, leave the file untouched, and NOT delete
    /// the Keychain item (deleting the secret while the list still names
    /// it would leave an entry pointing at nothing).
    func test_unreadableIndex_removeKeyRefuses_andChangesNothing() throws {
        let manager = makeManager()
        try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "KEEP-ME", label: "TMDB"))
        try garbage.write(to: jsonURL)

        XCTAssertThrowsError(try manager.removeKey(provider: .tmdb, label: "TMDB")) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListUnreadable)
        }
        XCTAssertEqual(try Data(contentsOf: jsonURL), garbage, "A refused removal must leave the list byte-for-byte as it was.")

        if keychainIsAvailable() {
            XCTAssertEqual(
                keychainStatus(account: "tmdb:TMDB"), errSecSuccess,
                "A refused removal must not delete the Keychain item."
            )
        }
    }

    /// Something that is not a readable FILE at the list's path (here a
    /// folder with its name) fails at the READ, not the decode — the other
    /// branch of `reloadLocked()`. It must refuse the same way.
    func test_indexThatCannotBeReadAtAll_storeKeyRefuses() throws {
        try FileManager.default.createDirectory(at: jsonURL, withIntermediateDirectories: true)
        let manager = makeManager()

        XCTAssertThrowsError(
            try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "MUST-NOT-LAND", label: "TMDB"))
        ) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListUnreadable)
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "The folder in the list's place must be left alone.")
    }

    /// `markUsed` has no caller to report to, so over a damaged list it
    /// quietly skips its save — but it must still never rewrite the file.
    func test_unreadableIndex_markUsedSkipsItsSave() throws {
        let manager = makeManager()
        try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
        try garbage.write(to: jsonURL)

        manager.markUsed(provider: .tmdb)

        XCTAssertEqual(try Data(contentsOf: jsonURL), garbage)
    }

    /// READS keep today's behaviour over a damaged list: an instance that
    /// read the list successfully before goes on answering from that copy
    /// (unknown is not "no keys"), while a brand-new instance, which has no
    /// earlier copy, finds nothing. Pinned so that nobody "fixes" reads to
    /// throw or to wipe, without meaning to.
    func test_unreadableIndex_readsAnswerFromTheLastGoodCopy() throws {
        let manager = makeManager()
        try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB"))
        try garbage.write(to: jsonURL)

        XCTAssertEqual(manager.key(for: .tmdb)?.label, "TMDB")
        XCTAssertNil(makeManager().key(for: .tmdb))
    }

    /// A list written by a NEWER version (a higher `version` number, and a
    /// field this version has never heard of). Rewriting it in this
    /// version's format would drop that field, so every write refuses with
    /// `.savedKeysListFromNewerVersion` and the file stays byte-identical.
    /// The presence check agrees that it is not understood.
    func test_newerVersionIndex_writesRefuse_andTheFileIsUntouched() throws {
        let newer = Data("""
        {
          "version": 3,
          "records": [
            { "provider": "tmdb", "label": "TMDB", "addedDate": "2026-01-01T00:00:00Z",
              "isActive": true, "keychainAccount": "tmdb:TMDB",
              "aFieldFromTheFuture": "this version must not drop me" }
          ]
        }
        """.utf8)
        try newer.write(to: jsonURL)
        let manager = makeManager()

        XCTAssertThrowsError(
            try manager.storeKey(StoredAPIKey(provider: .meedyaDB, apiKey: "MUST-NOT-LAND", label: "MeedyaDB"))
        ) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListFromNewerVersion)
        }
        XCTAssertThrowsError(try manager.removeKey(provider: .tmdb, label: "TMDB")) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListFromNewerVersion)
        }
        manager.markUsed(provider: .tmdb)
        XCTAssertEqual(try Data(contentsOf: jsonURL), newer, "No write may rewrite a newer version's list.")

        XCTAssertEqual(
            APIKeyManager.hasStoredKey(for: .tmdb, storageDirectory: storageDirectory, keychainService: keychainService),
            .couldNotCheck(.indexNotRecognised)
        )

        // Set-up sanity: with the version number this build writes, the
        // same records ARE understood — so the refusal above really is
        // caused by the version number, not by a typo in the fixture.
        let sameButCurrent = String(decoding: newer, as: UTF8.self)
            .replacingOccurrences(of: "\"version\": 3", with: "\"version\": 2")
        try Data(sameButCurrent.utf8).write(to: jsonURL)
        XCTAssertEqual(makeManager().key(for: .tmdb)?.label, "TMDB")
    }

    /// A newer list whose records would NOT decode here (a service this
    /// version doesn't know) is still recognised as NEWER, because the
    /// version number is checked on its own first — so the refusal names
    /// the real cause rather than calling the list unreadable.
    func test_newerVersionIndex_withRecordsThisVersionCannotDecode_isStillNewer() throws {
        let newer = Data("""
        {
          "version": 3,
          "records": [
            { "provider": "a_service_from_the_future", "addedDate": "2026-01-01T00:00:00Z",
              "isActive": true, "keychainAccount": "a_service_from_the_future:default" }
          ]
        }
        """.utf8)
        try newer.write(to: jsonURL)

        XCTAssertThrowsError(
            try makeManager().storeKey(StoredAPIKey(provider: .tmdb, apiKey: "MUST-NOT-LAND", label: "TMDB"))
        ) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .savedKeysListFromNewerVersion)
        }
        XCTAssertEqual(try Data(contentsOf: jsonURL), newer)
    }

    /// TRAP 1 is unchanged: no list at all still means "no keys", and a
    /// write over a missing list still works and creates it.
    func test_missingIndex_isNoKeys_andAWriteStillWorks() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path), "Set-up: there must be no list yet.")
        let manager = makeManager()
        XCTAssertNil(manager.key(for: .tmdb))

        XCTAssertNoThrow(try manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "TMDB-KEY", label: "TMDB")))

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertEqual(makeManager().key(for: .tmdb)?.label, "TMDB")
    }

    /// The refusal wording is shown on screen and can reach the Activity
    /// Log, so it must never name where the list lives. (It never sees a
    /// key, so it cannot contain one.)
    func test_refusalWording_isPlainAndNamesNoFile() {
        for error in [APIKeyStoreError.savedKeysListUnreadable, .savedKeysListFromNewerVersion] {
            let text = error.localizedDescription
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("api_keys"), "\(error): must not name the file.")
            XCTAssertFalse(text.contains("/"), "\(error): must not contain a path.")
            XCTAssertTrue(text.contains("changed nothing"), "\(error): must say that nothing was changed.")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - FailureLog
// ---------------------------------------------------------------------------

/// Collects failure messages from background threads, guarded by a lock.
///
/// Why this exists rather than a captured `var`: the closures handed to
/// `DispatchQueue.global().async` are `@Sendable`, and mutating a captured
/// `var` inside one is a compile error in Swift 6 language mode that
/// `swiftc -parse` does not catch — it once turned CI red (`d602cf0`). The
/// test thread reads `all` only after it has waited for the background work.
private final class FailureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }
}
