// ============================================================================
// MeedyaConverter — SettingsKeyRegistrySentinelTests (Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A second, independent line of defence for the settings allow-list.
//
// `SettingsKeyCoverageTests` makes sure every stored setting HAS a decision.
// It cannot tell whether the decision is RIGHT. These tests pin the
// decisions that matter for safety, from a list written out by hand here,
// without using the source scan at all:
//   - the known secrets are `.never` as credentials: the webhook address,
//     the webhook headers, and the media server key's old location;
//   - hooks, consents, the licence cache and the analytics ID are `.never`
//     for their own reasons (owner decisions: hooks left out of v1;
//     consents never travel);
//   - no exportable setting has a name that looks like a key, token,
//     password or secret;
//   - the two lists that can still hold secrets (SFTP servers, cloud
//     destinations) are marked for secret removal, and the two addresses
//     that could embed a token are marked as addresses;
//   - "This Mac only" is off by default, and encoding profiles are their
//     own group (owner decisions);
//   - the table is well formed (no duplicates, every entry explained).
//
// So if someone marks `webhookURL` as `.allowed`, this file fails even
// though the tripwire is perfectly happy. (That exact fault was planted by
// hand when this was written, and these tests caught it.)
//
// This is plan test 12 as briefed for #506 commit 4. The plan's own "test
// 12" (`SettingsRegistryAppConstantsTests`, checking the app-module enums
// and constants) is in `Tests/MeedyaConverterCoreTests/`.
//
// Only public API is used (`import ConverterEngine`, no `@testable`).
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class SettingsKeyRegistrySentinelTests: XCTestCase {

    // MARK: - Helpers

    /// Fails (and returns nil) when `key` has no entry, so deleting an
    /// entry can never be a way of passing these tests.
    private func entry(_ key: String, file: StaticString = #filePath, line: UInt = #line) -> SettingsKeyEntry? {
        let found = SettingsKeyRegistry.entry(for: key)
        XCTAssertNotNil(found, "\(key) must be in SettingsKeyRegistry.", file: file, line: line)
        return found
    }

    private func assertNever(
        _ key: String,
        as kind: SettingsNeverKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let found = entry(key, file: file, line: line) else { return }
        XCTAssertFalse(found.canBeExported, "\(key) must NEVER be exported.", file: file, line: line)
        XCTAssertEqual(found.neverKind, kind, "\(key) must be .never(.\(kind.rawValue), …).", file: file, line: line)
    }

    // MARK: - Secrets

    /// The known secrets. Written out by hand, on purpose.
    func test_knownSecretsAreNeverExported() {
        // For Slack and Discord the address works like a password.
        assertNever("webhookURL", as: .credential)
        // People put Authorization headers here.
        assertNever("webhookCustomHeaders", as: .credential)
        // Where the media server key used to be kept in plain text (#506
        // commit 1 moved it to the Keychain). Checked through the engine's
        // own constant AND the literal, so neither can drift.
        assertNever(MediaServerCredentialStore.legacyDefaultsKey, as: .legacyCredential)
        assertNever("mediaServerAPIKey", as: .legacyCredential)
    }

    /// No setting that can be exported may have a name that looks like it
    /// holds a secret. Catches a hurried `.allowed` on a new key-like setting
    /// even if nobody adds it to the hand-written list above.
    func test_noExportableSettingHasASecretLookingName() {
        let secretLooking = try? NSRegularExpression(
            pattern: "api[_.-]?key|token|passw(or)?d|secret|credential|bearer|authori[sz]|"
                + "webhookurl|customheaders|private[_.-]?key|licen[cs]e|entitlement",
            options: [.caseInsensitive]
        )
        guard let secretLooking else {
            XCTFail("The name pattern did not compile.")
            return
        }
        let offenders = SettingsKeyRegistry.entries.filter { entry in
            let range = NSRange(entry.key.startIndex..., in: entry.key)
            return entry.canBeExported && secretLooking.firstMatch(in: entry.key, range: range) != nil
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "These exportable settings have names that look like secrets; make them .never, or "
                + "rename them if they really are harmless: \(offenders.map(\.key))"
        )
    }

    // MARK: - Other things that must never travel

    func test_hooksAreLeftOut() {
        // Owner decision: hooks left out of v1 entirely. They can run a
        // shell script after every encode.
        assertNever("postEncodeActionChain", as: .runsCommands)
    }

    func test_consentsNeverTravel() {
        // Owner decision: consents are given on each Mac.
        assertNever(MakeMKVConsentStore.Keys.enabled, as: .consent)
        assertNever(MakeMKVConsentStore.Keys.termsAcknowledgement, as: .consent)
        assertNever(RenderFarmConfigurationLoader.Keys.allowInsecureTransports, as: .consent)
        assertNever(RenderFarmConfigurationLoader.Keys.insecureAcknowledgement, as: .consent)
        assertNever("analytics_enabled", as: .consent)
        assertNever("analytics_endpointURL", as: .consent)
    }

    func test_licenceCacheAndInstallationIdentityNeverTravel() {
        assertNever("Ltd.MWBMpartners.MeedyaConverter.cachedEntitlementLevel", as: .licenceCache)
        assertNever("Ltd.MWBMpartners.MeedyaConverter.entitlementCacheExpiry", as: .licenceCache)
        assertNever("analytics_anonymousId", as: .installationIdentity)
    }

    // MARK: - Allowed, but only with care

    /// The two lists that can still hold a secret must be marked so the
    /// exporter removes it; the two addresses that could embed a token must
    /// be marked as addresses (which carry the "no user name or password
    /// inside" rule).
    func test_secretBearingValuesCarryTheirSafetyRules() {
        XCTAssertTrue(SettingsJSONBlob.sftpProfiles.mustRemoveSecretsOnExport)
        XCTAssertTrue(SettingsJSONBlob.cloudStorageProfiles.mustRemoveSecretsOnExport)
        XCTAssertEqual(entry(SFTPProfileStore.userDefaultsKey)?.rules?.kind, .json(.sftpProfiles))
        XCTAssertEqual(entry(CloudStorageProfileStore.userDefaultsKey)?.rules?.kind, .json(.cloudStorageProfiles))
        XCTAssertEqual(entry("teamProfiles.gitRemote")?.rules?.kind, .address)
        XCTAssertEqual(entry(MeedyaDBConfigStore.Keys.baseURL)?.rules?.kind, .address)

        // Every other blob is checked to have NO secret field: if one gains
        // a secret, it must be moved into `mustRemoveSecretsOnExport`
        // deliberately, not found by accident.
        let redacted = SettingsJSONBlob.allCases.filter(\.mustRemoveSecretsOnExport)
        XCTAssertEqual(Set(redacted), [.sftpProfiles, .cloudStorageProfiles])
    }

    /// Settings that change something risky must warn when imported.
    func test_riskySettingsWarnWhenImported() {
        for key in ["overwriteExisting", "deleteSourceAfterEncode", "accurateRip.enabled",
                    MeedyaDBConfigStore.Keys.enabled, AutoTagSettingsStore.Keys.enabled] {
            guard case .whenTrue(let message)? = entry(key)?.rules?.importWarning else {
                XCTFail("\(key) must warn when a file sets it to true.")
                continue
            }
            XCTAssertFalse(message.isEmpty)
        }
        guard case .whenValue(let value, let message)? = entry(MeedyaDBConfigStore.Keys.submissionMode)?
            .rules?.importWarning else {
            XCTFail("meedyadb.submissionMode must warn when a file sets it to full.")
            return
        }
        XCTAssertEqual(value, MeedyaDBSubmissionMode.full.rawValue)
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: - Owner defaults

    func test_thisMacIsOffByDefaultAndEverythingElseIsOn() {
        for category in SettingsCategory.allCases {
            XCTAssertEqual(category.includedByDefault, category != .thisMac, "\(category)")
            XCTAssertEqual(category.warning != nil, category == .thisMac, "\(category)")
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.explanation.isEmpty)
        }
    }

    func test_encodingProfilesAreTheirOwnGroupAndTheOnlyFileThatTravels() {
        XCTAssertTrue(SettingsKeyRegistry.entries(in: .encodingProfiles).isEmpty,
                      "Encoding profiles are a file, not settings keys.")
        let travelling = SettingsKeyRegistry.fileStores.filter {
            if case .allowed = $0.decision { return true }
            return false
        }
        XCTAssertEqual(travelling.map(\.path), ["Profiles/user_profiles.json"])
        XCTAssertEqual(travelling.first?.decision, .allowed(.encodingProfiles))
    }

    // MARK: - The table is well formed

    func test_everyKeyAppearsOnce() {
        var seen: [String: Int] = [:]
        for entry in SettingsKeyRegistry.entries { seen[entry.key, default: 0] += 1 }
        let duplicates = seen.filter { $0.value > 1 }.keys.sorted()
        XCTAssertTrue(duplicates.isEmpty, "Keys listed more than once: \(duplicates)")
    }

    func test_everyEntryIsExplained() {
        for entry in SettingsKeyRegistry.entries {
            XCTAssertFalse(entry.key.isEmpty)
            XCTAssertFalse(entry.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.key): no label")
            XCTAssertFalse(entry.location.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.key): no location")
            switch entry.decision {
            case .allowed(let category, _):
                XCTAssertTrue(
                    [.general, .encoding, .connections].contains(category),
                    "\(entry.key): .allowed must use general, encoding or connections, not \(category)."
                )
            case .thisMac(_, let reason):
                XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.key): no reason")
            case .never(_, let reason):
                XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty, "\(entry.key): no reason")
            }
        }
        for kind in SettingsNeverKind.allCases {
            XCTAssertFalse(kind.summary.isEmpty, "\(kind)")
        }
    }

    /// Value rules must make sense: lists of allowed values are non-empty
    /// and have no repeats; warnings match the kind of value.
    func test_valueRulesAreConsistent() {
        for entry in SettingsKeyRegistry.entries {
            guard let rules = entry.rules else { continue }
            switch rules.kind {
            case .string(let allowed, let maxLength):
                XCTAssertGreaterThan(maxLength, 0, entry.key)
                if let allowed {
                    XCTAssertFalse(allowed.isEmpty, "\(entry.key): empty list of allowed values")
                    XCTAssertEqual(Set(allowed).count, allowed.count, "\(entry.key): repeated allowed value")
                    XCTAssertTrue(allowed.allSatisfy { $0.count <= maxLength }, entry.key)
                }
            case .bool, .int, .double, .address, .filePath, .hexColour, .json:
                break
            }
            switch rules.importWarning {
            case .whenTrue(let message)?:
                XCTAssertEqual(rules.kind, .bool, "\(entry.key): .whenTrue needs a true/false setting")
                XCTAssertFalse(message.isEmpty, entry.key)
            case .whenValue(let value, let message)?:
                guard case .string(let allowed?, _) = rules.kind else {
                    XCTFail("\(entry.key): .whenValue needs a setting with a fixed list of values")
                    continue
                }
                XCTAssertTrue(allowed.contains(value), "\(entry.key): warns about a value it never accepts")
                XCTAssertFalse(message.isEmpty, entry.key)
            case nil:
                break
            }
        }
    }

    /// The groups the registry uses are all real, and no exportable group
    /// that is made of settings is empty.
    func test_everySettingsGroupHasSettings() {
        for category in [SettingsCategory.general, .encoding, .connections, .thisMac] {
            XCTAssertFalse(SettingsKeyRegistry.entries(in: category).isEmpty, "\(category) has no settings")
        }
    }

    func test_fileStoresAreWellFormed() {
        let paths = SettingsKeyRegistry.fileStores.map(\.path)
        XCTAssertEqual(Set(paths).count, paths.count, "A file store is listed twice.")
        for store in SettingsKeyRegistry.fileStores {
            XCTAssertFalse(store.label.isEmpty, store.path)
            XCTAssertTrue(store.sourceFile.hasSuffix(".swift"), store.path)
            XCTAssertFalse(store.path.hasPrefix("/"), "\(store.path): paths are inside the app's folder")
            if case .never(let reason) = store.decision {
                XCTAssertFalse(reason.isEmpty, store.path)
            }
        }
        // The credentials index must never travel.
        XCTAssertEqual(
            SettingsKeyRegistry.fileStores.first { $0.path == "Keys/api_keys.json" }.map {
                if case .never = $0.decision { return true }
                return false
            },
            true
        )
    }
}
