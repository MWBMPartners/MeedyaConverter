// ============================================================================
// MeedyaConverter — SettingsDocument, the settings file's outer wrapper
// (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsDocument.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// The fixed outer wrapper ("envelope") of a settings file, which says what
// the file is and which format version wrote it. The settings themselves sit
// inside it, grouped by category:
//
//   {
//     "format": "meedyaconverter.settings",
//     "version": 1,
//     "exportedAt": "2026-09-25T14:03:11Z",
//     "appVersion": "0.1.0",
//     "categories": {
//       "general":          { "settings": { "appearanceMode": "Dark", … } },
//       "encoding":         { "settings": { … } },
//       "encodingProfiles": { "profiles": [ { …EncodingProfile… } ] },
//       "connections":      { "settings": { … } },
//       "thisMac":          { "settings": { … } }
//     },
//     "notIncluded": ["tmdbKey", "smtpPassword"]
//   }
//
// Only the groups the person ticked are present. `notIncluded` names, from a
// fixed list, the passwords, keys and other things that were set up on the
// Mac that made the file but are never copied, so the importing Mac can say
// "TMDB still needs a key". It holds names only, never a value (see
// `SettingsLeftOutItem`). Owner decision 4 in the #506 plan accepted that
// this reveals which services were in use.
//
// Reading a file is done in a fixed order, because each step decides whether
// the next one can be trusted:
//   1. size (before reading anything into memory, when reading from disk);
//   2. nesting depth (a hostile file nested thousands of levels deep could
//      exhaust the stack of a recursive reader, so it is refused first);
//   3. is it JSON at all;
//   4. is it a MeedyaConverter settings file (`format`);
//   5. which version — BEFORE looking at anything else, because a newer
//      version is allowed to have a different shape, and should get
//      "update MeedyaConverter", not "this file is damaged";
//   6. the rest of the wrapper's shape.
//
// Room to grow (#505): `categories` is an open map. A group this version
// does not know is reported and ignored, not refused, so a later version can
// add a group while keeping version 1. The version number only goes up for a
// change to the wrapper itself that an older version would misread.
//
// Honest limit: JSON allows the same name twice in one object, and
// Foundation keeps only one of them before this code sees the object. A file
// with `"version": 2, "version": 1` cannot be detected as odd.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsDocument

/// The settings file's fixed facts, and reading and writing its wrapper.
public enum SettingsDocument {

    /// The `format` marker every settings file carries. Never changes.
    public static let formatIdentifier = "meedyaconverter.settings"

    /// The wrapper format this version writes and the newest it reads.
    public static let currentVersion = 1

    /// The largest file accepted: 10 MB. A real settings file is a few
    /// kilobytes; even thousands of profiles stay far below this.
    public static let maximumFileSize = 10 * 1_048_576

    /// Deeper nesting than this is refused before the file is decoded. A real
    /// file nests about ten levels (an encoding profile inside a pipeline
    /// step inside the pipelines list); 64 leaves generous room.
    static let maximumNestingDepth = 64

    /// The names used in the wrapper.
    enum Field {
        static let format = "format"
        static let version = "version"
        static let exportedAt = "exportedAt"
        static let appVersion = "appVersion"
        static let categories = "categories"
        static let notIncluded = "notIncluded"
        static let all: Set<String> = [format, version, exportedAt, appVersion, categories, notIncluded]
    }

    // MARK: Reading

    /// The wrapper of a settings file, checked, with each group's contents
    /// still unchecked (the section handlers check those).
    struct Envelope {
        let version: Int
        let exportedAt: Date?
        let appVersion: String?
        /// Every group in the file, by the name written in the file.
        let categories: [String: JSONValue]
        /// The `notIncluded` names, as written.
        let notIncluded: [String]
        /// Top-level names this version does not know (reported, ignored).
        let unknownFields: [String]
    }

