// ============================================================================
// MeedyaConverter — SettingsCredentialNeedsTests (Issue #506 commit 5)
// Tests/ConverterEngineTests/SettingsCredentialNeedsTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan test 5: after an import, "still needed on this Mac" names the
// right services with the right places to set them up, and is worked out
// WITHOUT READING ANY SECRET.
//
// How "without reading a secret" is shown, in three independent ways:
//   1. With a recording fake: the engine only ever asks the presence
//      protocol, whose answers (`KeyPresence`) cannot carry a secret.
//   2. With the REAL checks over a saved-keys list in the OLD, pre-Keychain
//      format holding a marker "secret": creating an `APIKeyManager` over
//      that list would convert it (rewriting the file and writing Keychain
//      items). After an export and an import, the file's bytes are unchanged
//      and no Keychain item exists under the test's service, so no
//      `APIKeyManager` was created (the #506 commit-2 correction: creating
//      one reads every secret). The marker appears in no output.
//   3. A source check: no file in `Sources/ConverterEngine/Settings/` creates
//      an `APIKeyManager`, reads an SFTP password or a Keychain item's data,
//      or asks the Keychain for secret data.
// Plus the real checks against real items under throwaway Keychain services
// (skipped, with a message, where the Keychain doesn't work).
//
// Honest limit (from the plan): this checks the QUERIES, not the absence of
// a macOS prompt. That needs one manual run of the command-line tool against
// keys the app saved. And for the App Store build the command-line tool
// cannot see the app's keys at all (see `SettingsCredentialNeeds.swift`).
// ---------------------------------------------------------------------------

import XCTest
import Security
@testable import ConverterEngine

final class SettingsCredentialNeedsTests: XCTestCase {

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

    /// A real export of the samples, with `notIncluded` set to `leftOut`.
    private func file(leftOut: [SettingsLeftOutItem]) throws -> SettingsImportPlan {
        let source = fixture.makeDomain("needs-source")
        SettingsTransferSamples.storeAll(in: source.defaults)
        let data = try SettingsExporter(
            domain: source, profileStore: fixture.makeProfileStore("needs-source"),
            presence: SettingsTransferFakePresence(), appVersion: "9.9.9",
            now: { SettingsTransferSamples.exportDate }
        ).makeData(categories: Set(SettingsCategory.allCases))
        var editable = try SettingsTransferEditableFile(data)
        editable.root["notIncluded"] = leftOut.map(\.rawValue)
        return try SettingsImporter.prepare(editable.data)
    }

    private func apply(
        _ plan: SettingsImportPlan,
        to target: SettingsDomain,
        presence: any SettingsCredentialPresence,
        selection: Set<SettingsCategory> = Set(SettingsCategory.allCases)
    ) throws -> SettingsImportResult {
        try SettingsImporter(domain: target, profileStore: fixture.makeProfileStore(target.name), presence: presence)
            .apply(plan, selection: selection, mode: .merge)
    }

    // MARK: - Names and places

