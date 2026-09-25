// ============================================================================
// MeedyaConverter — Building the CLI's --format json settings report
// (Issue #506 commit 7)
// Sources/ConverterEngine/Settings/SettingsCLIReport.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Turns the engine's own result types (`SettingsExport`, `SettingsImportPreview`,
// `SettingsImportResult`) into the exact JSON shape `SettingsCLIReportSchema`
// pins down, so that `meedya-convert settings export` / `settings import`
// `--format json` (Sources/meedya-convert/Commands/SettingsCommand.swift,
// #506 commit 7) and the schema test that checks it in `ConverterEngineTests`
// build the SAME bytes from the SAME function, rather than two independent
// descriptions of the same shape that could quietly drift apart.
//
// Why this lives HERE, in the engine, and not in the CLI target. The schema
// check needs `SettingsSchemaMiniValidator`, a test-only type that lives
// inside `Tests/ConverterEngineTests` (see that folder's header). SwiftPM
// does not let one test target's sources be imported by another test
// target — `Tests/MeedyaConvertTests` depends only on the `ConverterEngine`
// library (see `Package.swift`'s comment on why: an executable target's
// `@main` cannot be imported by a second `@main`-bearing test bundle
// either). So the ONLY place that can both build a real report AND run it
// through the mini-validator is `ConverterEngineTests`, against a function
// that is public engine API — which is what this file provides. The
// process-level CLI test (`SettingsCommandProcessTests`, MeedyaConvertTests)
// then only has to decode the JSON the real binary printed and check a
// handful of fields (exit code, "applied", a category name), because the
// shape itself is already proven, once, here.
//
// Deliberate choices where the plan (and the commit-6 schema, written
// BEFORE this command existed) leaves room:
//   - `takesEffectNextLaunch` is filled in for a PREVIEW too (before
//     `--apply`), not only after applying. The schema's own field
//     description says "after applying", written when only
//     `SettingsImportResult` existed to draw it from; but
//     `SettingsImportPreview` already computes the very same list before
//     anything is written (the plan's §5 wants the app's preview screen to
//     show it too, for the same reason). Telling someone who has not yet
//     typed `--apply` what would take effect next launch, before they
//     commit to it, is more useful than withholding it until afterwards —
//     and it costs nothing: the field was always optional, and the type is
//     unchanged (an array of plain-English labels).
//   - `stillNeeded` and `leftOut` genuinely ARE apply-only / export-only,
//     and are simply left out of a report where they do not apply:
//       - `stillNeeded` cannot be known before a write happens — it reads
//         the settings just imported (`SettingsCredentialNeeds`'s own file
//         overview says so), so a preview report has no such list to give;
//       - `leftOut` only exists on the export side (`SettingsExport.leftOut`).
//     The schema's "additionalProperties: false" sits over an otherwise
//     all-optional set of fields for exactly this reason: which fields are
//     present says as much as their values do.
//   - An export's per-category "summary" is worded with the very same
//     helper `SettingsExport.reportLines` uses (`SettingsImportReport
//     .count`), so the JSON and text reports never disagree about the
//     count wording.
//   - Per-category "added"/"updated"/"removed" are only ever produced for
//     an IMPORT (a settings export has nothing to compare against — every
//     exported item is simply "in the file"), so they are omitted from an
//     export's category entries rather than sent as 0, which would read as
//     "nothing changed" rather than "not applicable".
// ---------------------------------------------------------------------------

import Foundation

/// Builds the `--format json` report for `meedya-convert settings export`
/// and `meedya-convert settings import`, in the exact shape
/// `SettingsCLIReportSchema` describes. See the file overview for why this
/// lives in the engine rather than the CLI target.
public enum SettingsCLIReport {

    // MARK: - Export

