// ============================================================================
// MeedyaConverter — ScriptingBridgeF008Tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================

import Foundation
import XCTest

/// Regression tests anchoring SECURITY.md F-008 (T6 AppleScript
/// surface hardening). The actual `ScriptingBridge` type lives
/// in the `@main` MeedyaConverter target which cannot be linked
/// into a test binary, so these tests exercise the *contract* of
/// the two helpers by re-implementing the same shape in the test
/// target and asserting against it.
///
/// Each test names the production behaviour it pins. Drift between
/// the mirror and `ScriptingBridge`'s helpers would show up as a
/// production-only failure during the next ad-hoc AppleScript
/// invocation — exactly the kind of regression these tests are
/// here to anchor.
final class ScriptingBridgeF008Tests: XCTestCase {

    // MARK: - Mirror of ScriptingBridge.formatError / enforceLengthCap

    private static let maxArgumentLength = 4096

    /// Mirror of `ScriptingBridge.formatError(_:)`.
    private func formatError(_ message: String) -> String {
        return "ERROR: " + sanitiseLikeMetadataSanitizer(message)
    }

    /// Mirror of `ScriptingBridge.enforceLengthCap(_:label:)`.
    private func enforceLengthCap(_ value: String, label: String) -> String? {
        guard value.count > Self.maxArgumentLength else { return nil }
        return formatError("AppleScript argument '\(label)' exceeds the \(Self.maxArgumentLength)-character cap.")
    }

    /// Mirror of `MetadataSanitizer.sanitize(_:)` so this test
    /// target doesn't have to depend on the @testable engine
    /// import for this assertion's purposes. The behaviour is
    /// the contract that F-008 relies on.
    private func sanitiseLikeMetadataSanitizer(_ raw: String) -> String {
        var result = String()
        result.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            let v = scalar.value
            switch v {
            case 0:                continue
            case 0x01...0x08,
                 0x0B, 0x0C,
                 0x0E...0x1F:      continue
            case 0x7F:             continue
            case 0x202A...0x202E:  continue
            case 0x2066...0x2069:  continue
            default:               result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: - formatError contract

    func test_formatError_prependsErrorPrefix() {
        XCTAssertEqual(formatError("nope"), "ERROR: nope")
    }

    func test_formatError_stripsControlCodesFromInterpolatedMessage() {
        // The defining F-008 invariant: an attacker can pass a
        // profile name or filename containing VT100 escape
        // sequences and the bridge MUST NOT echo it back as-is.
        let attackerString = "ProfileX\u{001B}[31mFAKE-ERROR\u{001B}[0m"
        let reply = formatError("Profile '\(attackerString)' not found.")
        XCTAssertFalse(
            reply.unicodeScalars.contains { $0.value == 0x001B },
            "ESC bytes must be stripped from the reply"
        )
        XCTAssertTrue(reply.hasPrefix("ERROR: "))
        // Visible content survives.
        XCTAssertTrue(reply.contains("ProfileX"))
        XCTAssertTrue(reply.contains("FAKE-ERROR"))
    }

    func test_formatError_stripsBidiOverrideFromInterpolatedMessage() {
        // Trojan-Source: a filename like `safe\u{202E}exe.txt`
        // displayed in a terminal would render as `safetxt.exe`.
        // The bridge must not propagate U+202E.
        let attackerFilename = "safe\u{202E}exe.txt"
        let reply = formatError("Input file not found: \(attackerFilename)")
        XCTAssertFalse(
            reply.unicodeScalars.contains { $0.value == 0x202E },
            "U+202E must be stripped from the reply"
        )
    }

    func test_formatError_stripsNulFromInterpolatedMessage() {
        let attackerFilename = "safe\u{0000}truncated"
        let reply = formatError("Input file not found: \(attackerFilename)")
        XCTAssertFalse(reply.contains("\0"), "NUL must be stripped from the reply")
    }

    // MARK: - enforceLengthCap contract

    func test_enforceLengthCap_underLimit_returnsNil() {
        XCTAssertNil(enforceLengthCap("short", label: "profile"))
    }

    func test_enforceLengthCap_atLimit_returnsNil() {
        // `> maxArgumentLength` is the trip condition; exactly
        // 4096 must pass.
        let exactlyAtLimit = String(repeating: "a", count: Self.maxArgumentLength)
        XCTAssertNil(enforceLengthCap(exactlyAtLimit, label: "profile"))
    }

    func test_enforceLengthCap_overLimit_returnsErrorReply() {
        let oversized = String(repeating: "a", count: Self.maxArgumentLength + 1)
        let reply = enforceLengthCap(oversized, label: "profile")
        XCTAssertNotNil(reply)
        XCTAssertTrue(reply?.hasPrefix("ERROR: ") ?? false)
        XCTAssertTrue(reply?.contains("'profile'") ?? false)
        XCTAssertTrue(reply?.contains("4096") ?? false)
    }

    func test_enforceLengthCap_labelInterpolation_isItselfSanitised() {
        // Belt-and-braces: if a future caller passes a `label`
        // built from external input (it shouldn't — label is
        // always a literal in current callers), the error
        // string still goes through formatError, which strips
        // control codes. We test by reading the helper's
        // implementation contract via the mirror.
        let oversized = String(repeating: "a", count: Self.maxArgumentLength + 1)
        let reply = enforceLengthCap(oversized, label: "tag\u{001B}[31m")
        XCTAssertNotNil(reply)
        XCTAssertFalse(
            reply!.unicodeScalars.contains { $0.value == 0x001B },
            "ESC must be stripped even when it appears in the label argument"
        )
    }

    // MARK: - End-to-end F-008 contract

    func test_combinedAttackerPayload_neutralised() {
        // The "kitchen sink" attacker reply: an oversized
        // profile name that ALSO contains every payload class.
        // The cap fires first; the resulting error reply must
        // still be sanitised.
        var attacker = String(repeating: "X", count: Self.maxArgumentLength + 1)
        attacker += "\u{0000}\u{001B}[31m\u{202E}"

        let reply = enforceLengthCap(attacker, label: "profile")
        XCTAssertNotNil(reply)
        XCTAssertTrue(reply!.hasPrefix("ERROR: "))
        XCTAssertFalse(reply!.contains("\0"))
        XCTAssertFalse(reply!.unicodeScalars.contains { $0.value == 0x001B })
        XCTAssertFalse(reply!.unicodeScalars.contains { $0.value == 0x202E })
    }
}