    func test_stillNeededNamesEachServiceAndWhereToSetItUp() throws {
        let plan = try file(leftOut: SettingsLeftOutItem.allCases)
        let presence = SettingsTransferFakePresence(
            apiKeys: [
                "tmdb": .present,
                "meedya_db": .missing,
                "media_server": .couldNotCheck(.indexNotRecognised),
            ],
            smtp: .missing,
            sftp: [SettingsTransferSamples.sftpNASID: .missing]
        )
        let result = try apply(plan, to: fixture.makeDomain("needs-target"), presence: presence)
        let lines = result.stillNeeded.map(\.line)

        XCTAssertEqual(result.stillNeeded.map(\.kind), [
            .leftOut(.meedyaDBKey), .leftOut(.mediaServerKey), .leftOut(.smtpPassword),
            .leftOut(.webhookAddress), .leftOut(.webhookHeaders), .leftOut(.hooks),
            .leftOut(.makeMKVConsent), .leftOut(.renderFarmInsecureTransport),
            .sftpPassword(profileID: SettingsTransferSamples.sftpNASID),
            .sftpKeyFile(profileID: SettingsTransferSamples.sftpBackupID),
            .cloudCredential(profileID: SettingsTransferSamples.cloudS3ID),
        ], lines.joined(separator: "\n"))

        // TMDB is saved here, so it is not listed.
        XCTAssertFalse(result.stillNeeded.contains { $0.kind == .leftOut(.tmdbKey) })

        XCTAssertTrue(lines.contains("MeedyaDB key: Settings › MeedyaDB"))
        XCTAssertTrue(lines.contains("SMTP password: Settings › Email"))
        XCTAssertTrue(lines.contains(
            "Webhook address: Settings › Webhooks. For Slack and Discord the address works like a password, "
                + "so it's never copied."
        ))
        XCTAssertTrue(lines.contains(
            "Hooks (actions after each encode): Settings › Hooks. Hooks aren't copied, because they can run "
                + "commands: set them up again."
        ))
        XCTAssertTrue(lines.contains("MakeMKV: Settings › MakeMKV. The terms have to be accepted on each Mac."))
        XCTAssertTrue(lines.contains("SFTP server ‘NAS’ password: SFTP, in the main window's sidebar"))
        XCTAssertTrue(lines.contains("Cloud destination ‘Work S3’ key or token: Cloud Storage, in the main window's sidebar"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("SFTP server ‘Backup’ key file: SFTP, in the main window's sidebar.") })

        // "Couldn't check" is listed as such, never as missing.
        let mediaServer = result.stillNeeded.first { $0.kind == .leftOut(.mediaServerKey) }
        XCTAssertEqual(mediaServer?.status,
                       .couldNotCheck(reason: KeyPresenceCheckFailure.indexNotRecognised.description))

        // The SSH-agent server needs nothing stored here, so it isn't asked
        // about; the cloud key is looked for by label, then for any label.
        let asked = presence.asked
        XCTAssertFalse(asked.contains("sftp \(SettingsTransferSamples.sftpAgentID.uuidString)"))
        XCTAssertTrue(asked.contains("apiKey aws_s3 Work S3"))
        XCTAssertTrue(asked.contains("apiKey aws_s3 -"))

        // The report lists them.
        XCTAssertTrue(result.reportLines.contains("Still needed on this Mac:"))
        XCTAssertTrue(result.reportLines.contains("  - SMTP password: Settings › Email"))
    }

