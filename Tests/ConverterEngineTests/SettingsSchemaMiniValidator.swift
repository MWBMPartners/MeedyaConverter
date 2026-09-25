// ============================================================================
// MeedyaConverter — SettingsSchemaMiniValidator (Issue #506 commit 6)
// Tests/ConverterEngineTests/SettingsSchemaMiniValidator.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// TEST-ONLY. A small, from-scratch JSON Schema (draft 2020-12) checker, so
// `SettingsSchemaTests` can prove a real settings export actually validates
// against `docs/schemas/settings-export-v1.schema.json`, without adding a
// JSON Schema library as a dependency (checked: `Package.swift`, CI and
// `scripts/` use none — the #506 plan's own search came up empty too).
//
// It supports EXACTLY this keyword list, on purpose, and nothing else:
//   type, properties, required, additionalProperties, items, enum, const,
//   minimum, maximum, minLength, maxLength, minProperties, maxProperties,
//   pattern, format (only "date-time" and "uuid"), and local $ref / $defs.
// It also recognises, but never applies, four purely documentary keywords:
// description, $comment, title, $id, $schema. Every schema object passed to
// it — the WHOLE document, including every `$defs` entry, whether or not
// anything actually `$ref`s to it — is walked first for keywords outside
// that list, and the whole check FAILS if it finds one
// (`checkNoUnsupportedKeywords`). So a schema can never smuggle in something
// this checker would otherwise silently ignore.
//
// WHAT IT CANNOT CATCH (read this before trusting a green result):
//   - It is not a conformance-tested JSON Schema implementation. It has not
//     been run against the official JSON Schema test suite, and draft
//     2020-12 has keywords and edge cases (oneOf, anyOf, not, if/then/else,
//     unevaluatedProperties, non-local $ref, numeric "multipleOf",
//     $anchor, …) this checker simply refuses outright by design, rather
//     than mishandling.
//   - `minItems` / `maxItems` / `uniqueItems` are NOT in the supported list,
//     deliberately: nothing here checks array length or duplicate array
//     items. `SettingsExportSchema`'s own header explains why the real
//     export schema has no array-length keywords to check in the first
//     place.
//   - "type" only ever accepts ONE type name as a plain string (never an
//     array of types, and never a boolean schema such as `"items": true`).
//     `SettingsExportSchema` and `SettingsCLIReportSchema` never produce
//     either form, so this is a limit on the checker, not a gap in what it
//     checks here.
//   - `pattern` is checked with `NSRegularExpression` (ICU regex), not the
//     ECMA 262 dialect JSON Schema formally specifies. The patterns this
//     project's schemas actually use (a hex colour, a leading "/" or "~")
//     behave identically under both.
//   - `format: date-time` accepts anything `ISO8601DateFormatter` accepts
//     (with or without fractional seconds); it is looser than RFC 3339.
//   - Duplicate keys inside one JSON object cannot be detected: like
//     `SettingsDocument`, this reads schemas and data through `JSONValue`,
//     and Foundation's decoder keeps only the last of a duplicated key
//     before either ever sees the object.
//   - `$ref` only resolves a LOCAL pointer of the exact shape `#/a/b/c`
//     (walked by `/`-separated object keys against the schema's own root).
//     A remote `$ref`, a JSON Pointer with `~0`/`~1` escapes, or `$anchor`
//     is refused, not resolved.
// ---------------------------------------------------------------------------

import Foundation
@testable import ConverterEngine

// MARK: - SettingsSchemaMiniValidatorError

/// Why `SettingsSchemaMiniValidator` refused a schema, or why a value did not
/// validate against one. `path` is a "$.a.b[2].c"-style breadcrumb into the
/// value being checked (or, for `unsupportedKeyword`, into the SCHEMA).
enum SettingsSchemaMiniValidatorError: Error, CustomStringConvertible, Equatable {
    case unsupportedKeyword(String, path: String)
    case malformedSchema(String, path: String)
    case typeMismatch(expected: String, path: String)
    case missingRequiredProperty(String, path: String)
    case additionalPropertyNotAllowed(String, path: String)
    case notInEnum(path: String)
    case constMismatch(path: String)
    case belowMinimum(path: String)
    case aboveMaximum(path: String)
    case tooShort(path: String)
    case tooLong(path: String)
    case tooFewProperties(path: String)
    case tooManyProperties(path: String)
    case patternMismatch(path: String)
    case formatMismatch(format: String, path: String)
    case refNotFound(String, path: String)

