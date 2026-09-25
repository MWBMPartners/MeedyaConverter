// ============================================================================
// MeedyaConverter — Settings export/import test support (Issue #506 commit 5)
// Tests/ConverterEngineTests/SettingsTransferTestSupport.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Shared by the four settings export/import test classes:
//   - `SettingsTransferFixture`: one test's throwaway world. Every test gets
//     its own temporary folder (for its settings files, profile stores, the
//     API-key list and exported files) and its own Keychain services for API
//     keys, SMTP and SFTP. `tearDown` removes the folder and every Keychain
//     item under this test's own services. Nothing here ever touches the
//     real services or the app's real settings.
//
//     Why each settings suite is named by a PATH inside that folder, not a
//     plain name. A plainly named suite lives in `~/Library/Preferences`,
//     and macOS's settings service rewrites an emptied copy of its file one
//     to two seconds AFTER the suite is removed, sometimes even after the
//     file was deleted. No `tearDown` can reliably clean that up: the first
//     local runs of these tests left 1,532 such 42-byte files there (all
//     removed by hand afterwards). A suite named by an absolute path keeps
//     its file at that path instead (the long-standing preferences
//     behaviour `defaults read /path/to/file.plist` relies on), so deleting
//     the test's folder removes it. `persistentDomain(forName:)` reads it
//     exactly like any other domain, which is all `SettingsDomain` uses.
//     Apple does not document path names for `UserDefaults(suiteName:)`; if
//     that ever stopped working, these tests would fail loudly (every
//     snapshot would come back empty), not pass quietly.
//   - `SettingsTransferFakePresence`: a "is this secret saved?" checker
//     with fixed answers, which records every question it is asked.
//   - `SettingsTransferSamples`: a stored sample value for EVERY setting the
//     registry allows (written out by hand, one per key), plus two user
//     profiles. `SettingsRoundTripTests` fails if the registry allows a key
//     that has no sample here, which forces every new exportable setting
//     into the round trip.
//
// The SFTP Keychain check is redirected with `SFTPCredentialStore
// .serviceOverride`, a process-wide setting (as `KeyPresenceTests` does).
// That is safe because XCTest runs one test at a time in a process, and
// `swift test --parallel` uses separate processes.
// ---------------------------------------------------------------------------

import XCTest
import Security
@testable import ConverterEngine

// MARK: - SettingsTransferFixture

/// One test's throwaway settings, folders and Keychain services.
final class SettingsTransferFixture {

    let unique = UUID().uuidString
    /// This test's temporary folder.
    let root: URL
    /// Where this test's `api_keys.json` lives.
    let apiKeysDirectory: URL
    /// This test's Keychain services.
    let apiKeyService: String
    let smtpService: String
    let sftpService: String

    /// Suite names made by this test, for `tearDown`.
    private var suiteNames: [String] = []
    private let previousSFTPOverride: String?

