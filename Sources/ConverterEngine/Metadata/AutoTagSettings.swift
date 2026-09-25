// ============================================================================
// MeedyaConverter — AutoTagSettings (Issue #508, commit 3/10)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Where the auto-tag feature's settings live, and the honest verdict on
// whether it can actually run right now. Deliberately mirrors
// `MeedyaDBAccess.swift`'s shape (`MeedyaDBConfigStore` / `MeedyaDBReadiness`
// / `MeedyaDBGate`): an engine-owned `Keys` enum as the single source of
// truth for the defaults spelling, a read-only store that never retains the
// `UserDefaults` it was handed, and a gate that returns a plain-English
// reason rather than a bare `false`.
//
// ⚠️ WHAT IS AND ISN'T WIRED UP. `EncodingEngine` calls
// `AutoTagSettingsSource.currentRequest()` once at the start of every job —
// but only an engine that was GIVEN a source when it was built (#508
// commit 6). The app does not give its engine one until #508 commit 8, and
// the Settings toggle that writes `autotag.enabled` is commit 9. Until
// then, no real encode in the app reads these settings; they are exercised
// by `AutoTagSettingsTests` and, through a real `encode`, by
// `AutoTagEncodeDeliveryTests`. See `.claude/plans/autotag-encode-plan.md`.
//
// Auto-tagging is OFF by default. An absent `autotag.enabled` key reads as
// `false` from `UserDefaults.bool(forKey:)`, which is exactly the default
// wanted: a new install (and a freshly-created settings suite in a test)
// tags nothing until someone deliberately turns it on. This matters more
// than the usual "sensible default" reason — issue #508 is explicit that
// this feature changes embedded tags and must be opt-in.
// ============================================================================

import Foundation

// MARK: - AutoTagSettingsStore

/// Reads the auto-tag on/off switch and the NFO-writing switch from
/// `UserDefaults`. Read-only: the Settings UI (`@AppStorage`, added in #508
/// commit 9) writes these keys; this type only interprets them.
public enum AutoTagSettingsStore {

    /// Defaults keys. Kept here as the single source of truth so the
    /// Settings UI and the engine-side reader can never silently drift onto
    /// different key strings — the same reason `MeedyaDBConfigStore.Keys`
    /// and `MakeMKVConsentStore.Keys` exist.
    public enum Keys {
        /// Bool. The master switch for auto-tagging. Absent → off.
        public static let enabled = "autotag.enabled"
        /// Bool. Whether to also write a Kodi `.nfo` sidecar next to an
        /// identified film's output. Absent → off. Meaningless while
        /// `enabled` is false; the Settings UI disables this toggle in that
        /// state, and a runner (a later commit) never writes one either way
        /// unless a lookup actually succeeded.
        public static let writeNFO = "autotag.writeNFO"
    }

    /// Whether the user has switched auto-tagging on. Off by default.
    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.enabled)
    }

    /// Whether an identified film should also get a Kodi `.nfo` sidecar.
    /// Off by default.
    public static func writesNFO(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.writeNFO)
    }

    /// Builds the effective `AutoTagConfig` for the next job.
    ///
    /// Only `enabled` and `writeNFO` are read from `defaults` — everything
    /// else is FIXED here, not user-configurable yet, per the owner's
    /// decisions recorded at the end of `.claude/plans/autotag-encode-plan.md`:
    ///   - `sources`: `[.filename, .existingMetadata, .tmdb, .musicBrainz]`.
    ///     Filename parsing and existing metadata only ever SEED a search;
    ///     they never add a network call.
    ///   - `renameOutput`: always `false`. See
    ///     `AutoTagConfig.renameOutput`'s doc comment — renaming touches
    ///     roughly ten post-encode readers of the output path and is a
    ///     separate follow-up issue, not part of #508.
    ///   - `embedArtwork`: always `false`. See
    ///     `AutoTagConfig.embedArtwork`'s doc comment and
    ///     `AutoTagger.buildArtworkArguments`'s warning — appending that
    ///     fragment to a real transcode would silently turn it into a copy.
    public static func config(in defaults: UserDefaults = .standard) -> AutoTagConfig {
        AutoTagConfig(
            enabled: isEnabled(in: defaults),
            sources: [.filename, .existingMetadata, .tmdb, .musicBrainz],
            embedArtwork: false,
            writeNFO: writesNFO(in: defaults),
            renameOutput: false
        )
    }
}

// MARK: - AutoTagReadiness

/// The honest verdict on whether auto-tagging can actually do anything right
/// now, mirroring `MeedyaDBReadiness`'s three-state shape.
public enum AutoTagReadiness: Sendable, Equatable {

    /// Switched off. This is the normal, default state, not a problem:
    /// `reason` explains it in words a settings screen can show as
    /// information rather than as a warning.
    case off(reason: String)

