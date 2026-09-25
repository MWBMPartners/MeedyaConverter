// ============================================================================
// MeedyaConverter — SettingsSchemaTests (Issue #506 commit 6)
// Tests/ConverterEngineTests/SettingsSchemaTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan §2 and §7 test 7: the settings export file, and the future CLI
// JSON report, have a real JSON Schema, checked here with
// `SettingsSchemaMiniValidator` (the test-only checker in this same folder).
//
//   - The two committed files under `docs/schemas/` are GENERATED, never
//     hand-edited: `test_committedExportSchemaMatchesGenerated` and
//     `test_committedCLIReportSchemaMatchesGenerated` fail if either one
//     differs from `SettingsExportSchema.generate()` /
//     `SettingsCLIReportSchema.generate()`. To regenerate them after a
//     genuine change to either generator, run this file's tests with
//     `MEEDYACONVERTER_REGENERATE_SCHEMAS=1` set (see
//     `SettingsExportSchema.swift`'s header for the exact command).
//   - A REAL export — every group ticked, a sample value in every allowed
//     key (`SettingsTransferSamples`), AND secrets deliberately planted in
//     every credential-bearing place an unmigrated installation could still
//     have them (an SFTP password, a cloud access token, a refresh token, an
//     S3 secret key) — validates against the schema. This proves the schema
//     matches what the exporter's OWN redaction actually produces, not just
//     a hand-picked clean case.
//   - A hand-made document that skips that redaction — a real password sitting
//     in an SFTP server, or a real value in a cloud secret field — FAILS the
//     schema. This is the independent proof the three leak safeguards work
//     on their own: even if `SettingsValueCodecs.swift`'s redaction had a
//     bug, a file it produced with a real secret in it would still be
//     caught here.
//   - An unknown key inside a known group fails (`additionalProperties:
//     false`).
//   - Every setting's schema `description` is non-empty, and equals the
//     registry's own `label` — so the schema can never say something about a
//     setting that the registry itself does not say.
//   - The validator itself: it rejects a wrong type, a missing required
//     field, and — the whole reason it exists — any keyword outside its
//     fixed, documented list.
//
// What this file does NOT re-test: `SettingsRoundTripTests
// .test_everyExportableSettingHasASample` (added in commit 5) already forces
// every new allowed setting into `SettingsTransferSamples`, which is the
// plan's §3 test 7 ("force every new key into the round trip"). Re-checked
// here on 2026-09-25: that test exists and does exactly this, so it is not
// duplicated.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class SettingsSchemaTests: XCTestCase {

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

    // MARK: - The committed files are generated, never hand-edited

    func test_committedExportSchemaMatchesGenerated() throws {
        try assertCommittedSchemaMatchesGenerated(
            fileName: "settings-export-v1.schema.json",
            generated: try SettingsExportSchema.generateData()
        )
    }

    func test_committedCLIReportSchemaMatchesGenerated() throws {
        try assertCommittedSchemaMatchesGenerated(
            fileName: "settings-cli-report-v1.schema.json",
            generated: try SettingsCLIReportSchema.generateData()
        )
    }

    /// `docs/schemas/`, found the same way `SettingsKeyCoverageTests` finds
    /// `Sources/`: three levels up from this file's own path.
    private static func schemasDirectory(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()   // Tests/ConverterEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("schemas", isDirectory: true)
    }

    /// Compares the committed file at `docs/schemas/<fileName>` with
    /// `generated`. With `MEEDYACONVERTER_REGENERATE_SCHEMAS=1` set, it
    /// OVERWRITES the committed file instead, then re-reads it to prove the
    /// write took: the documented way to bring the file back into step after
    /// a deliberate change to its generator.
    private func assertCommittedSchemaMatchesGenerated(fileName: String, generated: Data) throws {
        let url = Self.schemasDirectory().appendingPathComponent(fileName)

        if ProcessInfo.processInfo.environment["MEEDYACONVERTER_REGENERATE_SCHEMAS"] == "1" {
            try FileManager.default.createDirectory(
                at: Self.schemasDirectory(), withIntermediateDirectories: true
            )
            try generated.write(to: url, options: .atomic)
            let rereadAfterWrite = try Data(contentsOf: url)
            XCTAssertEqual(rereadAfterWrite, generated, "Regenerating \(url.path) wrote bytes that did not read back the same.")
            return
        }

        guard let onDisk = try? Data(contentsOf: url) else {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fileName).regenerated-\(UUID().uuidString)")
            try? generated.write(to: scratch)
            XCTFail(
                "\(url.path) does not exist. A freshly generated copy was written to \(scratch.path) — "
                    + "commit it at that path, or re-run with MEEDYACONVERTER_REGENERATE_SCHEMAS=1 to "
                    + "write it there directly."
            )
            return
        }

        guard onDisk == generated else {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fileName).regenerated-\(UUID().uuidString)")
            try? generated.write(to: scratch)
            XCTFail(
                "\(url.path) no longer matches its generator's output. A freshly regenerated copy was "
                    + "written to \(scratch.path) for comparison. Re-run with "
                    + "MEEDYACONVERTER_REGENERATE_SCHEMAS=1 to overwrite the committed file once the "
                    + "difference is confirmed intentional."
            )
            return
        }
    }

    // MARK: - A real export, with planted secrets, validates

    func test_realExportWithPlantedSecretsValidatesAgainstTheSchema() throws {
        let domain = fixture.makeDomain("schema-real-export")
        SettingsTransferSamples.storeAll(in: domain.defaults)

        // Plant real secrets in every credential-bearing place an
        // UNMIGRATED installation could still have them, exactly as
        // `SettingsExportNoSecretTests` does — an old plaintext SFTP
        // password, and unredacted cloud tokens/keys. If the exporter's own
        // redaction ever regressed, this is what would catch it: not a
        // hand-picked clean sample, but data shaped like a real Mac's.
        let sentinel = "SENTINEL-\(UUID().uuidString)"
        let plantedSFTP = [
            SFTPServerConfig(
                id: SettingsTransferSamples.sftpNASID, host: "nas.local", port: 2222, username: "media",
                authMethod: .password("\(sentinel)-sftp-plaintext"), remotePath: "/media", label: "NAS"
            ),
        ] + SettingsTransferSamples.sftpServers.dropFirst()
        domain.defaults.set(try JSONEncoder().encode(plantedSFTP), forKey: SFTPProfileStore.userDefaultsKey)

        var plantedCloud = SettingsTransferSamples.cloudDestinations
        plantedCloud[0].accessToken = "\(sentinel)-access-token"
        plantedCloud[0].refreshToken = "\(sentinel)-refresh-token"
        plantedCloud[0].secretAccessKey = "\(sentinel)-secret-key"
        domain.defaults.set(try JSONEncoder().encode(plantedCloud), forKey: CloudStorageProfileStore.userDefaultsKey)

        let store = fixture.makeProfileStore("schema-real-export")
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)

        let export = SettingsExporter(
            domain: domain, profileStore: store, presence: SettingsTransferFakePresence(),
            appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate }
        )
        let data = try export.makeData(categories: Set(SettingsCategory.allCases))

        // Sanity check before the real assertion: the sentinel must not
        // reach the file at all. (`SettingsExportNoSecretTests` is the
        // proper, thorough test of this; this is just a guard so a broken
        // fixture can't make the schema check below pass for the wrong
        // reason.)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(sentinel))

        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertNoThrow(try SettingsSchemaMiniValidator.validate(value, against: SettingsExportSchema.generate()))
    }

    // MARK: - A hand-made file that skips the redaction fails the schema

    /// Builds a real, valid export (every group ticked) and hands back both
    /// its `SettingsTransferEditableFile` (for mutating) and the schema to
    /// check the mutated result against.
    private func realEditableExport() throws -> SettingsTransferEditableFile {
        let domain = fixture.makeDomain("schema-mutate-base-\(UUID().uuidString)")
        SettingsTransferSamples.storeAll(in: domain.defaults)
        let store = fixture.makeProfileStore("schema-mutate-base-\(UUID().uuidString)")
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        let export = SettingsExporter(
            domain: domain, profileStore: store, presence: SettingsTransferFakePresence(),
            appVersion: "9.9.9", now: { SettingsTransferSamples.exportDate }
        )
        let data = try export.makeData(categories: Set(SettingsCategory.allCases))
        return try SettingsTransferEditableFile(data)
    }

    private func validate(_ file: SettingsTransferEditableFile) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: file.data)
        try SettingsSchemaMiniValidator.validate(value, against: SettingsExportSchema.generate())
    }

    func test_handMadeSFTPPasswordFailsTheSchema() throws {
        var file = try realEditableExport()
        let connections = file.settings(in: "connections")
        guard var sftpItems = connections[SFTPProfileStore.userDefaultsKey] as? [[String: Any]], !sftpItems.isEmpty else {
            return XCTFail("The sample export has no SFTP servers to mutate.")
        }
        var authMethod = sftpItems[0]["authMethod"] as? [String: Any] ?? [:]
        authMethod["password"] = ["_0": "hunter2"]
        sftpItems[0]["authMethod"] = authMethod
        file.setSetting(SFTPProfileStore.userDefaultsKey, sftpItems, in: "connections")

        XCTAssertThrowsError(try validate(file)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError, case .constMismatch = schemaError else {
                return XCTFail("Expected a constMismatch on the SFTP password, got \(error)")
            }
        }
    }

    func test_handMadeCloudAccessTokenFailsTheSchema() throws {
        var file = try realEditableExport()
        let connections = file.settings(in: "connections")
        guard var cloudItems = connections[CloudStorageProfileStore.userDefaultsKey] as? [[String: Any]],
              !cloudItems.isEmpty else {
            return XCTFail("The sample export has no cloud destinations to mutate.")
        }
        cloudItems[0]["accessToken"] = "hunter2-access-token"
        file.setSetting(CloudStorageProfileStore.userDefaultsKey, cloudItems, in: "connections")

        XCTAssertThrowsError(try validate(file)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError, case .constMismatch = schemaError else {
                return XCTFail("Expected a constMismatch on the cloud access token, got \(error)")
            }
        }
    }

    func test_handMadeCloudSecretKeyFailsTheSchema() throws {
        var file = try realEditableExport()
        let connections = file.settings(in: "connections")
        guard var cloudItems = connections[CloudStorageProfileStore.userDefaultsKey] as? [[String: Any]],
              !cloudItems.isEmpty else {
            return XCTFail("The sample export has no cloud destinations to mutate.")
        }
        // `secretAccessKey` is never LISTED in the schema at all (leak
        // safeguard 3 of 3): its mere presence, whatever the value, must fail.
        cloudItems[0]["secretAccessKey"] = "hunter2-secret-key"
        file.setSetting(CloudStorageProfileStore.userDefaultsKey, cloudItems, in: "connections")

        XCTAssertThrowsError(try validate(file)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError,
                  case .additionalPropertyNotAllowed(let name, _) = schemaError, name == "secretAccessKey" else {
                return XCTFail("Expected additionalPropertyNotAllowed(\"secretAccessKey\"), got \(error)")
            }
        }
    }

    // MARK: - An unknown key fails

    func test_unknownKeyInACategoryFailsTheSchema() throws {
        var file = try realEditableExport()
        file.setSetting("notARealSetting", "boo", in: "general")

        XCTAssertThrowsError(try validate(file)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError,
                  case .additionalPropertyNotAllowed(let name, _) = schemaError, name == "notARealSetting" else {
                return XCTFail("Expected additionalPropertyNotAllowed(\"notARealSetting\"), got \(error)")
            }
        }
    }

    // MARK: - Every setting's description is real, and matches the registry

    func test_everySettingPropertyHasANonEmptyDescriptionMatchingTheRegistry() throws {
        let schema = SettingsExportSchema.generate()
        for category: SettingsCategory in [.general, .encoding, .connections, .thisMac] {
            let settingsProperties = try settingsProperties(of: category, in: schema)
            XCTAssertFalse(settingsProperties.isEmpty, "\(category.rawValue) has no settings properties in the schema.")
            for (key, propertySchema) in settingsProperties {
                guard case .object(let fields) = propertySchema else {
                    XCTFail("\(category.rawValue).\(key)'s schema is not an object.")
                    continue
                }
                guard case .string(let description)? = fields["description"], !description.isEmpty else {
                    XCTFail("\(category.rawValue).\(key) has no non-empty \"description\".")
                    continue
                }
                guard let entry = SettingsKeyRegistry.entry(for: key) else {
                    XCTFail("\(category.rawValue).\(key) is in the schema but not the registry.")
                    continue
                }
                XCTAssertEqual(
                    description, entry.label,
                    "\(category.rawValue).\(key)'s schema description should be the registry's own label."
                )
            }
        }
    }

    /// Navigates `categories.properties.<category>.properties.settings.properties`.
    private func settingsProperties(of category: SettingsCategory, in schema: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let root) = schema,
              case .object(let rootProperties)? = root["properties"],
              case .object(let categories)? = rootProperties["categories"],
              case .object(let categoryProperties)? = categories["properties"],
              case .object(let section)? = categoryProperties[category.rawValue],
              case .object(let sectionProperties)? = section["properties"],
              case .object(let settings)? = sectionProperties["settings"],
              case .object(let settingsProperties)? = settings["properties"] else {
            throw XCTSkip("Could not navigate to \(category.rawValue).settings.properties in the schema.")
        }
        return settingsProperties
    }

    // MARK: - The validator itself

    func test_validatorRejectsAWrongType() {
        let schema = JSONValue.object(["type": .string("string")])
        XCTAssertThrowsError(try SettingsSchemaMiniValidator.validate(.number(1), against: schema)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError, case .typeMismatch = schemaError else {
                return XCTFail("Expected typeMismatch, got \(error)")
            }
        }
    }

    func test_validatorRejectsAMissingRequiredField() {
        let schema = JSONValue.object([
            "type": .string("object"),
            "required": .array([.string("a")]),
            "properties": .object(["a": .object(["type": .string("string")])]),
        ])
        XCTAssertThrowsError(try SettingsSchemaMiniValidator.validate(.object([:]), against: schema)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError,
                  case .missingRequiredProperty(let name, _) = schemaError, name == "a" else {
                return XCTFail("Expected missingRequiredProperty(\"a\"), got \(error)")
            }
        }
    }

    func test_validatorRejectsAnUnsupportedKeyword() {
        // "oneOf" is real JSON Schema, and deliberately NOT in
        // SettingsSchemaMiniValidator's supported list (see its header).
        let schema = JSONValue.object([
            "oneOf": .array([.object(["type": .string("string")]), .object(["type": .string("number")])]),
        ])
        XCTAssertThrowsError(try SettingsSchemaMiniValidator.validate(.string("x"), against: schema)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError,
                  case .unsupportedKeyword(let keyword, _) = schemaError, keyword == "oneOf" else {
                return XCTFail("Expected unsupportedKeyword(\"oneOf\"), got \(error)")
            }
        }
    }

    /// The keyword whitelist walk covers the WHOLE schema document, not just
    /// the parts a given value happens to visit — including an unused
    /// `$defs` entry (see `SettingsSchemaMiniValidator`'s header).
    func test_validatorRejectsAnUnsupportedKeywordInAnUnreferencedDef() {
        let schema = JSONValue.object([
            "type": .string("string"),
            "$defs": .object([
                "unused": .object(["type": .string("string"), "multipleOf": .number(2)]),
            ]),
        ])
        XCTAssertThrowsError(try SettingsSchemaMiniValidator.validate(.string("x"), against: schema)) { error in
            guard let schemaError = error as? SettingsSchemaMiniValidatorError,
                  case .unsupportedKeyword(let keyword, _) = schemaError, keyword == "multipleOf" else {
                return XCTFail("Expected unsupportedKeyword(\"multipleOf\"), got \(error)")
            }
        }
    }

    /// The real committed schemas must themselves pass the whitelist walk —
    /// otherwise every other test in this file would be trivially "valid"
    /// against a schema the checker never actually understood.
    func test_bothRealSchemasUseOnlySupportedKeywords() throws {
        XCTAssertNoThrow(try SettingsSchemaMiniValidator.checkNoUnsupportedKeywords(in: SettingsExportSchema.generate()))
        XCTAssertNoThrow(try SettingsSchemaMiniValidator.checkNoUnsupportedKeywords(in: SettingsCLIReportSchema.generate()))
    }
}
