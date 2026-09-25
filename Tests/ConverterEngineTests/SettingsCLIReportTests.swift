// ============================================================================
// MeedyaConverter — SettingsCLIReportTests (Issue #506 commit 7)
// Tests/ConverterEngineTests/SettingsCLIReportTests.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// #506 plan §7 test 9 asks for the CLI's `--format json` output to validate
// against `docs/schemas/settings-cli-report-v1.schema.json`, using the
// test-only `SettingsSchemaMiniValidator`. That checker lives in THIS test
// target (`ConverterEngineTests`), and `Tests/MeedyaConvertTests` cannot
// reach it (see `Sources/ConverterEngine/Settings/SettingsCLIReport.swift`'s
// file overview for exactly why — SwiftPM does not let one test target's
// sources be imported by another). So the schema check happens HERE,
// against `SettingsCLIReport`, the exact function
// `Sources/meedya-convert/Commands/SettingsCommand.swift` calls to build
// its JSON output. `SettingsCommandProcessTests` (MeedyaConvertTests) then
// only has to run the real binary and check a few fields in the JSON it
// printed, because the shape itself is proven once, here.
//
// Every report built below is also run through
// `SettingsSchemaMiniValidator.validate(_:against: SettingsCLIReportSchema
// .generate())` — the schema ITSELF is separately proven to equal the
// committed file, and to use only supported keywords, by
// `SettingsSchemaTests` (commit 6); this file only proves that REAL reports
// pass it.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class SettingsCLIReportTests: XCTestCase {

    private var fixture: SettingsTransferFixture!
    private static let fixedDate = Date(timeIntervalSince1970: 1_790_100_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try SettingsTransferFixture()
    }

    override func tearDown() {
        fixture.tearDown()
        fixture = nil
        super.tearDown()
    }

    private func validate(_ report: JSONValue) throws {
        try SettingsSchemaMiniValidator.validate(report, against: SettingsCLIReportSchema.generate())
    }

    // MARK: - Export

    func test_exportReport_validatesAndHasNoImportOnlyFields() throws {
        let domain = fixture.makeDomain("cli-report-export")
        SettingsTransferSamples.storeAll(in: domain.defaults)
        let store = fixture.makeProfileStore("cli-report-export")
        try store.upsertUserProfiles(SettingsTransferSamples.userProfiles)

        // A presence that reports TMDB as set up, so `leftOut` has something
        // real in it to check, not just an empty array.
        let presence = SettingsTransferFakePresence(apiKeys: ["tmdb": .present])
        let exporter = SettingsExporter(
            domain: domain, profileStore: store, presence: presence,
            now: { SettingsTransferSamples.exportDate }
        )
        let export = try exporter.makeExport(categories: [.general, .encoding, .encodingProfiles])

        let report = SettingsCLIReport.forExport(
            export, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/export.json"
        )
        try validate(report)

        guard case .object(let fields) = report else { return XCTFail("not an object") }
        XCTAssertEqual(fields["command"], .string("export"))
        XCTAssertEqual(fields["appVersion"], .string("9.9.9"))
        XCTAssertEqual(fields["file"], .string("/tmp/export.json"))
        let expectedFormatter = ISO8601DateFormatter()
        expectedFormatter.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(fields["generatedAt"], .string(expectedFormatter.string(from: Self.fixedDate)))

        // Import-only fields must be entirely absent from an export report,
        // not present-but-empty: their presence at all would say something
        // false about what an export knows.
        for key in ["mode", "applied", "stillNeeded", "crossChecks", "replaceConfirmation"] {
            XCTAssertNil(fields[key], "export report should not have a \"\(key)\" field.")
        }

        guard case .array(let leftOut)? = fields["leftOut"] else {
            return XCTFail("expected a non-empty \"leftOut\" array (TMDB was reported present).")
        }
        XCTAssertEqual(leftOut, [.string("tmdbKey")])

        guard case .array(let categories)? = fields["categories"] else { return XCTFail("no categories") }
        XCTAssertEqual(categories.count, 3)
        for entry in categories {
            guard case .object(let categoryFields) = entry else { return XCTFail("category entry not an object") }
            XCTAssertEqual(categoryFields["selected"], .bool(true))
            // added/updated/removed are meaningless for an export (nothing
            // to compare against) and must be left out entirely.
            for key in ["added", "updated", "removed"] {
                XCTAssertNil(categoryFields[key], "export category should not have a \"\(key)\" field.")
            }
        }
    }

    func test_exportReport_noGroupsSelected_stillValidatesAsEmptyCategories() throws {
        // `makeExport` itself refuses an empty selection (`noGroupsChosen`),
        // so this checks the smallest REAL export instead: one category,
        // nothing stored in it. The report must still validate — an empty
        // settings group is not malformed, just uninteresting.
        let domain = fixture.makeDomain("cli-report-export-empty")
        let store = fixture.makeProfileStore("cli-report-export-empty")
        let exporter = SettingsExporter(
            domain: domain, profileStore: store, presence: SettingsTransferFakePresence(),
            now: { SettingsTransferSamples.exportDate }
        )
        let export = try exporter.makeExport(categories: [.general])
        let report = SettingsCLIReport.forExport(
            export, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/empty.json"
        )
        try validate(report)
        guard case .object(let fields) = report, case .array(let categories)? = fields["categories"] else {
            return XCTFail("no categories")
        }
        XCTAssertEqual(categories.count, 1)
        XCTAssertNil(fields["leftOut"], "nothing was set up here, so leftOut should be entirely absent, not [].")
    }

    // MARK: - Import: preview (no --apply)

    func test_importPreviewReport_validatesAndHasNoApplyOnlyFields() throws {
        let (plan, importer) = try makePlanAndImporter(
            exportCategories: [.general, .encoding, .encodingProfiles],
            targetSamples: false
        )
        // Deliberately does NOT select "encodingProfiles", even though the
        // file has it: this is what makes the cross-check below fire —
        // "My HEVC" (the exported default profile) is not on this Mac AND
        // is not being imported, because its whole group was left unticked.
        let preview = importer.preview(plan, selection: [.general, .encoding], mode: .merge)
        let report = SettingsCLIReport.forImportPreview(
            preview, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/import.json"
        )
        try validate(report)

        guard case .object(let fields) = report else { return XCTFail("not an object") }
        XCTAssertEqual(fields["command"], .string("import"))
        XCTAssertEqual(fields["mode"], .string("merge"))
        XCTAssertEqual(fields["applied"], .bool(false))

        // Apply-only fields: absent before anything has been written.
        XCTAssertNil(fields["stillNeeded"], "a preview cannot know what still needs entering.")
        XCTAssertNil(fields["leftOut"], "leftOut is export-only.")

        // Deliberate design choice (see SettingsCLIReport's file overview):
        // takesEffectNextLaunch IS available at preview time, because the
        // engine already computes it before writing anything.
        guard case .array(let nextLaunch)? = fields["takesEffectNextLaunch"], !nextLaunch.isEmpty else {
            return XCTFail("expected a non-empty takesEffectNextLaunch (defaultProfileName takes effect next launch).")
        }

        guard case .array(let crossChecks)? = fields["crossChecks"], !crossChecks.isEmpty else {
            return XCTFail("expected a cross-check about the missing default profile.")
        }
        XCTAssertTrue(crossChecks[0].isString(containing: "My HEVC"))
    }

    // MARK: - Import: applied (--apply)

    func test_importAppliedReport_validatesAndHasStillNeededWithBothStatuses() throws {
        // Export presence: TMDB and MeedyaDB both "set up there", so the
        // file's notIncluded names both.
        let exportPresence = SettingsTransferFakePresence(apiKeys: ["tmdb": .present, "meedya_db": .present])
        let sourceDomain = fixture.makeDomain("cli-report-stillneeded-source")
        SettingsTransferSamples.storeAll(in: sourceDomain.defaults)
        let sourceStore = fixture.makeProfileStore("cli-report-stillneeded-source")
        let exporter = SettingsExporter(
            domain: sourceDomain, profileStore: sourceStore, presence: exportPresence,
            now: { SettingsTransferSamples.exportDate }
        )
        let data = try exporter.makeData(categories: [.encoding, .connections])

        // Import presence: TMDB definitely missing here; MeedyaDB could not
        // be checked — the two `KeyPresence` outcomes `SettingsCredentialNeed
        // .Status` distinguishes, both exercised in one report.
        let importPresence = SettingsTransferFakePresence(
            apiKeys: ["tmdb": .missing, "meedya_db": .couldNotCheck(.indexUnreadable)]
        )
        let targetDomain = fixture.makeDomain("cli-report-stillneeded-target")
        let targetStore = fixture.makeProfileStore("cli-report-stillneeded-target")
        let plan = try SettingsImporter.prepare(data)
        let importer = SettingsImporter(domain: targetDomain, profileStore: targetStore, presence: importPresence)
        let selection: Set<SettingsCategory> = [.encoding, .connections]
        let preview = importer.preview(plan, selection: selection, mode: .merge)
        let result = try importer.apply(plan, selection: selection, mode: .merge)

        let report = SettingsCLIReport.forImportResult(
            result, preview: preview, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/apply.json"
        )
        try validate(report)

        guard case .object(let fields) = report else { return XCTFail("not an object") }
        XCTAssertEqual(fields["applied"], .bool(true))
        guard case .array(let stillNeeded)? = fields["stillNeeded"] else { return XCTFail("expected stillNeeded") }

        func entry(titleContains needle: String) -> [String: JSONValue]? {
            for item in stillNeeded {
                if case .object(let itemFields) = item,
                   case .string(let title)? = itemFields["title"], title.contains(needle) {
                    return itemFields
                }
            }
            return nil
        }

        guard let tmdbEntry = entry(titleContains: "TMDB") else { return XCTFail("no TMDB entry in stillNeeded") }
        XCTAssertEqual(tmdbEntry["status"], .string("missing"))
        XCTAssertNil(tmdbEntry["statusReason"], "\"missing\" never carries a statusReason.")

        guard let meedyaDBEntry = entry(titleContains: "MeedyaDB") else {
            return XCTFail("no MeedyaDB entry in stillNeeded")
        }
        XCTAssertEqual(meedyaDBEntry["status"], .string("couldNotCheck"))
        guard case .string(let reason)? = meedyaDBEntry["statusReason"] else {
            return XCTFail("couldNotCheck must carry a statusReason")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func test_replaceMode_reportShowsRemovedCountsAndConfirmation() throws {
        // The source file exports "general" with only ONE setting stored.
        let sourceDomain = fixture.makeDomain("cli-report-replace-source")
        sourceDomain.defaults.set("Dark", forKey: "appearanceMode")
        let sourceStore = fixture.makeProfileStore("cli-report-replace-source")
        let exporter = SettingsExporter(
            domain: sourceDomain, profileStore: sourceStore, presence: SettingsTransferFakePresence(),
            now: { SettingsTransferSamples.exportDate }
        )
        let data = try exporter.makeData(categories: [.general])

        // The target Mac has the FULL sample set for "general" already
        // stored, so "replace" has real work to remove.
        let targetDomain = fixture.makeDomain("cli-report-replace-target")
        SettingsTransferSamples.storeAll(in: targetDomain.defaults)
        let targetStore = fixture.makeProfileStore("cli-report-replace-target")

        let plan = try SettingsImporter.prepare(data)
        let importer = SettingsImporter(domain: targetDomain, profileStore: targetStore, presence: SettingsTransferFakePresence())
        let preview = importer.preview(plan, selection: [.general], mode: .replace)
        let result = try importer.apply(plan, selection: [.general], mode: .replace)

        let report = SettingsCLIReport.forImportResult(
            result, preview: preview, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/replace.json"
        )
        try validate(report)

        guard case .object(let fields) = report else { return XCTFail("not an object") }
        XCTAssertEqual(fields["mode"], .string("replace"))
        guard case .string(let confirmation)? = fields["replaceConfirmation"], !confirmation.isEmpty else {
            return XCTFail("expected a non-empty replaceConfirmation")
        }

        guard case .array(let categories)? = fields["categories"] else { return XCTFail("no categories") }
        guard let general = categories.first(where: { category in
            if case .object(let categoryFields) = category { return categoryFields["category"] == .string("general") }
            return false
        }), case .object(let generalFields) = general else {
            return XCTFail("no general category entry")
        }
        guard case .number(let removed)? = generalFields["removed"], removed > 0 else {
            return XCTFail("expected \"removed\" > 0 for a replace that drops most of general")
        }
    }

    // MARK: - Ignored items map to the schema's fixed reason strings

    func test_ignoredItems_mapToTheSchemasReasonStrings() throws {
        let domain = fixture.makeDomain("cli-report-ignored")
        SettingsTransferSamples.storeAll(in: domain.defaults)
        let store = fixture.makeProfileStore("cli-report-ignored")
        let exporter = SettingsExporter(
            domain: domain, profileStore: store, presence: SettingsTransferFakePresence(),
            now: { SettingsTransferSamples.exportDate }
        )
        let data = try exporter.makeData(categories: [.general, .encoding])
        var file = try SettingsTransferEditableFile(data)
        file.setSetting("notARealSetting", "boo", in: "general")       // unknownSetting
        file.setSetting("webhookURL", "https://hooks.example.com/x", in: "general")  // neverImported (a credential)
        file.setSetting("defaultProfileName", "Whatever", in: "general") // belongs in "encoding" -> wrongGroup

        let plan = try SettingsImporter.prepare(file.data)
        let importer = SettingsImporter(domain: domain, profileStore: store, presence: SettingsTransferFakePresence())
        let preview = importer.preview(plan, selection: [.general, .encoding], mode: .merge)
        let report = SettingsCLIReport.forImportPreview(
            preview, appVersion: "9.9.9", generatedAt: Self.fixedDate, file: "/tmp/ignored.json"
        )
        try validate(report)

        guard case .object(let fields) = report, case .array(let ignored)? = fields["ignored"] else {
            return XCTFail("expected a non-empty ignored array")
        }

        func reason(for name: String) -> (reason: String, belongsIn: String?)? {
            for item in ignored {
                guard case .object(let itemFields) = item, itemFields["name"] == .string(name) else { continue }
                guard case .string(let reason)? = itemFields["reason"] else { return nil }
                if case .string(let belongsIn)? = itemFields["belongsIn"] { return (reason, belongsIn) }
                return (reason, nil)
            }
            return nil
        }

        XCTAssertEqual(reason(for: "notARealSetting")?.reason, "unknownSetting")
        XCTAssertEqual(reason(for: "webhookURL")?.reason, "neverImported")
        let wrongGroup = reason(for: "defaultProfileName")
        XCTAssertEqual(wrongGroup?.reason, "wrongGroup")
        XCTAssertEqual(wrongGroup?.belongsIn, "encoding")
    }

    // MARK: - Helpers

    /// Builds a plan (from a fresh export of the sample settings) and an
    /// importer over an EMPTY target domain, so every setting shows up as
    /// "added" and the cross-check about the missing default profile fires.
    private func makePlanAndImporter(
        exportCategories: Set<SettingsCategory>,
        targetSamples: Bool
    ) throws -> (SettingsImportPlan, SettingsImporter) {
        let sourceDomain = fixture.makeDomain("cli-report-plan-source-\(UUID().uuidString)")
        SettingsTransferSamples.storeAll(in: sourceDomain.defaults)
        let sourceStore = fixture.makeProfileStore("cli-report-plan-source-\(UUID().uuidString)")
        try sourceStore.upsertUserProfiles(SettingsTransferSamples.userProfiles)
        let exporter = SettingsExporter(
            domain: sourceDomain, profileStore: sourceStore, presence: SettingsTransferFakePresence(),
            now: { SettingsTransferSamples.exportDate }
        )
        let data = try exporter.makeData(categories: exportCategories)

        let targetDomain = fixture.makeDomain("cli-report-plan-target-\(UUID().uuidString)")
        if targetSamples { SettingsTransferSamples.storeAll(in: targetDomain.defaults) }
        let targetStore = fixture.makeProfileStore("cli-report-plan-target-\(UUID().uuidString)")
        let plan = try SettingsImporter.prepare(data)
        let importer = SettingsImporter(domain: targetDomain, profileStore: targetStore, presence: SettingsTransferFakePresence())
        return (plan, importer)
    }
}

// MARK: - Small JSONValue test helper

private extension JSONValue {
    /// Whether this is a string containing `needle` — for asserting on a
    /// free-text sentence without pinning its exact wording.
    func isString(containing needle: String) -> Bool {
        guard case .string(let text) = self else { return false }
        return text.contains(needle)
    }
}