    var description: String {
        switch self {
        case .unsupportedKeyword(let keyword, let path):
            return "schema keyword \"\(keyword)\" at \(path) is outside what SettingsSchemaMiniValidator supports"
        case .malformedSchema(let reason, let path):
            return "schema at \(path) is malformed: \(reason)"
        case .typeMismatch(let expected, let path):
            return "\(path) should be \(expected)"
        case .missingRequiredProperty(let name, let path):
            return "\(path) is missing required property \"\(name)\""
        case .additionalPropertyNotAllowed(let name, let path):
            return "\(path) has property \"\(name)\", which additionalProperties: false does not allow"
        case .notInEnum(let path):
            return "\(path) is not one of the accepted values"
        case .constMismatch(let path):
            return "\(path) does not equal the fixed value the schema requires"
        case .belowMinimum(let path):
            return "\(path) is below the schema's minimum"
        case .aboveMaximum(let path):
            return "\(path) is above the schema's maximum"
        case .tooShort(let path):
            return "\(path) is shorter than the schema's minLength"
        case .tooLong(let path):
            return "\(path) is longer than the schema's maxLength"
        case .tooFewProperties(let path):
            return "\(path) has fewer properties than the schema's minProperties"
        case .tooManyProperties(let path):
            return "\(path) has more properties than the schema's maxProperties"
        case .patternMismatch(let path):
            return "\(path) does not match the schema's pattern"
        case .formatMismatch(let format, let path):
            return "\(path) is not a valid \"\(format)\""
        case .refNotFound(let ref, let path):
            return "$ref \"\(ref)\" at \(path) does not resolve to anything in the schema"
        }
    }
}

// MARK: - SettingsSchemaMiniValidator

enum SettingsSchemaMiniValidator {

    /// Every keyword this checker knows about. The four documentary ones are
    /// recognised and skipped; every other one here is actually applied.
    static let supportedKeywords: Set<String> = [
        "type", "properties", "required", "additionalProperties", "items", "enum", "const",
        "minimum", "maximum", "minLength", "maxLength", "minProperties", "maxProperties",
        "pattern", "format", "$ref", "$defs",
        "description", "$comment", "title", "$id", "$schema",
    ]

    /// Checks `data` against `schema` (the schema's own root, used to resolve
    /// any `$ref` inside it). Throws the first problem found, naming a path
    /// into `data`; throws naming a path into the SCHEMA if the schema itself
    /// uses an unsupported keyword anywhere, even in a `$defs` entry nothing
    /// references.
    static func validate(_ data: JSONValue, against schema: JSONValue) throws {
        try checkNoUnsupportedKeywords(in: schema, path: "$")
        try validate(data, schema: schema, root: schema, path: "$")
    }

    /// Only the "does this schema use anything unsupported?" half of
    /// `validate`, for a test that wants to check a schema on its own
    /// (`SettingsSchemaTests.test_validatorRejectsAnUnsupportedKeyword`).
    static func checkNoUnsupportedKeywords(in schema: JSONValue) throws {
        try checkNoUnsupportedKeywords(in: schema, path: "$")
    }

    // MARK: Keyword whitelist (whole document, including unreferenced $defs)

    private static func checkNoUnsupportedKeywords(in schema: JSONValue, path: String) throws {
        guard case .object(let fields) = schema else {
            throw SettingsSchemaMiniValidatorError.malformedSchema("a schema must be a JSON object", path: path)
        }
        for key in fields.keys where !supportedKeywords.contains(key) {
            throw SettingsSchemaMiniValidatorError.unsupportedKeyword(key, path: path)
        }
        // Recurse into every place a sub-schema can appear, so an unused
        // `$defs` entry cannot hide a keyword this checker does not support.
        if case .object(let properties)? = fields["properties"] {
            for (name, subschema) in properties {
                try checkNoUnsupportedKeywords(in: subschema, path: "\(path).properties.\(name)")
            }
        }
        if let items = fields["items"] {
            try checkNoUnsupportedKeywords(in: items, path: "\(path).items")
        }
        if case .object(let defs)? = fields["$defs"] {
            for (name, subschema) in defs {
                try checkNoUnsupportedKeywords(in: subschema, path: "\(path).$defs.\(name)")
            }
        }
        // "required" holds plain strings; "enum" and "const" hold plain
        // data values, never sub-schemas; "$ref" is a plain string. None of
        // those need recursing into.
    }

    // MARK: $ref resolution (local pointers only: "#/a/b/c")