    /// Switched on, but films will be skipped because no TMDB key is saved
    /// (issue #508's decision: "skip a provider with no key rather than
    /// treat it as an error"). Music lookups are unaffected — MusicBrainz
    /// needs no key.
    case limited(config: AutoTagConfig, reason: String)

    /// Switched on and fully able to look films and music up.
    case ready(config: AutoTagConfig)

    /// The usable config for `.limited` and `.ready`; `nil` for `.off`,
    /// where there is nothing to run with.
    public var config: AutoTagConfig? {
        switch self {
        case .off:
            return nil
        case .limited(let config, _), .ready(let config):
            return config
        }
    }

    /// The plain-English explanation for the two non-`.ready` cases; `nil`
    /// for `.ready`, where nothing needs explaining.
    public var reason: String? {
        switch self {
        case .off(let reason), .limited(_, let reason):
            return reason
        case .ready:
            return nil
        }
    }
}

// MARK: - AutoTagGate

/// Turns the stored settings plus "is a TMDB key saved" into one verdict.
/// Reads settings; contacts nothing and runs no lookup.
///
/// This is deliberately the SAME function both a settings screen's status
/// line (#508 commit 9) and the runner's own skip decision (#508 commit 4
/// onward) are meant to call, so the two can never disagree about whether
/// auto-tagging is off, limited, or ready.
public enum AutoTagGate {

    // Public and named so a UI can tell these cases apart without parsing
    // prose, and so tests pin the exact wording. Treat an edit as a
    // user-facing copy change, not a refactor. Matches the wording specified
    // in `.claude/plans/autotag-encode-plan.md`'s "Proposed wording" section.
    public static let offReason = "Automatic tagging is off."
    public static let limitedNoTMDBKeyReason =
        "On, but films are skipped until you save a TMDB key above."
    public static let readyReason = "On."

    /// - Parameters:
    ///   - defaults: where the enabled/writeNFO switches are read from.
    ///   - hasTMDBKey: whether a TMDB key is currently saved (the caller
    ///     fetches this from `APIKeyManager`; this file has no opinion
    ///     about, and no access to, where keys are kept — matching
    ///     `MeedyaDBGate.readiness`'s same separation of concerns).
    public static func readiness(
        in defaults: UserDefaults = .standard,
        hasTMDBKey: Bool
    ) -> AutoTagReadiness {
        let config = AutoTagSettingsStore.config(in: defaults)
        guard config.enabled else {
            return .off(reason: offReason)
        }
        guard hasTMDBKey else {
            return .limited(config: config, reason: limitedNoTMDBKeyReason)
        }
        return .ready(config: config)
    }
}

// MARK: - AutoTagRequest

/// Everything a job's auto-tag lookup needs, resolved once at the start of
/// the job by `AutoTagSettingsSource.currentRequest()`.
public struct AutoTagRequest: Sendable {

    /// The effective configuration for this job (see
    /// `AutoTagSettingsStore.config(in:)`).
    public let config: AutoTagConfig

    /// `nil` means no TMDB key is currently saved. A runner (#508 commit 4)
    /// must treat this as "skip film lookups", never as a failure — the
    /// same "skip a provider with no key" decision `AutoTagGate.readiness`
    /// reports as `.limited`.
    public let tmdbService: TMDBLookupService?

    /// Always present: MusicBrainz needs no API key, so a music lookup is
    /// never blocked the way a film lookup can be.
    public let musicBrainzService: MusicBrainzLookupService

    /// Wall-clock cap on the whole lookup. A runner (#508 commit 4) races
    /// this against the actual lookup and a stop-request poll; the first to
    /// finish wins and the others are cancelled.
    public let deadline: Duration

    public init(
        config: AutoTagConfig,
        tmdbService: TMDBLookupService?,
        musicBrainzService: MusicBrainzLookupService,
        deadline: Duration
    ) {
        self.config = config
        self.tmdbService = tmdbService
        self.musicBrainzService = musicBrainzService
        self.deadline = deadline
    }
}

// MARK: - AutoTagSettingsSource

/// Builds an `AutoTagRequest` for the job about to run, reading the setting
/// fresh every time it's asked.
///
/// `EncodingEngine` (from #508 commit 6) holds at most one of these
/// (`autoTagSettings`) and calls `currentRequest()` once at the start of
/// EACH job — never caching the result across jobs. That is the whole reason this type
/// exists rather than the engine just holding a captured `AutoTagConfig`:
/// flipping the Settings toggle mid-queue must apply starting with the very
/// next job, without restarting the app or re-creating the engine.
public final class AutoTagSettingsSource: @unchecked Sendable {

