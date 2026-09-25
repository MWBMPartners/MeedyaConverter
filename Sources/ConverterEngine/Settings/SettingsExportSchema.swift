// ============================================================================
// MeedyaConverter — SettingsExportSchema (Issue #506 commit 6)
// Sources/ConverterEngine/Settings/SettingsExportSchema.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Builds the JSON Schema (draft 2020-12) that describes a settings file —
// the same file `SettingsExporter` writes and `SettingsImporter` reads —
// straight FROM `SettingsKeyRegistry`, so the schema cannot say something the
// registry itself does not say.
//
// `generate()` returns the schema as a `JSONValue` (the same small "any JSON
// value" type the settings file itself is built from). `generateData()`
// turns that into the exact bytes committed at
// `docs/schemas/settings-export-v1.schema.json`: pretty-printed, with sorted
// keys and unescaped "/", the same formatting `SettingsDocument.makeData`
// uses, so the file is stable and readable in a diff.
//
// KEEPING THE COMMITTED FILE IN STEP WITH THIS CODE. The file on disk is
// GENERATED, never hand-edited. `SettingsSchemaTests
// .test_committedExportSchemaMatchesGenerated` fails if it ever differs from
// `generateData()`. To regenerate it after a genuine change here, run:
//
//   MEEDYACONVERTER_REGENERATE_SCHEMAS=1 swift test \
//     --filter SettingsSchemaTests/test_committedExportSchemaMatchesGenerated
//
// (or the equivalent single-test run through this repository's local test
// harness — see `.claude/local-test-harness.md`). That test, when the
// environment variable is set, overwrites the committed file instead of
// comparing against it, then re-reads it to prove the write matches.
//
// THE THREE LEAK SAFEGUARDS. These do not depend on the registry filtering
// secrets out (that already happens), so they check the actual, redacted
// SHAPE `SettingsValueCodecs.swift` writes, independently of it:
//   - an SFTP server's password is always the empty string, at the exact
//     path Swift's own `Codable` puts it: `authMethod.password._0` (proven
//     empirically: `AuthMethod.password("x")` encodes as
//     `{"password":{"_0":"x"}}`, `.keyFile("x")` as `{"keyFile":{"_0":"x"}}`,
//     `.agent` as `{"agent":{}}`);
//   - a cloud destination's access token (for S3, the access key ID) is
//     always the empty string;
//   - a cloud destination's refresh token and S3 secret key are never
//     PRESENT at all: `CloudStorageConfig.exportForm()` sets them to `nil`,
//     and Swift's synthesised `Encodable` omits a `nil` optional's key
//     entirely, so `additionalProperties: false` with no "refreshToken" or
//     "secretAccessKey" listed makes either one's presence a schema failure.
//
// WHERE THIS IS DELIBERATELY LOOSE, AND WHY.
//   - `EncodingProfile`, `ConditionalRule` and `EncodingPipeline`: only their
//     identity fields (`id`, `name`) are required, with
//     `additionalProperties: true`. `EncodingProfile` alone has about 45
//     fields, `EncodingPipeline` carries arbitrary per-step `config`
//     dictionaries, and `ConditionalRule` carries an open-ended condition
//     list; the REAL check on all three is `SettingsImporter` decoding them
//     into their actual Swift type, which drops anything the type does not
//     declare. Duplicating that shape here would drift the moment either
//     type gains a field, and would give no more safety than the decode
//     already provides.
//   - Addresses (`emailSMTPHost`, `mediaServerHost`, git remotes, …): this
//     schema only checks they are text within a sane length. The real rule —
//     never a user name, password or query string — is
//     `SettingsAddressCheck`, which needs logic (parsing a URL's authority
//     part) the mini validator's fixed keyword list cannot express.
//   - Array lengths (at most so many email recipients, keyboard shortcuts,
//     items in `notIncluded`, …): the mini validator supports no
//     `minItems`/`maxItems` keyword (see its own file), so this schema
//     cannot state them; `SettingsValueCodec.maximumListItems` and the
//     per-field length checks in `SettingsDocument` and
//     `SettingsValueCodecs.swift` are the real limits.
//
// HONEST LIMIT ON THE VALIDATOR ITSELF. This schema is checked, in this
// repository, only by `SettingsSchemaMiniValidator`
// (`Tests/ConverterEngineTests/`), a small TEST-ONLY checker that supports a
// fixed, short list of JSON Schema keywords and refuses to run against any
// schema using a keyword outside that list. See that file's header for
// exactly what it can and cannot catch. A real JSON Schema validator (this
// project adds no such dependency; see `Package.swift`) would naturally
// support more of draft 2020-12 than the checks below exercise.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsExportSchema

