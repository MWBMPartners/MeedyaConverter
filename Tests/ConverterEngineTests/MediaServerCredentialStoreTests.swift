// ============================================================================
// MeedyaConverter — MediaServerCredentialStore tests (Issue #506 commit 1)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Covers `MediaServerCredentialStore` (SECURITY.md F-013): the migration that
// moves the media server's plaintext `UserDefaults` key into the Keychain,
// and the `currentKey`/`saveKey`/`removeKey` helpers every reader and writer
// of that key now goes through.
//
// Each test gets its own UUID-named `UserDefaults` suite (so parallel runs
// and re-runs never see each other's leftovers), a UUID-named temp storage
// directory, and a UUID-named Keychain service.
//
// Most tests use `FakeMediaServerKeyStore` below rather than a real
// `APIKeyManager`, because the whole point of several of them is to force a
// failure or a corrupted write — the REAL Keychain cannot be made to do
// either on demand. Only `test_migrate_deliveryProof_…` needs the real
// thing: it is the one test proving the migrated value survives through a
// SECOND, independently constructed `APIKeyManager`, which a fake cannot
// stand in for. It follows the exact skip-on-unavailable-Keychain pattern
// from `APIKeyManagerKeychainTests.probeKeychainPersistence()`.
//
// `tearDown` removes the UserDefaults suite's on-disk plist directly
// (`~/Library/Preferences/<suite>.plist`) in addition to
// `removePersistentDomain` — `cfprefsd` on this Mac has been observed to
// leave a small file behind even after the domain is removed in-process.
// These tests are run locally (see `.claude/local-test-harness.md`), never
// inside CI's sandbox, so reaching into `~/Library/Preferences` directly is
// safe here.
// ---------------------------------------------------------------------------

import XCTest
import Security
@testable import ConverterEngine

final class MediaServerCredentialStoreTests: XCTestCase {

