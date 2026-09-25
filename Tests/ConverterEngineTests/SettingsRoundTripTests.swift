// ============================================================================
// MeedyaConverter — SettingsRoundTripTests (Issue #506 commit 5)
// Tests/ConverterEngineTests/SettingsRoundTripTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan test 4: what goes out comes back, and what is here is kept.
//   - Round trip: every allowed setting gets a sample value
//     (`SettingsTransferSamples`), is exported to a real file, the settings
//     and the profiles folder are WIPED, and the file is imported. Every
//     value must come back with the same type and content, the profiles with
//     the same IDs, and the email recipients still as TEXT holding a JSON
//     list. A test fails if the registry allows a setting with no sample.
//   - Merge keeps this Mac's list items, settings and profiles that the file
//     doesn't mention (lists are merged by `id`), and keeps a password this
//     Mac still holds in its own settings for a server the file also has.
//   - Replace removes things only inside the ticked groups; a missing
//     `useHardwareAcceleration` is REMOVED (so it keeps meaning "on"), never
//     written as off; "never" settings and Keychain items are untouched.
//   - "This Mac only" is not applied unless ticked.
//   - The half-apply guard: when saving the profiles file fails, the import
//     throws and the settings are exactly as they were.
//   - The preview: counts, warnings, cross-checks, the replace confirmation,
//     and that it writes nothing.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class SettingsRoundTripTests: XCTestCase {

    private var fixture: SettingsTransferFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try SettingsTransferFixture()
    }

    override func tearDown() {
        fixture.tearDown()
        fixture = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func exporter(_ domain: SettingsDomain, _ store: EncodingProfileStore) -> SettingsExporter {
        SettingsExporter(domain: domain, profileStore: store, presence: SettingsTransferFakePresence(),
                         appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate })
    }

    private func importer(_ domain: SettingsDomain, _ store: EncodingProfileStore) -> SettingsImporter {
        SettingsImporter(domain: domain, profileStore: store, presence: SettingsTransferFakePresence())
    }

    /// A full export of the samples and both profiles, every group ticked.
    private func sampleFile() throws -> Data {
        let source = fixture.makeDomain("sample-source")
        SettingsTransferSamples.storeAll(in: source.defaults)
        let store = fixture.makeProfileStore("sample-source")
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        return try exporter(source, store).makeData(categories: Set(SettingsCategory.allCases))
    }

    private func sftpServers(in domain: SettingsDomain) throws -> [SFTPServerConfig] {
        guard let data = domain.snapshot()[SFTPProfileStore.userDefaultsKey] as? Data else { return [] }
        return try JSONDecoder().decode([SFTPServerConfig].self, from: data)
    }

    // MARK: - Every allowed setting has a sample

    func test_everyExportableSettingHasASample() {
        let samples = Set(SettingsTransferSamples.storedValues.keys)
        let exportable = SettingsTransferSamples.exportableKeys
        XCTAssertEqual(
            exportable.subtracting(samples).sorted(), [],
            "These settings can be exported but have no sample in SettingsTransferSamples.storedValues. "
                + "Add one, so the round trip covers them."
        )
        XCTAssertEqual(
            samples.subtracting(exportable).sorted(), [],
            "These samples are for settings that can't be exported (never, or unknown). Remove them."
        )
    }

    // MARK: - The round trip

    func test_roundTripThroughAFileRestoresEverythingExactly() throws {
        let domain = fixture.makeDomain("roundtrip")
        SettingsTransferSamples.storeAll(in: domain.defaults)
        let store = fixture.makeProfileStore("roundtrip")
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        let before = domain.snapshot()
        let profilesBefore = store.allProfiles().filter { !$0.isBuiltIn }
        XCTAssertEqual(profilesBefore.map(\.id), SettingsTransferSamples.userProfiles.map(\.id))

        // Export every group, to a real file.
        let url = fixture.root.appendingPathComponent("roundtrip.json")
        try exporter(domain, store).write(to: url, categories: Set(SettingsCategory.allCases))

        // Wipe this Mac: the settings and the profiles folder.
        domain.defaults.removePersistentDomain(forName: domain.name)
        XCTAssertTrue(domain.snapshot().isEmpty, "The wipe must leave nothing behind.")
        try FileManager.default.removeItem(at: fixture.profilesDirectory("roundtrip"))
        let wipedStore = fixture.makeProfileStore("roundtrip")
        XCTAssertTrue(wipedStore.allProfiles().allSatisfy(\.isBuiltIn))

        // Import from the file on disk, every group.
        let plan = try SettingsImporter.prepare(contentsOf: url)
        let result = try importer(domain, wipedStore)
            .apply(plan, selection: Set(SettingsCategory.allCases), mode: .merge)
        let after = domain.snapshot()

        for key in SettingsTransferSamples.exportableKeys.sorted() {
            XCTAssertTrue(
                SettingsTransferSamples.sameStoredValue(before[key], after[key], key: key),
                "\(key) did not come back exactly: before \(String(describing: before[key])), "
                    + "after \(String(describing: after[key]))"
            )
        }
        XCTAssertEqual(Set(after.keys), Set(before.keys), "The import wrote something that wasn't exported.")
        XCTAssertEqual(Set(result.settingsWritten), Set(before.keys))

        // The email recipients stay TEXT holding a JSON list, in the app's
        // own form.
        XCTAssertTrue(after["emailToAddresses"] is String, "emailToAddresses must be stored as text.")
        XCTAssertEqual(after["emailToAddresses"] as? String, #"["a@example.com","b@example.com"]"#)

        // Profiles: same IDs, same content, same order; and on disk.
        XCTAssertEqual(wipedStore.allProfiles().filter { !$0.isBuiltIn }, profilesBefore)
        let reopened = fixture.makeProfileStore("roundtrip")
        XCTAssertEqual(reopened.allProfiles().filter { !$0.isBuiltIn }, profilesBefore)
        XCTAssertEqual(result.profileChanges.added, profilesBefore.map(\.name))

        // The conditional rule still points at the profile it pointed at.
        let rules = try JSONDecoder().decode([ConditionalRule].self, from: after["conditionalRules"] as? Data ?? Data())
        XCTAssertEqual(rules.first?.profileId, SettingsTransferSamples.profileAID)
        XCTAssertNotNil(reopened.profile(id: SettingsTransferSamples.profileAID))
    }

    func test_roundTripInMemoryToAnotherMac() throws {
        let data = try sampleFile()
        let other = fixture.makeDomain("other-mac")
        let otherStore = fixture.makeProfileStore("other-mac")
        let plan = try SettingsImporter.prepare(data)
        _ = try importer(other, otherStore).apply(plan, selection: Set(SettingsCategory.allCases), mode: .replace)
        let after = other.snapshot()
        let samples = SettingsTransferSamples.storedValues
        for key in SettingsTransferSamples.exportableKeys.sorted() {
            XCTAssertTrue(SettingsTransferSamples.sameStoredValue(samples[key], after[key], key: key), key)
        }
        XCTAssertEqual(otherStore.allProfiles().filter { !$0.isBuiltIn }, SettingsTransferSamples.userProfiles)
    }

    // MARK: - Merge keeps what is here

    func test_mergeKeepsThisMacsItemsSettingsAndProfiles() throws {
        let data = try SettingsTransferEditableFile(try sampleFile())
        var file = data
        file.removeSetting("filenameTemplate", in: "encoding")

        let target = fixture.makeDomain("merge-target")
        let store = fixture.makeProfileStore("merge-target")
        let localOnlyID = UUID()
        let localServers = [
            SFTPServerConfig(id: localOnlyID, host: "local.example", username: "me",
                             authMethod: .password(""), remotePath: "/in", label: "Local only"),
            SFTPServerConfig(id: SettingsTransferSamples.sftpNASID, host: "old-nas.local", username: "media",
                             authMethod: .password(""), remotePath: "/old", label: "NAS"),
        ]
        target.defaults.set(SettingsTransferSamples.encoded(localServers), forKey: SFTPProfileStore.userDefaultsKey)
        let localRule = ConditionalRule(name: "Local rule", profileId: UUID())
        target.defaults.set(SettingsTransferSamples.encoded([localRule]), forKey: "conditionalRules")
        target.defaults.set("local-{name}", forKey: "filenameTemplate")
        let localProfile = EncodingProfile(name: "Local only profile", containerFormat: .mov)
        var oldA = SettingsTransferSamples.userProfiles[0]
        oldA.videoCRF = 30
        try store.upsertUserProfiles([localProfile, oldA])

        let keychainWorks = fixture.keychainIsAvailable()
        if keychainWorks {
            try SFTPCredentialStore.save(password: "local-keychain-password", forProfileID: localOnlyID)
        }

        let plan = try SettingsImporter.prepare(file.data)
        let result = try importer(target, store).apply(plan, selection: Set(SettingsCategory.allCases), mode: .merge)

        // SFTP: this Mac's order kept, the shared one updated, new ones added.
        let servers = try sftpServers(in: target)
        XCTAssertEqual(servers.map(\.id), [localOnlyID, SettingsTransferSamples.sftpNASID,
                                           SettingsTransferSamples.sftpBackupID, SettingsTransferSamples.sftpAgentID])
        XCTAssertEqual(servers.first { $0.id == SettingsTransferSamples.sftpNASID }?.host, "nas.local")
        XCTAssertEqual(result.listChanges[SFTPProfileStore.userDefaultsKey],
                       SettingsListChanges(added: ["Backup", "Agent"], updated: ["NAS"], removed: []))
        if keychainWorks {
            XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: localOnlyID), .present,
                           "A merge must never touch a Keychain password.")
        }

        // Conditional rules: the local one kept, the file's added.
        let rules = try JSONDecoder().decode([ConditionalRule].self,
                                             from: target.snapshot()["conditionalRules"] as? Data ?? Data())
        XCTAssertEqual(rules.map(\.id), [localRule.id, SettingsTransferSamples.ruleID])

        // A setting the file doesn't have is left alone.
        XCTAssertEqual(target.snapshot()["filenameTemplate"] as? String, "local-{name}")

        // Profiles: the local one kept, A updated, B added.
        let profiles = store.allProfiles().filter { !$0.isBuiltIn }
        XCTAssertEqual(profiles.map(\.id), [localProfile.id, SettingsTransferSamples.profileAID,
                                            SettingsTransferSamples.profileBID])
        XCTAssertEqual(store.profile(id: SettingsTransferSamples.profileAID)?.videoCRF, 19)
        XCTAssertEqual(result.profileChanges.added, ["Archive"])
        XCTAssertEqual(result.profileChanges.updated, ["My HEVC"])
        XCTAssertEqual(result.profileChanges.removed, [])
    }

    func test_mergeKeepsAPasswordThisMacStillHoldsInItsOwnSettings() throws {
        // This Mac has never opened its SFTP screen since upgrading, so its
        // NAS password is still in the settings file. The file's copy of NAS
        // has the blank password every file has; merging must not wipe it.
        let target = fixture.makeDomain("legacy-target")
        let legacy = [SFTPServerConfig(id: SettingsTransferSamples.sftpNASID, host: "nas.local", port: 2222,
                                       username: "media", authMethod: .password("legacy-plaintext"),
                                       remotePath: "/media", label: "NAS")]
        target.defaults.set(SettingsTransferSamples.encoded(legacy), forKey: SFTPProfileStore.userDefaultsKey)

        let plan = try SettingsImporter.prepare(try sampleFile())
        for mode in SettingsImportMode.allCases {
            let result = try importer(target, fixture.makeProfileStore("legacy-target"))
                .apply(plan, selection: [.connections], mode: mode)
            let nas = try sftpServers(in: target).first { $0.id == SettingsTransferSamples.sftpNASID }
            XCTAssertEqual(nas?.authMethod, .password("legacy-plaintext"), "\(mode) wiped this Mac's password.")
            XCTAssertFalse(result.stillNeeded.contains { $0.kind == .sftpPassword(profileID: SettingsTransferSamples.sftpNASID) },
                           "A password kept here is not 'still needed'.")
        }
    }

    func test_mergeRefusesWhenThisMacsListCannotBeRead_replaceDoesNot() throws {
        let target = fixture.makeDomain("unreadable")
        target.defaults.set(Data("not json".utf8), forKey: SFTPProfileStore.userDefaultsKey)
        target.defaults.set("Light", forKey: "appearanceMode")
        let before = target.snapshotDictionary
        let plan = try SettingsImporter.prepare(try sampleFile())

        XCTAssertThrowsError(
            try importer(target, fixture.makeProfileStore("unreadable"))
                .apply(plan, selection: Set(SettingsCategory.allCases), mode: .merge)
        ) { error in
            XCTAssertEqual(error as? SettingsImportError,
                           .localValueUnreadable(category: .connections, key: SFTPProfileStore.userDefaultsKey))
        }
        XCTAssertEqual(target.snapshotDictionary, before, "A refused merge must change nothing.")

        _ = try importer(target, fixture.makeProfileStore("unreadable"))
            .apply(plan, selection: [.connections], mode: .replace)
        XCTAssertEqual(try sftpServers(in: target).count, SettingsTransferSamples.sftpServers.count)
    }

    // MARK: - Replace, inside the ticked groups only

    func test_replaceRemovesOnlyInsideTickedGroups() throws {
        // The file: a few settings in three groups, and two profiles.
        let source = fixture.makeDomain("replace-source")
        source.defaults.set("My HEVC", forKey: "defaultProfileName")
        source.defaults.set(2, forKey: ParallelEncoder.maxConcurrentJobsDefaultsKey)
        source.defaults.set(465, forKey: "emailSMTPPort")
        source.defaults.set(true, forKey: "autoScrollLog")
        let sourceStore = fixture.makeProfileStore("replace-source")
        try sourceStore.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        let plan = try SettingsImporter.prepare(
            try exporter(source, sourceStore).makeData(categories: Set(SettingsCategory.allCases))
        )

        // This Mac.
        let target = fixture.makeDomain("replace-target")
        let defaults = target.defaults
        defaults.set("local-{name}", forKey: "filenameTemplate")
        defaults.set(true, forKey: "overwriteExisting")
        defaults.set(false, forKey: "useHardwareAcceleration")
        defaults.set("smtp.local.example", forKey: "emailSMTPHost")
        defaults.set("Light", forKey: "appearanceMode")
        defaults.set("https://hooks.slack.com/services/LOCAL", forKey: "webhookURL")
        let hooks = SettingsTransferSamples.encoded(PostEncodeActionChain(actions: [
            PostEncodeAction(type: .openInFinder, name: "Reveal"),
        ]))
        defaults.set(hooks, forKey: "postEncodeActionChain")
        let localServerID = UUID()
        defaults.set(SettingsTransferSamples.encoded([SFTPServerConfig(
            id: localServerID, host: "local.example", username: "me", authMethod: .password(""),
            remotePath: "/", label: "Local server"
        )]), forKey: SFTPProfileStore.userDefaultsKey)
        let store = fixture.makeProfileStore("replace-target")
        let localProfile = EncodingProfile(name: "Local only", containerFormat: .mov)
        try store.upsertUserProfiles([localProfile])
        let keychainWorks = fixture.keychainIsAvailable()
        if keychainWorks {
            try SFTPCredentialStore.save(password: "local-keychain-password", forProfileID: localServerID)
        }

        // 1. Replace with ONLY Encoding ticked.
        _ = try importer(target, store).apply(plan, selection: [.encoding], mode: .replace)
        var stored = target.snapshot()
        XCTAssertNil(stored["filenameTemplate"], "Encoding settings not in the file go back to their defaults.")
        XCTAssertNil(stored["overwriteExisting"])
        XCTAssertNil(stored["useHardwareAcceleration"],
                     "A missing useHardwareAcceleration is REMOVED (meaning on), never written as off.")
        XCTAssertEqual(stored["defaultProfileName"] as? String, "My HEVC")
        XCTAssertEqual(stored[ParallelEncoder.maxConcurrentJobsDefaultsKey] as? Int, 2)
        // Untouched: other groups, never settings, profiles.
        XCTAssertEqual(stored["emailSMTPHost"] as? String, "smtp.local.example")
        XCTAssertNil(stored["emailSMTPPort"])
        XCTAssertEqual(stored["appearanceMode"] as? String, "Light")
        XCTAssertNil(stored["autoScrollLog"])
        XCTAssertEqual(stored["webhookURL"] as? String, "https://hooks.slack.com/services/LOCAL")
        XCTAssertEqual(stored["postEncodeActionChain"] as? Data, hooks)
        XCTAssertEqual(try sftpServers(in: target).map(\.id), [localServerID])
        XCTAssertEqual(store.allProfiles().filter { !$0.isBuiltIn }.map(\.id), [localProfile.id])

        // 2. Replace with Connections and profiles ticked.
        let result = try importer(target, store).apply(plan, selection: [.connections, .encodingProfiles],
                                                      mode: .replace)
        stored = target.snapshot()
        XCTAssertNil(stored["emailSMTPHost"])
        XCTAssertEqual(stored["emailSMTPPort"] as? Int, 465)
        XCTAssertNil(stored[SFTPProfileStore.userDefaultsKey], "The file has no SFTP servers, so the list goes.")
        XCTAssertEqual(result.listChanges[SFTPProfileStore.userDefaultsKey]?.removed, ["Local server"])
        XCTAssertEqual(stored["webhookURL"] as? String, "https://hooks.slack.com/services/LOCAL",
                       "A never setting is never removed.")
        XCTAssertEqual(stored["postEncodeActionChain"] as? Data, hooks)
        XCTAssertEqual(stored["appearanceMode"] as? String, "Light", "General was not ticked.")
        XCTAssertEqual(store.allProfiles().filter { !$0.isBuiltIn }.map(\.id),
                       SettingsTransferSamples.userProfiles.map(\.id))
        XCTAssertEqual(result.profileChanges.removed, ["Local only"])
        if keychainWorks {
            XCTAssertEqual(SFTPCredentialStore.exists(forProfileID: localServerID), .present,
                           "Replace removes the server, never its Keychain password.")
        }
    }

    func test_mergeLeavesUseHardwareAccelerationAloneWhenTheFileDoesNotHaveIt() throws {
        let source = fixture.makeDomain("hw-source")
        source.defaults.set(true, forKey: "overwriteExisting")
        let plan = try SettingsImporter.prepare(
            try exporter(source, fixture.makeProfileStore("hw-source")).makeData(categories: [.encoding])
        )
        let absent = fixture.makeDomain("hw-absent")
        _ = try importer(absent, fixture.makeProfileStore("hw-absent")).apply(plan, selection: [.encoding], mode: .merge)
        XCTAssertNil(absent.snapshot()["useHardwareAcceleration"], "Absent stays absent (meaning on).")

        let off = fixture.makeDomain("hw-off")
        off.defaults.set(false, forKey: "useHardwareAcceleration")
        _ = try importer(off, fixture.makeProfileStore("hw-off")).apply(plan, selection: [.encoding], mode: .merge)
        XCTAssertEqual(SettingsStoredValue.bool(off.snapshot()["useHardwareAcceleration"] as Any), false)
    }

    // MARK: - This Mac only

    func test_thisMacIsNotAppliedUnlessTicked() throws {
        let plan = try SettingsImporter.prepare(try sampleFile())
        XCTAssertTrue(plan.categoriesInFile.contains(.thisMac))
        XCTAssertFalse(plan.defaultSelection.contains(.thisMac), "This Mac only starts unticked on import.")

        let target = fixture.makeDomain("thismac")
        let store = fixture.makeProfileStore("thismac")
        let preview = importer(target, store).preview(plan, selection: plan.defaultSelection, mode: .merge)
        XCTAssertEqual(preview.groups.first { $0.category == .thisMac }?.isSelected, false)
        XCTAssertFalse(preview.warnings.contains(SettingsCategory.thisMac.warning ?? "-"))

        _ = try importer(target, store).apply(plan, selection: plan.defaultSelection, mode: .merge)
        for entry in SettingsKeyRegistry.entries(in: .thisMac) {
            XCTAssertNil(target.snapshot()[entry.key], "\(entry.key) was applied without This Mac ticked.")
        }

        let ticked = plan.defaultSelection.union([.thisMac])
        let tickedPreview = importer(target, store).preview(plan, selection: ticked, mode: .merge)
        XCTAssertTrue(tickedPreview.warnings.contains(SettingsCategory.thisMac.warning ?? "-"))
        _ = try importer(target, store).apply(plan, selection: ticked, mode: .merge)
        XCTAssertEqual(target.snapshot()["customFFmpegPath"] as? String, "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(target.snapshot()["accurateRip.driveOffset"] as? Int, -472)
    }

    // MARK: - The half-apply guard

    func test_failedProfileWriteLeavesSettingsUnchanged() throws {
        let plan = try SettingsImporter.prepare(try sampleFile())
        let target = fixture.makeDomain("halfapply")
        target.defaults.set("Light", forKey: "appearanceMode")
        target.defaults.set(false, forKey: "overwriteExisting")
        let before = target.snapshotDictionary

        // A FILE where the profiles folder should be: creating the folder,
        // and so saving the profiles, fails every time.
        let blocked = fixture.root.appendingPathComponent("blocked-profiles")
        try Data("not a folder".utf8).write(to: blocked)
        let store = EncodingProfileStore(storageDirectory: blocked)

        for mode in SettingsImportMode.allCases {
            XCTAssertThrowsError(
                try importer(target, store).apply(plan, selection: Set(SettingsCategory.allCases), mode: mode)
            ) { error in
                guard case .profileStoreWriteFailed? = error as? SettingsImportError else {
                    return XCTFail("Expected profileStoreWriteFailed, got \(error)")
                }
                XCTAssertTrue((error as? SettingsImportError)?.errorDescription?.hasSuffix("Nothing was changed.") == true)
            }
            XCTAssertEqual(target.snapshotDictionary, before, "Settings changed although the import failed (\(mode)).")
            XCTAssertTrue(store.allProfiles().allSatisfy(\.isBuiltIn))
        }
    }

    // MARK: - Preview

    func test_previewShowsCountsWarningsAndCrossChecksAndWritesNothing() throws {
        let plan = try SettingsImporter.prepare(try sampleFile())
        let target = fixture.makeDomain("preview")
        target.defaults.set("Dark", forKey: "appearanceMode")          // same as the file
        target.defaults.set(false, forKey: "overwriteExisting")        // the file turns it on
        let localServerID = UUID()
        target.defaults.set(SettingsTransferSamples.encoded([SFTPServerConfig(
            id: localServerID, host: "local.example", username: "me", authMethod: .agent,
            remotePath: "/", label: "Local server"
        )]), forKey: SFTPProfileStore.userDefaultsKey)
        let store = fixture.makeProfileStore("preview")
        try store.upsertUserProfiles([EncodingProfile(name: "Local only", containerFormat: .mov)])
        let settingsBefore = target.snapshotDictionary
        let profilesBefore = store.allProfiles()
        let importer = importer(target, store)

        // Without the profiles group: the default profile and the rule's
        // profile won't exist here.
        let withoutProfiles = importer.preview(plan, selection: [.general, .encoding, .connections], mode: .merge)
        XCTAssertTrue(withoutProfiles.crossChecks.contains(
            "Default profile ‘My HEVC’ isn't on this Mac and isn't being imported, so ‘Web Standard’ will be used."
        ), "\(withoutProfiles.crossChecks)")
        XCTAssertTrue(withoutProfiles.crossChecks.contains { $0.contains("‘HDR to HEVC’") })
        XCTAssertTrue(withoutProfiles.warnings.contains { $0.hasPrefix("Delete source after successful encode: ON") })
        XCTAssertTrue(withoutProfiles.warnings.contains { $0.hasPrefix("Overwrite existing output files: ON") })
        XCTAssertNil(withoutProfiles.replaceConfirmation)

        let general = withoutProfiles.groups.first { $0.category == .general }
        XCTAssertEqual(general?.countInFile, 13)
        XCTAssertEqual(general?.items.first { $0.key == "appearanceMode" }?.change, .unchanged)
        XCTAssertEqual(general?.summary, "13 settings, 12 differ from yours")
        let encoding = withoutProfiles.groups.first { $0.category == .encoding }
        XCTAssertEqual(encoding?.items.first { $0.key == "overwriteExisting" }?.change, .changed)
        XCTAssertEqual(encoding?.items.first { $0.key == "deleteSourceAfterEncode" }?.change, .added)
        XCTAssertTrue(withoutProfiles.takesEffectNextLaunch.contains("Default encoding profile (by name)"))
        XCTAssertEqual(withoutProfiles.groups.first { $0.category == .encodingProfiles }?.isSelected, false)

        // With the profiles group: both cross-checks clear.
        let withProfiles = importer.preview(plan, selection: plan.defaultSelection, mode: .merge)
        XCTAssertEqual(withProfiles.crossChecks, [])
        XCTAssertEqual(withProfiles.groups.first { $0.category == .encodingProfiles }?.summary,
                       "2 profiles: 2 new")

        // Replace says what it removes.
        let replace = importer.preview(plan, selection: Set(SettingsCategory.allCases), mode: .replace)
        XCTAssertEqual(replace.replaceConfirmation,
                       "This removes 1 profile and 1 SFTP server. Passwords and keys are never touched.")
        XCTAssertEqual(replace.groups.first { $0.category == .connections }?.listChanges[SFTPProfileStore.userDefaultsKey]?.removed,
                       ["Local server"])

        // A preview writes nothing.
        XCTAssertEqual(target.snapshotDictionary, settingsBefore)
        XCTAssertEqual(store.allProfiles(), profilesBefore)
    }

    func test_previewHidesAnAddressHoldingCredentialsOnThisMac() throws {
        let plan = try SettingsImporter.prepare(try sampleFile())
        let target = fixture.makeDomain("hidden")
        target.defaults.set("https://user:local-secret@github.com/x.git", forKey: "teamProfiles.gitRemote")
        let preview = importer(target, fixture.makeProfileStore("hidden"))
            .preview(plan, selection: [.connections], mode: .merge)
        let item = preview.groups.first { $0.category == .connections }?.items.first { $0.key == "teamProfiles.gitRemote" }
        XCTAssertEqual(item?.currentValue, "(hidden: it contains a user name, password or token)")
        XCTAssertFalse(String(describing: preview).contains("local-secret"))
    }

    // MARK: - The report

    func test_reportSaysWhatWasDoneInPlainEnglish() throws {
        let plan = try SettingsImporter.prepare(try sampleFile())
        let target = fixture.makeDomain("report")
        let result = try importer(target, fixture.makeProfileStore("report"))
            .apply(plan, selection: plan.defaultSelection, mode: .merge)
        let lines = result.reportLines
        XCTAssertEqual(lines.first, "Imported \(result.settingsWritten.count) settings and 2 profiles.")
        XCTAssertTrue(lines.contains { $0.hasPrefix("These take effect next time you open MeedyaConverter:") })
        let text = lines.joined(separator: "\n").lowercased()
        XCTAssertFalse(text.contains("restored"), "Never claim the setup was restored.")
        XCTAssertFalse(text.contains("secure"), "Never claim anything is secure.")
    }
}
