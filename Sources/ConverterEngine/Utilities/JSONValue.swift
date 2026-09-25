// ============================================================================
// MeedyaConverter — JSONValue (moved here for Issue #506 commit 4)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A small "any JSON value" type: a string, a number, true/false, a list, an
// object, or null.
//
// Where it came from, and why it moved. It was written for the remote
// feature-flag client (`IntAppsAPIClient.swift`), where a flag's `metadata`
// is an arbitrary JSON object with no fixed shape. It lived inside that file.
// Settings export and import (#506) also needs to carry plain JSON values
// (each setting in a settings file is written as ordinary JSON), so it now
// lives in its own file where both can use it.
//
// What changed in the move: nothing about how it reads or writes JSON. The
// one edit is the wording of the error thrown for input that is not JSON at
// all: it used to say "in FeatureFlag.metadata", which would have been wrong
// for every other user, so it now names the six shapes it accepts instead.
// No caller or test checks that wording (searched `Sources/` and `Tests/`
// when it moved).
//
// Why not a library: this codebase adds third-party dependencies deliberately
// (see the commented-out entries in `Package.swift`), and `Codable` cannot
// decode Swift's `Any`. This type is the small, fully `Sendable` stand-in.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - JSONValue

/// A type-erased JSON value.
///
/// Used by `FeatureFlag.metadata` (an arbitrary, admin-authored JSON object
/// per the intAppsAPI OpenAPI schema), and available to settings export and
/// import (#506).
///
/// What it cannot do:
/// - It does not keep integers and decimals apart: every number becomes a
///   `Double`. A caller that needs "this must be a whole number" has to check
///   that itself.
/// - It does not keep the order of an object's keys (it uses a dictionary).
/// - Duplicate keys inside one JSON object cannot be detected: Foundation's
///   decoder keeps only one of them before this type ever sees the object.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Order matters: `Bool` must be tried before `Double`/`Int`-ish
        // decoding, since JSONDecoder will NOT coerce "true"/"false" into
        // a Double, so there's no ambiguity risk trying Bool first.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value: expected null, true/false, a number, "
                + "a string, a list or an object"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):  try container.encode(value)
        case .number(let value):  try container.encode(value)
        case .bool(let value):    try container.encode(value)
        case .object(let value):  try container.encode(value)
        case .array(let value):   try container.encode(value)
        case .null:                try container.encodeNil()
        }
    }
}
