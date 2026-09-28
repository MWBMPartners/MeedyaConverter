// ============================================================================
// MeedyaConverter — MediaLanguagePolicyTests / FixtureShapeCheck
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Policy §8.1: a conformance runner must FAIL — never quietly report success —
// on a case file that breaks its schema. Checking which fields are present is
// not enough: the reviews of the other implementations found `roles: null`
// read as "no roles", `input: 5` or `channels: 5` reaching the library as a
// number, an optional field set to null passing as "absent", and — once the
// file was decoded into plain dictionaries — an empty object `{}` and an empty
// list `[]` being taken for each other (`roles: {}` even changed a case's
// answer). So before any case runs, the WHOLE file is checked against the
// schema copy beside it (`bcp47-language-policy-v1.schema.json`):
//
//   * the file is read a second time into `JSONValue`, which keeps an object
//     an object, a list a list, true/false true/false and a number a number —
//     none of them can pass for another;
//   * `FixtureShapeCheck` then applies the schema's own rules to it: types
//     (with null only where the schema allows it), required fields, no field
//     the schema does not list, the allowed words (roles, track types, modes,
//     match levels, kinds), constants (`error` may only be `true`), patterns
//     (case ids, rule ids, versions), number limits, list lengths, and the
//     schema's if/then rules (a case with `error` must expect null).
//
// It reads the rules FROM THE SCHEMA rather than from a hand-written copy of
// them, so it cannot drift from the schema. A schema keyword it does not know
// how to check is reported as a problem — never skipped — so a later version
// of the schema cannot switch a check off by using a new keyword.
//
// WHAT IT CANNOT DO: it implements only the JSON Schema keywords this schema
// uses (listed in `checkedKeywords`), and `$ref` only to `#/$defs/…`. It is a
// test helper, not a general validator.
// ============================================================================

import Foundation

// MARK: - JSONValue

/// A JSON value exactly as the file has it. Unlike `JSONSerialization`'s
/// output, an empty object and an empty list cannot be confused, and
/// true/false is never a number.
indirect enum JSONValue: Decodable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // The order matters: `Bool` before the numbers (JSONDecoder refuses
        // to read true/false as a number, and a number as true/false), whole
        // numbers before other numbers, and lists before objects.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a JSON value")
        }
    }

    /// Equality as JSON Schema means it: `1` and `1.0` are the same number.
    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.integer(a), .integer(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.integer(a), .number(b)), let (.number(b), .integer(a)): return Double(a) == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)): return a == b
        default: return false
        }
    }

    /// The value's kind in plain words, for messages.
    var kind: String {
        switch self {
        case .null: return "null"
        case .bool: return "true/false"
        case .integer: return "a whole number"
        case .number: return "a number"
        case .string: return "a string"
        case .array: return "a list"
        case .object: return "an object"
        }
    }

    /// The value as the plain Foundation values the case runner reads —
    /// `[String: Any]`, `[Any]`, `String`, `Bool`, `Int`, `Double`, `NSNull`
    /// — built from THIS reading of the file.
    ///
    /// Why it exists: the runner used to read the file a second time with
    /// `JSONSerialization` to run the cases from, and on macOS that reader
    /// silently drops a U+FEFF (an invisible "byte order mark" character) at
    /// the start of a string, while `JSONDecoder` — the shape check's reader
    /// — and Linux keep it. So a case whose input begins with U+FEFF was run
    /// on a DIFFERENT input from the one the file holds (the second
    /// independent review planted `"\u{FEFF}en"` expecting `en`: the PHP
    /// runner failed it, this runner passed it). Running the cases from the
    /// shape check's own reading means one reading of the file, checked and
    /// run alike. Swift's own `Bool` and `Int` are used, so a number can
    /// never pass for true/false here either.
    var plainValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .integer(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let values): return values.map(\.plainValue)
        case .object(let members): return members.mapValues(\.plainValue)
        }
    }

    /// The value as a number, if it is one.
    var numberValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    var description: String {
        switch self {
        case .string(let value): return "'\(value)'"
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        default: return kind
        }
    }
}

// MARK: - FixtureShapeCheck

/// Checks a JSON value against the conformance cases' schema (see the file
/// header). Every problem is returned, each naming where it is.
struct FixtureShapeCheck {

    /// The schema, and its `$defs` for `$ref`.
    let schema: JSONValue
    private let definitions: [String: JSONValue]

    /// Keywords that only describe, and are not checked.
    static let annotationKeywords: Set<String> = ["description", "$comment", "title", "$schema", "$id", "$defs"]

    /// Keywords this checker enforces. Anything else in the schema is
    /// reported as a problem, never ignored.
    static let checkedKeywords: Set<String> = [
        "$ref", "type", "enum", "const", "properties", "required", "additionalProperties",
        "items", "minItems", "uniqueItems", "pattern", "minimum", "maximum",
        "allOf", "oneOf", "if", "then", "else"
    ]

    init(schema: JSONValue) {
        self.schema = schema
        if case .object(let root) = schema, case .object(let defs)? = root["$defs"] {
            definitions = defs
        } else {
            definitions = [:]
        }
    }

