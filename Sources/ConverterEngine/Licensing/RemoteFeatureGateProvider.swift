// ============================================================================
// MeedyaConverter — RemoteFeatureGateProvider (Roadmap #5)
// (C) 2026–present MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// `RemoteFeatureGateProvider` is a remote kill-switch for features that are
// not (yet) safe to expose to every user — the first consumer is the
// permanently-disabled "Video Upload" area (`VideoUploadView`, gated behind
// the `video-upload` flag key), which shipped disabled for v0.1.0 because
// its OAuth2 wiring is incomplete (#446/#294).
//
// This is a DIFFERENT axis from `FeatureGateProvider`'s existing
// `EntitlementLevel` tiers (free/plus/pro — see `EntitlementGating.swift`):
// that system answers "is the user PAYING for this feature", while this
// type answers "is this feature currently SAFE/FUNCTIONAL to show at all,
// regardless of what the user paid". A broken feature should stay hidden
// from free AND paying users alike until a maintainer flips the remote
// flag — no entitlement tier should unlock a feature that doesn't work.
//
// `RemoteFeatureGateProvider` still conforms to `FeatureGateProvider` (see
// the note on that conformance below) so it slots into
// `FeatureGateManager.shared.provider` without introducing a second
// parallel gating protocol — but the actual boolean remote-flag surface
// this type exists for is the additive `isEnabled(_:)` / `refreshFlags()`
// API, not the entitlement methods.
//
// ### Dormancy + fail-safe (the two hard requirements)
// * **Dormant when unconfigured**: intAppsAPI is not yet provisioned for
//   MeedyaConverter. `init()`'s default `client` parameter resolves via
//   `IntAppsAPIClient.configured()`, which returns `nil` when Keychain +
//   environment both lack credentials. A `nil` client means `refreshFlags()`
//   returns immediately without touching the network OR the disk cache, and
//   `isEnabled(_:)` falls straight through to the compiled-in defaults —
//   i.e. the app behaves exactly as it did before this file existed.
// * **Fail-safe on remote failure**: `refreshFlags()` never throws. Any
//   network/decode/HTTP failure is swallowed, leaving whatever was already
//   cached (persisted cache, or the compiled-in default) untouched. A dead
//   or misconfigured intAppsAPI can never crash the app, hang the UI, or
//   silently enable a feature that was compiled-in as unsafe.
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - RemoteFeatureGateProvider
// ---------------------------------------------------------------------------
/// Fetches, caches, and exposes intAppsAPI's boolean remote feature flags.
///
/// ### Thread Safety
/// `@unchecked Sendable`, following the same pattern as
/// `FeatureGateManager`/`RevenueCatGateProvider` elsewhere in this file's
/// neighbourhood: all mutable state (`cachedFlags`) lives behind `lock`,
/// every public method takes/releases it for the shortest possible
/// section, and nothing escapes the lock by reference.
public final class RemoteFeatureGateProvider: FeatureGateProvider, @unchecked Sendable {

    // -----------------------------------------------------------------
    // MARK: - Well-known flag keys
    // -----------------------------------------------------------------

    /// The flag key gating the Video Upload feature (#5 / #446).
    public static let videoUploadFlagKey = "video-upload"

    /// Locally-compiled default enabled/disabled state per feature key —
    /// the fail-safe fallback used whenever a flag has never been
    /// fetched (dormant, or every fetch so far has failed). Any key not
    /// listed here defaults to `false` via `isEnabled(_:)` — an unknown
    /// remote flag is treated as "off" rather than guessed at.
    ///
    /// `video-upload` defaults to `false`: the honest #446 state (the
    /// Upload button is non-functional pending #294's OAuth2 wiring), so
    /// an unconfigured or unreachable intAppsAPI reproduces today's
    /// behaviour exactly.
    public static let builtInDefaults: [String: Bool] = [
        videoUploadFlagKey: false,
    ]

    // -----------------------------------------------------------------
    // MARK: - Dependencies (immutable — set once at init)
    // -----------------------------------------------------------------

    /// The intAppsAPI client. `nil` means dormant — see the file overview.
    private let client: IntAppsAPIClient?