    /// `nil` means `UserDefaults.standard` — matching `@AppStorage`'s
    /// implicit store, so the app's real Settings tab and this source read
    /// the exact same place. Tests pass a per-test suite name instead, so
    /// runs never touch the developer's real defaults or each other's.
    public let suiteName: String?

    private let tmdbKeyProvider: @Sendable () -> String?
    private let httpClient: any MetadataHTTPClient
    private let musicBrainzThrottle: MusicBrainzRequestThrottle

    /// Wall-clock cap passed through to every `AutoTagRequest` this source
    /// builds. 30 seconds by default — the owner's decision recorded in
    /// `.claude/plans/autotag-encode-plan.md`.
    public let deadline: Duration

    /// - Parameters:
    ///   - suiteName: `nil` for the app's real, shared `UserDefaults`.
    ///   - tmdbKeyProvider: Reads the currently-saved TMDB key, or `nil`/
    ///     blank if none. The app constructs this as
    ///     `{ APIKeyManager().key(for: .tmdb)?.apiKey }` (#508 commit 8);
    ///     this file has no access to the Keychain itself, matching
    ///     `MeedyaDBGate`'s same separation.
    ///   - httpClient: The `MetadataHTTPClient` seam both lookup services
    ///     are built with. Defaults to the real `URLSessionMetadataHTTPClient`;
    ///     tests inject a fake.
    ///   - musicBrainzThrottle: Defaults to `.shared`, MusicBrainz's single
    ///     rate limiter for the whole app. Tests MUST inject their own
    ///     `MusicBrainzRequestThrottle(minimumInterval: .zero)` — sharing
    ///     `.shared` across parallel test runs would serialise them behind
    ///     MusicBrainz's real one-request-per-second limit for no reason.
    ///   - deadline: Wall-clock cap on a lookup. Defaults to 30 seconds.
    public init(
        suiteName: String? = nil,
        tmdbKeyProvider: @escaping @Sendable () -> String?,
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient(),
        musicBrainzThrottle: MusicBrainzRequestThrottle = .shared,
        deadline: Duration = .seconds(30)
    ) {
        self.suiteName = suiteName
        self.tmdbKeyProvider = tmdbKeyProvider
        self.httpClient = httpClient
        self.musicBrainzThrottle = musicBrainzThrottle
        self.deadline = deadline
    }

    /// The `UserDefaults` this source reads from. Resolved freshly on every
    /// call rather than cached at init — see `currentRequest()`'s doc
    /// comment for why that matters. Falls back to `.standard` if a named
    /// suite somehow fails to open, matching `RenderFarmConfigurationLoader`'s
    /// same defensive fallback.
    private func defaults() -> UserDefaults {
        guard let suiteName else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// `true` when this source reads the app's real, shared `UserDefaults`
    /// rather than an isolated test suite.
    ///
    /// `AutoTagAppWiringTests` (#508 commit 8) checks this is `true` for the
    /// `AutoTagSettingsSource` the app actually constructs in
    /// `AppViewModel.init` — proving the running app's engine reads the
    /// SAME defaults the Settings UI writes to, not an accidental copy.
    /// (This is the same shape of check `#507` exists for: a setting the
    /// UI writes and nothing reads is worse than no setting at all.)
    public var readsStandardDefaults: Bool { suiteName == nil }

    /// Reads the setting NOW and builds a request for the job about to run,
    /// or `nil` when auto-tagging is off.
    ///
    /// Deliberately re-reads `UserDefaults` on every call instead of
    /// caching anything from `init` — see this type's own doc comment for
    /// why a per-job read matters.
    ///
    /// `tmdbService` is `nil` whenever `tmdbKeyProvider()` returns `nil` or
    /// a blank string. No key means no TMDB request is ever attempted; a
    /// runner (#508 commit 4) must treat that as "skip film lookups", never
    /// as a failure.
    ///
    /// Called by `EncodingEngine.encode(job:onProgress:)` once per job, for an
    /// engine built with a settings source (#508 commit 6) — see this file's
    /// header for why no app encode reaches it before #508 commit 8.
    public func currentRequest() -> AutoTagRequest? {
        let defaults = self.defaults()
        let config = AutoTagSettingsStore.config(in: defaults)
        guard config.enabled else { return nil }

        let rawKey = tmdbKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tmdbService: TMDBLookupService?
        if let rawKey, !rawKey.isEmpty {
            tmdbService = TMDBLookupService(apiKey: rawKey, httpClient: httpClient)
        } else {
            tmdbService = nil
        }

        return AutoTagRequest(
            config: config,
            tmdbService: tmdbService,
            musicBrainzService: MusicBrainzLookupService(
                httpClient: httpClient,
                throttle: musicBrainzThrottle
            ),
            deadline: deadline
        )
    }
}