    /// The start of every suite file name these tests create, so any file
    /// ever found elsewhere can be recognised as ours.
    static let suitePrefix = "MeedyaConverter.Tests.SettingsTransfer."

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-transfer-tests-\(unique)")
        apiKeysDirectory = root.appendingPathComponent("Keys")
        try FileManager.default.createDirectory(at: apiKeysDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Preferences"), withIntermediateDirectories: true
        )
        apiKeyService = "Ltd.MWBMpartners.MeedyaConverter.Tests.SettingsTransfer.APIKeys.\(unique)"
        smtpService = "Ltd.MWBMpartners.MeedyaConverter.Tests.SettingsTransfer.SMTP.\(unique)"
        sftpService = "Ltd.MWBMpartners.MeedyaConverter.Tests.SettingsTransfer.SFTP.\(unique)"
        previousSFTPOverride = SFTPCredentialStore.serviceOverride
        SFTPCredentialStore.serviceOverride = sftpService
    }

    /// A new, empty settings domain belonging to this test, stored as a file
    /// inside this test's folder (see the file overview for why).
    func makeDomain(_ label: String) -> SettingsDomain {
        let name = root.appendingPathComponent("Preferences")
            .appendingPathComponent("\(Self.suitePrefix)\(unique).\(label)").path
        suiteNames.append(name)
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("UserDefaults(suiteName:) refused \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        return SettingsDomain(defaults: defaults, name: name)
    }

    /// This test's profile folder with `label`.
    func profilesDirectory(_ label: String) -> URL {
        root.appendingPathComponent("Profiles-\(label)")
    }

    /// A profile store over this test's folder with `label`.
    func makeProfileStore(_ label: String) -> EncodingProfileStore {
        EncodingProfileStore(storageDirectory: profilesDirectory(label))
    }

    /// The REAL presence checks, pointed at this test's services and folder.
    var presence: SystemSettingsCredentialPresence {
        SystemSettingsCredentialPresence(
            apiKeyStorageDirectory: apiKeysDirectory,
            apiKeyKeychainService: apiKeyService,
            smtpService: smtpService,
            smtpAccount: SMTPPasswordKeychain.account
        )
    }

    /// An `APIKeyManager` over this test's folder and service. Used only to
    /// SET UP saved keys; the code under test never makes one.
    func makeAPIKeyManager() -> APIKeyManager {
        APIKeyManager(storageDirectory: apiKeysDirectory, keychainService: apiKeyService)
    }

    /// Saves an SMTP password under this test's service. True on success.
    func saveSMTPPassword(_ password: String) -> Bool {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: smtpService,
            kSecAttrAccount as String: SMTPPasswordKeychain.account,
            kSecValueData as String: Data(password.utf8),
        ]
        SecItemDelete(item as CFDictionary)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Whether any Keychain item exists under `service`, asked without
    /// reading any secret.
    static func anyKeychainItem(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Whether the Keychain round-trips on this host (write, read, delete
    /// under this test's own API-key service), as `KeyPresenceTests` checks.
    func keychainIsAvailable() -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: "probe-\(UUID().uuidString)",
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data("probe".utf8)
        let added = SecItemAdd(add as CFDictionary, nil)
        var read = base
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let found = SecItemCopyMatching(read as CFDictionary, &result)
        SecItemDelete(base as CFDictionary)
        return added == errSecSuccess && found == errSecSuccess && (result as? Data) == Data("probe".utf8)
    }

    /// Removes everything this test made. See the file overview.
    func tearDown() {
        // The suites' files are inside `root`, which is deleted below.
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        APIKeyManagerTestSupport.clearKeychain(service: apiKeyService)
        try? SFTPCredentialStore.deleteAll(service: sftpService)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: smtpService,
        ] as CFDictionary)
        SFTPCredentialStore.serviceOverride = previousSFTPOverride
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - SettingsTransferFakePresence

/// Fixed answers to "is this secret saved?", recording every question.
/// Mutable state is only touched under `lock` (never a captured `var`).
final class SettingsTransferFakePresence: SettingsCredentialPresence, @unchecked Sendable {

    private let lock = NSLock()
    private var questions: [String] = []

    /// Keyed "provider" (any label) or "provider|label".
    private let apiKeys: [String: KeyPresence]
    private let smtp: KeyPresence
    private let sftp: [UUID: KeyPresence]
    private let files: Set<String>

    init(
        apiKeys: [String: KeyPresence] = [:],
        smtp: KeyPresence = .missing,
        sftp: [UUID: KeyPresence] = [:],
        files: Set<String> = []
    ) {
        self.apiKeys = apiKeys
        self.smtp = smtp
        self.sftp = sftp
        self.files = files
    }

    /// Every question asked, in order.
    var asked: [String] { lock.withLock { questions } }

    private func record(_ question: String) {
        lock.withLock { questions.append(question) }
    }

    func apiKey(for provider: APIKeyProvider, label: String?) -> KeyPresence {
        record("apiKey \(provider.rawValue) \(label ?? "-")")
        if let label { return apiKeys["\(provider.rawValue)|\(label)"] ?? .missing }
        return apiKeys[provider.rawValue] ?? .missing
    }

    func smtpPassword() -> KeyPresence {
        record("smtp")
        return smtp
    }

    func sftpPassword(forProfileID id: UUID) -> KeyPresence {
        record("sftp \(id.uuidString)")
        return sftp[id] ?? .missing
    }

    func fileExists(atPath path: String) -> Bool {
        record("file \(path)")
        return files.contains(path)
    }
}

// MARK: - SettingsTransferSamples

/// A sample stored value for every allowed setting, and two profiles.
enum SettingsTransferSamples {

    // Fixed IDs, so tests can refer to items.
    static let profileAID = UUID(uuidString: "0A000000-0000-4000-8000-000000000001")!
    static let profileBID = UUID(uuidString: "0B000000-0000-4000-8000-000000000002")!
    static let ruleID = UUID(uuidString: "0C000000-0000-4000-8000-000000000003")!
    static let pipelineID = UUID(uuidString: "0D000000-0000-4000-8000-000000000004")!
    static let pipelineStepID = UUID(uuidString: "0D000000-0000-4000-8000-000000000005")!
    static let agentID = UUID(uuidString: "0E000000-0000-4000-8000-000000000006")!
    static let sftpNASID = UUID(uuidString: "0F000000-0000-4000-8000-000000000007")!
    static let sftpBackupID = UUID(uuidString: "0F000000-0000-4000-8000-000000000008")!
    static let sftpAgentID = UUID(uuidString: "0F000000-0000-4000-8000-000000000009")!
    static let cloudS3ID = UUID(uuidString: "10000000-0000-4000-8000-00000000000A")!
    static let themeID = UUID(uuidString: "11000000-0000-4000-8000-00000000000B")!
    static let shortcutID = UUID(uuidString: "12000000-0000-4000-8000-00000000000C")!

    /// Two user profiles with fixed IDs (not built in).
    static let userProfiles: [EncodingProfile] = [
        EncodingProfile(
            id: profileAID, name: "My HEVC", description: "Sample profile A",
            videoCodec: .h265, videoCRF: 19, audioBitrate: 192_000, containerFormat: .mkv
        ),
        EncodingProfile(
            id: profileBID, name: "Archive", description: "Sample profile B",
            videoCRF: 16, encodingPasses: 2, containerFormat: .mp4
        ),
    ]

    static let sftpServers: [SFTPServerConfig] = [
        SFTPServerConfig(id: sftpNASID, host: "nas.local", port: 2222, username: "media",
                         authMethod: .password(""), remotePath: "/media", label: "NAS"),
        SFTPServerConfig(id: sftpBackupID, host: "backup.example.com", port: 22, username: "backup",
                         authMethod: .keyFile("~/.ssh/id_backup_test_\(sftpBackupID.uuidString)"),
                         remotePath: "/srv/backup", label: "Backup"),
        SFTPServerConfig(id: sftpAgentID, host: "git@agent.example.com", port: 22, username: "deploy",
                         authMethod: .agent, remotePath: "/deploy", label: "Agent"),
    ]

    static let cloudDestinations: [CloudStorageConfig] = [
        CloudStorageConfig(id: cloudS3ID, provider: .s3, accessToken: "", remotePath: "videos/",
                           label: "Work S3", bucket: "bucket-1", region: "eu-west-2",
                           endpoint: "https://s3.example.com"),
    ]

    /// The stored form of `value` (plain `JSONEncoder`, as the app writes).
    static func encoded<T: Encodable>(_ value: T) -> Data {
        // Force-try: these are fixed, valid samples; a failure is a bug in
        // this file.
        try! JSONEncoder().encode(value)
    }

    /// One sample stored value per allowed setting, by key, in the TYPE the
    /// app stores (Bool, Int, Double, String, or Data). Written out one by
    /// one on purpose (see the file overview).
    static var storedValues: [String: Any] {
        [
            // General and appearance (13)
            "appearanceMode": "Dark",
            "confirmBeforeEncoding": false,
            "showMenuBarStatus": true,
            "autoScrollLog": false,
            "notifyOnCompletion": false,
            "notifyOnFailure": false,
            "notifyOnQueueFinished": true,
            "playSoundOnCompletion": true,
            "customAccentColor": "#12AB34",
            "customSidebarTint": "#FE0010",
            "customThemeData": encoded(SettingsThemeShape(
                id: themeID, name: "Ocean", accentHex: "#0A84FF", sidebarTintHex: "#102030"
            )),
            "keyboard_shortcuts": encoded([SettingsShortcutShape(
                id: shortcutID, action: "encode.start", label: "Start encoding", key: "e",
                modifiers: ["command", "shift"]
            )]),
            "updateChannel": "beta",

            // Encoding and output (29)
            "defaultProfileName": "My HEVC",
            "useHardwareAcceleration": false,
            "overwriteExisting": true,
            "deleteSourceAfterEncode": true,
            "filenameTemplate": "{name}-{profile}",
            ParallelEncoder.maxConcurrentJobsDefaultsKey: 3,
            "conditionalRules": encoded([ConditionalRule(
                id: ruleID, name: "HDR to HEVC", conditions: [.hasHDR(true), .extension("mkv")],
                profileId: profileAID, isEnabled: true, priority: 2
            )]),
            "savedPipelines": encoded([EncodingPipeline(
                id: pipelineID, name: "Encode and thumbnail",
                steps: [PipelineStep(id: pipelineStepID, name: "Thumbnail", type: .extractThumbnail,
                                     config: ["timestamp": "00:00:30"])],
                cleanIntermediateFiles: false
            )]),
            "metadataBackend": SuiteCoreMetadataBackend.allCases.last!.rawValue,
            "vectorConversion.preset": EditabilityPreset.allCases.last!.rawValue,
            "vectorConversion.tracingMode": TracingMode.allCases.last!.rawValue,
            "vectorConversion.colorCount": 17,
            "vectorConversion.alpha": AlphaStrategy.allCases.last!.rawValue,
            "vectorConversion.animation": AnimationMethod.allCases.last!.rawValue,
            "vectorConversion.curveSimplification": 2.5,
            "proresVector.sourceVariant": ProResVariant.allCases.last!.rawValue,
            "proresVector.frameRate": ProResFrameRate.allCases.last!.rawValue,
            "proresVector.frameStride": 3,
            "proresVector.alphaHandling": ProResAlphaHandling.allCases.last!.rawValue,
            "proresVector.animation": AnimationMethod.allCases.first!.rawValue,
            "proresVector.tracing.preset": EditabilityPreset.allCases.first!.rawValue,
            "proresVector.tracing.tracingMode": TracingMode.allCases.first!.rawValue,
            "proresVector.tracing.colorCount": 9,
            "proresVector.tracing.alpha": AlphaStrategy.allCases.first!.rawValue,
            "proresVector.tracing.curveSimplification": 1.25,
            "accurateRip.enabled": true,
            "accurateRip.softwareId": "MeedyaConverter-test",
            AutoTagSettingsStore.Keys.enabled: true,
            AutoTagSettingsStore.Keys.writeNFO: true,

            // Connections (29)
            "emailSMTPHost": "smtp.example.com",
            "emailSMTPPort": 465,
            "emailSMTPUsername": "sender@example.com",
            "emailSMTPUseTLS": true,
            "emailFromAddress": "sender@example.com",
            // TEXT holding a JSON list, exactly as EmailSettingsView stores it.
            "emailToAddresses": String(decoding: encoded(["a@example.com", "b@example.com"]), as: UTF8.self),
            "emailOnComplete": true,
            "emailOnFailure": true,
            "emailOnQueueFinished": false,
            "mediaServerType": MediaServerType.allCases.last!.rawValue,
            "mediaServerHost": "192.168.1.20",
            "mediaServerPort": 8096,
            "mediaServerUseTLS": true,
            "mediaServerLibraryId": "library-7",
            "mediaServerAutoScan": true,
            "webhookPreset": "Discord",
            "webhookOnComplete": true,
            "webhookOnFailure": false,
            "webhookOnQueueFinished": true,
            MeedyaDBConfigStore.Keys.enabled: true,
            MeedyaDBConfigStore.Keys.baseURL: "https://meedyadb.example.com/api",
            MeedyaDBConfigStore.Keys.submissionMode: MeedyaDBSubmissionMode.full.rawValue,
            RenderFarmConfigurationLoader.Keys.discoveryIntervalSeconds: 45.5,
            RenderFarmConfigurationLoader.Keys.chunkSizeMiB: 16,
            RenderFarmConfigurationLoader.Keys.agentsJSON: encoded([RenderFarmAgentInfo(
                id: agentID, displayName: "Studio", host: "render.local", port: 2230, sshUsername: "render"
            )]),
            SFTPProfileStore.userDefaultsKey: encoded(sftpServers),
            CloudStorageProfileStore.userDefaultsKey: encoded(cloudDestinations),
            "teamProfiles.gitRemote": "git@github.com:example/profiles.git",
            "teamProfiles.gitBranch": "team-main",

            // This Mac only (7)
            "customFFmpegPath": "/opt/homebrew/bin/ffmpeg",
            "customFFprobePath": "/opt/homebrew/bin/ffprobe",
            "customPotracePath": "/usr/local/bin/potrace",
            "customVTracerPath": "~/bin/vtracer",
            MakeMKVConsentStore.Keys.binaryPath: "/Applications/MakeMKV.app/Contents/MacOS/makemkvcon",
            "accurateRip.driveModel": "PIONEER BD-RW BDR-XD07",
            "accurateRip.driveOffset": -472,
        ]
    }

    /// Stores every sample in `defaults`, with the app's own types.
    static func storeAll(in defaults: UserDefaults) {
        for (key, value) in storedValues {
            defaults.set(value, forKey: key)
        }
    }

    /// Every setting the registry lets travel (allowed or This Mac only).
    static var exportableKeys: Set<String> {
        Set(SettingsKeyRegistry.entries.filter(\.canBeExported).map(\.key))
    }

    /// Compares two stored values by the setting's rules: the same type AND
    /// the same content. JSON documents are compared decoded (key order in
    /// stored JSON is not meaningful).
    static func sameStoredValue(_ lhs: Any?, _ rhs: Any?, key: String) -> Bool {
        guard let lhs, let rhs, let kind = SettingsKeyRegistry.entry(for: key)?.rules?.kind else {
            return lhs == nil && rhs == nil
        }
        switch kind {
        case .bool:
            return SettingsStoredValue.bool(lhs) != nil && SettingsStoredValue.bool(lhs) == SettingsStoredValue.bool(rhs)
        case .int:
            return SettingsStoredValue.int(lhs) != nil && SettingsStoredValue.int(lhs) == SettingsStoredValue.int(rhs)
        case .double:
            return SettingsStoredValue.double(lhs) != nil
                && SettingsStoredValue.double(lhs) == SettingsStoredValue.double(rhs)
        case .string, .address, .filePath, .hexColour:
            return (lhs as? String) != nil && (lhs as? String) == (rhs as? String)
        case .json(let blob):
            switch blob.storage {
            case .jsonString:
                // Must stay TEXT, and the very same text.
                return (lhs as? String) != nil && (lhs as? String) == (rhs as? String)
            case .data:
                guard let left = lhs as? Data, let right = rhs as? Data else { return false }
                return canonical(left) != nil && canonical(left) == canonical(right)
            }
        }
    }

    private static func canonical(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// A fixed clock for exports.
    static let exportDate = Date(timeIntervalSince1970: 1_790_000_000)
}

// MARK: - Small helpers

extension SettingsDomain {
    /// The stored snapshot as an `NSDictionary`, for "exactly equal" checks.
    var snapshotDictionary: NSDictionary { NSDictionary(dictionary: snapshot()) }
}

/// A settings file (as a JSON object) that tests can edit, made by a real
/// export and read back with `JSONSerialization`.
struct SettingsTransferEditableFile {
    var root: [String: Any]

    init(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "SettingsTransferTests", code: 1)
        }
        root = object
    }

    var data: Data {
        // Force-try: the dictionary came from JSON and only gains JSON values.
        try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    /// Sets `value` under `categories.<group>.settings.<key>`.
    mutating func setSetting(_ key: String, _ value: Any, in group: String) {
        var categories = root["categories"] as? [String: Any] ?? [:]
        var section = categories[group] as? [String: Any] ?? [:]
        var settings = section["settings"] as? [String: Any] ?? [:]
        settings[key] = value
        section["settings"] = settings
        categories[group] = section
        root["categories"] = categories
    }

    /// Removes `categories.<group>.settings.<key>`.
    mutating func removeSetting(_ key: String, in group: String) {
        var categories = root["categories"] as? [String: Any] ?? [:]
        var section = categories[group] as? [String: Any] ?? [:]
        var settings = section["settings"] as? [String: Any] ?? [:]
        settings.removeValue(forKey: key)
        section["settings"] = settings
        categories[group] = section
        root["categories"] = categories
    }

    /// The group's `settings` object.
    func settings(in group: String) -> [String: Any] {
        ((root["categories"] as? [String: Any])?[group] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
    }

    /// Replaces `categories.encodingProfiles.profiles`.
    mutating func setProfiles(_ profiles: [Any]) {
        var categories = root["categories"] as? [String: Any] ?? [:]
        categories["encodingProfiles"] = ["profiles": profiles]
        root["categories"] = categories
    }

    /// `categories.encodingProfiles.profiles`.
    var profiles: [[String: Any]] {
        ((root["categories"] as? [String: Any])?["encodingProfiles"] as? [String: Any])?["profiles"]
            as? [[String: Any]] ?? []
    }
}