    // -----------------------------------------------------------------
    // MARK: - Test fixtures
    // -----------------------------------------------------------------

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var storageDirectory: URL!
    private var keychainService: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let unique = UUID().uuidString
        suiteName = "com.mwbm.MeedyaConverter.Tests.MediaServerCredentialStore.\(unique)"
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create a UserDefaults suite for the test.")
        }
        defaults = suiteDefaults
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediaservercredentialstore-tests-\(unique)")
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        keychainService = "Ltd.MWBMpartners.MeedyaConverter.Tests.MediaServer.\(unique)"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        // See the file overview above: `cfprefsd` can leave a stray plist
        // behind even after `removePersistentDomain` finishes in-process.
        if let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let plistURL = libraryDir
                .appendingPathComponent("Preferences")
                .appendingPathComponent("\(suiteName!).plist")
            try? FileManager.default.removeItem(at: plistURL)
        }
        APIKeyManagerTestSupport.clearKeychain(service: keychainService)
        try? FileManager.default.removeItem(at: storageDirectory)
        super.tearDown()
    }

    // -----------------------------------------------------------------
    // MARK: - Fake store
    // -----------------------------------------------------------------

    /// A `MediaServerKeyStoring` fake for exercising migration failure
    /// paths deterministically — the real Keychain cannot be told to
    /// refuse or corrupt a specific write on demand.
    ///
    /// `Behavior` is what separates the two distinct failure shapes the
    /// plan calls out, both of which the read-back verification in
    /// `migrateLegacyKeyIfNeeded` must catch even though neither one
    /// makes `storeKey` throw (it never does — see that method's own doc
    /// comment):
    ///   - `.discardsWrites`: the write is silently dropped, so
    ///     `key(for:)` afterwards finds NOTHING for the provider.
    ///   - `.corruptsOnWrite`: the write "succeeds" but stores a
    ///     DIFFERENT value than the one asked for, so `key(for:)` finds
    ///     SOMETHING, just not a match.
    ///
    /// Backed by an array (not a dictionary keyed by provider), mirroring
    /// `APIKeyManager`'s own storage shape, so `removeKey(provider:label:)`
    /// behaves the same way the real thing does: a `nil` label removes
    /// every record for the provider regardless of label, a non-nil label
    /// removes only a matching one.
    ///
    /// Uses `NSLock` even though these tests run single-threaded, for the
    /// same reason `APIKeyManager` itself does: nothing here is `@Sendable`
    /// by inference, and being explicit about the invariant ("mutating
    /// `keys` only under `lock`") costs nothing and matches the style of
    /// the type this fake stands in for.
    final class FakeMediaServerKeyStore: MediaServerKeyStoring {
        enum Behavior {
            case persists
            case discardsWrites
            case corruptsOnWrite(replacement: String)
        }

        private let lock = NSLock()
        private var keys: [StoredAPIKey] = []
        private let behavior: Behavior

        init(behavior: Behavior = .persists) {
            self.behavior = behavior
        }

        func key(for provider: APIKeyProvider) -> StoredAPIKey? {
            lock.lock()
            defer { lock.unlock() }
            return keys.first { $0.provider == provider && $0.isActive }
        }

        func storeKey(_ key: StoredAPIKey) {
            lock.lock()
            defer { lock.unlock() }
            switch behavior {
            case .persists:
                upsertLocked(key)
            case .discardsWrites:
                break
            case .corruptsOnWrite(let replacement):
                var corrupted = key
                corrupted.apiKey = replacement
                upsertLocked(corrupted)
            }
        }

        func removeKey(provider: APIKeyProvider, label: String?) {
            lock.lock()
            defer { lock.unlock() }
            keys.removeAll { $0.provider == provider && (label == nil || $0.label == label) }
        }

        /// Must be called with `lock` already held.
        private func upsertLocked(_ key: StoredAPIKey) {
            if let index = keys.firstIndex(where: { $0.provider == key.provider && $0.label == key.label }) {
                keys[index] = key
            } else {
                keys.append(key)
            }
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Migration: every outcome
    // -----------------------------------------------------------------

    func test_migrate_nothingToMigrate_whenNoLegacyValuePresent() {
        let store = FakeMediaServerKeyStore()

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        XCTAssertEqual(outcome, .nothingToMigrate)
        XCTAssertNil(store.key(for: .mediaServer))
    }

    func test_migrate_removesEmptyLegacyValue_whenBlank() {
        defaults.set("   ", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore()

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        XCTAssertEqual(outcome, .removedEmptyLegacyValue)
        XCTAssertNil(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey))
        XCTAssertNil(store.key(for: .mediaServer), "A blank legacy value must not be written to the store.")
    }

    func test_migrate_migratesAndRemovesLegacyValue_whenAcceptedByTheStore() {
        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore()

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        XCTAssertEqual(outcome, .migrated)
        XCTAssertNil(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey))
        XCTAssertEqual(store.key(for: .mediaServer)?.apiKey, "LEGACY-KEY-VALUE")
        XCTAssertEqual(store.key(for: .mediaServer)?.label, MediaServerCredentialStore.keyLabel)
    }

    func test_migrate_failedKeptLegacyValue_whenTheStoreDiscardsTheWrite() {
        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore(behavior: .discardsWrites)

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        guard case .failedKeptLegacyValue = outcome else {
            return XCTFail("Expected .failedKeptLegacyValue, got \(outcome).")
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Legacy wins over a different Keychain value
    // -----------------------------------------------------------------

    func test_migrate_legacyValueWinsOverADifferentExistingStoreValue() {
        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore()
        // Something is already sitting in the store under this provider —
        // e.g. because the app quit between the migration's write and its
        // removal of the legacy value on a previous launch. The plan is
        // explicit that the OLD (legacy) value always wins, overwriting
        // whatever is already there.
        store.storeKey(
            StoredAPIKey(provider: .mediaServer, apiKey: "OLD-STORE-VALUE", label: MediaServerCredentialStore.keyLabel)
        )

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        XCTAssertEqual(outcome, .migrated)
        XCTAssertEqual(store.key(for: .mediaServer)?.apiKey, "LEGACY-KEY-VALUE")
        XCTAssertNil(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey))
    }

    // -----------------------------------------------------------------
    // MARK: - Failed store keeps the legacy value
    // -----------------------------------------------------------------

    func test_migrate_failedStore_keepsTheLegacyValueSoTheKeyStaysUsable() {
        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore(behavior: .discardsWrites)

        _ = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        // The legacy value must survive UNTOUCHED — removing it here on a
        // failed write would be a silent data loss (the key would then
        // exist nowhere at all: not in the store, not in `defaults`).
        XCTAssertEqual(
            defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey),
            "LEGACY-KEY-VALUE"
        )
        // And the system as a whole keeps working through the failure:
        // `currentKey` still returns it, since the store has nothing.
        XCTAssertEqual(
            MediaServerCredentialStore.currentKey(defaults: defaults, store: store),
            "LEGACY-KEY-VALUE"
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Read-back mismatch keeps the legacy value
    // -----------------------------------------------------------------

    func test_migrate_readBackMismatch_keepsTheLegacyValue() {
        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        // Unlike `.discardsWrites` (nothing comes back at all), this fake
        // DOES persist something — just not what was asked for. This is
        // exactly the failure shape the read-back verification exists to
        // catch: a write that "succeeds" without `storeKey` throwing is
        // not proof the right bytes landed.
        let store = FakeMediaServerKeyStore(behavior: .corruptsOnWrite(replacement: "CORRUPTED-VALUE"))

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: store)

        guard case .failedKeptLegacyValue = outcome else {
            return XCTFail("Expected .failedKeptLegacyValue, got \(outcome).")
        }
        XCTAssertEqual(
            defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey),
            "LEGACY-KEY-VALUE",
            "A read-back mismatch must leave the legacy value exactly as it was."
        )
        // The corrupted value is what the store ended up holding — proof
        // this test actually exercised the mismatch path, not the
        // discards-writes path.
        XCTAssertEqual(store.key(for: .mediaServer)?.apiKey, "CORRUPTED-VALUE")
    }

    // -----------------------------------------------------------------
    // MARK: - currentKey precedence
    // -----------------------------------------------------------------

    func test_currentKey_prefersTheStoreOverTheLegacyValue() {
        defaults.set("LEGACY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore()
        store.storeKey(
            StoredAPIKey(provider: .mediaServer, apiKey: "STORE-VALUE", label: MediaServerCredentialStore.keyLabel)
        )

        XCTAssertEqual(
            MediaServerCredentialStore.currentKey(defaults: defaults, store: store),
            "STORE-VALUE"
        )
    }

    func test_currentKey_fallsBackToTheLegacyValue_whenTheStoreHasNothing() {
        defaults.set("LEGACY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let store = FakeMediaServerKeyStore()

        XCTAssertEqual(
            MediaServerCredentialStore.currentKey(defaults: defaults, store: store),
            "LEGACY-VALUE"
        )
    }

    func test_currentKey_isNilWhenNeitherSourceHasAKey() {
        let store = FakeMediaServerKeyStore()

        XCTAssertNil(MediaServerCredentialStore.currentKey(defaults: defaults, store: store))
    }

    // -----------------------------------------------------------------
    // MARK: - saveKey / removeKey
    // -----------------------------------------------------------------

    func test_saveKey_neverWritesToUserDefaults() {
        let store = FakeMediaServerKeyStore()

        MediaServerCredentialStore.saveKey("NEW-KEY", store: store)

        XCTAssertEqual(store.key(for: .mediaServer)?.apiKey, "NEW-KEY")
        XCTAssertNil(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey))
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?[MediaServerCredentialStore.legacyDefaultsKey],
            "saveKey must never touch UserDefaults, under this key or any other."
        )
    }

    func test_removeKey_removesBothLabelledAndUnlabelledEntries() {
        let store = FakeMediaServerKeyStore()
        store.storeKey(
            StoredAPIKey(provider: .mediaServer, apiKey: "LABELLED", label: MediaServerCredentialStore.keyLabel)
        )
        // An unlabelled record could exist from a future/other caller —
        // `removeKey` must clear it too, mirroring
        // `MetadataSettingsTab.removeTMDBKey()`'s reasoning.
        store.storeKey(StoredAPIKey(provider: .mediaServer, apiKey: "UNLABELLED", label: nil))

        MediaServerCredentialStore.removeKey(store: store)

        XCTAssertNil(store.key(for: .mediaServer))
    }

    // -----------------------------------------------------------------
    // MARK: - Delivery proof: a fresh APIKeyManager sees the migrated key
    // -----------------------------------------------------------------

    /// Mirrors `APIKeyManagerKeychainTests.probeKeychainPersistence()`
    /// (see that file for the full rationale): on a headless CI runner
    /// with no unlocked default Keychain, a real `APIKeyManager` cannot
    /// persist anything, which would make this test's assertions
    /// meaningless rather than genuinely red. Returns a `Bool` for use
    /// with `XCTSkipUnless` in this ONE test, rather than skipping the
    /// whole file from `setUpWithError()` — every other test in this file
    /// uses `FakeMediaServerKeyStore` and has nothing to do with real
    /// Keychain availability, so skipping them all would hide regressions
    /// they are specifically there to catch.
    private func probeKeychainIsAvailable() -> Bool {
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
        let recoveredData = readResult as? Data

        SecItemDelete(deleteQuery as CFDictionary)

        return addStatus == errSecSuccess && readStatus == errSecSuccess && recoveredData == probeData
    }

    func test_migrate_deliveryProof_freshlyCreatedAPIKeyManagerSeesTheMigratedKey() throws {
        try XCTSkipUnless(
            probeKeychainIsAvailable(),
            "Keychain round-trip not supported on this host — see "
            + "APIKeyManagerKeychainTests.probeKeychainPersistence() for the full rationale."
        )

        defaults.set("LEGACY-KEY-VALUE", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        let firstManager = APIKeyManager(storageDirectory: storageDirectory, keychainService: keychainService)

        let outcome = MediaServerCredentialStore.migrateLegacyKeyIfNeeded(defaults: defaults, store: firstManager)

        XCTAssertEqual(outcome, .migrated)
        XCTAssertNil(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey))

        // The delivery proof: a SECOND, independently constructed manager,
        // pointed at the same storage directory and Keychain service, must
        // see the migrated key too. If migration had only updated
        // `firstManager`'s in-memory state without truly reaching the
        // Keychain and the on-disk metadata index, this would fail —
        // exactly the class of bug `APIKeyManagerIndexConsistencyTests`
        // exists to catch for `APIKeyManager` itself.
        let secondManager = APIKeyManager(storageDirectory: storageDirectory, keychainService: keychainService)
        XCTAssertEqual(secondManager.key(for: .mediaServer)?.apiKey, "LEGACY-KEY-VALUE")
    }
}
