// ============================================================================
// MeedyaConverter — MeedyaDB access (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Where the app's MeedyaDB settings live, and the honest verdict on whether
// contributing is possible right now. Deliberately mirrors `MakeMKVAccess`:
// an engine-owned `Keys` enum as the single source of truth for the defaults
// spelling, a read-only store that never retains the `UserDefaults` it was
// handed, and a gate that returns a plain-English reason rather than a bare
// `false`.
//
// ⚠️ THE API KEY IS NOT IN HERE, AND MUST NEVER BE.
// `UserDefaults` is a plain-text plist in the user's Library; an API key with
// write access to a shared database does not belong there. The key lives in
// the system Keychain via `APIKeyManager` (provider `.meedyaDB`), and is
// passed in to the functions below by the app layer that reads it. That is
// also why `config(in:apiKey:)` takes the key as an argument instead of
// fetching it: this file can then have no opinion about, and no access to,
// where secrets are kept.
//
// Contributing is OFF by default. An absent key reads as `false` from
// `bool(forKey:)`, which is exactly the default we want: a new install
// contributes nothing until someone deliberately turns it on.
// ============================================================================

import Foundation

// MARK: - MeedyaDBConfigStore

/// Reads the MeedyaDB switch, server address and submission mode from
/// `UserDefaults`. Read-only: the Settings UI (`@AppStorage`) writes these
/// keys; this type only interprets them.
public enum MeedyaDBConfigStore {

    /// Defaults keys shared with the Settings UI. Kept here as the single
    /// source of truth so both sides agree on the spelling — the same reason
    /// `MakeMKVConsentStore.Keys` exists.
    public enum Keys {
        /// Bool. The master switch for contributing to MeedyaDB. Absent → off.
        public static let enabled = "meedyadb.enabled"
        /// String. The MeedyaDB server address, e.g. `https://db.example`.
        public static let baseURL = "meedyadb.baseURL"
        /// String. `anonymous` (default) or `full`. Anything unrecognised —
        /// including an absent key — is treated as `anonymous`, so a typo can
        /// never silently upgrade someone to sending more than they meant to.
        public static let submissionMode = "meedyadb.submissionMode"
    }