    /// The report for a completed `settings export`.
    public static func forExport(
        _ export: SettingsExport,
        appVersion: String,
        generatedAt: Date,
        file: String
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "command": .string("export"),
            "appVersion": .string(appVersion),
            "generatedAt": .string(iso8601(generatedAt)),
            "file": .string(file),
            "categories": .array(export.categories.map { category in
                let count = export.itemCounts[category] ?? 0
                return categoryReport(
                    category: category, selected: true, count: count,
                    added: nil, updated: nil, removed: nil,
                    summary: exportSummary(for: category, count: count)
                )
            }),
        ]
        if !export.leftOut.isEmpty {
            fields["leftOut"] = .array(export.leftOut.map { .string($0.rawValue) })
        }
        return .object(fields)
    }

    // MARK: - Import: preview (no --apply; nothing was written)

    /// The report for `settings import` WITHOUT `--apply`: a preview only.
    public static func forImportPreview(
        _ preview: SettingsImportPreview,
        appVersion: String,
        generatedAt: Date,
        file: String
    ) -> JSONValue {
        var fields = commonImportFields(
            appVersion: appVersion, generatedAt: generatedAt, file: file,
            mode: preview.mode, applied: false,
            groups: preview.groups, warnings: preview.warnings, crossChecks: preview.crossChecks,
            replaceConfirmation: preview.replaceConfirmation, ignored: preview.ignored
        )
        // See the file overview: filled in at preview time too, on purpose.
        if !preview.takesEffectNextLaunch.isEmpty {
            fields["takesEffectNextLaunch"] = .array(preview.takesEffectNextLaunch.map { .string($0) })
        }
        return .object(fields)
    }

    // MARK: - Import: applied (--apply; the change has been written)

    /// The report for `settings import --apply`.
    ///
    /// - Parameter preview: The preview computed for the SAME plan,
    ///   selection and mode, before `apply` ran. The per-category
    ///   added/updated/removed counts come from it, because
    ///   `SettingsImportResult` does not keep that breakdown itself (only
    ///   the final written/removed keys) — `SettingsImporter.changes(for:…)`
    ///   is what both `preview` and `apply` share, so the two agree by
    ///   construction.
    public static func forImportResult(
        _ result: SettingsImportResult,
        preview: SettingsImportPreview,
        appVersion: String,
        generatedAt: Date,
        file: String
    ) -> JSONValue {
        var fields = commonImportFields(
            appVersion: appVersion, generatedAt: generatedAt, file: file,
            mode: result.mode, applied: true,
            groups: preview.groups, warnings: preview.warnings, crossChecks: preview.crossChecks,
            replaceConfirmation: preview.replaceConfirmation, ignored: result.ignored
        )
        if !result.takesEffectNextLaunch.isEmpty {
            fields["takesEffectNextLaunch"] = .array(result.takesEffectNextLaunch.map { .string($0) })
        }
        if !result.stillNeeded.isEmpty {
            fields["stillNeeded"] = .array(result.stillNeeded.map(stillNeededItem))
        }
        return .object(fields)
    }

    // MARK: - Encoding

    /// The bytes to print for `--format json`: pretty-printed, sorted keys,
    /// "/" left unescaped (paths and addresses read as they are) — the same
    /// formatting `SettingsDocument.makeData` uses for the settings file
    /// itself, so both the file and the report are easy to diff by eye.
    public static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    // MARK: - Shared pieces (import)

    private static func commonImportFields(
        appVersion: String, generatedAt: Date, file: String,
        mode: SettingsImportMode, applied: Bool,
        groups: [SettingsGroupPreview], warnings: [String], crossChecks: [String],
        replaceConfirmation: String?, ignored: [SettingsIgnoredItem]
    ) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "command": .string("import"),
            "appVersion": .string(appVersion),
            "generatedAt": .string(iso8601(generatedAt)),
            "file": .string(file),
            "mode": .string(mode.rawValue),
            "applied": .bool(applied),
            "categories": .array(groups.map { group in
                let counts = addedUpdatedRemoved(for: group)
                return categoryReport(
                    category: group.category, selected: group.isSelected, count: group.countInFile,
                    added: counts.added, updated: counts.updated, removed: counts.removed,
                    summary: group.summary
                )
            }),
        ]
        if !warnings.isEmpty { fields["warnings"] = .array(warnings.map { .string($0) }) }
        if !crossChecks.isEmpty { fields["crossChecks"] = .array(crossChecks.map { .string($0) }) }
        if let replaceConfirmation { fields["replaceConfirmation"] = .string(replaceConfirmation) }
        if !ignored.isEmpty { fields["ignored"] = .array(ignored.map(ignoredItem)) }
        return fields
    }

    /// One `categoryReport` object (`SettingsCLIReportSchema`'s `$defs
    /// .categoryReport`). `added`/`updated`/`removed` are only written when
    /// given (see the file overview: export has nothing to compare against).
    private static func categoryReport(
        category: SettingsCategory, selected: Bool, count: Int,
        added: Int?, updated: Int?, removed: Int?, summary: String
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "category": .string(category.rawValue),
            "displayName": .string(category.displayName),
            "selected": .bool(selected),
            "count": .number(Double(count)),
            "summary": .string(summary),
        ]
        if let added { fields["added"] = .number(Double(added)) }
        if let updated { fields["updated"] = .number(Double(updated)) }
        if let removed { fields["removed"] = .number(Double(removed)) }
        return .object(fields)
    }

    /// Tallies one group's preview items into "how many added / changed /
    /// would be removed", the same way for a settings group (item-by-item)
    /// and a profiles group (`profileChanges`, which already carries the
    /// count by name).
    private static func addedUpdatedRemoved(
        for group: SettingsGroupPreview
    ) -> (added: Int, updated: Int, removed: Int) {
        if let profileChanges = group.profileChanges {
            return (profileChanges.added.count, profileChanges.updated.count, profileChanges.removed.count)
        }
        let added = group.items.filter { $0.change == .added }.count
        let updated = group.items.filter { $0.change == .changed }.count
        let removed = group.items.filter { $0.change == .removed }.count
        return (added, updated, removed)
    }

    private static func ignoredItem(_ item: SettingsIgnoredItem) -> JSONValue {
        var fields: [String: JSONValue] = [
            "name": .string(item.name),
            "reason": .string(reasonName(item.reason)),
            "explanation": .string(item.explanation),
        ]
        if let group = item.group { fields["group"] = .string(group) }
        if case .wrongGroup(let belongsIn) = item.reason { fields["belongsIn"] = .string(belongsIn.rawValue) }
        return .object(fields)
    }

    /// `SettingsIgnoredItem.Reason`'s case name, exactly as the schema's
    /// `ignoredItem.reason` enum spells it. The `neverImported` case's
    /// associated `SettingsNeverKind` is not carried into JSON: the plain
    /// English is already in `explanation`, and the schema was written
    /// (commit 6) without a second enum for it.
    private static func reasonName(_ reason: SettingsIgnoredItem.Reason) -> String {
        switch reason {
        case .unknownGroup:       return "unknownGroup"
        case .unknownSetting:     return "unknownSetting"
        case .neverImported:      return "neverImported"
        case .wrongGroup:         return "wrongGroup"
        case .unknownLeftOutName: return "unknownLeftOutName"
        case .unknownField:       return "unknownField"
        }
    }

    private static func stillNeededItem(_ need: SettingsCredentialNeed) -> JSONValue {
        var fields: [String: JSONValue] = [
            "title": .string(need.title),
            "location": .string(need.location),
        ]
        if let explanation = need.explanation { fields["explanation"] = .string(explanation) }
        switch need.status {
        case .missing:
            fields["status"] = .string("missing")
        case .couldNotCheck(let reason):
            fields["status"] = .string("couldNotCheck")
            fields["statusReason"] = .string(reason)
        }
        return .object(fields)
    }

    /// The same count wording `SettingsExport.reportLines` uses per
    /// category, so the JSON and text export reports never disagree.
    private static func exportSummary(for category: SettingsCategory, count: Int) -> String {
        let noun = category == .encodingProfiles ? "profile" : "setting"
        return SettingsImportReport.count(count, noun)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
