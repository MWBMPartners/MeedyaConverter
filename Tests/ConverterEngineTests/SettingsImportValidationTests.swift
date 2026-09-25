// ============================================================================
// MeedyaConverter — SettingsImportValidationTests (Issue #506 commit 5)
// Tests/ConverterEngineTests/SettingsImportValidationTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan test 3. Every bad file must be refused WHOLE, and this Mac's
// settings and profiles file must be exactly as they were before (compared
// as a full snapshot of the settings domain, and the profiles file's bytes).
//
// Each bad file starts as a REAL export (so only the one thing under test is
// wrong) and is run through the whole import flow the app and command-line
// tool use: `prepare`, then `apply` with every group in the file ticked, in
// "replace" mode, the mode that would change the most.
//
// Also: things that are NOT errors (an unknown setting, an unknown group, a
// known setting in the wrong group, a "never" setting such as a password or
// hooks, an unknown `notIncluded` name) are listed in `ignored` and never
// written, while the rest of the file imports.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class SettingsImportValidationTests: XCTestCase {

    private var fixture: SettingsTransferFixture!
    /// This Mac: some settings and a profile of its own, so "nothing
    /// changed" is checked against something real.
    private var target: SettingsDomain!
    private var targetStore: EncodingProfileStore!
    /// A valid file, from a real export of a fully populated source.
    private var validFile: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try SettingsTransferFixture()

        let source = fixture.makeDomain("source")
        SettingsTransferSamples.storeAll(in: source.defaults)
        let sourceStore = fixture.makeProfileStore("source")
        try sourceStore.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        validFile = try SettingsExporter(
            domain: source, profileStore: sourceStore, presence: SettingsTransferFakePresence(),
            appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate }
        ).makeData(categories: Set(SettingsCategory.allCases))

        target = fixture.makeDomain("target")
        target.defaults.set("Light", forKey: "appearanceMode")
        target.defaults.set(false, forKey: "overwriteExisting")
        target.defaults.set("smtp.local.example", forKey: "emailSMTPHost")
        target.defaults.set("https://hooks.slack.com/services/LOCAL", forKey: "webhookURL")
        target.defaults.set("/usr/local/bin/ffmpeg", forKey: "customFFmpegPath")
        targetStore = fixture.makeProfileStore("target")
        try targetStore.upsertUserProfiles([EncodingProfile(name: "Local only", containerFormat: .mov)])
    }

    override func tearDown() {
        fixture.tearDown()
        fixture = nil
        target = nil
        targetStore = nil
        validFile = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// The whole import flow: check, then apply every group, replacing.
    private func importFile(_ data: Data) throws -> SettingsImportResult {
        let plan = try SettingsImporter.prepare(data)
        return try SettingsImporter(domain: target, profileStore: targetStore, presence: SettingsTransferFakePresence())
            .apply(plan, selection: Set(SettingsCategory.allCases), mode: .replace)
    }

    private var profilesFileBytes: Data? {
        try? Data(contentsOf: fixture.profilesDirectory("target").appendingPathComponent("user_profiles.json"))
    }

    /// Imports `data`, expects it refused as `expected`, and checks that
    /// nothing on "this Mac" changed.
    private func assertRefusedWithoutChange(
        _ data: Data,
        _ expected: (SettingsImportError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let settingsBefore = target.snapshotDictionary
        let profilesBefore = profilesFileBytes
        let inMemoryBefore = targetStore.allProfiles()

        XCTAssertThrowsError(try importFile(data), file: file, line: line) { error in
            guard let importError = error as? SettingsImportError else {
                return XCTFail("Expected a SettingsImportError, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(expected(importError), "Unexpected error: \(importError)", file: file, line: line)
            XCTAssertTrue(
                importError.errorDescription?.hasSuffix("Nothing was changed.") == true,
                "Every import error must say nothing was changed: \(importError.errorDescription ?? "")",
                file: file, line: line
            )
        }
        XCTAssertEqual(target.snapshotDictionary, settingsBefore, "Settings changed after a refused file.",
                       file: file, line: line)
        XCTAssertEqual(profilesFileBytes, profilesBefore, "The profiles file changed after a refused file.",
                       file: file, line: line)
        XCTAssertEqual(targetStore.allProfiles(), inMemoryBefore, file: file, line: line)
    }

    private func edited(_ change: (inout SettingsTransferEditableFile) -> Void) throws -> Data {
        var file = try SettingsTransferEditableFile(validFile)
        change(&file)
        return file.data
    }

    private func isInvalidValue(_ category: SettingsCategory, _ key: String) -> (SettingsImportError) -> Bool {
        { error in
            if case .invalidValue(let foundCategory, let foundKey, _) = error {
                return foundCategory == category && foundKey == key
            }
            return false
        }
    }

    // MARK: - The valid file really is valid

    func test_theUneditedFileImports() throws {
        XCTAssertNoThrow(try importFile(validFile))
    }

    // MARK: - The file's wrapper

    func test_newerVersionIsRefusedWithAClearMessage() throws {
        let data = try edited { $0.root["version"] = 2 }
        assertRefusedWithoutChange(data) { $0 == .newerFormat(found: 2, supported: 1) }
        let message = SettingsImportError.newerFormat(found: 2, supported: 1).errorDescription ?? ""
        XCTAssertTrue(message.contains("This file was made by a newer version of MeedyaConverter (format 2)."))
        XCTAssertTrue(message.contains("This version reads format 1. Update MeedyaConverter, then import again."))
    }

    func test_newerVersionIsRefusedEvenWhenItsShapeIsDifferent() throws {
        // A newer format may be shaped differently; it must get "update",
        // never "damaged".
        let data = Data(#"{"format":"meedyaconverter.settings","version":7,"groups":[1,2,3]}"#.utf8)
        assertRefusedWithoutChange(data) { $0 == .newerFormat(found: 7, supported: 1) }
    }

    func test_notJSONIsRefused() {
        assertRefusedWithoutChange(Data("appearanceMode = Dark".utf8)) { $0 == .notJSON }
        assertRefusedWithoutChange(Data()) { $0 == .notJSON }
    }

    func test_wrongOrMissingMarkerIsRefused() throws {
        assertRefusedWithoutChange(try edited { $0.root["format"] = "someone.else.settings" }) { $0 == .notASettingsFile }
        assertRefusedWithoutChange(try edited { $0.root.removeValue(forKey: "format") }) { $0 == .notASettingsFile }
        assertRefusedWithoutChange(Data("[1, 2, 3]".utf8)) { $0 == .notASettingsFile }
    }

    func test_versionZeroIsRefused() throws {
        assertRefusedWithoutChange(try edited { $0.root["version"] = 0 }) { $0 == .unsupportedFormat(found: 0) }
    }

    func test_versionThatIsNotAWholeNumberIsRefused() throws {
        assertRefusedWithoutChange(try edited { $0.root["version"] = "1" }) {
            $0 == .malformed(path: "version", reason: "should be a whole number")
        }
    }

    func test_missingCategoriesIsRefused() throws {
        assertRefusedWithoutChange(try edited { $0.root.removeValue(forKey: "categories") }) {
            $0 == .malformed(path: "categories", reason: "is missing")
        }
    }

    func test_badDateIsRefused() throws {
        assertRefusedWithoutChange(try edited { $0.root["exportedAt"] = "yesterday" }) {
            if case .malformed(let path, _) = $0 { return path == "exportedAt" }
            return false
        }
    }

    func test_groupWithoutItsSettingsObjectIsRefused() throws {
        let data = try edited { file in
            var categories = file.root["categories"] as? [String: Any] ?? [:]
            categories["general"] = ["values": ["appearanceMode": "Dark"]]
            file.root["categories"] = categories
        }
        assertRefusedWithoutChange(data) {
            $0 == .malformed(path: "categories.general.settings", reason: "is missing")
        }
    }

    func test_fileOverTheSizeLimitIsRefused() throws {
        // A valid file padded with spaces past 10 MB.
        var padded = validFile!
        padded.append(Data(repeating: UInt8(ascii: " "), count: SettingsDocument.maximumFileSize))
        assertRefusedWithoutChange(padded) {
            if case .fileTooLarge(let bytes, let limit) = $0 { return bytes == padded.count && limit == 10 * 1_048_576 }
            return false
        }

        // From disk, it is refused by its size before being read.
        let url = fixture.root.appendingPathComponent("huge.json")
        try padded.write(to: url)
        XCTAssertThrowsError(try SettingsImporter.prepare(contentsOf: url)) { error in
            guard case .fileTooLarge? = error as? SettingsImportError else { return XCTFail("\(error)") }
        }
    }

    func test_fileNestedTooDeeplyIsRefusedBeforeDecoding() {
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        let data = Data("{\"format\":\"meedyaconverter.settings\",\"version\":1,\"categories\":{},\"x\":\(deep)}".utf8)
        assertRefusedWithoutChange(data) {
            if case .malformed(let path, _) = $0 { return path.isEmpty }
            return false
        }
    }

    func test_missingFileIsReportedAsUnreadable() {
        let url = fixture.root.appendingPathComponent("does-not-exist.json")
        XCTAssertThrowsError(try SettingsImporter.prepare(contentsOf: url)) { error in
            guard case .fileUnreadable? = error as? SettingsImportError else { return XCTFail("\(error)") }
        }
    }

    // MARK: - One bad value refuses the whole file

    func test_textWhereOnOffBelongsRefusesTheWholeFile() throws {
        let data = try edited { $0.setSetting("autoScrollLog", "yes", in: "general") }
        assertRefusedWithoutChange(data, isInvalidValue(.general, "autoScrollLog"))
    }

    func test_portOutOfRangeIsRefused() throws {
        let data = try edited { $0.setSetting("emailSMTPPort", 70_000, in: "connections") }
        assertRefusedWithoutChange(data, isInvalidValue(.connections, "emailSMTPPort"))
    }

    func test_decimalWhereAWholeNumberBelongsIsRefused() throws {
        let data = try edited { $0.setSetting("proresVector.frameStride", 2.5, in: "encoding") }
        assertRefusedWithoutChange(data, isInvalidValue(.encoding, "proresVector.frameStride"))
    }

    func test_unknownChoiceIsRefused() throws {
        let data = try edited { $0.setSetting("appearanceMode", "Purple", in: "general") }
        assertRefusedWithoutChange(data, isInvalidValue(.general, "appearanceMode"))
    }

    func test_nullForAKnownSettingIsRefused() throws {
        let data = try edited { $0.setSetting("updateChannel", NSNull(), in: "general") }
        assertRefusedWithoutChange(data, isInvalidValue(.general, "updateChannel"))
    }

    func test_badColourIsRefused() throws {
        let data = try edited { $0.setSetting("customAccentColor", "blue", in: "general") }
        assertRefusedWithoutChange(data, isInvalidValue(.general, "customAccentColor"))
    }

    func test_relativeToolPathIsRefused() throws {
        let data = try edited { $0.setSetting("customFFmpegPath", "bin/ffmpeg", in: "thisMac") }
        assertRefusedWithoutChange(data, isInvalidValue(.thisMac, "customFFmpegPath"))
    }

    func test_addressWithCredentialsIsRefused() throws {
        for address in ["https://user:secret@github.com/example/profiles.git",
                        "https://ghp_token@github.com/example/profiles.git",
                        "ssh://git:secret@github.com/example.git",
                        "user:secret@github.com:example/profiles.git",
                        "https://github.com/example/profiles.git?access_token=abc"] {
            let data = try edited { $0.setSetting("teamProfiles.gitRemote", address, in: "connections") }
            assertRefusedWithoutChange(data, isInvalidValue(.connections, "teamProfiles.gitRemote"))
        }
        let plex = try edited {
            $0.setSetting("mediaServerHost", "http://10.0.0.2:32400/?X-Plex-Token=abc", in: "connections")
        }
        assertRefusedWithoutChange(plex, isInvalidValue(.connections, "mediaServerHost"))
    }

    func test_addressesWithoutCredentialsAreAccepted() throws {
        for address in ["https://github.com/example/profiles.git",
                        "git@github.com:example/profiles.git",
                        "ssh://git@github.com/example/profiles.git",
                        ""] {
            let data = try edited { $0.setSetting("teamProfiles.gitRemote", address, in: "connections") }
            XCTAssertNoThrow(try SettingsImporter.prepare(data), address)
        }
    }

    func test_sftpServerCarryingAPasswordIsRefused() throws {
        let data = try edited { file in
            var servers = file.settings(in: "connections")[SFTPProfileStore.userDefaultsKey] as? [[String: Any]] ?? []
            XCTAssertFalse(servers.isEmpty)
            servers[0]["authMethod"] = ["password": ["_0": "hunter2"]]
            file.setSetting(SFTPProfileStore.userDefaultsKey, servers, in: "connections")
        }
        assertRefusedWithoutChange(data, isInvalidValue(.connections, SFTPProfileStore.userDefaultsKey))
    }

    func test_sftpServerWithoutAnIDIsRefused() throws {
        let data = try edited { file in
            var servers = file.settings(in: "connections")[SFTPProfileStore.userDefaultsKey] as? [[String: Any]] ?? []
            servers[0].removeValue(forKey: "id")
            file.setSetting(SFTPProfileStore.userDefaultsKey, servers, in: "connections")
        }
        assertRefusedWithoutChange(data, isInvalidValue(.connections, SFTPProfileStore.userDefaultsKey))
    }

    func test_duplicateListIDsAreRefused() throws {
        let data = try edited { file in
            let servers = file.settings(in: "connections")[SFTPProfileStore.userDefaultsKey] as? [[String: Any]] ?? []
            file.setSetting(SFTPProfileStore.userDefaultsKey, servers + [servers[0]], in: "connections")
        }
        assertRefusedWithoutChange(data, isInvalidValue(.connections, SFTPProfileStore.userDefaultsKey))
    }

    func test_cloudDestinationCarryingATokenIsRefused() throws {
        for (field, value) in [("accessToken", "tok"), ("refreshToken", "ref"), ("secretAccessKey", "sec")] {
            let data = try edited { file in
                var items = file.settings(in: "connections")[CloudStorageProfileStore.userDefaultsKey]
                    as? [[String: Any]] ?? []
                XCTAssertFalse(items.isEmpty)
                items[0][field] = value
                file.setSetting(CloudStorageProfileStore.userDefaultsKey, items, in: "connections")
            }
            assertRefusedWithoutChange(data, isInvalidValue(.connections, CloudStorageProfileStore.userDefaultsKey))
        }
    }

    func test_profileClaimingToBeBuiltInRefusesTheWholeFile() throws {
        let data = try edited { file in
            var profiles = file.profiles
            XCTAssertEqual(profiles.count, 2)
            profiles[1]["isBuiltIn"] = true
            file.setProfiles(profiles)
        }
        assertRefusedWithoutChange(data) {
            if case .invalidValue(.encodingProfiles, "Archive", let reason) = $0 {
                return reason.contains("built-in")
            }
            return false
        }
    }

    func test_duplicateProfileIDsAreRefused() throws {
        let data = try edited { file in
            let profiles = file.profiles
            file.setProfiles(profiles + [profiles[0]])
        }
        assertRefusedWithoutChange(data) {
            if case .invalidValue(.encodingProfiles, _, let reason) = $0 { return reason.contains("share the ID") }
            return false
        }
    }

    func test_brokenProfileIsRefused() throws {
        let data = try edited { file in
            var profiles = file.profiles
            profiles[0]["containerFormat"] = "not-a-container"
            file.setProfiles(profiles)
        }
        assertRefusedWithoutChange(data, isInvalidValue(.encodingProfiles, "profile 1"))
    }

    // MARK: - Reported, never written

    func test_unknownAndNeverItemsAreReportedAndNeverWritten() throws {
        let data = try edited { file in
            file.setSetting("zzBrandNewSetting", "surprise", in: "general")            // unknown setting
            file.setSetting("emailSMTPHost", "smtp.wrong-group.example", in: "general") // right name, wrong group
            file.setSetting("webhookURL", "https://discord.com/api/webhooks/1/x", in: "connections") // never: credential
            file.setSetting(MediaServerCredentialStore.legacyDefaultsKey, "key", in: "connections")   // never: legacy
            file.setSetting("analytics_enabled", true, in: "general")                   // never: consent
            file.setSetting("Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel", "pro", in: "general") // licence
            var categories = file.root["categories"] as? [String: Any] ?? [:]
            categories["futureGroup"] = ["settings": ["zzFuture": 1]]                   // unknown group
            file.root["categories"] = categories
            file.root["notIncluded"] = ["tmdbKey", "somethingNew"]                      // unknown left-out name
            file.root["futureField"] = "hello"                                           // unknown top-level field
        }

        let plan = try SettingsImporter.prepare(data)
        func reason(of name: String) -> SettingsIgnoredItem.Reason? {
            plan.ignored.first { $0.name == name }?.reason
        }
        XCTAssertEqual(reason(of: "zzBrandNewSetting"), .unknownSetting)
        XCTAssertEqual(reason(of: "emailSMTPHost"), .wrongGroup(belongsIn: .connections))
        XCTAssertEqual(reason(of: "webhookURL"), .neverImported(.credential))
        XCTAssertEqual(reason(of: MediaServerCredentialStore.legacyDefaultsKey), .neverImported(.legacyCredential))
        XCTAssertEqual(reason(of: "analytics_enabled"), .neverImported(.consent))
        XCTAssertEqual(reason(of: "Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel"),
                       .neverImported(.licenceCache))
        XCTAssertEqual(reason(of: "futureGroup"), .unknownGroup)
        XCTAssertEqual(reason(of: "somethingNew"), .unknownLeftOutName)
        XCTAssertEqual(reason(of: "futureField"), .unknownField)
        XCTAssertEqual(plan.leftOut, [.tmdbKey])
        XCTAssertFalse(plan.categoriesInFile.contains { $0.rawValue == "futureGroup" })

        let result = try SettingsImporter(domain: target, profileStore: targetStore,
                                          presence: SettingsTransferFakePresence())
            .apply(plan, selection: Set(SettingsCategory.allCases), mode: .merge)
        let stored = target.snapshot()

        XCTAssertNil(stored["zzBrandNewSetting"])
        XCTAssertNil(stored["zzFuture"])
        XCTAssertNil(stored[MediaServerCredentialStore.legacyDefaultsKey])
        XCTAssertNil(stored["analytics_enabled"])
        XCTAssertNil(stored["Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel"])
        // The wrong-group copy did not win: the Connections copy did.
        XCTAssertEqual(stored["emailSMTPHost"] as? String, "smtp.example.com")
        // This Mac's own webhook address is untouched (never imported,
        // never removed).
        XCTAssertEqual(stored["webhookURL"] as? String, "https://hooks.slack.com/services/LOCAL")
        XCTAssertFalse(result.settingsWritten.contains("zzBrandNewSetting"))
        XCTAssertFalse(result.settingsWritten.contains("webhookURL"))
        // Only registry-allowed settings were written, every one of them.
        for key in result.settingsWritten {
            XCTAssertEqual(SettingsKeyRegistry.entry(for: key)?.canBeExported, true, key)
        }
        // The report lists what was ignored.
        XCTAssertTrue(result.reportLines.contains { $0.contains("zzBrandNewSetting") })
    }

    /// Hooks (which can run a shell script) are never imported, from any
    /// group, and this Mac's own hooks are left exactly as they were.
    func test_hooksAreNeverImported() throws {
        let localHooks = SettingsTransferSamples.encoded(PostEncodeActionChain(actions: [
            PostEncodeAction(type: .openInFinder, name: "Local reveal"),
        ]))
        target.defaults.set(localHooks, forKey: "postEncodeActionChain")
        let planted = SettingsTransferSamples.encoded(PostEncodeActionChain(actions: [
            PostEncodeAction(type: .runShellScript, name: "Planted", config: ["script": "rm -rf ~/Movies"]),
        ]))
        let plantedJSON = try JSONSerialization.jsonObject(with: planted)

        let data = try edited { file in
            for group in ["general", "encoding", "connections", "thisMac"] {
                file.setSetting("postEncodeActionChain", plantedJSON, in: group)
            }
        }
        let plan = try SettingsImporter.prepare(data)
        let hookEntries = plan.ignored.filter { $0.name == "postEncodeActionChain" }
        XCTAssertEqual(hookEntries.count, 4)
        XCTAssertTrue(hookEntries.allSatisfy { $0.reason == .neverImported(.runsCommands) })

        for mode in SettingsImportMode.allCases {
            _ = try SettingsImporter(domain: target, profileStore: targetStore, presence: SettingsTransferFakePresence())
                .apply(plan, selection: Set(SettingsCategory.allCases), mode: mode)
            XCTAssertEqual(target.snapshot()["postEncodeActionChain"] as? Data, localHooks,
                           "Hooks changed in \(mode) mode.")
        }
    }
}