    func test_thingsAlreadySetUpHereAreNotListed() throws {
        let plan = try file(leftOut: SettingsLeftOutItem.allCases)
        let target = fixture.makeDomain("setup-here")
        let defaults = target.defaults
        defaults.set("https://hooks.slack.com/services/HERE", forKey: "webhookURL")
        defaults.set(#"{"X-Token":"here"}"#, forKey: "webhookCustomHeaders")
        defaults.set(SettingsTransferSamples.encoded(PostEncodeActionChain(actions: [
            PostEncodeAction(type: .openInFinder, name: "Reveal"),
        ])), forKey: "postEncodeActionChain")
        defaults.set(true, forKey: MakeMKVConsentStore.Keys.enabled)
        defaults.set("I accept", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set("I understand", forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement)
        // The media server key's old place still counts while its move to
        // the Keychain keeps failing.
        defaults.set("legacy-key", forKey: MediaServerCredentialStore.legacyDefaultsKey)

        let presence = SettingsTransferFakePresence(
            apiKeys: ["tmdb": .present, "meedya_db": .present, "aws_s3|Work S3": .present],
            smtp: .present,
            sftp: [SettingsTransferSamples.sftpNASID: .present],
            files: [SettingsTransferSamples.sftpServers[1].authMethod.keyFilePath ?? ""]
        )
        let result = try apply(plan, to: target, presence: presence)
        XCTAssertEqual(result.stillNeeded, [], result.stillNeeded.map(\.line).joined(separator: "\n"))
        XCTAssertTrue(result.reportLines.contains("Nothing else needs setting up on this Mac for the imported groups."))
    }

    func test_onlyImportedGroupsAreConsidered() throws {
        let plan = try file(leftOut: SettingsLeftOutItem.allCases)
        let presence = SettingsTransferFakePresence()

        let generalOnly = try apply(plan, to: fixture.makeDomain("general-only"), presence: presence,
                                    selection: [.general])
        XCTAssertEqual(generalOnly.stillNeeded, [], "Nothing relates to General.")

        let encodingOnly = try apply(plan, to: fixture.makeDomain("encoding-only"), presence: presence,
                                     selection: [.encoding])
        XCTAssertEqual(encodingOnly.stillNeeded.map(\.kind),
                       [.leftOut(.tmdbKey), .leftOut(.hooks), .leftOut(.makeMKVConsent)])
    }

    // MARK: - The real checks, against real Keychain items

    func test_realChecksWithTestKeychainServices() throws {
        try XCTSkipUnless(fixture.keychainIsAvailable(),
                          "No working Keychain on this host (for example a CI runner); this test needs one.")
        let manager = fixture.makeAPIKeyManager()   // set-up only
        manager.storeKey(StoredAPIKey(provider: .tmdb, apiKey: "real-test-tmdb-key", label: "TMDB"))
        try SFTPCredentialStore.save(password: "real-test-sftp", forProfileID: SettingsTransferSamples.sftpNASID)

        let plan = try file(leftOut: [.tmdbKey, .smtpPassword])
        var result = try apply(plan, to: fixture.makeDomain("real-1"), presence: fixture.presence,
                               selection: [.encoding, .connections])
        var kinds = result.stillNeeded.map(\.kind)
        XCTAssertFalse(kinds.contains(.leftOut(.tmdbKey)), "The TMDB key is saved under the test service.")
        XCTAssertTrue(kinds.contains(.leftOut(.smtpPassword)), "No SMTP password is saved.")
        XCTAssertFalse(kinds.contains(.sftpPassword(profileID: SettingsTransferSamples.sftpNASID)))
        XCTAssertTrue(kinds.contains(.cloudCredential(profileID: SettingsTransferSamples.cloudS3ID)))

        XCTAssertTrue(fixture.saveSMTPPassword("real-test-smtp"))
        manager.removeKey(provider: .tmdb, label: "TMDB")
        result = try apply(plan, to: fixture.makeDomain("real-2"), presence: fixture.presence,
                           selection: [.encoding, .connections])
        kinds = result.stillNeeded.map(\.kind)
        XCTAssertTrue(kinds.contains(.leftOut(.tmdbKey)), "The TMDB key was removed.")
        XCTAssertFalse(kinds.contains(.leftOut(.smtpPassword)), "The SMTP password is now saved.")

        let everything = result.reportLines.joined(separator: "\n")
        for secret in ["real-test-tmdb-key", "real-test-sftp", "real-test-smtp"] {
            XCTAssertFalse(everything.contains(secret))
        }
    }

    // MARK: - Never reads a secret

    /// Proof 2 in the file overview: no `APIKeyManager` is ever created by
    /// export or import, shown with an old-format key list that creating one
    /// would convert.
    func test_neverCreatesAnAPIKeyManagerOrReadsASecret() throws {
        let marker = "SENTINEL-NEEDS-\(fixture.unique)"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyList = try encoder.encode([
            StoredAPIKey(provider: .tmdb, apiKey: marker, addedDate: Date(timeIntervalSince1970: 1_700_000_000)),
        ])
        let indexURL = fixture.apiKeysDirectory.appendingPathComponent("api_keys.json")
        try legacyList.write(to: indexURL)

        // Export from a Mac with that list (fills `notIncluded`)…
        let source = fixture.makeDomain("legacy-source")
        source.defaults.set(true, forKey: "autoScrollLog")
        let export = try SettingsExporter(
            domain: source, profileStore: fixture.makeProfileStore("legacy-source"), presence: fixture.presence,
            appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate }
        ).makeExport(categories: [.general, .encoding])
        XCTAssertTrue(export.leftOut.contains(.tmdbKey), "“Couldn't check” counts as set up on export.")

        // …and import on a Mac with the same list (works out "still needed").
        let plan = try SettingsImporter.prepare(export.data)
        let result = try apply(plan, to: fixture.makeDomain("legacy-target"), presence: fixture.presence,
                               selection: [.general, .encoding])
        let tmdb = result.stillNeeded.first { $0.kind == .leftOut(.tmdbKey) }
        XCTAssertEqual(tmdb?.status, .couldNotCheck(reason: KeyPresenceCheckFailure.indexNotRecognised.description))

        // Creating an APIKeyManager would have converted the list and moved
        // the marker into the Keychain. Neither happened.
        XCTAssertEqual(try Data(contentsOf: indexURL), legacyList, "The key list was rewritten.")
        XCTAssertFalse(SettingsTransferFixture.anyKeychainItem(service: fixture.apiKeyService),
                       "A Keychain item appeared under the test service.")
        let output = String(decoding: export.data, as: UTF8.self)
            + export.reportLines.joined() + result.reportLines.joined()
            + result.stillNeeded.map(\.line).joined()
        XCTAssertFalse(output.contains(marker))
    }

    /// Proof 3 in the file overview: a source check over the settings engine.
    func test_settingsEngineSourceNeverReadsSecrets() throws {
        let settingsFolder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ConverterEngine/Settings")
        let files = try FileManager.default.contentsOfDirectory(at: settingsFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThanOrEqual(files.count, 10, "The settings engine's source folder wasn't found.")
        for file in files {
            // Code lines only: comments may name what is avoided.
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for forbidden in ["APIKeyManager(", "SFTPCredentialStore.read(", "KeychainStore.read(",
                              "kSecReturnData", "CloudStorageProfileStore.loadProfiles(",
                              "SFTPProfileStore.loadProfiles(", "MediaServerCredentialStore.currentKey("] {
                XCTAssertFalse(code.contains(forbidden), "\(file.lastPathComponent) uses \(forbidden)")
            }
        }
    }

    func test_existenceQueryNeverAsksForTheSecret() {
        let query = KeychainItemExistence.query(service: "s", account: "a")
        for key in [kSecReturnData, kSecReturnAttributes, kSecReturnRef, kSecReturnPersistentRef] {
            XCTAssertNil(query[key as String])
        }
    }

    /// The settings the local check reads must exist, and must be "never"
    /// (they are all secrets or consents); a renamed key would otherwise make
    /// the check quietly answer "not set up" for ever.
    func test_settingsReadByTheLocalCheckAreRegisteredAsNever() {
        for key in SettingsLocalSetup.settingsRead {
            let entry = SettingsKeyRegistry.entry(for: key)
            XCTAssertNotNil(entry, "\(key) is not in the registry.")
            XCTAssertEqual(entry?.canBeExported, false, "\(key) should be never-exported.")
        }
    }

    func test_everyLeftOutItemHasAPlaceAndAGroup() {
        for item in SettingsLeftOutItem.allCases {
            XCTAssertTrue(item.location.hasPrefix("Settings › "), "\(item)")
            XCTAssertFalse(item.displayName.isEmpty)
            XCTAssertNotEqual(item.relatedCategory, .thisMac)
            XCTAssertNotEqual(item.relatedCategory, .encodingProfiles)
        }
    }
}

private extension AuthMethod {
    /// The key file path, for `.keyFile`.
    var keyFilePath: String? {
        if case .keyFile(let path) = self { return path }
        return nil
    }
}
