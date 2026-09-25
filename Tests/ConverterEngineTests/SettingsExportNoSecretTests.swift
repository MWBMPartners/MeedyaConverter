// ============================================================================
// MeedyaConverter — SettingsExportNoSecretTests (Issue #506 commit 5)
// Tests/ConverterEngineTests/SettingsExportNoSecretTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The delivery proof for "a settings file never contains a secret" (#506
// plan, test 2). It plants a marker string, "SENTINEL-…", in EVERY place a
// secret could hide, exports with EVERY group ticked (including This Mac
// only), writes the file to disk, reads the BYTES back, and checks the
// marker appears nowhere:
//   - the media server key's old plain-text setting;
//   - a Discord webhook address, and webhook headers with a Bearer token;
//   - an SFTP list never moved to the Keychain, holding a plain-text
//     password;
//   - cloud destinations holding an access token, a refresh token and an S3
//     secret key, and one whose endpoint address has a password in it;
//   - a git remote and a MeedyaDB address with credentials in them, and a
//     Plex-style media server address with `?X-Plex-Token=…`;
//   - hooks holding a shell script;
//   - the analytics ID and endpoint, the cached licence level, and the
//     MakeMKV and render-farm consents;
//   - a setting the registry has never heard of;
//   - where the Keychain works: a real TMDB key, SMTP password and SFTP
//     password under this test's own Keychain services.
// It then checks the file still carries the SAFE parts of those settings
// (the SFTP servers with blank passwords, the cloud destinations with no
// tokens), so the test cannot pass by exporting nothing.
//
// A second test pins "hooks are never exported", and a third that "This
// Mac only" is not exported unless asked for.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class SettingsExportNoSecretTests: XCTestCase {

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

    private func makeExporter(domain: SettingsDomain, store: EncodingProfileStore) -> SettingsExporter {
        SettingsExporter(
            domain: domain, profileStore: store, presence: fixture.presence,
            appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate }
        )
    }

    // MARK: - The delivery proof

    func test_realExportedFileContainsNoPlantedSecret() throws {
        let marker = "SENTINEL"
        let secret = "\(marker)-\(fixture.unique)"
        let domain = fixture.makeDomain("source")
        let store = fixture.makeProfileStore("source")
        let defaults = domain.defaults

        // A realistic, full set of allowed settings and profiles first.
        SettingsTransferSamples.storeAll(in: defaults)
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)

        // Then a secret everywhere one could hide.
        defaults.set("\(secret)-mediaserver", forKey: MediaServerCredentialStore.legacyDefaultsKey)
        defaults.set("https://discord.com/api/webhooks/123/\(secret)-webhook", forKey: "webhookURL")
        defaults.set("{\"Authorization\":\"Bearer \(secret)-header\"}", forKey: "webhookCustomHeaders")

        let unmigratedSFTP = [
            SFTPServerConfig(id: SettingsTransferSamples.sftpNASID, host: "nas.local", port: 22,
                             username: "media", authMethod: .password("\(secret)-sftp-plaintext"),
                             remotePath: "/media", label: "NAS"),
            SFTPServerConfig(id: SettingsTransferSamples.sftpBackupID, host: "backup.example.com",
                             username: "backup", authMethod: .keyFile("~/.ssh/id_backup"),
                             remotePath: "/srv", label: "Backup"),
        ]
        defaults.set(SettingsTransferSamples.encoded(unmigratedSFTP), forKey: SFTPProfileStore.userDefaultsKey)

        let leakyCloudID = UUID()
        let cloud = [
            CloudStorageConfig(id: SettingsTransferSamples.cloudS3ID, provider: .s3,
                               accessToken: "\(secret)-accesskeyid", remotePath: "videos/", label: "Work S3",
                               secretAccessKey: "\(secret)-secretaccesskey", bucket: "bucket-1"),
            CloudStorageConfig(provider: .dropbox, accessToken: "\(secret)-oauth",
                               refreshToken: "\(secret)-refresh", remotePath: "/Apps", label: "Dropbox"),
            CloudStorageConfig(id: leakyCloudID, provider: .s3, accessToken: "", remotePath: "x/",
                               label: "Leaky endpoint", endpoint: "https://user:\(secret)-endpoint@s3.example.com"),
        ]
        defaults.set(SettingsTransferSamples.encoded(cloud), forKey: CloudStorageProfileStore.userDefaultsKey)

        defaults.set("https://user:\(secret)-git@github.com/example/profiles.git", forKey: "teamProfiles.gitRemote")
        defaults.set("https://\(secret)-token@meedyadb.example.com", forKey: MeedyaDBConfigStore.Keys.baseURL)
        defaults.set("http://192.168.1.20:32400/?X-Plex-Token=\(secret)-plex", forKey: "mediaServerHost")

        let hooks = PostEncodeActionChain(actions: [
            PostEncodeAction(type: .runShellScript, name: "Run", config: ["script": "echo \(secret)-hook"]),
            PostEncodeAction(type: .webhook, name: "Ping", config: ["url": "https://\(secret)-hookurl.example.com"]),
        ])
        defaults.set(SettingsTransferSamples.encoded(hooks), forKey: "postEncodeActionChain")

        defaults.set(true, forKey: "analytics_enabled")
        defaults.set("\(secret)-analytics-id", forKey: "analytics_anonymousId")
        defaults.set("https://\(secret)-analytics.example.com", forKey: "analytics_endpointURL")
        defaults.set("\(secret)-licence", forKey: "Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel")
        defaults.set(Date(), forKey: "Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry")
        defaults.set(true, forKey: MakeMKVConsentStore.Keys.enabled)
        defaults.set("\(secret)-terms", forKey: MakeMKVConsentStore.Keys.termsAcknowledgement)
        defaults.set(true, forKey: RenderFarmConfigurationLoader.Keys.allowInsecureTransports)
        defaults.set("\(secret)-insecure", forKey: RenderFarmConfigurationLoader.Keys.insecureAcknowledgement)
        defaults.set("\(secret)-unknown", forKey: "zzBrandNewApiToken")

        // Real Keychain items, under this test's own services.
        let keychainWorks = fixture.keychainIsAvailable()
        if keychainWorks {
            try fixture.makeAPIKeyManager().storeKey(
                StoredAPIKey(provider: .tmdb, apiKey: "\(secret)-tmdb", label: "TMDB")
            )
            XCTAssertTrue(fixture.saveSMTPPassword("\(secret)-smtp"))
            try SFTPCredentialStore.save(password: "\(secret)-sftp-keychain",
                                         forProfileID: SettingsTransferSamples.sftpNASID)
        }

        // Export EVERYTHING, to a real file.
        let url = fixture.root.appendingPathComponent("MeedyaConverter Settings.json")
        let export = try makeExporter(domain: domain, store: store)
            .write(to: url, categories: Set(SettingsCategory.allCases))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes, export.data, "The bytes on disk must be the bytes the exporter made.")
        let text = String(decoding: bytes, as: UTF8.self)

        // THE check: the marker is nowhere in the file.
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains(marker),
            "A planted secret reached the settings file:\n\(text)"
        )

        // No never-exported setting name appears as a key either.
        for name in ["webhookURL", "webhookCustomHeaders", "postEncodeActionChain",
                     MediaServerCredentialStore.legacyDefaultsKey, "analytics_enabled",
                     "analytics_anonymousId", "analytics_endpointURL",
                     "Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel",
                     "Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry",
                     MakeMKVConsentStore.Keys.enabled, MakeMKVConsentStore.Keys.termsAcknowledgement,
                     RenderFarmConfigurationLoader.Keys.allowInsecureTransports,
                     RenderFarmConfigurationLoader.Keys.insecureAcknowledgement,
                     "zzBrandNewApiToken", "secretAccessKey", "refreshToken"] {
            XCTAssertFalse(text.contains("\"\(name)\""), "“\(name)” must never appear in a settings file.")
        }

        // The safe parts are still there, so the test can't pass by
        // exporting nothing.
        let file = try SettingsTransferEditableFile(bytes)
        let connections = file.settings(in: SettingsCategory.connections.rawValue)
        let sftpItems = connections[SFTPProfileStore.userDefaultsKey] as? [[String: Any]] ?? []
        XCTAssertEqual(sftpItems.count, 2, "Both SFTP servers travel, with the password blanked.")
        let passwordItem = sftpItems.first { ($0["label"] as? String) == "NAS" }
        let passwordField = ((passwordItem?["authMethod"] as? [String: Any])?["password"] as? [String: Any])?["_0"]
        XCTAssertEqual(passwordField as? String, "", "The SFTP password is written as an empty string.")
        let cloudItems = connections[CloudStorageProfileStore.userDefaultsKey] as? [[String: Any]] ?? []
        XCTAssertEqual(cloudItems.count, 2, "The two safe cloud destinations travel; the leaky one does not.")
        XCTAssertFalse(cloudItems.contains { ($0["id"] as? String) == leakyCloudID.uuidString })
        XCTAssertTrue(cloudItems.allSatisfy { ($0["accessToken"] as? String) == "" })
        XCTAssertNil(connections["teamProfiles.gitRemote"], "A git remote with a password is left out.")
        XCTAssertNil(connections[MeedyaDBConfigStore.Keys.baseURL], "A MeedyaDB address with a token is left out.")
        XCTAssertNil(connections["mediaServerHost"], "A media server address with a token is left out.")
        XCTAssertNotNil(connections["emailSMTPHost"], "Ordinary connection settings still travel.")
        XCTAssertEqual(file.profiles.count, SettingsTransferSamples.userProfiles.count)

        // The report says what was taken out, naming settings, never values.
        let noteText = export.notes.map(\.message).joined(separator: "\n")
        XCTAssertTrue(noteText.contains("SFTP server “NAS”"), noteText)
        XCTAssertTrue(noteText.contains("Leaky endpoint"), noteText)
        XCTAssertTrue(noteText.contains("Team profiles: git remote address"), noteText)
        XCTAssertFalse(noteText.localizedCaseInsensitiveContains(marker), "Notes must never quote a value.")
        XCTAssertFalse(export.reportLines.joined().localizedCaseInsensitiveContains(marker))

        // `notIncluded` names what was set up here: names, never values.
        var expected: Set<SettingsLeftOutItem> = [
            .mediaServerKey, .webhookAddress, .webhookHeaders, .hooks, .makeMKVConsent,
            .renderFarmInsecureTransport,
        ]
        if keychainWorks { expected.formUnion([.tmdbKey, .smtpPassword]) }
        XCTAssertTrue(expected.isSubset(of: Set(export.leftOut)), "notIncluded: \(export.leftOut)")
        if !keychainWorks {
            // Not a failure: the file checks above still ran. Said so the
            // run log shows the Keychain part was not exercised here.
            print("SettingsExportNoSecretTests: Keychain unavailable; Keychain-held secrets not planted.")
        }
    }

    // MARK: - Hooks and This Mac only

    /// Hooks can run a shell script after every encode: never in a file,
    /// even with every group ticked (owner decision: left out of v1).
    func test_hooksAreNeverExported() throws {
        let domain = fixture.makeDomain("hooks")
        let chain = PostEncodeActionChain(actions: [
            PostEncodeAction(type: .openInFinder, name: "Reveal"),
            PostEncodeAction(type: .runShellScript, name: "Script", config: ["script": "touch /tmp/x"]),
        ])
        domain.defaults.set(SettingsTransferSamples.encoded(chain), forKey: "postEncodeActionChain")
        domain.defaults.set(true, forKey: "confirmBeforeEncoding")

        let export = try makeExporter(domain: domain, store: fixture.makeProfileStore("hooks"))
            .makeExport(categories: Set(SettingsCategory.allCases))
        let text = String(decoding: export.data, as: UTF8.self)

        XCTAssertFalse(text.contains("postEncodeActionChain"))
        XCTAssertFalse(text.contains("touch /tmp/x"))
        XCTAssertFalse(text.contains("Reveal"))
        XCTAssertTrue(text.contains("confirmBeforeEncoding"), "Other settings still export.")
        XCTAssertTrue(export.leftOut.contains(.hooks), "The file says hooks were set up, by name only.")
    }

    /// "This Mac only" is not in an export made with the default groups.
    func test_thisMacIsExcludedFromTheDefaultExport() throws {
        XCTAssertFalse(SettingsExporter.defaultCategories.contains(.thisMac))
        XCTAssertEqual(SettingsExporter.defaultCategories,
                       [.general, .encoding, .encodingProfiles, .connections])

        let domain = fixture.makeDomain("thismac")
        SettingsTransferSamples.storeAll(in: domain.defaults)
        let export = try makeExporter(domain: domain, store: fixture.makeProfileStore("thismac"))
            .makeExport(categories: SettingsExporter.defaultCategories)
        let text = String(decoding: export.data, as: UTF8.self)

        XCTAssertFalse(text.contains("\"thisMac\""))
        XCTAssertFalse(text.contains("customFFmpegPath"))
        XCTAssertFalse(text.contains("accurateRip.driveOffset"))
        XCTAssertEqual(try SettingsImporter.prepare(export.data).categoriesInFile,
                       [.general, .encoding, .encodingProfiles, .connections])
    }

    /// Nothing ticked is refused, rather than writing an empty file.
    func test_exportWithNoGroupsIsRefused() {
        let domain = fixture.makeDomain("none")
        XCTAssertThrowsError(
            try makeExporter(domain: domain, store: fixture.makeProfileStore("none")).makeExport(categories: [])
        ) { error in
            XCTAssertEqual(error as? SettingsExportError, .noGroupsChosen)
        }
    }

    /// A value stored with the wrong type is left out with a note, never
    /// converted (Foundation would read the number 1 as "on").
    func test_wrongTypeStoredValueIsLeftOutNotGuessed() throws {
        let domain = fixture.makeDomain("types")
        domain.defaults.set(1, forKey: "confirmBeforeEncoding")          // a number, not on/off
        domain.defaults.set("5", forKey: "emailSMTPPort")                 // text, not a number
        domain.defaults.set(3.0, forKey: "proresVector.frameStride")      // a decimal, not a whole number
        domain.defaults.set(70_000, forKey: "mediaServerPort")            // out of range
        domain.defaults.set("Purple", forKey: "appearanceMode")           // not an allowed value
        domain.defaults.set(true, forKey: "autoScrollLog")                // fine

        let export = try makeExporter(domain: domain, store: fixture.makeProfileStore("types"))
            .makeExport(categories: Set(SettingsCategory.allCases))
        let file = try SettingsTransferEditableFile(export.data)
        let general = file.settings(in: "general")
        let encoding = file.settings(in: "encoding")
        let connections = file.settings(in: "connections")

        XCTAssertNil(general["confirmBeforeEncoding"])
        XCTAssertNil(connections["emailSMTPPort"])
        XCTAssertNil(encoding["proresVector.frameStride"])
        XCTAssertNil(connections["mediaServerPort"])
        XCTAssertNil(general["appearanceMode"])
        XCTAssertEqual(general["autoScrollLog"] as? Bool, true)
        let leftOutKeys = Set(export.notes.map(\.key))
        XCTAssertTrue(leftOutKeys.isSuperset(of: [
            "confirmBeforeEncoding", "emailSMTPPort", "proresVector.frameStride", "mediaServerPort", "appearanceMode",
        ]), "\(export.notes)")
    }
}