    /// Whether the user has switched contributing on. Off by default.
    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.enabled)
    }

    /// The configured server address, or `nil` when unset or blank.
    public static func baseURL(in defaults: UserDefaults = .standard) -> String? {
        let value = (defaults.string(forKey: Keys.baseURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// How much to send. Fails SAFE: anything other than an exact `full`
    /// means `anonymous`.
    public static func submissionMode(in defaults: UserDefaults = .standard) -> MeedyaDBSubmissionMode {
        let raw = (defaults.string(forKey: Keys.submissionMode) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == MeedyaDBSubmissionMode.full.rawValue ? .full : .anonymous
    }

    /// Assemble a publisher config from the stored settings plus a key the
    /// caller has fetched from the Keychain.
    ///
    /// The result may well be unusable (blank address, no key) — that is not
    /// an error here. `MeedyaDBPublisher` refuses to send in that state and
    /// `MeedyaDBGate.readiness` explains why in plain English.
    public static func config(
        in defaults: UserDefaults = .standard,
        apiKey: String?
    ) -> MeedyaDBPublisherConfig {
        MeedyaDBPublisherConfig(
            baseURL: baseURL(in: defaults) ?? "",
            apiKey: (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: isEnabled(in: defaults)
        )
    }
}

// MARK: - MeedyaDBReadiness

/// The honest verdict on whether a disc can be contributed right now.
public enum MeedyaDBReadiness: Sendable, Equatable {

    /// Switched on and fully configured.
    case ready(MeedyaDBPublisherConfig)

    /// Switched off. This is the normal state, not a problem: `reason` says
    /// how to turn it on, and a UI should present it as information rather
    /// than as an error.
    case off(reason: String)

    /// Switched on but unusable — the server address, the API key, or both
    /// are missing. `reason` names exactly which, because a setting that is
    /// on and silently doing nothing is worse than one that is off.
    case incomplete(reason: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The usable config when ready, else `nil`.
    public var config: MeedyaDBPublisherConfig? {
        if case .ready(let config) = self { return config }
        return nil
    }

    /// The plain-English explanation for the two not-ready cases.
    public var reason: String? {
        switch self {
        case .off(let reason), .incomplete(let reason):
            return reason
        case .ready:
            return nil
        }
    }
}

// MARK: - MeedyaDBGate

/// Turns the stored settings plus a Keychain key into one verdict. Contacts
/// nothing and sends nothing — this only reads settings.
public enum MeedyaDBGate {

    // Public and named so a UI can tell these cases apart without parsing
    // prose, and so tests pin the exact wording. Treat an edit as a
    // user-facing copy change, not a refactor.

    public static let offReason =
        "Contributing to MeedyaDB is turned off. You can turn it on in Settings."
    public static let missingBothReason =
        "Contributing is on, but MeedyaDB needs a server address and an API key before "
        + "anything can be sent. Add both in Settings."
    public static let missingURLReason =
        "Contributing is on, but MeedyaDB has no server address yet. Add one in Settings."
    public static let missingKeyReason =
        "Contributing is on, but MeedyaDB has no API key yet. Add one in Settings."

    /// - Parameters:
    ///   - defaults: where the switch, address and mode are read from.
    ///   - apiKey: the key the caller fetched from the Keychain, or `nil`.
    public static func readiness(
        in defaults: UserDefaults = .standard,
        apiKey: String?
    ) -> MeedyaDBReadiness {
        guard MeedyaDBConfigStore.isEnabled(in: defaults) else {
            return .off(reason: offReason)
        }

        let config = MeedyaDBConfigStore.config(in: defaults, apiKey: apiKey)
        let hasURL = !config.baseURL.isEmpty
        let hasKey = !config.apiKey.isEmpty

        switch (hasURL, hasKey) {
        case (true, true):
            return .ready(config)
        case (false, false):
            return .incomplete(reason: missingBothReason)
        case (false, true):
            return .incomplete(reason: missingURLReason)
        case (true, false):
            return .incomplete(reason: missingKeyReason)
        }
    }
}

// MARK: - MeedyaDBContributor

/// Sends an already-built submission to MeedyaDB, turning every outcome into
/// a `MeedyaDBContribution` rather than an error.
///
/// This is the shared half of the music and video identification runs, and it
/// lives in ONE place deliberately: the failure posture here is a set of
/// judgement calls (see below), and two copies of it would drift. Whenever a
/// new kind of disc learns to contribute, it should reuse this rather than
/// re-deciding what counts as a failure.
///
/// The posture, in one place:
///   * publishing switched off or not configured is `.notAttempted`, NEVER
///     `.failed` — that is the normal state for anyone without a MeedyaDB
///     account, and must not be shown as an error;
///   * a genuine rejection or network failure is `.failed`, recorded rather
///     than thrown, so a caller can show it without a `do`/`catch`;
///   * cancellation is rethrown untouched. The user stopping a run is not
///     MeedyaDB rejecting it, and reporting it as a failure would be a lie;
///   * a submission with nothing matchable in it is skipped rather than sent,
///     because a row nobody can ever merge is noise in a shared database.
public struct MeedyaDBContributor: Sendable {

    /// Public and named so callers can recognise these cases without string
    /// matching, and so tests pin the wording. Treat an edit as a
    /// user-facing copy change.
    public static let notRequestedReason =
        "Contributing to MeedyaDB wasn't requested, so nothing was sent."
    public static let noIdentityReason =
        "This disc didn't produce a usable identifier, so nothing was sent."

    private let publisher: MeedyaDBPublisher

    /// The default publisher has an empty, disabled config, so a contributor
    /// built with no arguments is a usable production object that quietly
    /// skips the upload — which is what everyone gets until MeedyaDB is set up.
    public init(
        publisher: MeedyaDBPublisher = MeedyaDBPublisher(config: MeedyaDBPublisherConfig())
    ) {
        self.publisher = publisher
    }

    /// - Throws: `CancellationError`, and nothing else.
    public func contribute(
        _ submission: MeedyaDBDiscSubmissionInputs,
        requested: Bool,
        mode: MeedyaDBSubmissionMode
    ) async throws -> MeedyaDBContribution {
        guard requested else {
            return .notAttempted(reason: Self.notRequestedReason)
        }
        guard submission.hasUsableIdentity else {
            return .notAttempted(reason: Self.noIdentityReason)
        }

        do {
            let result = try await publisher.submit(
                disc: submission.disc,
                identifiers: submission.identifiers,
                candidates: submission.candidates,
                mode: mode
            )
            return .succeeded(result)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MeedyaDBPublishError {
            switch error {
            case .disabled, .notConfigured:
                return .notAttempted(reason: error.localizedDescription)
            case .invalidURL, .unauthorized, .rateLimited, .httpStatus, .transport, .malformedResponse:
                return .failed(reason: error.localizedDescription)
            }
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}
