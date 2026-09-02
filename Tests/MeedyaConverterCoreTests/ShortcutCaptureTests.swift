// ============================================================================
// MeedyaConverter — ShortcutBinding.captureBinding tests (#331)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// The keyboard-shortcut recorder was decorative (no key capture). captureBinding
// is the pure translation the new NSEvent monitor calls; these pin it so a
// custom shortcut is assigned correctly and unusable keystrokes are rejected.
// ============================================================================

import XCTest
@testable import MeedyaConverterCore

final class ShortcutCaptureTests: XCTestCase {

    func test_letterWithCommand() {
        let r = ShortcutBinding.captureBinding(characters: "o", command: true, shift: false, option: false, control: false)
        XCTAssertEqual(r?.key, "o")
        XCTAssertEqual(r?.modifiers, ["command"])
    }

    func test_modifiersAreCanonicalOrder() {
        // Passed control-first, but the result must be command→shift→option→control.
        let r = ShortcutBinding.captureBinding(characters: "O", command: true, shift: true, option: true, control: true)
        XCTAssertEqual(r?.key, "o", "must lowercase")
        XCTAssertEqual(r?.modifiers, ["command", "shift", "option", "control"])
    }

    func test_noModifier_isRejected() {
        XCTAssertNil(ShortcutBinding.captureBinding(characters: "o", command: false, shift: false, option: false, control: false))
    }

    func test_specialKeysAreNamed() {
        XCTAssertEqual(ShortcutBinding.captureBinding(characters: "\r", command: true, shift: false, option: false, control: false)?.key, "return")
        XCTAssertEqual(ShortcutBinding.captureBinding(characters: " ", command: true, shift: false, option: false, control: false)?.key, "space")
        XCTAssertEqual(ShortcutBinding.captureBinding(characters: "\t", command: true, shift: false, option: false, control: false)?.key, "tab")
    }

    func test_digitWithCommand() {
        XCTAssertEqual(ShortcutBinding.captureBinding(characters: "1", command: true, shift: false, option: false, control: false)?.key, "1")
    }

    func test_nilOrEmptyCharacters_isRejected() {
        XCTAssertNil(ShortcutBinding.captureBinding(characters: nil, command: true, shift: false, option: false, control: false))
        XCTAssertNil(ShortcutBinding.captureBinding(characters: "", command: true, shift: false, option: false, control: false))
    }

    /// The captured binding is usable end-to-end: keyEquivalent resolves.
    func test_capturedBindingProducesUsableKeyEquivalent() {
        let r = ShortcutBinding.captureBinding(characters: "k", command: true, shift: false, option: false, control: false)!
        let binding = ShortcutBinding(action: "test", label: "T", key: r.key, modifiers: r.modifiers)
        XCTAssertNotNil(binding.keyEquivalent)
        XCTAssertEqual(binding.displayString, "\u{2318}K")
    }
}