    private static func resolveRef(_ ref: String, root: JSONValue, path: String) throws -> JSONValue {
        guard ref.hasPrefix("#/") else {
            throw SettingsSchemaMiniValidatorError.malformedSchema(
                "only a local $ref of the form \"#/a/b/c\" is supported, found \"\(ref)\"", path: path
            )
        }
        var current = root
        for segment in ref.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
            guard case .object(let fields) = current, let next = fields[String(segment)] else {
                throw SettingsSchemaMiniValidatorError.refNotFound(ref, path: path)
            }
            current = next
        }
        return current
    }

    // MARK: Validation proper

    private static func validate(_ data: JSONValue, schema: JSONValue, root: JSONValue, path: String) throws {
        guard case .object(let fields) = schema else {
            throw SettingsSchemaMiniValidatorError.malformedSchema("a schema must be a JSON object", path: path)
        }

        if case .string(let ref)? = fields["$ref"] {
            let target = try resolveRef(ref, root: root, path: path)
            try validate(data, schema: target, root: root, path: path)
        }

        if case .string(let typeName)? = fields["type"] {
            try checkType(data, typeName: typeName, path: path)
        }

        if case .array(let allowed)? = fields["enum"] {
            guard allowed.contains(data) else { throw SettingsSchemaMiniValidatorError.notInEnum(path: path) }
        }

        if let constValue = fields["const"] {
            guard constValue == data else { throw SettingsSchemaMiniValidatorError.constMismatch(path: path) }
        }

        switch data {
        case .number(let value):
            if case .number(let minimum)? = fields["minimum"], value < minimum {
                throw SettingsSchemaMiniValidatorError.belowMinimum(path: path)
            }
            if case .number(let maximum)? = fields["maximum"], value > maximum {
                throw SettingsSchemaMiniValidatorError.aboveMaximum(path: path)
            }

        case .string(let text):
            if case .number(let minLength)? = fields["minLength"], Double(text.count) < minLength {
                throw SettingsSchemaMiniValidatorError.tooShort(path: path)
            }
            if case .number(let maxLength)? = fields["maxLength"], Double(text.count) > maxLength {
                throw SettingsSchemaMiniValidatorError.tooLong(path: path)
            }
            if case .string(let pattern)? = fields["pattern"] {
                try checkPattern(text, pattern: pattern, path: path)
            }
            if case .string(let format)? = fields["format"] {
                try checkFormat(text, format: format, path: path)
            }

        case .object(let dataFields):
            if case .number(let minProperties)? = fields["minProperties"], Double(dataFields.count) < minProperties {
                throw SettingsSchemaMiniValidatorError.tooFewProperties(path: path)
            }
            if case .number(let maxProperties)? = fields["maxProperties"], Double(dataFields.count) > maxProperties {
                throw SettingsSchemaMiniValidatorError.tooManyProperties(path: path)
            }
            var propertySchemas: [String: JSONValue] = [:]
            if case .object(let properties)? = fields["properties"] {
                propertySchemas = properties
            }
            if case .array(let requiredNames)? = fields["required"] {
                for case .string(let name) in requiredNames where dataFields[name] == nil {
                    throw SettingsSchemaMiniValidatorError.missingRequiredProperty(name, path: path)
                }
            }
            let additionalAllowed: Bool
            switch fields["additionalProperties"] {
            case .bool(let allowed)?: additionalAllowed = allowed
            case nil: additionalAllowed = true   // JSON Schema's own default
            default:
                throw SettingsSchemaMiniValidatorError.malformedSchema(
                    "additionalProperties must be true or false", path: path
                )
            }
            for (key, value) in dataFields {
                if let propertySchema = propertySchemas[key] {
                    try validate(value, schema: propertySchema, root: root, path: "\(path).\(key)")
                } else if !additionalAllowed {
                    throw SettingsSchemaMiniValidatorError.additionalPropertyNotAllowed(key, path: "\(path).\(key)")
                }
            }

        case .array(let items):
            if let itemSchema = fields["items"] {
                for (index, item) in items.enumerated() {
                    try validate(item, schema: itemSchema, root: root, path: "\(path)[\(index)]")
                }
            }

        case .bool, .null:
            break   // No keyword above applies extra checks to these.
        }
    }

    private static func checkType(_ data: JSONValue, typeName: String, path: String) throws {
        switch typeName {
        case "object":
            guard case .object = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "an object", path: path) }
        case "array":
            guard case .array = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "an array", path: path) }
        case "string":
            guard case .string = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "a string", path: path) }
        case "boolean":
            guard case .bool = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "true or false", path: path) }
        case "number":
            guard case .number = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "a number", path: path) }
        case "integer":
            guard case .number(let value) = data, value == value.rounded(.towardZero) else {
                throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "a whole number", path: path)
            }
        case "null":
            guard case .null = data else { throw SettingsSchemaMiniValidatorError.typeMismatch(expected: "null", path: path) }
        default:
            throw SettingsSchemaMiniValidatorError.malformedSchema("unsupported type name \"\(typeName)\"", path: path)
        }
    }

    private static func checkPattern(_ text: String, pattern: String, path: String) throws {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw SettingsSchemaMiniValidatorError.malformedSchema("pattern \"\(pattern)\" is not a valid regular expression", path: path)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard regex.firstMatch(in: text, options: [], range: range) != nil else {
            throw SettingsSchemaMiniValidatorError.patternMismatch(path: path)
        }
    }

    private static func checkFormat(_ text: String, format: String, path: String) throws {
        switch format {
        case "date-time":
            let plain = ISO8601DateFormatter()
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard plain.date(from: text) != nil || withFraction.date(from: text) != nil else {
                throw SettingsSchemaMiniValidatorError.formatMismatch(format: format, path: path)
            }
        case "uuid":
            guard UUID(uuidString: text) != nil else {
                throw SettingsSchemaMiniValidatorError.formatMismatch(format: format, path: path)
            }
        default:
            throw SettingsSchemaMiniValidatorError.malformedSchema("unsupported format \"\(format)\"", path: path)
        }
    }
}