    /// Reads and checks the wrapper. Throws a `SettingsImportError` naming
    /// the first problem; see the file overview for the order.
    static func readEnvelope(from data: Data) throws -> Envelope {
        guard data.count <= maximumFileSize else {
            throw SettingsImportError.fileTooLarge(bytes: data.count, limit: maximumFileSize)
        }
        guard nestingDepthIsAcceptable(data) else {
            throw SettingsImportError.malformed(path: "", reason: "is nested more deeply than any settings file")
        }
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw SettingsImportError.notJSON
        }
        guard case .object(let fields) = root,
              case .string(let format)? = fields[Field.format], format == formatIdentifier else {
            throw SettingsImportError.notASettingsFile
        }

        // The version, before anything else about the shape.
        guard case .number(let versionNumber)? = fields[Field.version],
              let version = SettingsValueCodec.wholeNumber(versionNumber) else {
            throw SettingsImportError.malformed(path: Field.version, reason: "should be a whole number")
        }
        if version > currentVersion {
            throw SettingsImportError.newerFormat(found: version, supported: currentVersion)
        }
        if version < 1 {
            throw SettingsImportError.unsupportedFormat(found: version)
        }

        guard let categoriesValue = fields[Field.categories] else {
            throw SettingsImportError.malformed(path: Field.categories, reason: "is missing")
        }
        guard case .object(let categories) = categoriesValue else {
            throw SettingsImportError.malformed(path: Field.categories, reason: "should be an object")
        }

        var exportedAt: Date?
        if let value = fields[Field.exportedAt] {
            guard case .string(let text) = value, let date = ISO8601DateFormatter().date(from: text) else {
                throw SettingsImportError.malformed(path: Field.exportedAt, reason: "should be a date and time")
            }
            exportedAt = date
        }

        var appVersion: String?
        if let value = fields[Field.appVersion] {
            guard case .string(let text) = value, text.count <= 64 else {
                throw SettingsImportError.malformed(path: Field.appVersion, reason: "should be a short piece of text")
            }
            appVersion = text
        }

        var notIncluded: [String] = []
        if let value = fields[Field.notIncluded] {
            guard case .array(let names) = value, names.count <= 256 else {
                throw SettingsImportError.malformed(path: Field.notIncluded, reason: "should be a list of names")
            }
            for name in names {
                guard case .string(let text) = name, text.count <= 64 else {
                    throw SettingsImportError.malformed(path: Field.notIncluded, reason: "should be a list of names")
                }
                notIncluded.append(text)
            }
        }

        return Envelope(
            version: version,
            exportedAt: exportedAt,
            appVersion: appVersion,
            categories: categories,
            notIncluded: notIncluded,
            unknownFields: fields.keys.filter { !Field.all.contains($0) }.sorted()
        )
    }

    /// Counts how deeply `[` and `{` nest, outside strings, without decoding
    /// anything. False when deeper than `maximumNestingDepth`. It only has
    /// to be right for well-formed JSON; anything else fails to decode in the
    /// next step anyway.
    static func nestingDepthIsAcceptable(_ data: Data) -> Bool {
        var depth = 0
        var insideString = false
        var escaped = false
        for byte in data {
            if insideString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    insideString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                insideString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > maximumNestingDepth { return false }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
        }
        return true
    }

    // MARK: Writing

    /// Builds the file's bytes: pretty-printed, keys sorted (so two exports
    /// of the same settings are identical apart from the date, and a diff is
    /// readable), and "/" left unescaped so paths and addresses read as they
    /// are.
    static func makeData(
        exportedAt: Date,
        appVersion: String,
        categories: [String: JSONValue],
        notIncluded: [String]
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let root: JSONValue = .object([
            Field.format: .string(formatIdentifier),
            Field.version: .number(Double(currentVersion)),
            Field.exportedAt: .string(formatter.string(from: exportedAt)),
            Field.appVersion: .string(appVersion),
            Field.categories: .object(categories),
            Field.notIncluded: .array(notIncluded.map { .string($0) }),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(root)
    }
}
