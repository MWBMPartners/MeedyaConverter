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

    /// The reason to show AFTER a run when contributing was requested but
    /// could not go ahead, for #507. `nil` for `.ready` (there is nothing to
    /// decline) and, deliberately, for `.off` too: that case did not ask for
    /// anything, so `MeedyaDBContributor.notRequestedReason` ("wasn't
    /// requested") stays the honest description of it.
    ///
    /// `.incomplete` is the one case this exists for: the user DID switch
    /// contributing on, so telling them afterwards that it "wasn't
    /// requested" is false — it was requested, and simply is not finished
    /// being set up. `reason` already says exactly which piece is missing,
    /// so this just makes that reason available to a caller that only has a
    /// `Bool` to hand the contributor (see `MeedyaDBContributor.contribute`'s
    /// `declinedBecause` parameter).
    public var declinedReason: String? {
        if case .incomplete(let reason) = self { return reason }
        return nil
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
    /// Codex round-1 review, finding F1: shown when a `recheck` closure reports that MeedyaDB's settings
    /// no longer match what this run started with, immediately before the
    /// network call. Named and public for the same reason as the two above —
    /// so a caller or a test can recognise this specific outcome without
    /// string-matching, and so an edit to the wording is treated as a
    /// user-facing copy change.
    public static let withdrawnReason =
        "MeedyaDB settings changed while this disc was being identified, so nothing was sent."

    private let publisher: MeedyaDBPublisher

    /// The default publisher has an empty, disabled config, so a contributor
    /// built with no arguments is a usable production object that quietly
    /// skips the upload — which is what everyone gets until MeedyaDB is set up.
    public init(
        publisher: MeedyaDBPublisher = MeedyaDBPublisher(config: MeedyaDBPublisherConfig())
    ) {
        self.publisher = publisher
    }

    /// - Parameters:
    ///   - requested: whether the caller asked to contribute at all.
    ///   - mode: the submission mode captured when the run started.
    ///   - declinedBecause: #507. When `requested` is `false`, the SPECIFIC
    ///     reason contributing did not happen, if the caller has one — for
    ///     example "contributing is on, but MeedyaDB has no API key yet"
    ///     (`MeedyaDBReadiness.declinedReason`). `nil` falls back to
    ///     `notRequestedReason`, which stays correct for the two callers that
    ///     genuinely never asked: the CLI without `--submit`, and MeedyaDB
    ///     switched off outright (`MeedyaDBReadiness.declinedReason` returns
    ///     `nil` for `.off` on purpose — see its doc comment).
    ///   - recheck: an optional re-read of the CURRENT submission mode,
    ///     called IMMEDIATELY before `publisher.submit` — as late as this
    ///     type can make it, short of being inside the network call itself.
    ///
    ///     This exists because a run can take a while: the music path waits
    ///     on a disc read plus one MusicBrainz request, and the video path
    ///     can wait on up to about seven TMDB requests. Without a recheck,
    ///     switching contributing off — or narrowing `.full` to `.anonymous`
    ///     — after a run has already started has no effect, because the
    ///     `mode` and `requested` above were captured once, at the start.
    ///
    ///     `recheck` returning `nil` means "the settings this run started
    ///     with no longer hold" (switched off, server changed, key removed
    ///     or replaced — see the app-layer callers for the exact equality
    ///     check), and withdraws the whole submission. Returning a mode
    ///     combines it with the CAPTURED `mode` by taking the NARROWER of
    ///     the two (`MeedyaDBSubmissionMode.narrower`), so a `recheck`
    ///     closure that is wrong can only make a run send LESS than it
    ///     promised, never more — the narrowing happens HERE, in the one
    ///     shared place, rather than trusting every caller to get it right.
    ///
    ///     `nil` (the default) skips the recheck entirely: the engine has no
    ///     Keychain access (see this file's header) and cannot build one
    ///     itself, and the CLI's settings cannot change while it runs, so
    ///     there is nothing for it to re-read. The two GUI screens
    ///     (`DiscIdentifyViewModel`, `MakeMKVRipViewModel`) are the callers
    ///     that supply one, built from the same providers they used to
    ///     capture the original config and mode.
    ///
    ///     STATED LIMIT: this closes the window as far as it can be closed
    ///     from here, but not all the way. Once `publisher.submit` has
    ///     handed the request to the network layer, a change arriving after
    ///     that point cannot recall it — there is no message in flight to
    ///     cancel.
    /// - Throws: `CancellationError`, and nothing else.
    public func contribute(
        _ submission: MeedyaDBDiscSubmissionInputs,
        requested: Bool,
        mode: MeedyaDBSubmissionMode,
        declinedBecause: String? = nil,
        recheck: (@Sendable () -> MeedyaDBSubmissionMode?)? = nil
    ) async throws -> MeedyaDBContribution {
        guard requested else {
            return .notAttempted(reason: declinedBecause ?? Self.notRequestedReason)
        }
        guard submission.hasUsableIdentity else {
            return .notAttempted(reason: Self.noIdentityReason)
        }

        // The LAST check before anything leaves the machine. See `recheck`'s
        // doc comment above for why this exists and what it cannot do.
        var modeToSend = mode
        if let recheck {
            guard let currentMode = recheck() else {
                return .notAttempted(reason: Self.withdrawnReason)
            }
            modeToSend = MeedyaDBSubmissionMode.narrower(mode, currentMode)
        }

        do {
            let result = try await publisher.submit(
                disc: submission.disc,
                identifiers: submission.identifiers,
                candidates: submission.candidates,
                mode: modeToSend
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
