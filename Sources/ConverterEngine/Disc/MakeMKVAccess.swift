// ============================================================================
// MeedyaConverter — MakeMKVAccess (Issue #503, slice 2)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// Slice 2 of the optional, opt-in MakeMKV backend (#503): the *access gate* that
// decides whether MakeMKV may be used at all, and whether it is actually usable.
//
// Two independent conditions, both required, mirroring the render-farm
// insecure-transport consent pattern (`InsecureTransportOverride`):
//   1. CONSENT — the user has turned the feature on AND typed a non-blank terms
//      acknowledgement. Off by default; a flipped-on toggle with no acknowledgement
//      does NOT count (guards a mid-typing or a stray persisted `true`). Expressed
//      as a typed `MakeMKVConsent` that is un-constructable except through its
//      factory, so a call site cannot fabricate consent by accident.
//   2. AVAILABILITY — `makemkvcon` is actually installed (located via
//      `BundledToolLocator`, or a user-set path). When it is missing the feature is
//      "disabled with a reason", never a dead button.
//
// `MakeMKVGate.readiness(...)` combines the two into a single honest verdict. It
// does NOT launch makemkvcon (that is slice 3) and it does NOT change the
// copy-protection refuse-gate (#492): MakeMKV is a separate, user-gated path.
//
// Settings/CLI store the two values under the `Keys` below (the GUI via
// `@AppStorage`, the CLI via an explicit flag), so the store reads injectable
// `UserDefaults` the way `HardwareAccelerationPreference` does — no `UserDefaults`
// is retained, keeping every type here trivially `Sendable`.
// ============================================================================

import Foundation

// MARK: - MakeMKVConsent

/// Proof that the user opted in to MakeMKV AND acknowledged its terms. There is
/// no public initialiser: the only way to obtain one is `userAcknowledged(_:)`,
/// which the store calls solely after both conditions hold. A `nil`
/// `MakeMKVConsent?` therefore always means "not permitted".
public struct MakeMKVConsent: Sendable, Equatable {
    /// The user's acknowledgement text, surfaced in logs and UI so it is always
    /// visible *why* the MakeMKV path was permitted.
    public let acknowledgement: String

    private init(acknowledgement: String) {
        self.acknowledgement = acknowledgement
    }

    /// The only way to construct consent. Named so "userAcknowledged" appears at
    /// every site that unlocks MakeMKV — an obvious review signal that no
    /// innocuous-sounding alternative exists.
    public static func userAcknowledged(_ acknowledgement: String) -> MakeMKVConsent {
        MakeMKVConsent(acknowledgement: acknowledgement)
    }
}

// MARK: - MakeMKVConsentStore

/// Reads the opt-in toggle, terms acknowledgement, and optional binary-path
/// override from `UserDefaults`. Read-only: the Settings UI (`@AppStorage`) and
/// the CLI write these keys; this type only interprets them, and never retains
/// the `UserDefaults` instance.
public enum MakeMKVConsentStore {

    /// Defaults keys shared with the Settings UI and CLI. Kept here as the single
    /// source of truth so both sides agree on the spelling.
    public enum Keys {
        /// Bool. The master opt-in switch. Absent → off (the default).
        public static let enabled = "makemkv.enabled"
        /// String. The user's terms acknowledgement; must be non-blank to consent.
        public static let termsAcknowledgement = "makemkv.termsAcknowledgement"
        /// String. Optional full path to `makemkvcon`; blank → auto-locate.
        public static let binaryPath = "makemkv.binaryPath"
    }

    /// The user's consent, or `nil` when MakeMKV is not permitted.
    ///
    /// Requires BOTH the opt-in toggle to be on AND a non-blank acknowledgement
    /// (a whitespace-only string is not a real acknowledgement). Off by default.
    public static func consent(in defaults: UserDefaults = .standard) -> MakeMKVConsent? {
        // `bool(forKey:)` returns `false` for an absent key, which is exactly the
        // off-by-default behaviour we want.
        guard defaults.bool(forKey: Keys.enabled) else { return nil }
        let acknowledgement = defaults.string(forKey: Keys.termsAcknowledgement) ?? ""
        guard !acknowledgement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .userAcknowledged(acknowledgement)
    }

    /// The user-set `makemkvcon` path, or `nil` when unset/blank (auto-locate).
    public static func binaryOverridePath(in defaults: UserDefaults = .standard) -> String? {
        let path = (defaults.string(forKey: Keys.binaryPath) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

// MARK: - MakeMKVReadiness

/// The honest verdict on whether MakeMKV can be used right now.
public enum MakeMKVReadiness: Sendable, Equatable {
    /// Permitted and installed — `makemkvcon` is at `binaryPath`.
    case ready(binaryPath: String)
    /// Not permitted: the feature is off, or on without a terms acknowledgement.
    /// `reason` is a user-facing explanation of how to enable it.
    case notEnabled(reason: String)
    /// Permitted, but `makemkvcon` could not be found. `reason` tells the user how
    /// to install it or point the app at it.
    case notInstalled(reason: String)

    /// Whether MakeMKV can actually be invoked.
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The located binary path when ready, else `nil`.
    public var binaryPath: String? {
        if case .ready(let path) = self { return path }
        return nil
    }
}

// MARK: - MakeMKVGate

/// Combines consent (may we?) with availability (can we?) into one verdict.
/// Launches nothing and decrypts nothing.
public enum MakeMKVGate {

    static let disabledReason =
        "MakeMKV support is turned off. Turn it on and acknowledge MakeMKV's terms "
        + "in Settings before it can be used."

    /// Decide readiness from an already-resolved consent plus an injected locate
    /// step. The `locate` closure is only called when consent is present, so a
    /// disabled feature never touches the file system — and tests can prove that
    /// by passing a `locate` that fails if invoked.
    public static func readiness(
        consent: MakeMKVConsent?,
        locate: () throws -> String
    ) -> MakeMKVReadiness {
        guard consent != nil else {
            return .notEnabled(reason: disabledReason)
        }
        do {
            return .ready(binaryPath: try locate())
        } catch {
            return .notInstalled(reason:
                "MakeMKV (makemkvcon) could not be found. Install MakeMKV, or set its "
                + "path in Settings. (\(error.localizedDescription))")
        }
    }

    /// Production convenience: read consent + override path from `defaults` and
    /// locate `makemkvcon` via the shared `BundledToolLocator`.
    public static func readiness(in defaults: UserDefaults = .standard) -> MakeMKVReadiness {
        readiness(consent: MakeMKVConsentStore.consent(in: defaults)) {
            try BundledToolLocator(
                toolName: "makemkvcon",
                userOverridePath: MakeMKVConsentStore.binaryOverridePath(in: defaults)
            ).locate()
        }
    }
}
