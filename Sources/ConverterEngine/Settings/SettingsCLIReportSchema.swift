// ============================================================================
// MeedyaConverter — SettingsCLIReportSchema (Issue #506 commit 6)
// Sources/ConverterEngine/Settings/SettingsCLIReportSchema.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// PROVISIONAL SPEC, written ahead of the code it describes. `meedya-convert
// settings export` and `meedya-convert settings import` (the #506 plan,
// section 6) are commit 7, and have not been written yet — this is commit 6.
// This file defines the JSON shape `--format json` must produce, worked out
// from:
//   - the plan's section 6 (the text report's content: a header, one row per
//     group, ignored items, the mode, "still needed" and "next launch"
//     lists);
//   - the engine types that content already comes from: `SettingsExport`
//     (`SettingsExporter.swift`), `SettingsImportPreview`,
//     `SettingsImportResult`, `SettingsIgnoredItem` and
//     `SettingsCredentialNeed` (`SettingsImporter.swift`,
//     `SettingsCredentialNeeds.swift`).
//
// Commit 7 MUST produce exactly this shape. If, once it is actually being
// built, this shape turns out not to fit — a field that can't be filled in
// cleanly, one that's missing — THIS FILE is what changes, together with
// `generate()` below and `SettingsSchemaTests`, in that commit. It must never
// be the case that commit 7 quietly emits something else while this schema
// sits uncorrected: that would defeat the entire point of pinning the
// contract now, which is to give commit 7 a target to build to rather than a
// shape invented while also writing the command.
//
// Why this exists at all in commit 6, before commit 7's code does: writing
// the contract down first, and checking it can't silently drift (the same
// generated-file-plus-test mechanism as `SettingsExportSchema`), is cheaper
// than discovering after commit 7 that its JSON output was never checked
// against anything.
//
// Deliberately loose: this report is read by scripts and other tools, not by
// MeedyaConverter itself, so nothing here needs the tight, registry-derived
// precision `SettingsExportSchema` has. Free-text fields (`summary`,
// `explanation`, the various report sentences) are simply `string`, with no
// attempt to pin their exact wording — that would make ordinary copy changes
// break a schema test for no safety benefit.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsCLIReportSchema

/// The JSON Schema for `meedya-convert settings … --format json`'s output.
/// See the file overview: this is a forward-looking contract for #506
/// commit 7, not a description of code that exists yet.
public enum SettingsCLIReportSchema {

    /// The schema's `$id`.
    public static let schemaID = "urn:mwbm:meedyaconverter:settings-cli-report:v1"

