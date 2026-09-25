// ============================================================================
// MeedyaConverter — EncodingProfileStoreBulkImportTests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 (settings export/import) needs a way to write a WHOLE batch of user
// profiles into `EncodingProfileStore` at once, in a way that:
//   - keeps every profile's `id` exactly as given (today's single-profile
//     `importProfile(from:)` deliberately mints a fresh UUID per import,
//     which would break `conditionalRules` that refer to a profile by id);
//   - refuses the whole batch — never half of it — if any profile in it
//     claims to be built-in, or if two profiles share an id;
//   - never leaves the in-memory profiles and the on-disk file disagreeing,
//     even if the disk write itself fails.
//
// `upsertUserProfiles(_:)` merges by id (existing id → replaced in place,
// new id → added, everything else untouched). `replaceUserProfiles(with:)`
// makes the user profiles become exactly the input. Both keep built-in
// profiles completely untouched, and both are proven here.
//
// Built-in profiles get a new random `id` every time the app launches
// (issue #510 — not fixed here). These tests never assume today's built-in
// ids are the same as any other run's: every check that needs "the current
// built-ins" reads them fresh from the store's own `profiles` array
// (`store.profiles.filter { $0.isBuiltIn }`), the same way the store's own
// implementation does, so nothing here would break if #510 changes how
// built-in ids are minted.
//
// Only public API is exercised (`import ConverterEngine`, no `@testable`),
// matching the policy documented at the top of `ConverterEngineTests.swift`
// and followed by `ProfileImportSubtitleTonemapTests.swift`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class EncodingProfileStoreBulkImportTests: XCTestCase {

    // MARK: - Fixtures

    /// A fresh, empty directory for this test's store, so tests never share
    /// state or race each other over a real file.
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoding-profile-store-bulk-import-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // If a permission-denial test forgot to restore write access before
        // failing, put it back before trying to remove the directory —
        // otherwise the removal itself fails and leaks the folder.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tempDir.path
        )
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    /// A minimal, valid user profile with a caller-chosen id, so tests can
    /// assert on exactly the id they passed in.
    private func makeUserProfile(id: UUID = UUID(), name: String) -> EncodingProfile {
        EncodingProfile(id: id, name: name, category: .custom, isBuiltIn: false)
    }

    /// A profile that dishonestly claims to be built-in, for the rejection
    /// tests. Nothing about `EncodingProfile.init` stops a caller building
    /// one of these — the store's validation is what has to catch it.
    private func makeFakeBuiltInProfile(id: UUID = UUID(), name: String) -> EncodingProfile {
        EncodingProfile(id: id, name: name, category: .custom, isBuiltIn: true)
    }

    // MARK: - IDs are kept

    func test_upsertUserProfiles_keepsCallerSuppliedIDs() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let id = UUID()
        let profile = makeUserProfile(id: id, name: "Keep My ID")

        try store.upsertUserProfiles([profile])

        let stored = store.profile(id: id)
        XCTAssertNotNil(stored, "The profile should be found by the exact id it was given")
        XCTAssertEqual(stored?.id, id)
        XCTAssertEqual(stored?.name, "Keep My ID")
    }

    func test_replaceUserProfiles_keepsCallerSuppliedIDs() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let id = UUID()
        let profile = makeUserProfile(id: id, name: "Keep My ID Too")

        try store.replaceUserProfiles(with: [profile])

        let stored = store.profile(id: id)
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.id, id)
    }

    // MARK: - Merge (upsert) semantics

    func test_upsertUserProfiles_replacesExistingIDAndAddsNewID_leavingOthersAlone() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let untouchedID = UUID()
        let replacedID = UUID()
        let newID = UUID()

        try store.upsertUserProfiles([
            makeUserProfile(id: untouchedID, name: "Untouched (v1)"),
            makeUserProfile(id: replacedID, name: "Will Be Replaced (v1)")
        ])

        try store.upsertUserProfiles([
            makeUserProfile(id: replacedID, name: "Replaced (v2)"),
            makeUserProfile(id: newID, name: "Brand New")
        ])

        XCTAssertEqual(store.profile(id: untouchedID)?.name, "Untouched (v1)",
                        "A profile whose id wasn't in the second batch must be left alone")
        XCTAssertEqual(store.profile(id: replacedID)?.name, "Replaced (v2)",
                        "A profile whose id WAS in the second batch must be replaced, not duplicated")
        XCTAssertEqual(store.profile(id: newID)?.name, "Brand New")

        let userProfiles = store.profiles.filter { !$0.isBuiltIn }
        XCTAssertEqual(userProfiles.count, 3, "Merge must not duplicate the replaced profile")
    }

    // MARK: - Replace semantics

    func test_replaceUserProfiles_removesUserProfilesNotInInput_andKeepsBuiltIns() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let builtInsBefore = Set(store.profiles.filter { $0.isBuiltIn }.map(\.id))
        XCTAssertFalse(builtInsBefore.isEmpty, "The store should start with its shipped built-in profiles")

        let keptID = UUID()
        let droppedID = UUID()
        try store.upsertUserProfiles([
            makeUserProfile(id: keptID, name: "Kept"),
            makeUserProfile(id: droppedID, name: "Dropped")
        ])
        XCTAssertNotNil(store.profile(id: droppedID), "Sanity check: the profile exists before the replace")

        try store.replaceUserProfiles(with: [
            makeUserProfile(id: keptID, name: "Kept")
        ])

        XCTAssertNotNil(store.profile(id: keptID), "Replace must keep a profile that IS in the input")
        XCTAssertNil(store.profile(id: droppedID), "Replace must remove a user profile that is NOT in the input")

        let builtInsAfter = Set(store.profiles.filter { $0.isBuiltIn }.map(\.id))
        XCTAssertEqual(builtInsAfter, builtInsBefore, "Replace must never touch built-in profiles")

        let userProfilesAfter = store.profiles.filter { !$0.isBuiltIn }
        XCTAssertEqual(userProfilesAfter.count, 1, "Only the one profile named in the replace input should remain")
    }

    // MARK: - Built-in claim is refused, whole batch, nothing changes

    func test_upsertUserProfiles_rejectsProfileClaimingBuiltIn_andChangesNothing() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let survivorID = UUID()
        try store.upsertUserProfiles([makeUserProfile(id: survivorID, name: "Already Here")])

        let profilesBefore = store.profiles
        let diskBefore = try Data(contentsOf: tempDir.appendingPathComponent("user_profiles.json"))

        let fakeBuiltInID = UUID()
        XCTAssertThrowsError(
            try store.upsertUserProfiles([
                makeUserProfile(name: "Fine On Its Own"),
                makeFakeBuiltInProfile(id: fakeBuiltInID, name: "Pretends To Be Built-in")
            ])
        ) { error in
            guard let bulkError = error as? EncodingProfileBulkImportError,
                  case .builtInProfileRejected(let id, _) = bulkError else {
                XCTFail("Expected .builtInProfileRejected, got \(error)")
                return
            }
            XCTAssertEqual(id, fakeBuiltInID)
        }

        XCTAssertEqual(store.profiles, profilesBefore, "Nothing in memory should change when the batch is refused")
        let diskAfter = try Data(contentsOf: tempDir.appendingPathComponent("user_profiles.json"))
        XCTAssertEqual(diskAfter, diskBefore, "The file on disk should be untouched when the batch is refused")
        XCTAssertNil(store.profile(named: "Fine On Its Own"),
                     "The valid profile in the same batch must NOT have been applied either — all or nothing")
        XCTAssertNotNil(store.profile(id: survivorID), "The pre-existing survivor profile must still be present")
    }

    func test_replaceUserProfiles_rejectsProfileClaimingBuiltIn_andChangesNothing() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        try store.upsertUserProfiles([makeUserProfile(name: "Already Here")])
        let profilesBefore = store.profiles

        XCTAssertThrowsError(
            try store.replaceUserProfiles(with: [makeFakeBuiltInProfile(name: "Pretends To Be Built-in")])
        ) { error in
            XCTAssertTrue(error is EncodingProfileBulkImportError)
        }

        XCTAssertEqual(store.profiles, profilesBefore)
    }

    // MARK: - Duplicate IDs are refused, whole batch, nothing changes

    func test_upsertUserProfiles_rejectsDuplicateIDsWithinBatch_andChangesNothing() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let profilesBefore = store.profiles
        let dupeID = UUID()

        XCTAssertThrowsError(
            try store.upsertUserProfiles([
                makeUserProfile(id: dupeID, name: "First"),
                makeUserProfile(id: dupeID, name: "Second")
            ])
        ) { error in
            guard let bulkError = error as? EncodingProfileBulkImportError,
                  case .duplicateID(let id) = bulkError else {
                XCTFail("Expected .duplicateID, got \(error)")
                return
            }
            XCTAssertEqual(id, dupeID)
        }

        XCTAssertEqual(store.profiles, profilesBefore)
        XCTAssertNil(store.profile(id: dupeID))
    }

    func test_replaceUserProfiles_rejectsDuplicateIDsWithinBatch_andChangesNothing() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let profilesBefore = store.profiles
        let dupeID = UUID()

        XCTAssertThrowsError(
            try store.replaceUserProfiles(with: [
                makeUserProfile(id: dupeID, name: "First"),
                makeUserProfile(id: dupeID, name: "Second")
            ])
        )

        XCTAssertEqual(store.profiles, profilesBefore)
    }

    // MARK: - A write failure throws, and leaves memory AND disk unchanged

    func test_upsertUserProfiles_writeFailure_throwsAndLeavesMemoryAndDiskUnchanged() throws {
        let store = EncodingProfileStore(storageDirectory: tempDir)
        let survivorID = UUID()
        try store.upsertUserProfiles([makeUserProfile(id: survivorID, name: "Before The Failure")])

        let profilesBefore = store.profiles
        let profilesFileURL = tempDir.appendingPathComponent("user_profiles.json")
        let diskBefore = try Data(contentsOf: profilesFileURL)

        // Make the profiles directory refuse writes (read + execute only),
        // so the next write's `createDirectory` succeeds trivially (the
        // directory already exists) but `Data.write(..., options: .atomic)`
        // fails, because an atomic write has to create a temporary file in
        // the same directory before renaming it into place, and that needs
        // write permission on the directory itself.
        //
        // No internal test seam was needed for this: `EncodingProfileStore`
        // already accepts its storage directory via the public
        // `storageDirectory:` initialiser parameter, so pointing a store at
        // an unwritable folder is possible with the existing public API.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)
        defer {
            // Restore before tearDown, and before any later assertion in
            // this test, so cleanup and re-reading the file both work.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        }

        XCTAssertThrowsError(
            try store.upsertUserProfiles([makeUserProfile(name: "Should Never Land")])
        ) { error in
            guard let bulkError = error as? EncodingProfileBulkImportError,
                  case .writeFailed = bulkError else {
                XCTFail("Expected .writeFailed, got \(error)")
                return
            }
        }

        XCTAssertEqual(store.profiles, profilesBefore,
                        "A failed write must leave the in-memory profiles exactly as they were")

        // Permissions are restored by the `defer` above before this read.
        let diskAfter = try Data(contentsOf: profilesFileURL)
        XCTAssertEqual(diskAfter, diskBefore,
                        "A failed write must leave the file on disk exactly as it was")
    }

    // MARK: - Round trip: the delivery proof

    func test_upsertThenFreshStore_seesSameProfilesWithSameIDs() throws {
        let firstID = UUID()
        let secondID = UUID()

        do {
            let store = EncodingProfileStore(storageDirectory: tempDir)
            try store.upsertUserProfiles([
                makeUserProfile(id: firstID, name: "Round Trip One"),
                makeUserProfile(id: secondID, name: "Round Trip Two")
            ])
        }

        // A brand-new store instance, reading the same folder on disk —
        // this is the actual point of `upsertUserProfiles`/
        // `replaceUserProfiles` existing: a settings file imported on
        // another Mac (or re-opened later on this one) must see the same
        // profiles under the same ids, so that any `conditionalRules` that
        // refer to them by id keep matching.
        let freshStore = EncodingProfileStore(storageDirectory: tempDir)

        let first = freshStore.profile(id: firstID)
        let second = freshStore.profile(id: secondID)
        XCTAssertEqual(first?.name, "Round Trip One")
        XCTAssertEqual(second?.name, "Round Trip Two")

        let userProfiles = freshStore.profiles.filter { !$0.isBuiltIn }
        XCTAssertEqual(userProfiles.count, 2)
    }
}
