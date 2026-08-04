// ============================================================================
// MeedyaConverter — RenderFarmConfigurationLoader
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Consumes the `renderFarm.*` `UserDefaults` keys persisted by the GUI's
// `RenderFarmSettingsTab` (`@AppStorage`) and turns them into the two
// things the engine actually needs: a `RenderFarmClient.Configuration`
// and the initial (manually-added) agent registry.
//
// This is the "consumer" that the tab's header comment has been pointing
// at since #381/#406 landed:
//
//   "When #346 completes, the consumer reads these AppStorage keys to
//    construct its Configuration + initial agent registry."
//
// Scope note: this file intentionally implements ONLY that bridge. It is
// NOT the transport layer (SSH/TLS wire implementations), NOT Bonjour
// discovery, and NOT the remote agent binary — those remain the large,
// still-open remainder of issue #346. Keeping this file pure Foundation
// (no AppKit, no SwiftUI, no networking) means the settings->engine
// bridge itself can be fully unit tested without a UI or a live agent.
//
// GitHub Issue #346 — Remote encoding / render farm submission.
// ============================================================================

import Foundation

// MARK: - RenderFarmConfigurationLoader

/// Reads the `renderFarm.*` `UserDefaults` keys written by
/// `RenderFarmSettingsTab` and produces a `RenderFarmClient.Configuration`
/// plus the manually-added `[RenderFarmAgentInfo]` registry.
///
/// A thin wrapper over an injected `UserDefaults` — no singleton, no
/// AppKit/SwiftUI dependency — so callers (CLI, GUI, tests) can each
/// supply their own store.
///
/// `@unchecked Sendable`, matching `RenderFarmClient`'s own pattern
/// immediately below: `UserDefaults` does not itself conform to
/// `Sendable` in this SDK, but it is documented by Apple as thread-safe,
/// and this type never mutates the store — it only reads from it.
public final class RenderFarmConfigurationLoader: @unchecked Sendable {

    // -----------------------------------------------------------------
    // MARK: - Shared keys
    // -----------------------------------------------------------------

    /// Shared `UserDefaults` key names. `RenderFarmSettingsTab`'s
    /// `@AppStorage` property wrappers reference these same constants so
    /// the tab and this loader can never silently drift onto different
    /// key strings.
    public enum Keys {
        public static let allowInsecureTransports = "renderFarm.allowInsecureTransports"
        public static let insecureAcknowledgement = "renderFarm.insecureAcknowledgement"
        public static let discoveryIntervalSeconds = "renderFarm.discoveryIntervalSeconds"
        public static let chunkSizeMiB = "renderFarm.chunkSizeMiB"
        public static let agentsJSON = "renderFarm.agentsJSON"
    }

    // -----------------------------------------------------------------
    // MARK: - Defaults (must mirror RenderFarmSettingsTab's @AppStorage
    // default values exactly, so a fresh UserDefaults with no keys
    // written yet produces the same Configuration the tab implicitly
    // assumes)
    // -----------------------------------------------------------------

    public static let defaultAllowInsecureTransports = false
    public static let defaultInsecureAcknowledgement = ""
    public static let defaultDiscoveryIntervalSeconds: Double = 30.0
    public static let defaultChunkSizeMiB = 4

    // -----------------------------------------------------------------
    // MARK: - Validation bounds
    // -----------------------------------------------------------------

    /// Matches the `Stepper(value:in: 5...300, step: 5)` bounds in
    /// `RenderFarmSettingsTab`'s discovery section. A stored value
    /// outside this range (corrupt default, older/newer build with a
    /// different range) is clamped rather than trusted verbatim.
    public static let discoveryIntervalBounds: ClosedRange<Double> = 5...300

    /// The tab only ever writes one of `[1, 4, 16, 64]` MiB via its
    /// segmented picker, but the loader defends against an arbitrary
    /// stored `Int` (corrupt plist, manual edit, future schema): values
    /// below 1 MiB would produce a useless-or-zero `chunkSizeBytes`, and
    /// an unbounded upper value risks overflow once converted to bytes.
    /// `1...1024` MiB comfortably covers the picker's range while
    /// keeping both failure modes impossible.
    public static let chunkSizeMiBBounds: ClosedRange<Int> = 1...1024

    // -----------------------------------------------------------------
    // MARK: - Lifecycle
    // -----------------------------------------------------------------