    /// The schema, as a `JSONValue`. See `generateData()` for the exact bytes
    /// committed to disk.
    public static func generate() -> JSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "$id": .string(schemaID),
            "title": .string("meedya-convert settings — JSON report"),
            "description": .string(
                "The “--format json” output of “meedya-convert settings export” and "
                    + "“meedya-convert settings import” (issue #506)."
            ),
            "$comment": .string(provisionalComment),
            "type": .string("object"),
            "required": .array(["command", "appVersion", "generatedAt", "categories"].map(JSONValue.string)),
            "additionalProperties": .bool(false),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([.string("export"), .string("import")]),
                    "description": .string("Which subcommand produced this report."),
                ]),
                "appVersion": .object([
                    "type": .string("string"),
                    "maxLength": .number(64),
                    "description": .string("The version of MeedyaConverter running the command."),
                ]),
                "generatedAt": .object([
                    "type": .string("string"),
                    "format": .string("date-time"),
                    "description": .string("When this report was produced."),
                ]),
                "file": .object([
                    "type": .string("string"),
                    "description": .string("The settings file path that was read (import) or written (export)."),
                ]),
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array(SettingsImportMode.allCases.map { .string($0.rawValue) }),
                    "description": .string(
                        "Import only: how the file was, or would be, combined with this Mac's settings."
                    ),
                ]),
                "applied": .object([
                    "type": .string("boolean"),
                    "description": .string(
                        "Import only: true once --apply has written the change; false for a preview "
                            + "(the default — see the plan's owner decision 2)."
                    ),
                ]),
                "categories": .object([
                    "type": .string("array"),
                    "description": .string(
                        "One entry per settings group the command touched, in the usual order "
                            + "(General, Encoding, Your encoding profiles, Connections, This Mac only)."
                    ),
                    "items": .object(["$ref": .string("#/$defs/categoryReport")]),
                ]),
                "warnings": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string(
                        "Cautions for risky settings selected for import (for example, a switched-on "
                            + "“delete source after encode”)."
                    ),
                ]),
                "crossChecks": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string(
                        "Import only: statements about things that will not work exactly as the other "
                            + "Mac had them (for example, a default profile this Mac does not have)."
                    ),
                ]),
                "replaceConfirmation": .object([
                    "type": .string("string"),
                    "description": .string("Import, replace mode only: one sentence naming what Replace removes."),
                ]),
                "ignored": .object([
                    "type": .string("array"),
                    "items": .object(["$ref": .string("#/$defs/ignoredItem")]),
                    "description": .string("Import only: things in the file that were not imported, and why."),
                ]),
                "stillNeeded": .object([
                    "type": .string("array"),
                    "items": .object(["$ref": .string("#/$defs/stillNeededItem")]),
                    "description": .string(
                        "Import only, after applying: passwords, keys and consents that still need "
                            + "entering on this Mac."
                    ),
                ]),
                "leftOut": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(SettingsLeftOutItem.allCases.map { .string($0.rawValue) }),
                    ]),
                    "description": .string(
                        "Export only: the names of things set up on this Mac that the file never carries."
                    ),
                ]),
                "takesEffectNextLaunch": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string(
                        "Import only, after applying: plain-English labels of settings that only take "
                            + "effect the next time MeedyaConverter opens."
                    ),
                ]),
            ]),
            "$defs": .object(definitions()),
        ])
    }

    /// The schema's bytes, exactly as committed at
    /// `docs/schemas/settings-cli-report-v1.schema.json`.
    public static func generateData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(generate())
    }

    private static let provisionalComment = """
    PROVISIONAL SPEC, not yet produced by any code. #506 commit 7 (the "meedya-convert \
    settings" command) has not been written yet; this file defines the shape it must produce, \
    worked out from the plan (.claude/plans/settings-export-import-plan.md, section 6) and from \
    the engine's SettingsExport, SettingsImportPreview and SettingsImportResult types. If commit \
    7 finds this shape does not fit once it is actually being built, THIS FILE is what changes, \
    together with SettingsCLIReportSchema.generate() and SettingsSchemaTests — never a silent \
    mismatch between what the CLI prints and what this schema describes.
    """

    // MARK: - `$defs`

    private static func definitions() -> [String: JSONValue] {
        [
            "categoryReport": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["category", "displayName", "selected", "count"].map(JSONValue.string)),
                "description": .string("One settings group's counts."),
                "properties": .object([
                    "category": .object([
                        "type": .string("string"),
                        "enum": .array(SettingsCategory.allCases.map { .string($0.rawValue) }),
                        "description": .string(
                            "The group's internal name, exactly as SettingsCategory and the settings "
                                + "file itself use it."
                        ),
                    ]),
                    "displayName": .object([
                        "type": .string("string"),
                        "description": .string("The group's plain-English name (SettingsCategory.displayName)."),
                    ]),
                    "selected": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether this group was ticked (chosen with --categories, or the default)."),
                    ]),
                    "count": .object([
                        "type": .string("integer"),
                        "minimum": .number(0),
                        "description": .string("How many settings, or profiles, the file has for this group."),
                    ]),
                    "added": .object([
                        "type": .string("integer"),
                        "minimum": .number(0),
                        "description": .string("Import only: how many items this group adds."),
                    ]),
                    "updated": .object([
                        "type": .string("integer"),
                        "minimum": .number(0),
                        "description": .string("Import only: how many items this group changes."),
                    ]),
                    "removed": .object([
                        "type": .string("integer"),
                        "minimum": .number(0),
                        "description": .string(
                            "Import, replace mode only: how many of this Mac's items this group removes."
                        ),
                    ]),
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string(
                            "One plain-English sentence summarising this group, the same wording the "
                                + "text report and the app's preview use."
                        ),
                    ]),
                ]),
            ]),
            "ignoredItem": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["name", "reason", "explanation"].map(JSONValue.string)),
                "description": .string(
                    "Something in the imported file that was not imported. Never fatal: the rest of "
                        + "the file still imports (SettingsIgnoredItem)."
                ),
                "properties": .object([
                    "group": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The group name as written in the file, when the ignored item was inside "
                                + "one. Absent for a problem with the file's top level."
                        ),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("The setting, group or field name, exactly as written in the file."),
                    ]),
                    "reason": .object([
                        "type": .string("string"),
                        "enum": .array([
                            "unknownGroup", "unknownSetting", "neverImported", "wrongGroup",
                            "unknownLeftOutName", "unknownField",
                        ].map(JSONValue.string)),
                        "description": .string("Which of SettingsIgnoredItem.Reason applies."),
                    ]),
                    "belongsIn": .object([
                        "type": .string("string"),
                        "enum": .array(SettingsCategory.allCases.map { .string($0.rawValue) }),
                        "description": .string(
                            "Only present when reason is \"wrongGroup\": the group the setting actually belongs in."
                        ),
                    ]),
                    "explanation": .object([
                        "type": .string("string"),
                        "description": .string(
                            "One plain sentence saying what was ignored and why (SettingsIgnoredItem.explanation)."
                        ),
                    ]),
                ]),
            ]),
            "stillNeededItem": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["title", "location", "status"].map(JSONValue.string)),
                "description": .string(
                    "A password, key, key file or consent that still needs entering on this Mac "
                        + "(SettingsCredentialNeed)."
                ),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("What it is (“TMDB key”, “SFTP server ‘NAS’ password”)."),
                    ]),
                    "location": .object([
                        "type": .string("string"),
                        "description": .string("Where to set it up (SettingsCredentialNeed.location)."),
                    ]),
                    "explanation": .object([
                        "type": .string("string"),
                        "description": .string("Why it was not copied, when worth saying."),
                    ]),
                    "status": .object([
                        "type": .string("string"),
                        "enum": .array([.string("missing"), .string("couldNotCheck")]),
                        "description": .string(
                            "Whether it is definitely missing, or this Mac could not check."
                        ),
                    ]),
                    "statusReason": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only present when status is \"couldNotCheck\": why it could not be "
                                + "checked. Never implies the item is actually missing."
                        ),
                    ]),
                ]),
            ]),
        ]
    }
}