/// Builds the JSON Schema for a MeedyaConverter settings file, from
/// `SettingsKeyRegistry`. See the file overview.
public enum SettingsExportSchema {

    /// The schema's `$id`. Never changes for format version 1; a later,
    /// INCOMPATIBLE change to the envelope itself (not to which settings
    /// exist) would need a new `$id` alongside `SettingsDocument
    /// .currentVersion` going up.
    public static let schemaID = "urn:mwbm:meedyaconverter:settings-export:v1"

    /// The schema, as a `JSONValue`. See `generateData()` for the exact bytes
    /// committed to disk.
    public static func generate() -> JSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "$id": .string(schemaID),
            "title": .string("MeedyaConverter settings export"),
            "description": .string(
                "A settings file written by MeedyaConverter's Import & Export screen, or by "
                    + "“meedya-convert settings export”. Read back by MeedyaConverter's importer, on "
                    + "the same Mac or another one."
            ),
            "$comment": .string(honestLimitComment),
            "type": .string("object"),
            "required": .array(rootFieldOrder.map(JSONValue.string)),
            "additionalProperties": .bool(false),
            "properties": .object([
                "format": .object([
                    "type": .string("string"),
                    "const": .string(SettingsDocument.formatIdentifier),
                    "description": .string(
                        "Always “\(SettingsDocument.formatIdentifier)”. Says the file is a "
                            + "MeedyaConverter settings file, not something else that happens to be JSON."
                    ),
                ]),
                "version": .object([
                    "type": .string("integer"),
                    "const": .number(Double(SettingsDocument.currentVersion)),
                    "description": .string(
                        "The settings file format version. This schema describes exactly what "
                            + "version \(SettingsDocument.currentVersion) writes; it does not describe "
                            + "any other version."
                    ),
                ]),
                "exportedAt": .object([
                    "type": .string("string"),
                    "format": .string("date-time"),
                    "description": .string("When the file was written."),
                ]),
                "appVersion": .object([
                    "type": .string("string"),
                    "maxLength": .number(64),
                    "description": .string("The version of MeedyaConverter that wrote the file."),
                ]),
                "categories": categoriesSchema(),
                "notIncluded": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(SettingsLeftOutItem.allCases.map { .string($0.rawValue) }),
                    ]),
                    "description": .string(
                        "Names, from this fixed list, of passwords, keys and consents that were set "
                            + "up on the Mac that made this file but are never copied here. Lets the "
                            + "importing Mac say, for example, “TMDB still needs a key”. Never holds a "
                            + "value — only ever one of these names."
                    ),
                ]),
            ]),
            "$defs": .object(definitions()),
        ])
    }

    /// The schema's bytes, exactly as committed at
    /// `docs/schemas/settings-export-v1.schema.json`: pretty-printed, keys
    /// sorted, "/" left unescaped (the same formatting
    /// `SettingsDocument.makeData` uses for the settings file itself).
    public static func generateData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(generate())
    }

    // MARK: - The wrapper

    /// The envelope's own fields, in the order `SettingsDocument.Field.all`
    /// lists them conceptually (that set is private to `SettingsDocument`;
    /// this is the same six names, kept here so this file has no need to see
    /// inside it).
    private static let rootFieldOrder = ["format", "version", "exportedAt", "appVersion", "categories", "notIncluded"]

    private static let honestLimitComment = """
    This schema describes exactly what THIS version of MeedyaConverter writes. Reading a file \
    back is deliberately more forgiving than this schema: SettingsImporter reports and ignores \
    an unknown group, an unknown setting, or a setting sitting in the wrong group, rather than \
    refusing the whole file, so a future version can add a group (#505) or a setting without \
    breaking an older one's export. Three checks matter more than the rest, because they are a \
    second, independent line of defence against a secret ever reaching a settings file: an SFTP \
    server's password must be the empty string, at authMethod.password._0; a cloud \
    destination's access token (or, for S3, its access key ID) must be the empty string; and its \
    refresh token and S3 secret key must be absent entirely. Everywhere else this schema is \
    deliberately loose — array length limits, the "no user name, password or query string in an \
    address" rule, and the full shape of encoding profiles, conditional rules and saved \
    pipelines are all checked by MeedyaConverter's own code, not by this file, because the \
    test-only checker this schema is validated against (SettingsSchemaMiniValidator) supports \
    only a small, fixed list of JSON Schema keywords. See SettingsExportSchema.swift's header \
    for the full list of what is loose and why.
    """

    // MARK: - `categories`

    private static func categoriesSchema() -> JSONValue {
        var properties: [String: JSONValue] = [:]
        for category in SettingsCategory.allCases {
            properties[category.rawValue] = categorySectionSchema(category)
        }
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "description": .string(
                "Only the groups the person ticked are present. This lists every group THIS "
                    + "version can write; SettingsImporter accepts a group it doesn't recognise too "
                    + "(reported, ignored), which this schema deliberately does not allow for."
            ),
            "properties": .object(properties),
        ])
    }

    /// One group's part of the file: `{ "settings": { … } }` for every group
    /// except `encodingProfiles`, which is `{ "profiles": [ … ] }` (see
    /// `SettingsSectionHandlers.swift`).
    private static func categorySectionSchema(_ category: SettingsCategory) -> JSONValue {
        if category == .encodingProfiles {
            return .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("profiles")]),
                "description": .string(category.explanation),
                "properties": .object([
                    "profiles": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Your encoding profiles, merged by id. Built-in profiles are never "
                                + "included: every copy of MeedyaConverter already has them."
                        ),
                        "items": .object(["$ref": .string("#/$defs/encodingProfile")]),
                    ]),
                ]),
            ])
        }

        var settingsProperties: [String: JSONValue] = [:]
        for entry in SettingsKeyRegistry.entries(in: category) {
            guard let rules = entry.rules else { continue }   // .never entries can't reach here anyway
            settingsProperties[entry.key] = keySchema(label: entry.label, rules: rules)
        }
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("settings")]),
            "description": .string(category.explanation),
            "properties": .object([
                "settings": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(settingsProperties),
                ]),
            ]),
        ])
    }

    // MARK: - One setting

    /// One registry entry's schema: its value's shape (from `rules.kind`),
    /// with `description` set to the registry's own plain-English `label` —
    /// the same text used as the setting's location and, in the app, its
    /// "what's never included" wording.
    private static func keySchema(label: String, rules: SettingsValueRules) -> JSONValue {
        guard case .object(var fields) = valueKindSchema(rules.kind) else {
            // Every branch of `valueKindSchema` returns `.object`; this only
            // guards against that ever changing without this line changing too.
            return .object(["description": .string(label)])
        }
        fields["description"] = .string(label)
        return .object(fields)
    }

    private static func valueKindSchema(_ kind: SettingsValueKind) -> JSONValue {
        switch kind {
        case .bool:
            return .object(["type": .string("boolean")])

        case .int(let range):
            var fields: [String: JSONValue] = ["type": .string("integer")]
            if let range {
                fields["minimum"] = .number(Double(range.lowerBound))
                fields["maximum"] = .number(Double(range.upperBound))
            }
            return .object(fields)

        case .double(let range):
            var fields: [String: JSONValue] = ["type": .string("number")]
            if let range {
                fields["minimum"] = .number(range.lowerBound)
                fields["maximum"] = .number(range.upperBound)
            }
            return .object(fields)

        case .string(let allowed, let maxLength):
            var fields: [String: JSONValue] = ["type": .string("string"), "maxLength": .number(Double(maxLength))]
            if let allowed {
                fields["enum"] = .array(allowed.map(JSONValue.string))
            }
            return .object(fields)

        case .address:
            // Honest limit: see the file overview and the `$comment` above.
            // The "no user name, password or query string" rule is
            // `SettingsAddressCheck`'s job, not this schema's.
            return .object([
                "type": .string("string"),
                "maxLength": .number(Double(SettingsValueKind.defaultMaxStringLength)),
            ])

        case .filePath:
            // Empty (meaning "find it automatically"), or starting with "/"
            // or "~" — the same rule as `SettingsValueCodec.filePathProblem`,
            // minus the control-character check that rule also makes (no
            // keyword here expresses "no control characters").
            return .object([
                "type": .string("string"),
                "maxLength": .number(Double(SettingsValueKind.defaultMaxStringLength)),
                "pattern": .string("^$|^[/~]"),
            ])

        case .hexColour:
            return .object([
                "type": .string("string"),
                "pattern": .string("^#[0-9A-Fa-f]{6}$"),
            ])

        case .json(let blob):
            return blobSchema(blob)
        }
    }

    /// The shape of one JSON-blob setting's stored value (a single object, or
    /// a list of them — see `SettingsJSONBlob.storage` and
    /// `SettingsBlobCodec`).
    private static func blobSchema(_ blob: SettingsJSONBlob) -> JSONValue {
        switch blob {
        case .customTheme:
            return .object(["$ref": .string("#/$defs/customTheme")])
        case .keyboardShortcuts:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/shortcutBinding")]),
            ])
        case .emailRecipients:
            return .object([
                "type": .string("array"),
                "items": .object(["type": .string("string"), "maxLength": .number(320)]),
            ])
        case .conditionalRules:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/conditionalRule")]),
            ])
        case .encodingPipelines:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/encodingPipeline")]),
            ])
        case .renderFarmAgents:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/renderFarmAgent")]),
            ])
        case .sftpProfiles:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/sftpServer")]),
            ])
        case .cloudStorageProfiles:
            return .object([
                "type": .string("array"),
                "items": .object(["$ref": .string("#/$defs/cloudStorageDestination")]),
            ])
        }
    }

    // MARK: - `$defs`

    private static func definitions() -> [String: JSONValue] {
        [
            "encodingProfile": looseEngineModelSchema(
                typeName: "EncodingProfile",
                sourcePath: "Sources/ConverterEngine/Encoding/EncodingProfile.swift",
                extraNote: "It has about 45 fields in total."
            ),
            "conditionalRule": looseEngineModelSchema(
                typeName: "ConditionalRule",
                sourcePath: "Sources/ConverterEngine/Encoding/ConditionalRule.swift",
                extraNote: nil
            ),
            "encodingPipeline": looseEngineModelSchema(
                typeName: "EncodingPipeline",
                sourcePath: "Sources/ConverterEngine/Encoding/EncodingPipeline.swift",
                extraNote: "Its steps carry an open-ended per-step configuration dictionary."
            ),
            "customTheme": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["id", "name", "accentHex"].map(JSONValue.string)),
                "description": .string("The chosen colour theme (ThemeManager's CustomTheme)."),
                "properties": .object([
                    "id": uuidSchema(),
                    "name": .object(["type": .string("string"), "maxLength": .number(256)]),
                    "accentHex": .object(["type": .string("string"), "pattern": .string("^#[0-9A-Fa-f]{6}$")]),
                    "sidebarTintHex": .object(["type": .string("string"), "pattern": .string("^#[0-9A-Fa-f]{6}$")]),
                ]),
            ]),
            "shortcutBinding": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["id", "action", "label", "key", "modifiers"].map(JSONValue.string)),
                "description": .string("One keyboard shortcut (KeyboardShortcutManager's ShortcutBinding)."),
                "properties": .object([
                    "id": uuidSchema(),
                    "action": .object(["type": .string("string"), "maxLength": .number(256)]),
                    "label": .object(["type": .string("string"), "maxLength": .number(256)]),
                    "key": .object(["type": .string("string"), "maxLength": .number(32)]),
                    "modifiers": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string"), "maxLength": .number(32)]),
                    ]),
                ]),
            ]),
            "renderFarmAgent": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(
                    ["id", "displayName", "host", "port", "discovered", "hardwareEncoders"].map(JSONValue.string)
                ),
                "description": .string(
                    "A render-farm agent you added, or MeedyaConverter discovered on the network. "
                        + "No secret fields (RenderFarmAgentInfo)."
                ),
                "properties": .object([
                    "id": uuidSchema(),
                    "displayName": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "host": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "port": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(65_535)]),
                    "sshUsername": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "discovered": .object(["type": .string("boolean")]),
                    "architecture": .object(["type": .string("string"), "maxLength": .number(256)]),
                    "hardwareEncoders": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string"), "maxLength": .number(64)]),
                    ]),
                ]),
            ]),
            "sftpServer": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(
                    ["id", "host", "port", "username", "authMethod", "remotePath", "label"].map(JSONValue.string)
                ),
                "description": .string(
                    "An SFTP server (SFTPServerConfig). The password is always written as an empty "
                        + "string, whatever this Mac has saved for it — see \"authMethod\" below."
                ),
                "properties": .object([
                    "id": uuidSchema(),
                    "host": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "port": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(65_535)]),
                    "username": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "remotePath": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "label": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "authMethod": sftpAuthMethodSchema(),
                ]),
            ]),
            "cloudStorageDestination": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array(["id", "provider", "accessToken", "remotePath", "label"].map(JSONValue.string)),
                "description": .string(
                    "A cloud storage destination (CloudStorageConfig). Leak safeguards: the access "
                        + "token (for S3, the access key ID) is always the empty string, and the "
                        + "refresh token and S3 secret key are never present, whatever this Mac has "
                        + "saved for it."
                ),
                "properties": .object([
                    "id": uuidSchema(),
                    "provider": .object([
                        "type": .string("string"),
                        "enum": .array(CloudStorageProvider.allCases.map { .string($0.rawValue) }),
                    ]),
                    // LEAK SAFEGUARD 2 of 3: always blanked by
                    // `CloudStorageConfig.exportForm()`.
                    "accessToken": .object(["type": .string("string"), "const": .string("")]),
                    "remotePath": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "label": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "bucket": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "region": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    "endpoint": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    // LEAK SAFEGUARD 3 of 3: "refreshToken" and
                    // "secretAccessKey" are deliberately NOT listed here.
                    // `additionalProperties: false` means either one being
                    // present at all — with any value — fails the schema.
                    // `exportForm()` sets both to `nil`, and Swift's
                    // synthesised `Encodable` omits a `nil` optional's key
                    // entirely, so a clean export never has them; a file
                    // that somehow did would be refused, not silently
                    // accepted.
                ]),
            ]),
        ]
    }

    /// The three-shape `AuthMethod` enum, encoded the way Swift's
    /// synthesised `Codable` writes it: `{"password":{"_0":"…"}}`,
    /// `{"keyFile":{"_0":"…"}}` or `{"agent":{}}` (proven in this file's own
    /// header comment). The mini validator has no `oneOf`, so this cannot
    /// insist on EXACTLY one of the three keys; what it CAN insist on, and
    /// does, is that if "password" is present at all, its value is the
    /// leak-safeguard shape below.
    private static func sftpAuthMethodSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "description": .string(
                "Exactly one of these three, the way Swift's Codable writes AuthMethod. Never a "
                    + "plaintext password — see \"password\" below."
            ),
            "properties": .object([
                // LEAK SAFEGUARD 1 of 3.
                "password": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("_0")]),
                    "description": .string(
                        "Leak safeguard: always the empty string, whatever password this Mac has "
                            + "saved for this server (SFTPServerConfig.exportForm())."
                    ),
                    "properties": .object([
                        "_0": .object(["type": .string("string"), "const": .string("")]),
                    ]),
                ]),
                "keyFile": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("_0")]),
                    "description": .string("A key file's path on the Mac that made the file. Not a secret."),
                    "properties": .object([
                        "_0": .object(["type": .string("string"), "maxLength": .number(4096)]),
                    ]),
                ]),
                "agent": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "description": .string("Use the running SSH agent. Carries no value."),
                    "properties": .object([:]),
                ]),
            ]),
        ])
    }

    // MARK: - Small shared shapes

    private static func uuidSchema() -> JSONValue {
        .object(["type": .string("string"), "format": .string("uuid")])
    }

    /// `EncodingProfile`, `ConditionalRule` and `EncodingPipeline`: only
    /// their identity fields are checked here (see the file overview for
    /// why); the real check is `SettingsImporter` decoding the whole thing
    /// into its actual Swift type.
    private static func looseEngineModelSchema(typeName: String, sourcePath: String, extraNote: String?) -> JSONValue {
        var description = "validated on import by decoding into \(typeName) (\(sourcePath)). Only its "
            + "identity fields (id, name) are checked by this schema: the importer's own decode, which "
            + "drops anything the type doesn't declare, is the real check on the rest of its shape."
        if let extraNote {
            description += " \(extraNote)"
        }
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(true),
            "required": .array([.string("id"), .string("name")]),
            "description": .string(description),
            "properties": .object([
                "id": uuidSchema(),
                "name": .object(["type": .string("string")]),
            ]),
        ])
    }
}