    /// Every way `value` breaks the schema.
    func problems(in value: JSONValue) -> [String] {
        problems(value, against: schema, at: "the file")
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func problems(_ value: JSONValue, against schema: JSONValue, at path: String) -> [String] {
        let rules: [String: JSONValue]
        switch schema {
        case .bool(true): return []
        case .bool(false): return ["\(path): not allowed here"]
        case .object(let object): rules = object
        default: return ["\(path): the schema has something that is not a schema here"]
        }
        var found: [String] = []

        for keyword in rules.keys.sorted()
        where !Self.annotationKeywords.contains(keyword) && !Self.checkedKeywords.contains(keyword) {
            found.append("\(path): the schema uses '\(keyword)', which this runner cannot check")
        }

        if case .string(let reference)? = rules["$ref"] {
            let prefix = "#/$defs/"
            if reference.hasPrefix(prefix), let target = definitions[String(reference.dropFirst(prefix.count))] {
                found += problems(value, against: target, at: path)
            } else {
                found.append("\(path): the schema refers to '\(reference)', which this runner cannot find")
            }
        }

        if let type = rules["type"] {
            let allowed: [String]
            switch type {
            case .string(let one): allowed = [one]
            case .array(let many): allowed = many.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
            default: allowed = []
            }
            if !allowed.contains(where: { Self.has(value, type: $0) }) {
                found.append("\(path): must be \(allowed.joined(separator: " or ")), not \(value.kind)")
                return found  // Nothing else can be checked on the wrong kind of value.
            }
        }
        if case .array(let options)? = rules["enum"], !options.contains(value) {
            found.append("\(path): \(value) is not one of the allowed values \(options.map(\.description).joined(separator: ", "))")
        }
        if let constant = rules["const"], value != constant {
            found.append("\(path): must be \(constant), not \(value)")
        }

        switch value {
        case .object(let object):
            if case .array(let required)? = rules["required"] {
                for case .string(let field) in required where object[field] == nil {
                    found.append("\(path): missing required field '\(field)'")
                }
            }
            var listed = Set<String>()
            if case .object(let properties)? = rules["properties"] {
                for (field, fieldSchema) in properties {
                    listed.insert(field)
                    if let fieldValue = object[field] {
                        found += problems(fieldValue, against: fieldSchema, at: "\(path) -> \(field)")
                    }
                }
            }
            if let additional = rules["additionalProperties"] {
                for field in object.keys.sorted() where !listed.contains(field) {
                    if additional == .bool(false) {
                        found.append("\(path): field '\(field)' is not allowed here")
                    } else if let fieldValue = object[field] {
                        found += problems(fieldValue, against: additional, at: "\(path) -> \(field)")
                    }
                }
            }
        case .array(let items):
            if let itemSchema = rules["items"] {
                for (index, item) in items.enumerated() {
                    found += problems(item, against: itemSchema, at: "\(path)[\(index)]\(Self.caseName(item))")
                }
            }
            if let minimum = rules["minItems"]?.numberValue, Double(items.count) < minimum {
                found.append("\(path): must have at least \(Int(minimum)) item(s), has \(items.count)")
            }
            if rules["uniqueItems"] == .bool(true) {
                for (index, item) in items.enumerated() where items[..<index].contains(item) {
                    found.append("\(path): \(item) is listed more than once")
                }
            }
        case .string(let text):
            if case .string(let pattern)? = rules["pattern"], !Self.matches(text, pattern) {
                found.append("\(path): \(value) does not have the required form \(pattern)")
            }
        case .integer, .number:
            if let number = value.numberValue {
                if let minimum = rules["minimum"]?.numberValue, number < minimum {
                    found.append("\(path): \(value) is below the minimum \(minimum)")
                }
                if let maximum = rules["maximum"]?.numberValue, number > maximum {
                    found.append("\(path): \(value) is above the maximum \(maximum)")
                }
            }
        case .null, .bool:
            break
        }

        if case .array(let all)? = rules["allOf"] {
            for part in all { found += problems(value, against: part, at: path) }
        }
        if case .array(let alternatives)? = rules["oneOf"] {
            let results = alternatives.map { problems(value, against: $0, at: path) }
            let passing = results.filter(\.isEmpty).count
            if passing == 0 {
                // Report the alternative it came closest to (e.g. a sidecar
                // "build" case), so the message names the real problem.
                let closest = results.min { $0.count < $1.count } ?? []
                found.append("\(path): matches none of the allowed shapes; closest: \(closest.joined(separator: "; "))")
            } else if passing > 1 {
                found.append("\(path): matches more than one of the allowed shapes")
            }
        }
        if let condition = rules["if"] {
            let branch = problems(value, against: condition, at: path).isEmpty ? rules["then"] : rules["else"]
            if let branch { found += problems(value, against: branch, at: path) }
        }
        return found
    }

    /// Whether `value` is of the JSON Schema `type`.
    private static func has(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("null", .null), ("boolean", .bool), ("string", .string), ("array", .array), ("object", .object),
             ("integer", .integer), ("number", .integer), ("number", .number):
            return true
        case ("integer", .number(let number)):
            return number.rounded() == number
        default:
            return false
        }
    }

    /// Whether `text` has the form `pattern` (an ECMA-262 pattern, as JSON
    /// Schema uses). NSRegularExpression's `$` also matches just before a
    /// final line break, which ECMA-262's does not; so when the pattern ends
    /// with `$` the match must reach the very end of the text.
    static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: whole) else { return false }
        return !pattern.hasSuffix("$") || match.range.upperBound == whole.upperBound
    }

    /// " (canon-01)" for a case with an id, for readable paths.
    private static func caseName(_ value: JSONValue) -> String {
        if case .object(let object) = value, case .string(let id)? = object["id"] { return " (\(id))" }
        return ""
    }
}
