// ============================================================================
// MeedyaConverter — HardwareAccelerationPreference
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// One place that decides whether the app's global "Prefer hardware
// acceleration" setting should override a profile's own choice.
//
// GitHub Issue #475 — the setting was persisted by Settings and read by
// nothing at all, so flipping it changed no encode. Wiring it into a single
// enqueue path was not enough either: the app builds `EncodingJobConfig` from
// seven different places, so a switch honoured in only one of them would
// still have been a false promise everywhere else.
// ============================================================================

import Foundation
import ConverterEngine

// MARK: - HardwareAccelerationPreference

/// The app-wide "Prefer hardware acceleration" preference.
///
/// ## What this setting means
///
/// Hardware selection is fundamentally **per profile** —
/// `EncodingProfile.useHardwareEncoding` is real, is copied into
/// `FFmpegArgumentBuilder`, and drives the built-in `hardwareH264` /
/// `hardwareH265` profiles. This global setting is therefore deliberately
/// **not** a second way to request hardware encoding. It is a **kill switch**:
///
/// - **On (the default)** — profiles decide, exactly as they always have.
/// - **Off** — hardware encoding is forced off for the job, even when the
///   profile explicitly asks for it.
///
/// ## Why the default matters
///
/// The stored default must be `true`. `UserDefaults.bool(forKey:)` returns
/// `false` for a key that has never been written, so reading this preference
/// with `bool(forKey:)` would engage the kill switch on every fresh install
/// and for every existing user who never touched the (previously dead)
/// toggle — silently downgrading the `hardwareH264` / `hardwareH265` profiles
/// to software encoding. `isEnabled` therefore distinguishes "absent" from
/// "explicitly false" via `object(forKey:)`.
///
/// ## Scope
///
/// This governs the **GUI app's** enqueue paths only. The `meedya-convert`
/// CLI and the HTTP API run in a different context with their own explicit
/// options, and are deliberately not subject to a preference stored in the
/// app's `UserDefaults` domain — a headless encode should not change
/// behaviour because of a checkbox someone ticked in a GUI.
enum HardwareAccelerationPreference {

    /// The `UserDefaults` key, shared with `SettingsView`'s `@AppStorage`.
    static let defaultsKey = "useHardwareAcceleration"

    /// Whether hardware encoding is permitted at all.
    ///
    /// Defaults to `true` when the key has never been written — see the
    /// type-level note on why `bool(forKey:)` is not used here.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: defaultsKey) as? Bool) ?? true
    }

    /// Applies the global preference to a profile about to be encoded.
    ///
    /// Mutates the caller's own copy only. `EncodingProfile` is a struct, so
    /// this never touches the stored profile in `EncodingProfileStore` or the
    /// user's current selection — the override is scoped to one job.
    ///
    /// - Parameters:
    ///   - profile: The profile the job will use. Modified in place.
    ///   - defaults: Injection point for tests.
    /// - Returns: `true` if the preference actually changed something, so the
    ///   caller can log it. Returns `false` when the switch is on, or when the
    ///   profile was not asking for hardware encoding anyway — there is no
    ///   point telling the user about an override that overrode nothing.
    @discardableResult
    static func apply(
        to profile: inout EncodingProfile,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard profile.useHardwareEncoding, !isEnabled(in: defaults) else {
            return false
        }
        profile.useHardwareEncoding = false
        return true
    }

    /// Non-mutating convenience for the call sites that hold a `let` profile.
    static func applying(
        to profile: EncodingProfile,
        defaults: UserDefaults = .standard
    ) -> EncodingProfile {
        var copy = profile
        apply(to: &copy, defaults: defaults)
        return copy
    }
}
