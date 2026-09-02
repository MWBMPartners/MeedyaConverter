// ============================================================================
// MeedyaConverter — app-module regression tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// The app module (MeedyaConverterCore) previously had NO test target, so the
// subtle defects that lived here shipped unguarded. These tests pin the two
// worst: HardwareAccelerationPreference's default polarity (a wrong default
// would have engaged a kill switch on every fresh install) and
// ShortcutBinding.keyEquivalent's crash-safety (KeyEquivalent(Character(...))
// traps on an empty/multi-character key decoded from UserDefaults).
// ============================================================================

import XCTest
import SwiftUI
@testable import MeedyaConverterCore
import ConverterEngine

final class AppModuleRegressionTests: XCTestCase {

    // MARK: - HardwareAccelerationPreference (#475)

    private func defaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(name).\(UUID().uuidString)")!
        d.removePersistentDomain(forName: "test.\(name)")
        return d
    }

    /// An UNSET key must default to ENABLED. A false default would engage the
    /// kill switch out of the box and silently software-encode the built-in
    /// hardware profiles.
    func test_hardwarePreference_defaultsEnabledWhenUnset() {
        let d = defaults("hw-unset")
        XCTAssertTrue(HardwareAccelerationPreference.isEnabled(in: d))
    }

    func test_hardwarePreference_explicitFalseIsDisabled() {
        let d = defaults("hw-false")
        d.set(false, forKey: HardwareAccelerationPreference.defaultsKey)
        XCTAssertFalse(HardwareAccelerationPreference.isEnabled(in: d))
    }

    /// When enabled, a hardware profile is left untouched; when disabled, it is
    /// forced to software.
    func test_hardwarePreference_applyKillSwitch() {
        var hwProfile = EncodingProfile.webStandard
        hwProfile.useHardwareEncoding = true

        let on = defaults("hw-on")
        on.set(true, forKey: HardwareAccelerationPreference.defaultsKey)
        var a = hwProfile
        XCTAssertFalse(HardwareAccelerationPreference.apply(to: &a, defaults: on), "no change expected when enabled")
        XCTAssertTrue(a.useHardwareEncoding)

        let off = defaults("hw-off")
        off.set(false, forKey: HardwareAccelerationPreference.defaultsKey)
        var b = hwProfile
        XCTAssertTrue(HardwareAccelerationPreference.apply(to: &b, defaults: off), "should force software when disabled")
        XCTAssertFalse(b.useHardwareEncoding)

        // A software profile is never a "change" regardless of the switch.
        var swProfile = EncodingProfile.webStandard
        swProfile.useHardwareEncoding = false
        XCTAssertFalse(HardwareAccelerationPreference.apply(to: &swProfile, defaults: off))
    }

    // MARK: - ShortcutBinding key parsing (#331)

    /// KeyEquivalent(Character(binding.key)) traps on an empty or
    /// multi-character key — and `key` is decoded from UserDefaults JSON. The
    /// property must return nil for those rather than crash.
    func test_shortcutBinding_keyEquivalentFailsSafelyOnBadKeys() {
        func binding(_ key: String) -> ShortcutBinding {
            ShortcutBinding(action: "a", label: "A", key: key, modifiers: ["command"])
        }
        XCTAssertNil(binding("").keyEquivalent, "empty key must not crash")
        XCTAssertNil(binding("ctrl+k").keyEquivalent, "multi-character key must not crash")
        XCTAssertNotNil(binding("o").keyEquivalent)
        XCTAssertNotNil(binding("return").keyEquivalent)
    }

    /// displayString and keyEquivalent agree on which bindings are usable.
    func test_shortcutBinding_displayStringForUsableKeys() {
        let b = ShortcutBinding(action: "file.import", label: "Import", key: "o", modifiers: ["command"])
        XCTAssertEqual(b.displayString, "\u{2318}O")
        XCTAssertNotNil(b.keyEquivalent)
    }
}