    private let defaults: UserDefaults

    /// - Parameter defaults: The `UserDefaults` store to read from.
    ///   Defaults to `.standard`, matching `@AppStorage`'s implicit
    ///   store when the tab doesn't specify one explicitly. Tests should
    ///   inject an isolated `UserDefaults(suiteName:)` instance instead
    ///   of touching the real, shared defaults.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // -----------------------------------------------------------------
    // MARK: - Public API
    // -----------------------------------------------------------------

    /// Reads the persisted settings and builds the engine-side
    /// configuration together with the initial agent registry.
    public func load() -> (configuration: RenderFarmClient.Configuration, agents: [RenderFarmAgentInfo]) {
        (configuration: loadConfiguration(), agents: loadAgents())
    }

    /// Builds the `RenderFarmClient.Configuration` from the persisted
    /// settings.
    public func loadConfiguration() -> RenderFarmClient.Configuration {
        RenderFarmClient.Configuration(
            insecureTransportOverride: loadInsecureTransportOverride(),
            discoveryIntervalSeconds: clampedDiscoveryIntervalSeconds(),
            chunkSizeBytes: clampedChunkSizeBytes()
        )
    }

    /// Decodes the JSON-encoded agent list. Never throws: an empty
    /// `Data()` (fresh install, key never written) or malformed/corrupt
    /// JSON (future schema, truncated write) both yield an empty
    /// registry rather than crashing the caller — mirroring
    /// `RenderFarmSettingsTab.agents`'s own decode-failure handling.
    public func loadAgents() -> [RenderFarmAgentInfo] {
        guard let data = defaults.data(forKey: Keys.agentsJSON), !data.isEmpty else {
            return []
        }
        return (try? JSONDecoder().decode([RenderFarmAgentInfo].self, from: data)) ?? []
    }

    // -----------------------------------------------------------------
    // MARK: - Security contract
    // -----------------------------------------------------------------

    /// Only produces an override when `allowInsecureTransports` is
    /// `true` AND the stored acknowledgement is non-blank (a
    /// whitespace-only string doesn't count as a real acknowledgement).
    ///
    /// This mirrors the contract pinned by
    /// `test_renderFarm_insecureTransportRejectedByDefault` /
    /// `test_renderFarm_insecureTransportAllowedWhenConfigured` in
    /// `RenderFarmClient`: a submission over `.plainHTTP` is refused
    /// unless the client's `Configuration` was constructed with an
    /// explicit `InsecureTransportOverride`. If the user has flipped the
    /// toggle on but not yet typed an acknowledgement (e.g. mid-typing,
    /// or a stray persisted `true` from a corrupted defaults file), the
    /// produced `Configuration` must NOT permit insecure transport.
    private func loadInsecureTransportOverride() -> InsecureTransportOverride? {
        let allowed = defaults.object(forKey: Keys.allowInsecureTransports) != nil
            ? defaults.bool(forKey: Keys.allowInsecureTransports)
            : Self.defaultAllowInsecureTransports
        guard allowed else { return nil }

        let acknowledgement = defaults.string(forKey: Keys.insecureAcknowledgement)
            ?? Self.defaultInsecureAcknowledgement
        guard !acknowledgement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .developmentOnly(acknowledgement: acknowledgement)
    }

    // -----------------------------------------------------------------
    // MARK: - Numeric validation
    // -----------------------------------------------------------------

    private func clampedDiscoveryIntervalSeconds() -> TimeInterval {
        let stored = defaults.object(forKey: Keys.discoveryIntervalSeconds) != nil
            ? defaults.double(forKey: Keys.discoveryIntervalSeconds)
            : Self.defaultDiscoveryIntervalSeconds
        return min(
            max(stored, Self.discoveryIntervalBounds.lowerBound),
            Self.discoveryIntervalBounds.upperBound
        )
    }

    private func clampedChunkSizeBytes() -> UInt64 {
        let storedMiB = defaults.object(forKey: Keys.chunkSizeMiB) != nil
            ? defaults.integer(forKey: Keys.chunkSizeMiB)
            : Self.defaultChunkSizeMiB
        let clampedMiB = min(
            max(storedMiB, Self.chunkSizeMiBBounds.lowerBound),
            Self.chunkSizeMiBBounds.upperBound
        )
        return UInt64(clampedMiB) * 1024 * 1024
    }
}