    /// Where entitlement-tier checks (the `FeatureGateProvider` protocol
    /// methods) are actually delegated to. See the conformance note below.
    private let fallbackEntitlementProvider: FeatureGateProvider

    /// Compiled-in defaults, keyed by feature flag key.
    private let defaultFlags: [String: Bool]

    /// On-disk cache location. `nil` when dormant — a dormant provider
    /// never touches disk, matching "no network calls, no errors
    /// surfaced" literally.
    private let cacheURL: URL?

    // -----------------------------------------------------------------
    // MARK: - Mutable state (lock-protected)
    // -----------------------------------------------------------------

    private let lock = NSLock()
    private var cachedFlags: [String: FeatureFlag] = [:]

    // -----------------------------------------------------------------
    // MARK: - Initialiser
    // -----------------------------------------------------------------

    /// - Parameters:
    ///   - client: The intAppsAPI client to fetch flags from. Defaults to
    ///     `IntAppsAPIClient.configured()`, which resolves credentials
    ///     from the Keychain/environment and is `nil` when intAppsAPI is
    ///     not provisioned for this app — the dormancy gate. Tests pass
    ///     an explicit client (mock-backed session) or explicit `nil`
    ///     to exercise the configured/dormant paths deterministically.
    ///   - fallbackEntitlementProvider: The `FeatureGateProvider` this
    ///     type delegates `entitlementLevel()`/`isEntitled(to:)` to (see
    ///     the conformance note above `RemoteFeatureGateProvider`).
    ///     Defaults to `FreeGateProvider()`, matching every other
    ///     provider's zero-configuration baseline.
    ///   - defaultFlags: Compiled-in fail-safe defaults. Defaults to
    ///     `builtInDefaults`; tests override to check fallback behaviour
    ///     for keys not covered by the real defaults.
    ///   - cacheDirectory: Directory for the persisted flag cache.
    ///     Defaults to `~/Library/Application Support/MeedyaConverter/
    ///     RemoteFeatures`; tests pass an isolated temp directory. Only
    ///     consulted when `client != nil` — a dormant provider never
    ///     resolves or touches this directory.
    public init(
        client: IntAppsAPIClient? = IntAppsAPIClient.configured(),
        fallbackEntitlementProvider: FeatureGateProvider = FreeGateProvider(),
        defaultFlags: [String: Bool] = RemoteFeatureGateProvider.builtInDefaults,
        cacheDirectory: URL? = nil
    ) {
        self.client = client
        self.fallbackEntitlementProvider = fallbackEntitlementProvider
        self.defaultFlags = defaultFlags

        if client != nil {
            let defaultCacheDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MeedyaConverter")
                .appendingPathComponent("RemoteFeatures")
            let dir = cacheDirectory ?? defaultCacheDir
            self.cacheURL = dir.appendingPathComponent("flags_cache.json")
        } else {
            // DORMANT: no client means no disk I/O at all, not even a
            // read — "app behaves exactly as today" is literal.
            self.cacheURL = nil
        }

        if let cacheURL {
            loadPersistedCache(from: cacheURL)
        }
    }

    // -----------------------------------------------------------------
    // MARK: - FeatureGateProvider conformance
    // -----------------------------------------------------------------
    //
    // `FeatureGateProvider` models entitlement-TIER gating
    // (free/plus/pro), an orthogonal concern to the boolean remote
    // kill-switch flags this type manages — there is no `GatedFeature`
    // case for "is the video-upload remote flag on", nor should there
    // be, since a broken feature must stay hidden regardless of tier.
    // Conformance here is a pure pass-through to
    // `fallbackEntitlementProvider` purely so a `RemoteFeatureGateProvider`
    // instance CAN be installed as `FeatureGateManager.shared.provider`
    // without any other code needing to change, satisfying "no
    // architectural churn" — nothing currently requires installing it
    // there, since gating `video-upload` (see `isVideoUploadEnabled`
    // below) does not need to. The real, additive API is `isEnabled(_:)`
    // / `refreshFlags()`.

    public func entitlementLevel() async -> EntitlementLevel {
        await fallbackEntitlementProvider.entitlementLevel()
    }

    public func isEntitled(to feature: GatedFeature) -> Bool {
        fallbackEntitlementProvider.isEntitled(to: feature)
    }

    // -----------------------------------------------------------------
    // MARK: - Remote flag surface
    // -----------------------------------------------------------------

    /// Whether `key` is enabled right now.
    ///
    /// Resolution order: the freshest cached remote value (persisted
    /// cache on first launch, then whatever `refreshFlags()` last
    /// fetched), else the compiled-in default for `key`, else `false`
    /// for a completely unknown key.
    ///
    /// Synchronous and lock-protected (never `await`s) so SwiftUI can
    /// call this directly from a view's `body` — matching how
    /// `FeatureGateManager.isEntitled(to:)` is used throughout the app.
    public func isEnabled(_ key: String) -> Bool {
        if let flag = lock.withLock({ cachedFlags[key] }) {
            return flag.enabled
        }
        return defaultFlags[key] ?? false
    }

    /// Convenience accessor for the Video Upload gate (#5). Equivalent
    /// to `isEnabled(Self.videoUploadFlagKey)`.
    public var isVideoUploadEnabled: Bool {
        isEnabled(Self.videoUploadFlagKey)
    }

    /// Refreshes the in-memory + persisted cache from intAppsAPI.
    ///
    /// - Returns: `true` if a fetch actually completed and updated the
    ///   cache; `false` when dormant (no client) or when the fetch
    ///   failed. Callers generally don't need the return value — it
    ///   exists for tests and for optional diagnostic logging — since
    ///   `isEnabled(_:)` already degrades gracefully either way.
    ///
    /// **Never throws.** Every failure mode (dormant client, transport
    /// error, non-2xx, decode failure) is caught here and treated as
    /// "keep whatever we already have" — the fail-safe contract this
    /// type exists to provide. See `RemoteFeatureGateProviderTests` for
    /// the case that pins this down: a client that always throws must
    /// still leave `isEnabled(_:)` returning the compiled-in default,
    /// never crash, and never hang.
    @discardableResult
    public func refreshFlags() async -> Bool {
        guard let client else { return false }  // DORMANT

        do {
            let flags = try await client.fetchFeatureFlags(appSlug: client.credentials.appSlug)
            lock.withLock {
                for flag in flags {
                    cachedFlags[flag.featureKey] = flag
                }
            }
            persistCache()
            return true
        } catch {
            // FAIL-SAFE: swallow the error. `isEnabled(_:)` continues to
            // serve whatever was cached before this call (or the
            // compiled-in default, if nothing was ever cached).
            return false
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Persistence
    // -----------------------------------------------------------------

    /// On-disk shape for the persisted cache: the flags plus a
    /// timestamp (currently unused beyond diagnostics, kept for a
    /// future TTL/staleness policy without a storage-format migration).
    private struct FlagCacheEnvelope: Codable {
        let flags: [FeatureFlag]
        let savedAt: Date
    }

    /// Loads any persisted cache from a previous run into `cachedFlags`,
    /// merging by `featureKey`. Best-effort: any read/decode failure
    /// (missing file, corrupt JSON, first-ever launch) leaves
    /// `cachedFlags` untouched rather than throwing — this runs from
    /// `init` (after all stored properties are set, so calling this
    /// instance method is safe), and a gate provider must never fail to
    /// construct.
    private func loadPersistedCache(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(FlagCacheEnvelope.self, from: data) else { return }
        lock.withLock {
            for flag in envelope.flags {
                cachedFlags[flag.featureKey] = flag
            }
        }
    }

    /// Writes the current in-memory cache to disk. Best-effort: a write
    /// failure (e.g. read-only filesystem, disk full) is silently
    /// ignored — the in-memory cache still has the fresh values for the
    /// remainder of this run, and the next successful `refreshFlags()`
    /// will retry the write.
    private func persistCache() {
        guard let cacheURL else { return }  // DORMANT — should be unreachable (refreshFlags already returned), but stays defensive.

        let flags = lock.withLock { Array(cachedFlags.values) }
        let envelope = FlagCacheEnvelope(flags: flags, savedAt: Date())

        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Best-effort — see doc comment above.
        }
    }
}
